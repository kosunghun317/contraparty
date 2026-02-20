// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

interface IPropAMMAccruedPull {
    function pull_accrued(address token, uint256 amount, address recipient) external returns (uint256);
}

contract PropAMMAccruedPullTest is TestBase {
    address private owner;
    address private attacker = address(0xBAD);

    MockERC20 private token;

    function setUp() public {
        owner = address(this);
        token = new MockERC20("Test Token", "TEST", 18);
    }

    function testUniswapV3PropAMM_OwnerCanPullAccrued() public {
        address amm = vm.deployCode("src/UniswapV3PropAMM.vy", abi.encode(address(0x1234)));
        _assertPullIsOwnerOnly(amm);
    }

    function testUniswapV2PropAMM_OwnerCanPullAccrued() public {
        address amm = vm.deployCode("src/UniswapV2PropAMM.vy", abi.encode(address(0x5678)));
        _assertPullIsOwnerOnly(amm);
    }

    function testAerodromePropAMM_OwnerCanPullAccrued() public {
        address amm = vm.deployCode("src/AerodromePropAMM.vy", abi.encode(address(0x9ABC)));
        _assertPullIsOwnerOnly(amm);
    }

    function _assertPullIsOwnerOnly(address amm) internal {
        token.mint(amm, 777);

        vm.prank(attacker);
        (bool attackerOk,) =
            amm.call(abi.encodeWithSelector(IPropAMMAccruedPull.pull_accrued.selector, address(token), 0, attacker));
        assertTrue(!attackerOk, "non-owner pull must fail");

        uint256 pulled = IPropAMMAccruedPull(amm).pull_accrued(address(token), 0, owner);
        assertEq(pulled, 777, "owner should pull full accrued amount when amount=0");
        assertEq(token.balanceOf(owner), 777, "owner should receive accrued tokens");
        assertEq(token.balanceOf(amm), 0, "amm accrued balance should be emptied");
    }
}

