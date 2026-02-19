// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";

contract MegaethForkSmokeTest is TestBase {
    function testForkSmoke_MegaethChainAvailable() public {
        vm.createSelectFork("megaeth");
        assertEq(block.chainid, 4326, "unexpected chain id");
        assertGt(block.number, 0, "empty chain");
    }
}
