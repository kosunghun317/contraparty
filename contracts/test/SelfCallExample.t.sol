// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";

interface ISelfCallExample {
    function owner() external view returns (address);
    function number() external view returns (uint256);
    function set_number(uint256 newNumber) external returns (bool);
    function self_call(uint256 newNumber) external;
}

contract SelfCallExampleTest is TestBase {
    ISelfCallExample private example;
    address private attacker = address(0xBADD);

    function setUp() public {
        example = ISelfCallExample(vm.deployCode("src/selfCallExample.vy"));
    }

    function testAccessControl_OnlyOwnerCanTriggerSelfCall() public {
        assertEq(example.owner(), address(this), "owner mismatch");

        vm.prank(attacker);
        (bool ok,) = address(example).call(abi.encodeWithSelector(ISelfCallExample.self_call.selector, 123));
        assertTrue(!ok, "non-owner self_call must fail");
    }

    function testAccessControl_SetNumberOnlyCallableBySelf() public {
        (bool ok,) = address(example).call(abi.encodeWithSelector(ISelfCallExample.set_number.selector, 999));
        assertTrue(!ok, "direct set_number call must fail");
    }

    function testAccessControl_OwnerSelfCallUpdatesState() public {
        example.self_call(42);
        assertEq(example.number(), 42, "owner self_call should set number");
    }
}
