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

AMM_QUOTE_GAS_LIMIT: constant(uint256) = 1_000_000
TRY_FILL_GAS_LIMIT: constant(uint256) = 1_000_000


# -----------------------------------------------------------------------------
# Storage
# -----------------------------------------------------------------------------
owner: public(address)
amms: public(DynArray[address, MAX_AMMS])
penalty_score: public(HashMap[address, uint256])
penalty_last_update: public(HashMap[address, uint256])


# -----------------------------------------------------------------------------
# Constructor
# -----------------------------------------------------------------------------
@deploy
def __init__():
    self.owner = msg.sender


# -----------------------------------------------------------------------------
# Core API
# -----------------------------------------------------------------------------
@external
@view
def quote(token_in: address, token_out: address, amount_in: uint256) -> uint256:
    if amount_in == 0 or token_in == token_out:
        return 0

    amm_count: uint256 = len(self.amms)
    if amm_count == 0:
        return 0

    best_out: uint256 = 0
    for i: uint256 in range(MAX_AMMS):
        if i >= amm_count:
            break

        amm: address = self.amms[i]
        quoted_out: uint256 = self._quote_from_amm(amm, token_in, token_out, amount_in)
        if quoted_out > best_out:
            best_out = quoted_out

    return best_out


@external
@nonreentrant
def swap(
    token_in: address,
    token_out: address,
    amount_in: uint256,
    min_amount_out: uint256,
    recipient: address = msg.sender
) -> uint256:
    assert amount_in > 0, "AMOUNT_IN_ZERO"
    assert token_in != token_out, "SAME_TOKEN"
    assert recipient != empty(address), "ZERO_RECIPIENT"

    amm_count: uint256 = len(self.amms)
    assert amm_count > 0, "NO_AMMS"

    assert extcall ERC20(token_in).transferFrom(msg.sender, self, amount_in), "TRANSFER_FROM_FAIL"

    amms_local: DynArray[address, MAX_AMMS] = []
    quotes: DynArray[uint256, MAX_AMMS] = []
    scores: DynArray[uint256, MAX_AMMS] = []
    valid_quote_count: uint256 = 0

    amms_local, quotes, scores, valid_quote_count = self._build_quotes(
        token_in, token_out, amount_in, min_amount_out, amm_count
    )
    amms_local, quotes, scores = self._sort_by_score(amms_local, quotes, scores, valid_quote_count)

    filled: bool = False
    amount_out: uint256 = 0
    filled, amount_out = self._try_fill_full_order(
        token_in, token_out, amount_in, min_amount_out, amms_local, quotes, scores, valid_quote_count
    )

    assert filled, "ORDER_UNFILLED"
    assert amount_out >= min_amount_out, "MIN_AMOUNT_OUT"
    assert extcall ERC20(token_out).transfer(recipient, amount_out), "TRANSFER_OUT_FAIL"

    log SwapRouted(
        user=msg.sender,
        token_in=token_in,
        token_out=token_out,
        amount_in=amount_in,
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

    return extract32(response, 0, output_type=uint256)


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
