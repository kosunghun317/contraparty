# pragma version ^0.4.1
# @license MIT

# -----------------------------------------------------------------------------
# ContrapartyV2
# -----------------------------------------------------------------------------
# Execution model:
# - Ask each registered AMM for a quote for the full order size.
# - Score by (quote - user_min_out) * penalty and sort descending by score.
# - Apply second-price settlement for the winning AMM:
#   settlement_out = max(user_min_out, user_min_out + next_best_score)
# - For each candidate, call self-only try_fill_order() through raw_call.
# - If a candidate fails, penalize and continue. First success wins.
# -----------------------------------------------------------------------------


# -----------------------------------------------------------------------------
# External interfaces
# -----------------------------------------------------------------------------
interface ERC20:
    def transferFrom(sender: address, receiver: address, amount: uint256) -> bool: nonpayable
    def transfer(receiver: address, amount: uint256) -> bool: nonpayable
    def approve(spender: address, amount: uint256) -> bool: nonpayable
    def allowance(owner: address, spender: address) -> uint256: view
    def balanceOf(account: address) -> uint256: view


interface WrappedNative:
    def deposit(): payable
    def withdraw(amount: uint256): nonpayable


interface PropAMM:
    def quote(token_in: address, token_out: address, amount_in: uint256) -> uint256: view
    def swap(token_in: address, token_out: address, amount_in: uint256, min_amount_out: uint256) -> uint256: nonpayable


# -----------------------------------------------------------------------------
# Events
# -----------------------------------------------------------------------------
event AMMRegistered:
    amm: address


event AMMRemoved:
    amm: address


event PenaltyUpdated:
    amm: address
    new_penalty_score: uint256


event SwapRouted:
    user: address
    token_in: address
    token_out: address
    amount_in: uint256
    amount_out: uint256


# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------
MAX_AMMS: constant(uint256) = 16

PENALTY_SCALE: constant(uint256) = 10**18
PENALTY_RECOVERY_TIME: constant(uint256) = 600
RECOVERY_COEFF: constant(uint256) = PENALTY_SCALE // PENALTY_RECOVERY_TIME
QUOTE_OUT_CAP: constant(uint256) = 2**128 - 1

AMM_QUOTE_GAS_LIMIT: constant(uint256) = 1_000_000
TRY_FILL_GAS_LIMIT: constant(uint256) = 1_000_000
NATIVE_TOKEN_ADDRESS: constant(address) = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE


# -----------------------------------------------------------------------------
# Storage
# -----------------------------------------------------------------------------
owner: public(address)
WETH_ADDRESS: public(immutable(address))
amms: public(DynArray[address, MAX_AMMS])
penalty_score: public(HashMap[address, uint256])
penalty_last_update: public(HashMap[address, uint256])


# -----------------------------------------------------------------------------
# Constructor
# -----------------------------------------------------------------------------
@deploy
def __init__(weth_address: address):
    assert weth_address != empty(address), "ZERO_WETH"
    self.owner = msg.sender
    WETH_ADDRESS = weth_address


@external
@payable
def __default__():
    pass


# -----------------------------------------------------------------------------
# Core API
# -----------------------------------------------------------------------------
@external
@view
def quote(token_in: address, token_out: address, amount_in: uint256) -> uint256:
    execution_token_in: address = token_in
    execution_token_out: address = token_out
    if token_in == NATIVE_TOKEN_ADDRESS:
        execution_token_in = WETH_ADDRESS
    if token_out == NATIVE_TOKEN_ADDRESS:
        execution_token_out = WETH_ADDRESS

    if amount_in == 0 or execution_token_in == execution_token_out:
        return 0

    amm_count: uint256 = len(self.amms)
    if amm_count == 0:
        return 0

    best_out: uint256 = 0
    second_best_out: uint256 = 0
    for i: uint256 in range(MAX_AMMS):
        if i >= amm_count:
            break

        amm: address = self.amms[i]
        quoted_out: uint256 = self._quote_from_amm(amm, execution_token_in, execution_token_out, amount_in)
        if quoted_out > best_out:
            second_best_out = best_out
            best_out = quoted_out
        elif quoted_out > second_best_out:
            second_best_out = quoted_out

    # V2 quote reports the second-highest bid (second-price auction reference).
    return second_best_out


@external
@payable
@nonreentrant
def swap(
    token_in: address,
    token_out: address,
    amount_in: uint256,
    min_amount_out: uint256,
    recipient: address,
    deadline: uint256
) -> uint256:
    native_in: bool = token_in == NATIVE_TOKEN_ADDRESS
    native_out: bool = token_out == NATIVE_TOKEN_ADDRESS

    execution_token_in: address = token_in
    execution_token_out: address = token_out
    if native_in:
        execution_token_in = WETH_ADDRESS
    if native_out:
        execution_token_out = WETH_ADDRESS

    effective_amount_in: uint256 = amount_in
    if native_in:
        assert msg.value > 0, "NATIVE_IN_ZERO"
        assert amount_in == 0, "NATIVE_IN_AMOUNT"
        effective_amount_in = msg.value
    else:
        assert msg.value == 0, "UNEXPECTED_MSG_VALUE"

    assert effective_amount_in > 0, "AMOUNT_IN_ZERO"
    assert execution_token_in != execution_token_out, "SAME_TOKEN"
    assert recipient != empty(address), "ZERO_RECIPIENT"
    assert block.timestamp <= deadline, "DEADLINE_EXPIRED"

    amm_count: uint256 = len(self.amms)
    assert amm_count > 0, "NO_AMMS"

    token_in_balance_before: uint256 = staticcall ERC20(execution_token_in).balanceOf(self)
    if native_in:
        extcall WrappedNative(WETH_ADDRESS).deposit(value=msg.value)
    else:
        assert extcall ERC20(execution_token_in).transferFrom(msg.sender, self, effective_amount_in), "TRANSFER_FROM_FAIL"

    amms_local: DynArray[address, MAX_AMMS] = []
    quotes: DynArray[uint256, MAX_AMMS] = []
    scores: DynArray[uint256, MAX_AMMS] = []
    valid_quote_count: uint256 = 0

    amms_local, quotes, scores, valid_quote_count = self._build_quotes(
        execution_token_in, execution_token_out, effective_amount_in, min_amount_out, amm_count
    )
    amms_local, quotes, scores = self._sort_by_score(amms_local, quotes, scores, valid_quote_count)

    filled: bool = False
    amount_out: uint256 = 0
    filled, amount_out = self._try_fill_full_order(
        execution_token_in,
        execution_token_out,
        effective_amount_in,
        min_amount_out,
        amms_local,
        quotes,
        scores,
        valid_quote_count
    )

    assert filled, "ORDER_UNFILLED"
    assert amount_out >= min_amount_out, "MIN_AMOUNT_OUT"
    token_in_balance_after: uint256 = staticcall ERC20(execution_token_in).balanceOf(self)
    if token_in_balance_after > token_in_balance_before:
        leftover_in: uint256 = token_in_balance_after - token_in_balance_before
        if native_in:
            extcall WrappedNative(WETH_ADDRESS).withdraw(leftover_in)
            self._safe_send_native(msg.sender, leftover_in)
        else:
            assert extcall ERC20(execution_token_in).transfer(msg.sender, leftover_in), "REFUND_IN_FAIL"

    if native_out:
        extcall WrappedNative(WETH_ADDRESS).withdraw(amount_out)
        self._safe_send_native(recipient, amount_out)
    else:
        assert extcall ERC20(execution_token_out).transfer(recipient, amount_out), "TRANSFER_OUT_FAIL"

    log SwapRouted(
        user=msg.sender,
        token_in=token_in,
        token_out=token_out,
        amount_in=effective_amount_in,
        amount_out=amount_out,
    )

    return amount_out


@external
def try_fill_order(
    token_in: address,
    token_out: address,
    amount_in: uint256,
    amm: address,
    settlement_out: uint256,
    quoted_out: uint256
) -> uint256:
    assert msg.sender == self, "ONLY_SELF"
    assert amount_in > 0, "AMOUNT_IN_ZERO"
    assert settlement_out > 0, "ZERO_SETTLEMENT"
    assert quoted_out > 0, "ZERO_QUOTE"
    assert settlement_out <= quoted_out, "SETTLEMENT_GT_QUOTE"

    current_allowance: uint256 = staticcall ERC20(token_in).allowance(self, amm)
    if current_allowance != 0:
        assert extcall ERC20(token_in).approve(amm, 0), "APPROVE_RESET_FAIL"
    assert extcall ERC20(token_in).approve(amm, amount_in), "APPROVE_FAIL"

    amount_out: uint256 = extcall PropAMM(amm).swap(token_in, token_out, amount_in, settlement_out)
    assert amount_out >= settlement_out, "LOW_SWAP_OUT"

    # Pull only the clearing amount from the winning AMM (second-price settlement).
    assert extcall ERC20(token_out).transferFrom(amm, self, settlement_out), "PULL_OUT_FAIL"

    current_allowance = staticcall ERC20(token_in).allowance(self, amm)
    if current_allowance != 0:
        assert extcall ERC20(token_in).approve(amm, 0), "REVOKE_FAIL"

    return amount_out


# -----------------------------------------------------------------------------
# Admin
# -----------------------------------------------------------------------------
@external
def register_amm(amm: address):
    self._only_owner()

    assert amm != empty(address), "ZERO_ADDRESS"
    assert len(self.amms) < MAX_AMMS, "AMM_LIMIT"

    for i: uint256 in range(MAX_AMMS):
        if i >= len(self.amms):
            break
        assert self.amms[i] != amm, "AMM_EXISTS"

    self.amms.append(amm)
    if self.penalty_score[amm] == 0:
        self._update_penalty(amm, PENALTY_SCALE)

    log AMMRegistered(amm=amm)


@external
def remove_amm(amm: address):
    self._only_owner()

    amm_count: uint256 = len(self.amms)
    for i: uint256 in range(MAX_AMMS):
        if i >= amm_count:
            break

        if self.amms[i] == amm:
            if i < amm_count - 1:
                self.amms[i] = self.amms[amm_count - 1]
            self.amms.pop()
            log AMMRemoved(amm=amm)
            return

    assert False, "AMM_NOT_FOUND"


# -----------------------------------------------------------------------------
# Internal helpers
# -----------------------------------------------------------------------------
@internal
def _try_fill_full_order(
    token_in: address,
    token_out: address,
    amount_in: uint256,
    min_amount_out: uint256,
    amms_local: DynArray[address, MAX_AMMS],
    quotes: DynArray[uint256, MAX_AMMS],
    scores: DynArray[uint256, MAX_AMMS],
    amm_count: uint256
) -> (bool, uint256):
    for i: uint256 in range(MAX_AMMS):
        if i >= amm_count:
            break

        amm: address = amms_local[i]
        quoted_out: uint256 = quotes[i]
        second_best_score: uint256 = 0
        if i + 1 < amm_count:
            second_best_score = scores[i + 1]

        second_price_out: uint256 = min_amount_out + second_best_score
        settlement_out: uint256 = max(min_amount_out, second_price_out)
        assert settlement_out <= quoted_out, "CLEARING_GT_QUOTE"

        call_data: Bytes[196] = concat(
            method_id("try_fill_order(address,address,uint256,address,uint256,uint256)"),
            convert(token_in, bytes32),
            convert(token_out, bytes32),
            convert(amount_in, bytes32),
            convert(amm, bytes32),
            convert(settlement_out, bytes32),
            convert(quoted_out, bytes32),
        )

        ok: bool = False
        response: Bytes[32] = empty(Bytes[32])
        ok, response = raw_call(
            self,
            call_data,
            gas=TRY_FILL_GAS_LIMIT,
            max_outsize=32,
            revert_on_failure=False,
        )

        if not ok or len(response) != 32:
            self._apply_penalty(amm)
            continue

        raw_amount_out: uint256 = extract32(response, 0, output_type=uint256)
        if raw_amount_out < settlement_out:
            self._apply_penalty(amm)
            continue

        return True, settlement_out

    return False, 0


@internal
@view
def _build_quotes(
    token_in: address,
    token_out: address,
    amount_in: uint256,
    min_amount_out: uint256,
    amm_count: uint256
) -> (DynArray[address, MAX_AMMS], DynArray[uint256, MAX_AMMS], DynArray[uint256, MAX_AMMS], uint256):
    amms_local: DynArray[address, MAX_AMMS] = []
    quotes: DynArray[uint256, MAX_AMMS] = []
    scores: DynArray[uint256, MAX_AMMS] = []

    for i: uint256 in range(MAX_AMMS):
        if i >= amm_count:
            break

        amm: address = self.amms[i]
        quoted_out: uint256 = self._quote_from_amm(amm, token_in, token_out, amount_in)
        if quoted_out < min_amount_out:
            continue

        margin_above_min: uint256 = quoted_out - min_amount_out
        penalty: uint256 = self._effective_penalty(amm)
        weighted_score: uint256 = (margin_above_min * penalty) // PENALTY_SCALE

        amms_local.append(amm)
        quotes.append(quoted_out)
        scores.append(weighted_score)

    return amms_local, quotes, scores, len(amms_local)


@internal
@pure
def _sort_by_score(
    amms_local: DynArray[address, MAX_AMMS],
    quotes: DynArray[uint256, MAX_AMMS],
    scores: DynArray[uint256, MAX_AMMS],
    count: uint256
) -> (DynArray[address, MAX_AMMS], DynArray[uint256, MAX_AMMS], DynArray[uint256, MAX_AMMS]):
    for i: uint256 in range(MAX_AMMS):
        if i >= count:
            break

        best_index: uint256 = i
        for j: uint256 in range(MAX_AMMS):
            if j <= i:
                continue
            if j >= count:
                continue
            if scores[j] > scores[best_index]:
                best_index = j

        if best_index != i:
            tmp_amm: address = amms_local[i]
            amms_local[i] = amms_local[best_index]
            amms_local[best_index] = tmp_amm

            tmp_quote: uint256 = quotes[i]
            quotes[i] = quotes[best_index]
            quotes[best_index] = tmp_quote

            tmp_score: uint256 = scores[i]
            scores[i] = scores[best_index]
            scores[best_index] = tmp_score

    return amms_local, quotes, scores


@internal
@view
def _quote_from_amm(amm: address, token_in: address, token_out: address, amount_in: uint256) -> uint256:
    call_data: Bytes[100] = concat(
        method_id("quote(address,address,uint256)"),
        convert(token_in, bytes32),
        convert(token_out, bytes32),
        convert(amount_in, bytes32),
    )

    ok: bool = False
    response: Bytes[32] = empty(Bytes[32])
    ok, response = raw_call(
        amm,
        call_data,
        gas=AMM_QUOTE_GAS_LIMIT,
        max_outsize=32,
        is_static_call=True,
        revert_on_failure=False,
    )
    if not ok or len(response) != 32:
        return 0

    quoted_out: uint256 = extract32(response, 0, output_type=uint256)
    return min(quoted_out, QUOTE_OUT_CAP)


@internal
def _safe_send_native(recipient: address, amount: uint256):
    if amount == 0:
        return

    ok: bool = False
    return_data: Bytes[1] = empty(Bytes[1])
    ok, return_data = raw_call(
        recipient,
        b"",
        value=amount,
        max_outsize=1,
        revert_on_failure=False,
    )
    assert ok, "ETH_SEND_FAIL"


@internal
@view
def _effective_penalty(amm: address) -> uint256:
    stored_score: uint256 = self.penalty_score[amm]
    if stored_score == 0:
        stored_score = PENALTY_SCALE

    elapsed: uint256 = block.timestamp - self.penalty_last_update[amm]
    recovered: uint256 = stored_score + RECOVERY_COEFF * elapsed
    return self._clip(recovered, 0, PENALTY_SCALE)


@internal
def _apply_penalty(amm: address):
    current: uint256 = self._effective_penalty(amm)
    self._update_penalty(amm, current // 2)


@internal
def _update_penalty(amm: address, new_score: uint256):
    self.penalty_score[amm] = new_score
    self.penalty_last_update[amm] = block.timestamp
    log PenaltyUpdated(amm=amm, new_penalty_score=new_score)


@internal
@pure
def _clip(x: uint256, lower: uint256, upper: uint256) -> uint256:
    return min(max(x, lower), upper)


@internal
def _only_owner():
    assert msg.sender == self.owner, "ONLY_OWNER"
