# pragma version ~=0.4.3

number: public(uint256)
owner: public(address)


@deploy
def __init__():
    self.number = 0
    self.owner = msg.sender


@external
def set_number(new_number: uint256) -> bool:
    assert msg.sender == self, "not self"
    self.number = new_number
    return True

@external
def self_call(new_number: uint256):
    assert msg.sender == self.owner, "not owner"

    call_data: Bytes[4 + 32] = concat(
        method_id("set_number(uint256)"),
        convert(new_number, bytes32)
    )

    call_ok: bool = False
    raw_response: Bytes[32] = empty(Bytes[32])
    call_ok, raw_response = raw_call(
        self,
        call_data,
        max_outsize=32,
        value=0,
        gas=1_000_000,
        revert_on_failure=False
    )