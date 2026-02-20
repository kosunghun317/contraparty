// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockConstantPropAMM, MockReentrantPropAMM} from "./mocks/MockPropAMMs.sol";

interface IContrapartyVyperSecurity {
    function register_amm(address amm) external;
    function remove_amm(address amm) external;
    function penalty_score(address amm) external view returns (uint256);
    function swap(address token_in, address token_out, uint256 amount_in, uint256 min_amount_out, address recipient)
        external
        returns (uint256);
}

contract ContrapartyVyperSecurityTest is TestBase {
    uint256 private constant PENALTY_SCALE = 1e18;
    uint256 private constant SWAP_AMOUNT = 800;

    address private owner;
    address private user = address(0xBEEF);
    address private attacker = address(0xBAD);

    IContrapartyVyperSecurity private contraparty;
    MockERC20 private weth;
    MockERC20 private usdc;

    function setUp() public {
        owner = address(this);
        contraparty = IContrapartyVyperSecurity(vm.deployCode("src/Contraparty.vy"));
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);
    }

    function testSecurity_OnlyOwnerCanRegisterAndRemove() public {
        MockConstantPropAMM amm = new MockConstantPropAMM(address(usdc), 100);

        _assertCallFailsAs(
            attacker,
            abi.encodeWithSelector(IContrapartyVyperSecurity.register_amm.selector, address(amm)),
            "non-owner should not register AMM"
        );

        contraparty.register_amm(address(amm));

        _assertCallFailsAs(
            attacker,
            abi.encodeWithSelector(IContrapartyVyperSecurity.remove_amm.selector, address(amm)),
            "non-owner should not remove AMM"
        );

        contraparty.remove_amm(address(amm));

        _assertCallFailsAs(
            owner,
            abi.encodeWithSelector(IContrapartyVyperSecurity.remove_amm.selector, address(amm)),
            "removing a missing AMM should fail"
        );
    }

    function testSecurity_PenalizesFailingAMMAndUsesFallback() public {
        MockConstantPropAMM failingAmm = new MockConstantPropAMM(address(usdc), 300);
        MockConstantPropAMM fallbackAmm = new MockConstantPropAMM(address(usdc), 120);
        failingAmm.setMode(1); // Always revert.

        contraparty.register_amm(address(failingAmm));
        contraparty.register_amm(address(fallbackAmm));

        usdc.mint(address(fallbackAmm), 1_000_000);
        weth.mint(user, SWAP_AMOUNT);

        vm.prank(user);
        weth.approve(address(contraparty), SWAP_AMOUNT);

        vm.prank(user);
        uint256 amountOut = contraparty.swap(address(weth), address(usdc), SWAP_AMOUNT, 1, user);

        assertEq(amountOut, 120, "fallback AMM should fill full order once");
        assertLt(
            contraparty.penalty_score(address(failingAmm)),
            PENALTY_SCALE,
            "failing AMM should be penalized below full score"
        );
    }

    function testSecurity_FailedAttemptDoesNotKeepInputFunds() public {
        MockConstantPropAMM failingAmm = new MockConstantPropAMM(address(usdc), 300);
        MockConstantPropAMM fallbackAmm = new MockConstantPropAMM(address(usdc), 120);
        failingAmm.setMode(4); // pull then revert

        contraparty.register_amm(address(failingAmm));
        contraparty.register_amm(address(fallbackAmm));

        usdc.mint(address(fallbackAmm), 1_000_000);
        weth.mint(user, SWAP_AMOUNT);

        vm.prank(user);
        weth.approve(address(contraparty), SWAP_AMOUNT);

        vm.prank(user);
        uint256 amountOut = contraparty.swap(address(weth), address(usdc), SWAP_AMOUNT, 1, user);

        assertEq(amountOut, 120, "fallback AMM should still fill full order");
        assertEq(weth.balanceOf(address(failingAmm)), 0, "failed AMM must not retain tokenIn");
        assertEq(weth.balanceOf(address(fallbackAmm)), SWAP_AMOUNT, "full input should remain available for fallback");
        assertEq(weth.balanceOf(address(contraparty)), 0, "Contraparty should not retain input after successful fill");
    }

    function testSecurity_ReentrancyAttemptIsBlocked() public {
        MockReentrantPropAMM reentrantAmm = new MockReentrantPropAMM(address(contraparty), address(usdc), 100);
        contraparty.register_amm(address(reentrantAmm));

        usdc.mint(address(reentrantAmm), 1_000_000);
        weth.mint(user, SWAP_AMOUNT);

        vm.prank(user);
        weth.approve(address(contraparty), SWAP_AMOUNT);

        vm.prank(user);
        uint256 amountOut = contraparty.swap(address(weth), address(usdc), SWAP_AMOUNT, 1, user);

        assertEq(amountOut, 100, "swap should still succeed while reentry is blocked");
    }

    function testSecurity_MinAmountOutEnforced() public {
        MockConstantPropAMM amm = new MockConstantPropAMM(address(usdc), 100);
        contraparty.register_amm(address(amm));

        usdc.mint(address(amm), 1_000_000);
        weth.mint(user, SWAP_AMOUNT);

        vm.prank(user);
        weth.approve(address(contraparty), SWAP_AMOUNT);

        _assertCallFailsAs(
            user,
            abi.encodeWithSelector(
                IContrapartyVyperSecurity.swap.selector, address(weth), address(usdc), SWAP_AMOUNT, 801, user
            ),
            "swap should fail when minAmountOut exceeds routed output"
        );
    }

    function _assertCallFailsAs(address caller, bytes memory data, string memory message) internal {
        vm.prank(caller);
        (bool ok,) = address(contraparty).call(data);
        assertTrue(!ok, message);
    }
}
