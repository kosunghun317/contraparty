# pragma version ^0.4.1
# @license MIT

# -----------------------------------------------------------------------------
# CanonicPropAMM
# -----------------------------------------------------------------------------
# Pull-based adapter for Canonic MAOB markets.
# - Contraparty calls quote() for a conservative output estimate.
# - Contraparty calls swap(); adapter pulls token_in from Contraparty,
#   executes MAOB taker flow, then approves token_out for pull-settlement.
#
# This adapter is intentionally conservative in quote math:
# - It applies a configurable safety haircut.
# - It returns 0 when market state/data indicates unsafe quoting.
# -----------------------------------------------------------------------------


interface ERC20:
    def transferFrom(sender: address, receiver: address, amount: uint256) -> bool: nonpayable
    def transfer(receiver: address, amount: uint256) -> bool: nonpayable
    def approve(spender: address, amount: uint256) -> bool: nonpayable
    def allowance(owner: address, spender: address) -> uint256: view
    def balanceOf(account: address) -> uint256: view


interface CanonicMAOB:
    def baseToken() -> address: view
    def quoteToken() -> address: view
    def getMidPrice() -> (uint256, uint256, uint48): view
    def rungCount() -> uint256: view
    def bpsRungs(i: uint256) -> uint16: view
    def getRungState(rung: uint16) -> (uint256, uint256, uint32, uint32, uint256, uint256): view
    def quoteScale() -> uint256: view
    def baseScale() -> uint256: view
    def takerFee() -> uint32: view
    def FEE_DENOM() -> uint32: view
    def minQuoteTaker() -> uint256: view
    def RUNG_DENOM() -> uint32: view
    def PRICE_SIGFIGS() -> uint8: view
    def marketState() -> uint8: view
    def sellBaseTargetIn(baseAmount: uint256, minQuoteOut: uint256, deadline: uint64, minQuotePerRung: uint256) -> (uint256, uint256): nonpayable
    def buyBaseTargetIn(quoteIn: uint256, minBaseOut: uint256, deadline: uint64, minQuotePerRung: uint256) -> (uint256, uint256): nonpayable


event AccruedPulled:
    token: address
    recipient: address
    amount: uint256


event QuoteHaircutUpdated:
    old_haircut_bps: uint256
    new_haircut_bps: uint256


owner: public(address)
maob: public(address)
quote_haircut_bps: public(uint256)


MAX_RUNGS: constant(uint256) = 64
BPS_DENOM: constant(uint256) = 10_000
DEFAULT_QUOTE_HAIRCUT_BPS: constant(uint256) = 9_990
MIN_QUOTE_HAIRCUT_BPS: constant(uint256) = 9_500
MAX_QUOTE_HAIRCUT_BPS: constant(uint256) = 10_000

MARKET_HALTED: constant(uint8) = 1

MODE_INVALID: constant(uint256) = 0
MODE_SELL_BASE_TO_QUOTE: constant(uint256) = 1
MODE_BUY_QUOTE_TO_BASE: constant(uint256) = 2


@deploy
def __init__(maob_: address):
    assert maob_ != empty(address), "ZERO_MAOB"
    self.owner = msg.sender
    self.maob = maob_
    self.quote_haircut_bps = DEFAULT_QUOTE_HAIRCUT_BPS


@external
@view
def quote(token_in: address, token_out: address, amount_in: uint256) -> uint256:
    mode: uint256 = self._pair_mode(token_in, token_out)
    if mode == MODE_INVALID or amount_in == 0:
        return 0

    if not self._is_market_active():
        return 0

    if mode == MODE_SELL_BASE_TO_QUOTE:
        return self._quote_sell_base_to_quote(amount_in)

    return self._quote_buy_quote_to_base(amount_in)


@external
def swap(token_in: address, token_out: address, amount_in: uint256, min_amount_out: uint256) -> uint256:
    assert amount_in > 0, "AMOUNT_IN_ZERO"

    mode: uint256 = self._pair_mode(token_in, token_out)
    assert mode != MODE_INVALID, "BAD_PAIR"

    assert extcall ERC20(token_in).transferFrom(msg.sender, self, amount_in), "TRANSFER_FROM_FAIL"

    current_allowance: uint256 = staticcall ERC20(token_in).allowance(self, self.maob)
    if current_allowance != 0:
        assert extcall ERC20(token_in).approve(self.maob, 0), "APPROVE_RESET_FAIL"
    assert extcall ERC20(token_in).approve(self.maob, amount_in), "APPROVE_FAIL"

    amount_out: uint256 = 0
    if mode == MODE_SELL_BASE_TO_QUOTE:
        _quote_fee_paid: uint256 = 0
        amount_out, _quote_fee_paid = extcall CanonicMAOB(self.maob).sellBaseTargetIn(amount_in, min_amount_out, 0, 0)
    else:
        _base_fee_paid: uint256 = 0
        amount_out, _base_fee_paid = extcall CanonicMAOB(self.maob).buyBaseTargetIn(amount_in, min_amount_out, 0, 0)

    assert amount_out >= min_amount_out, "MIN_AMOUNT_OUT"

    current_allowance = staticcall ERC20(token_out).allowance(self, msg.sender)
    if current_allowance != 0:
        assert extcall ERC20(token_out).approve(msg.sender, 0), "APPROVE_OUT_RESET_FAIL"
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
    log AccruedPulled(token=token, recipient=recipient, amount=pull_amount)
    return pull_amount


@external
def set_quote_haircut_bps(new_haircut_bps: uint256):
    self._only_owner()
    assert new_haircut_bps >= MIN_QUOTE_HAIRCUT_BPS, "HAIRCUT_TOO_LOW"
    assert new_haircut_bps <= MAX_QUOTE_HAIRCUT_BPS, "HAIRCUT_TOO_HIGH"

    old_haircut_bps: uint256 = self.quote_haircut_bps
    self.quote_haircut_bps = new_haircut_bps
    log QuoteHaircutUpdated(old_haircut_bps=old_haircut_bps, new_haircut_bps=new_haircut_bps)


# -----------------------------------------------------------------------------
# Quote helpers
# -----------------------------------------------------------------------------
@internal
@view
def _quote_sell_base_to_quote(amount_in: uint256) -> uint256:
    min_quote_taker: uint256 = staticcall CanonicMAOB(self.maob).minQuoteTaker()

    mid_price: uint256 = 0
    precision: uint256 = 0
    updated_at: uint48 = 0
    mid_price, precision, updated_at = staticcall CanonicMAOB(self.maob).getMidPrice()
    if mid_price == 0 or precision == 0 or updated_at == 0:
        return 0

    quote_scale: uint256 = staticcall CanonicMAOB(self.maob).quoteScale()
    base_scale: uint256 = staticcall CanonicMAOB(self.maob).baseScale()
    if quote_scale == 0 or base_scale == 0:
        return 0

    if precision > max_value(uint256) // base_scale:
        return 0
    denom: uint256 = precision * base_scale
    if denom == 0:
        return 0

    # MAOB midpoint notional check for sellBaseTargetIn.
    if mid_price > max_value(uint256) // quote_scale:
        return 0
    sigfigs: uint8 = staticcall CanonicMAOB(self.maob).PRICE_SIGFIGS()
    mid_price_q_raw: uint256 = mid_price * quote_scale
    mid_price_q: uint256 = self._round_sigfig(mid_price_q_raw, sigfigs)
    if mid_price_q == 0:
        return 0
    quote_at_mid: uint256 = amount_in * mid_price_q // denom
    if quote_at_mid < min_quote_taker:
        return 0

    rung_count: uint256 = staticcall CanonicMAOB(self.maob).rungCount()
    if rung_count == 0:
        return 0

    rung_denom_u32: uint32 = staticcall CanonicMAOB(self.maob).RUNG_DENOM()
    if rung_denom_u32 == 0:
        return 0
    rung_denom: uint256 = convert(rung_denom_u32, uint256)

    remaining_base: uint256 = amount_in
    total_quote_gross: uint256 = 0

    for i: uint256 in range(MAX_RUNGS):
        if i >= rung_count or remaining_base == 0:
            break

        rung_bps_u16: uint16 = staticcall CanonicMAOB(self.maob).bpsRungs(i)
        rung_bps: uint256 = convert(rung_bps_u16, uint256)
        if rung_bps >= rung_denom:
            continue

        _ask_volume: uint256 = 0
        bid_volume: uint256 = 0
        _ask_generation: uint32 = 0
        _bid_generation: uint32 = 0
        _ask_cumulative: uint256 = 0
        _bid_cumulative: uint256 = 0
        _ask_volume, bid_volume, _ask_generation, _bid_generation, _ask_cumulative, _bid_cumulative = staticcall CanonicMAOB(self.maob).getRungState(convert(i, uint16))
        if bid_volume == 0:
            continue

        factor: uint256 = rung_denom - rung_bps
        if mid_price > max_value(uint256) // factor:
            continue
        rung_price: uint256 = (mid_price * factor) // rung_denom
        if rung_price == 0:
            continue

        if rung_price > max_value(uint256) // quote_scale:
            continue
        price_q: uint256 = self._round_sigfig(rung_price * quote_scale, sigfigs)
        if price_q == 0:
            continue

        base_available: uint256 = bid_volume * denom // price_q
        if base_available == 0:
            continue

        fill_base: uint256 = base_available
        if remaining_base < fill_base:
            fill_base = remaining_base

        quote_used: uint256 = fill_base * price_q // denom
        if fill_base == base_available and quote_used != bid_volume:
            quote_used = bid_volume

        remaining_base -= fill_base
        total_quote_gross += quote_used

    if remaining_base != 0 or total_quote_gross == 0:
        return 0

    taker_fee: uint256 = convert(staticcall CanonicMAOB(self.maob).takerFee(), uint256)
    fee_denom: uint256 = convert(staticcall CanonicMAOB(self.maob).FEE_DENOM(), uint256)
    if fee_denom == 0 or taker_fee >= fee_denom:
        return 0

    quote_fee: uint256 = self._ceil_div(total_quote_gross * taker_fee, fee_denom)
    if quote_fee >= total_quote_gross:
        return 0

    quote_net: uint256 = total_quote_gross - quote_fee
    quoted_out: uint256 = quote_net * self.quote_haircut_bps // BPS_DENOM
    return quoted_out


@internal
@view
def _quote_buy_quote_to_base(amount_in: uint256) -> uint256:
    min_quote_taker: uint256 = staticcall CanonicMAOB(self.maob).minQuoteTaker()
    if amount_in < min_quote_taker:
        return 0

    mid_price: uint256 = 0
    precision: uint256 = 0
    updated_at: uint48 = 0
    mid_price, precision, updated_at = staticcall CanonicMAOB(self.maob).getMidPrice()
    if mid_price == 0 or precision == 0 or updated_at == 0:
        return 0

    quote_scale: uint256 = staticcall CanonicMAOB(self.maob).quoteScale()
    base_scale: uint256 = staticcall CanonicMAOB(self.maob).baseScale()
    if quote_scale == 0 or base_scale == 0:
        return 0

    if precision > max_value(uint256) // base_scale:
        return 0
    denom: uint256 = precision * base_scale
    if denom == 0:
        return 0

    rung_count: uint256 = staticcall CanonicMAOB(self.maob).rungCount()
    if rung_count == 0:
        return 0

    rung_denom_u32: uint32 = staticcall CanonicMAOB(self.maob).RUNG_DENOM()
    if rung_denom_u32 == 0:
        return 0
    rung_denom: uint256 = convert(rung_denom_u32, uint256)

    sigfigs: uint8 = staticcall CanonicMAOB(self.maob).PRICE_SIGFIGS()
    remaining_quote: uint256 = amount_in
    base_gross: uint256 = 0

    for i: uint256 in range(MAX_RUNGS):
        if i >= rung_count or remaining_quote == 0:
            break

        ask_volume: uint256 = 0
        _bid_volume: uint256 = 0
        _ask_generation: uint32 = 0
        _bid_generation: uint32 = 0
        _ask_cumulative: uint256 = 0
        _bid_cumulative: uint256 = 0
        ask_volume, _bid_volume, _ask_generation, _bid_generation, _ask_cumulative, _bid_cumulative = staticcall CanonicMAOB(self.maob).getRungState(convert(i, uint16))
        if ask_volume == 0:
            continue

        rung_bps_u16: uint16 = staticcall CanonicMAOB(self.maob).bpsRungs(i)
        rung_bps: uint256 = convert(rung_bps_u16, uint256)
        if rung_bps > max_value(uint256) - rung_denom:
            continue

        factor: uint256 = rung_denom + rung_bps
        if mid_price > max_value(uint256) // factor:
            continue
        rung_price: uint256 = (mid_price * factor) // rung_denom
        if rung_price == 0:
            continue

        if rung_price > max_value(uint256) // quote_scale:
            continue
        price_q: uint256 = self._round_sigfig(rung_price * quote_scale, sigfigs)
        if price_q == 0:
            continue

        if ask_volume > max_value(uint256) // price_q:
            continue
        quote_for_full_ask: uint256 = self._ceil_div(ask_volume * price_q, denom)
        if quote_for_full_ask == 0:
            continue

        fill_base: uint256 = 0
        quote_used: uint256 = 0
        if remaining_quote >= quote_for_full_ask:
            fill_base = ask_volume
            quote_used = quote_for_full_ask
        else:
            fill_base = remaining_quote * denom // price_q
            if fill_base == 0:
                break
            # Conservative for partial rung: assume all remaining quote is consumed.
            quote_used = remaining_quote

        if fill_base > max_value(uint256) - base_gross:
            return 0

        base_gross += fill_base
        remaining_quote -= quote_used

    if base_gross == 0:
        return 0

    taker_fee: uint256 = convert(staticcall CanonicMAOB(self.maob).takerFee(), uint256)
    fee_denom: uint256 = convert(staticcall CanonicMAOB(self.maob).FEE_DENOM(), uint256)
    if fee_denom == 0 or taker_fee >= fee_denom:
        return 0

    base_fee: uint256 = self._ceil_div(base_gross * taker_fee, fee_denom)
    if base_fee >= base_gross:
        return 0

    base_net: uint256 = base_gross - base_fee
    quoted_out: uint256 = base_net * self.quote_haircut_bps // BPS_DENOM
    return quoted_out


# -----------------------------------------------------------------------------
# Generic helpers
# -----------------------------------------------------------------------------
@internal
@view
def _pair_mode(token_in: address, token_out: address) -> uint256:
    base_token: address = staticcall CanonicMAOB(self.maob).baseToken()
    quote_token: address = staticcall CanonicMAOB(self.maob).quoteToken()

    if token_in == base_token and token_out == quote_token:
        return MODE_SELL_BASE_TO_QUOTE
    if token_in == quote_token and token_out == base_token:
        return MODE_BUY_QUOTE_TO_BASE
    return MODE_INVALID


@internal
@view
def _is_market_active() -> bool:
    state: uint8 = staticcall CanonicMAOB(self.maob).marketState()
    return state != MARKET_HALTED


@internal
@pure
def _ceil_div(a: uint256, b: uint256) -> uint256:
    if a == 0:
        return 0
    return (a - 1) // b + 1


@internal
@pure
def _digits(val: uint256) -> uint256:
    if val == 0:
        return 1

    v: uint256 = val
    digits: uint256 = 0
    for _i: uint256 in range(78):
        if v == 0:
            break
        digits += 1
        v = v // 10
    return digits


@internal
@pure
def _pow10(exp: uint256) -> uint256:
    p: uint256 = 1
    for i: uint256 in range(78):
        if i >= exp:
            break
        p *= 10
    return p


@internal
@pure
def _round_sigfig(val: uint256, sigfigs: uint8) -> uint256:
    if val == 0:
        return 0
    if sigfigs == 0:
        return val

    digits: uint256 = self._digits(val)
    if digits <= convert(sigfigs, uint256):
        return val

    scale_digits: uint256 = digits - convert(sigfigs, uint256)
    scale: uint256 = self._pow10(scale_digits)
    return ((val + scale // 2) // scale) * scale


@internal
def _only_owner():
    assert msg.sender == self.owner, "ONLY_OWNER"
