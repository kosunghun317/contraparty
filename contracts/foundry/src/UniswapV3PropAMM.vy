# pragma version ^0.4.1
# @license MIT

# -----------------------------------------------------------------------------
# UniswapV3PropAMM
# -----------------------------------------------------------------------------
# Adapter model:
# - Find the best locally registered pool for (token_in, token_out).
# - Pull token_in from caller (Contraparty).
# - Execute V3 swap with recipient=self.
# - Approve caller to pull exact token_out via transferFrom.
# -----------------------------------------------------------------------------


# -----------------------------------------------------------------------------
# External interfaces
# -----------------------------------------------------------------------------
interface ERC20:
    def transferFrom(sender: address, receiver: address, amount: uint256) -> bool: nonpayable
    def transfer(receiver: address, amount: uint256) -> bool: nonpayable
    def approve(spender: address, amount: uint256) -> bool: nonpayable
    def allowance(owner: address, spender: address) -> uint256: view


interface UniswapV3Pool:
    def token0() -> address: view
    def token1() -> address: view
    def swap(
        recipient: address,
        zeroForOne: bool,
        amountSpecified: int256,
        sqrtPriceLimitX96: uint160,
        data: Bytes[1],
    ) -> (int256, int256): nonpayable


# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
MAX_POOLS: constant(uint256) = 64

MIN_SQRT_RATIO_PLUS_ONE: constant(uint160) = 4295128741
MAX_SQRT_RATIO_MINUS_ONE: constant(uint160) = 1461446703485210103287273052203988822378723970340

MAX_INT256: constant(uint256) = 2**255 - 1
QUOTER_GAS_LIMIT: constant(uint256) = 8_000_000


# -----------------------------------------------------------------------------
# Events
# -----------------------------------------------------------------------------
event PoolRegistered:
    pool: address
    token0: address
    token1: address
    fee: uint24


event PoolRemoved:
    pool: address


event QuoterUpdated:
    quoter: address


# -----------------------------------------------------------------------------
# Storage
# -----------------------------------------------------------------------------
owner: public(address)
quoter: public(address)
pools: public(DynArray[address, MAX_POOLS])
pool_registered: public(HashMap[address, bool])
pool_fee: public(HashMap[address, uint24])
pool_pair_key: public(HashMap[address, bytes32])


# -----------------------------------------------------------------------------
# Transient swap context
# -----------------------------------------------------------------------------
ts_active: transient(bool)
ts_pool: transient(address)
ts_received_out: transient(uint256)


# -----------------------------------------------------------------------------
# Constructor
# -----------------------------------------------------------------------------
@deploy
def __init__(quoter_: address):
    self.owner = msg.sender
    self.quoter = quoter_


# -----------------------------------------------------------------------------
# Core API
# -----------------------------------------------------------------------------
@external
@view
def quote(token_in: address, token_out: address, amount_in: uint256) -> uint256:
    _pool: address = empty(address)
    _fee: uint24 = 0
    quoted_out: uint256 = 0
    _pool, _fee, quoted_out = self._best_route(token_in, token_out, amount_in)
    return quoted_out


@external
def swap(token_in: address, token_out: address, amount_in: uint256, min_amount_out: uint256) -> uint256:
    assert amount_in > 0, "AMOUNT_IN_ZERO"
    assert amount_in <= MAX_INT256, "AMOUNT_IN_TOO_LARGE"
    assert not self.ts_active, "PENDING_SWAP"

    best_pool: address = empty(address)
    _fee: uint24 = 0
    quoted_out: uint256 = 0
    best_pool, _fee, quoted_out = self._best_route(token_in, token_out, amount_in)
    assert best_pool != empty(address), "NO_POOL"
    assert quoted_out >= min_amount_out, "NO_ROUTE_OR_LOW_QUOTE"

    assert extcall ERC20(token_in).transferFrom(msg.sender, self, amount_in), "TRANSFER_FROM_FAIL"

    zero_for_one: bool = False
    pool_matches_pair: bool = False
    zero_for_one, pool_matches_pair = self._direction(best_pool, token_in, token_out)
    assert pool_matches_pair, "BAD_POOL"

    self.ts_active = True
    self.ts_pool = best_pool
    self.ts_received_out = 0

    if zero_for_one:
        amount0_delta: int256 = 0
        amount1_delta: int256 = 0
        amount0_delta, amount1_delta = extcall UniswapV3Pool(best_pool).swap(
            self,
            True,
            convert(amount_in, int256),
            MIN_SQRT_RATIO_PLUS_ONE,
            b"1",
        )
        assert amount1_delta < 0, "BAD_SWAP_OUT"
    else:
        amount0_delta2: int256 = 0
        amount1_delta2: int256 = 0
        amount0_delta2, amount1_delta2 = extcall UniswapV3Pool(best_pool).swap(
            self,
            False,
            convert(amount_in, int256),
            MAX_SQRT_RATIO_MINUS_ONE,
            b"1",
        )
        assert amount0_delta2 < 0, "BAD_SWAP_OUT"

    assert not self.ts_active, "CALLBACK_NOT_COMPLETED"
    amount_out: uint256 = self.ts_received_out
    self._clear_pending()

    assert amount_out >= min_amount_out, "MIN_AMOUNT_OUT"

    current_allowance: uint256 = staticcall ERC20(token_out).allowance(self, msg.sender)
    if current_allowance != 0:
        assert extcall ERC20(token_out).approve(msg.sender, 0), "APPROVE_RESET_FAIL"
    assert extcall ERC20(token_out).approve(msg.sender, amount_out), "APPROVE_OUT_FAIL"

    return amount_out


@external
def uniswapV3SwapCallback(amount0_delta: int256, amount1_delta: int256, _data: Bytes[1]):
    assert self.ts_active, "NO_PENDING_SWAP"
    assert msg.sender == self.ts_pool, "BAD_CB_POOL"
    assert amount0_delta > 0 or amount1_delta > 0, "NO_DELTA"

    amount_out: uint256 = 0
    if amount0_delta < 0:
        amount_out = convert(0 - amount0_delta, uint256)
    else:
        amount_out = convert(0 - amount1_delta, uint256)

    if amount0_delta > 0:
        token0: address = staticcall UniswapV3Pool(msg.sender).token0()
        assert extcall ERC20(token0).transfer(msg.sender, convert(amount0_delta, uint256)), "PAY_POOL0_FAIL"
    if amount1_delta > 0:
        token1: address = staticcall UniswapV3Pool(msg.sender).token1()
        assert extcall ERC20(token1).transfer(msg.sender, convert(amount1_delta, uint256)), "PAY_POOL1_FAIL"

    self.ts_received_out = amount_out
    self.ts_active = False


# -----------------------------------------------------------------------------
# Admin
# -----------------------------------------------------------------------------
@external
def set_quoter(quoter_: address):
    self._only_owner()
    self.quoter = quoter_
    log QuoterUpdated(quoter=quoter_)


@external
def register_pool(pool: address, fee: uint24):
    self._only_owner()
    assert pool != empty(address), "ZERO_POOL"
    assert fee > 0, "ZERO_FEE"
    assert not self.pool_registered[pool], "POOL_EXISTS"
    assert len(self.pools) < MAX_POOLS, "POOL_LIMIT"

    token0: address = staticcall UniswapV3Pool(pool).token0()
    token1: address = staticcall UniswapV3Pool(pool).token1()
    assert token0 != empty(address) and token1 != empty(address), "BAD_POOL_TOKENS"
    assert token0 != token1, "BAD_POOL_TOKENS"

    self.pools.append(pool)
    self.pool_registered[pool] = True
    self.pool_fee[pool] = fee
    self.pool_pair_key[pool] = self._pair_key(token0, token1)

    log PoolRegistered(pool=pool, token0=token0, token1=token1, fee=fee)


@external
def remove_pool(pool: address):
    self._only_owner()
    assert self.pool_registered[pool], "POOL_NOT_FOUND"

    pool_count: uint256 = len(self.pools)
    for i: uint256 in range(MAX_POOLS):
        if i >= pool_count:
            break

        if self.pools[i] == pool:
            if i < pool_count - 1:
                self.pools[i] = self.pools[pool_count - 1]
            self.pools.pop()
            self.pool_registered[pool] = False
            self.pool_fee[pool] = 0
            self.pool_pair_key[pool] = empty(bytes32)
            log PoolRemoved(pool=pool)
            return

    assert False, "POOL_NOT_FOUND"


@external
@view
def pool_count() -> uint256:
    return len(self.pools)


# -----------------------------------------------------------------------------
# Internal helpers
# -----------------------------------------------------------------------------
@internal
@view
def _best_route(token_in: address, token_out: address, amount_in: uint256) -> (address, uint24, uint256):
    if amount_in == 0:
        return empty(address), 0, 0

    pair_key: bytes32 = self._pair_key(token_in, token_out)
    best_pool: address = empty(address)
    best_fee: uint24 = 0
    best_out: uint256 = 0

    pool_count: uint256 = len(self.pools)
    for i: uint256 in range(MAX_POOLS):
        if i >= pool_count:
            break

        pool: address = self.pools[i]
        if self.pool_pair_key[pool] != pair_key:
            continue

        out_i: uint256 = self._quote_single_pool(pool, token_in, token_out, amount_in)
        if out_i > best_out:
            best_pool = pool
            best_fee = self.pool_fee[pool]
            best_out = out_i

    return best_pool, best_fee, best_out


@internal
@view
def _quote_single_pool(pool: address, token_in: address, token_out: address, amount_in: uint256) -> uint256:
    if pool == empty(address) or amount_in == 0 or not self.pool_registered[pool]:
        return 0

    fee: uint24 = self.pool_fee[pool]
    if fee == 0:
        return 0

    return self._quote_with_quoter(token_in, token_out, amount_in, fee)


@internal
@view
def _quote_with_quoter(token_in: address, token_out: address, amount_in: uint256, fee: uint24) -> uint256:
    if self.quoter == empty(address):
        return 0

    call_data: Bytes[164] = concat(
        method_id("quoteExactInputSingle((address,address,uint256,uint24,uint160))"),
        convert(token_in, bytes32),
        convert(token_out, bytes32),
        convert(amount_in, bytes32),
        convert(convert(fee, uint256), bytes32),
        convert(0, bytes32),
    )

    ok: bool = False
    response: Bytes[128] = empty(Bytes[128])
    ok, response = raw_call(
        self.quoter,
        call_data,
        gas=QUOTER_GAS_LIMIT,
        max_outsize=128,
        is_static_call=True,
        revert_on_failure=False,
    )
    if not ok or len(response) < 32:
        return 0

    return convert(slice(response, 0, 32), uint256)


@internal
@view
def _direction(pool: address, token_in: address, token_out: address) -> (bool, bool):
    token0: address = staticcall UniswapV3Pool(pool).token0()
    token1: address = staticcall UniswapV3Pool(pool).token1()

    if token_in == token0 and token_out == token1:
        return True, True
    if token_in == token1 and token_out == token0:
        return False, True
    return False, False


@internal
@pure
def _pair_key(token_a: address, token_b: address) -> bytes32:
    if convert(token_a, uint256) < convert(token_b, uint256):
        return keccak256(concat(convert(token_a, bytes32), convert(token_b, bytes32)))
    return keccak256(concat(convert(token_b, bytes32), convert(token_a, bytes32)))


@internal
def _only_owner():
    assert msg.sender == self.owner, "ONLY_OWNER"


@internal
def _clear_pending():
    self.ts_active = False
    self.ts_pool = empty(address)
    self.ts_received_out = 0
