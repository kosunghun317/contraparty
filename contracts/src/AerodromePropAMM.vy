# pragma version ^0.4.1
# @license MIT

# AerodromePropAMM
# Pull-based adapter used by Contraparty.
# 1) Contraparty calls quote() to pick best volatile/stable pool.
# 2) Contraparty calls swap(), AMM pulls token_in from Contraparty.
# 3) AMM executes direct pool swap and approves token_out for pull-settlement.


interface ERC20:
    def transferFrom(sender: address, receiver: address, amount: uint256) -> bool: nonpayable
    def transfer(receiver: address, amount: uint256) -> bool: nonpayable
    def approve(spender: address, amount: uint256) -> bool: nonpayable
    def allowance(owner: address, spender: address) -> uint256: view
    def balanceOf(account: address) -> uint256: view


interface AerodromeFactory:
    def getPool(tokenA: address, tokenB: address, stable: bool) -> address: view


interface AerodromePool:
    def token0() -> address: view
    def token1() -> address: view
    def swap(amount0Out: uint256, amount1Out: uint256, to: address, data: Bytes[1]): nonpayable


owner: public(address)
factory: public(address)


@deploy
def __init__(factory_: address):
    self.owner = msg.sender
    self.factory = factory_


@external
@view
def quote(token_in: address, token_out: address, amount_in: uint256) -> uint256:
    _pool: address = empty(address)
    quoted_out: uint256 = 0
    _pool, quoted_out = self._best_pool(token_in, token_out, amount_in)
    return quoted_out


@external
def swap(token_in: address, token_out: address, amount_in: uint256, min_amount_out: uint256) -> uint256:
    assert amount_in > 0, "AMOUNT_IN_ZERO"

    best_pool: address = empty(address)
    quoted_out: uint256 = 0
    best_pool, quoted_out = self._best_pool(token_in, token_out, amount_in)
    assert best_pool != empty(address), "NO_POOL"
    assert quoted_out >= min_amount_out, "NO_ROUTE_OR_LOW_QUOTE"

    token0: address = staticcall AerodromePool(best_pool).token0()
    token1: address = staticcall AerodromePool(best_pool).token1()
    assert (token_in == token0 and token_out == token1) or (token_in == token1 and token_out == token0), "BAD_POOL"

    # Pull input from Contraparty and fund selected pool.
    assert extcall ERC20(token_in).transferFrom(msg.sender, self, amount_in), "TRANSFER_FROM_FAIL"
    assert extcall ERC20(token_in).transfer(best_pool, amount_in), "PAY_POOL_FAIL"

    amount_out_before: uint256 = staticcall ERC20(token_out).balanceOf(self)

    amount0_out: uint256 = 0
    amount1_out: uint256 = 0
    if token_out == token0:
        amount0_out = quoted_out
    else:
        amount1_out = quoted_out

    extcall AerodromePool(best_pool).swap(amount0_out, amount1_out, self, b"")

    amount_out_after: uint256 = staticcall ERC20(token_out).balanceOf(self)
    assert amount_out_after >= amount_out_before, "BAD_BALANCE_DELTA"
    amount_out: uint256 = amount_out_after - amount_out_before
    assert amount_out >= min_amount_out, "MIN_AMOUNT_OUT"

    current_allowance: uint256 = staticcall ERC20(token_out).allowance(self, msg.sender)
    if current_allowance != 0:
        assert extcall ERC20(token_out).approve(msg.sender, 0), "APPROVE_RESET_FAIL"
    assert extcall ERC20(token_out).approve(msg.sender, amount_out), "APPROVE_OUT_FAIL"

    return amount_out


@external
def pull_accrued(token: address, amount: uint256 = 0, recipient: address = msg.sender) -> uint256:
    self._only_owner()
    assert token != empty(address), "ZERO_TOKEN"
    assert recipient != empty(address), "ZERO_RECIPIENT"

    pull_amount: uint256 = amount
    if pull_amount == 0:
        pull_amount = staticcall ERC20(token).balanceOf(self)
    assert pull_amount > 0, "ZERO_AMOUNT"

    assert extcall ERC20(token).transfer(recipient, pull_amount), "PULL_FAIL"
    return pull_amount


@internal
@view
def _best_pool(token_in: address, token_out: address, amount_in: uint256) -> (address, uint256):
    if amount_in == 0:
        return empty(address), 0

    volatile_pool: address = staticcall AerodromeFactory(self.factory).getPool(token_in, token_out, False)
    stable_pool: address = staticcall AerodromeFactory(self.factory).getPool(token_in, token_out, True)

    volatile_out: uint256 = self._quote_pool(volatile_pool, token_in, amount_in)
    stable_out: uint256 = self._quote_pool(stable_pool, token_in, amount_in)

    if volatile_out >= stable_out:
        return volatile_pool, volatile_out
    return stable_pool, stable_out


@internal
@view
def _quote_pool(pool: address, token_in: address, amount_in: uint256) -> uint256:
    if pool == empty(address) or amount_in == 0:
        return 0

    call_data: Bytes[68] = concat(
        method_id("getAmountOut(uint256,address)"),
        convert(amount_in, bytes32),
        convert(token_in, bytes32),
    )

    ok: bool = False
    response: Bytes[32] = empty(Bytes[32])
    ok, response = raw_call(
        pool,
        call_data,
        max_outsize=32,
        is_static_call=True,
        revert_on_failure=False,
    )
    if not ok or len(response) < 32:
        return 0

    return convert(slice(response, 0, 32), uint256)


@internal
def _only_owner():
    assert msg.sender == self.owner, "ONLY_OWNER"
