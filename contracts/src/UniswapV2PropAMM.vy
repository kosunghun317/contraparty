# pragma version ^0.4.1
# @license MIT

# UniswapV2PropAMM
# Pull-based adapter used by Contraparty.
# 1) Contraparty calls quote() to discover expected output.
# 2) Contraparty calls swap(), AMM pulls token_in from Contraparty.
# 3) AMM swaps through Uniswap V2 pair and approves token_out for pull-settlement.


interface ERC20:
    def transferFrom(sender: address, receiver: address, amount: uint256) -> bool: nonpayable
    def transfer(receiver: address, amount: uint256) -> bool: nonpayable
    def approve(spender: address, amount: uint256) -> bool: nonpayable
    def allowance(owner: address, spender: address) -> uint256: view
    def balanceOf(account: address) -> uint256: view


interface UniswapV2Factory:
    def getPair(tokenA: address, tokenB: address) -> address: view


interface UniswapV2Pair:
    def token0() -> address: view
    def token1() -> address: view
    def getReserves() -> (uint112, uint112, uint32): view
    def swap(amount0Out: uint256, amount1Out: uint256, to: address, data: Bytes[1]): nonpayable


FEE_NUMERATOR: constant(uint256) = 997
FEE_DENOMINATOR: constant(uint256) = 1000


owner: public(address)
factory: public(address)


@deploy
def __init__(factory_: address):
    self.owner = msg.sender
    self.factory = factory_


@external
@view
def quote(token_in: address, token_out: address, amount_in: uint256) -> uint256:
    pair: address = staticcall UniswapV2Factory(self.factory).getPair(token_in, token_out)
    quoted_out: uint256 = 0
    ok: bool = False
    quoted_out, ok = self._quote_pair(pair, token_in, token_out, amount_in)
    if not ok:
        return 0
    return quoted_out


@external
def swap(token_in: address, token_out: address, amount_in: uint256, min_amount_out: uint256) -> uint256:
    assert amount_in > 0, "AMOUNT_IN_ZERO"

    pair: address = staticcall UniswapV2Factory(self.factory).getPair(token_in, token_out)
    quoted_out: uint256 = 0
    ok: bool = False
    quoted_out, ok = self._quote_pair(pair, token_in, token_out, amount_in)
    assert ok and quoted_out >= min_amount_out, "NO_ROUTE_OR_LOW_QUOTE"

    token0: address = staticcall UniswapV2Pair(pair).token0()
    token1: address = staticcall UniswapV2Pair(pair).token1()
    assert (token_in == token0 and token_out == token1) or (token_in == token1 and token_out == token0), "BAD_POOL"

    # Pull input from Contraparty and fund the pair.
    assert extcall ERC20(token_in).transferFrom(msg.sender, self, amount_in), "TRANSFER_FROM_FAIL"
    assert extcall ERC20(token_in).transfer(pair, amount_in), "PAY_PAIR_FAIL"

    amount_out_before: uint256 = staticcall ERC20(token_out).balanceOf(self)

    amount0_out: uint256 = 0
    amount1_out: uint256 = 0
    if token_out == token0:
        amount0_out = quoted_out
    else:
        amount1_out = quoted_out

    extcall UniswapV2Pair(pair).swap(amount0_out, amount1_out, self, b"")

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
def _quote_pair(pair: address, token_in: address, token_out: address, amount_in: uint256) -> (uint256, bool):
    if pair == empty(address) or amount_in == 0:
        return 0, False

    token0: address = staticcall UniswapV2Pair(pair).token0()
    token1: address = staticcall UniswapV2Pair(pair).token1()
    reserve0: uint112 = 0
    reserve1: uint112 = 0
    _timestamp: uint32 = 0
    reserve0, reserve1, _timestamp = staticcall UniswapV2Pair(pair).getReserves()

    reserve_in: uint256 = 0
    reserve_out: uint256 = 0
    if token_in == token0 and token_out == token1:
        reserve_in = convert(reserve0, uint256)
        reserve_out = convert(reserve1, uint256)
    elif token_in == token1 and token_out == token0:
        reserve_in = convert(reserve1, uint256)
        reserve_out = convert(reserve0, uint256)
    else:
        return 0, False

    if reserve_in == 0 or reserve_out == 0:
        return 0, False

    amount_in_with_fee: uint256 = amount_in * FEE_NUMERATOR
    numerator: uint256 = amount_in_with_fee * reserve_out
    denominator: uint256 = reserve_in * FEE_DENOMINATOR + amount_in_with_fee
    if denominator == 0:
        return 0, False

    amount_out: uint256 = numerator // denominator
    return amount_out, amount_out > 0


@internal
def _only_owner():
    assert msg.sender == self.owner, "ONLY_OWNER"
