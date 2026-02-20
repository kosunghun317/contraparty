// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockConstantPropAMM} from "./mocks/MockPropAMMs.sol";

interface IContrapartyV2 {
    function register_amm(address amm) external;
    function penalty_score(address amm) external view returns (uint256);
    function swap(address token_in, address token_out, uint256 amount_in, uint256 min_amount_out, address recipient)
        external
        returns (uint256);
}

contract ContrapartyV2Test is TestBase {
    uint256 private constant PENALTY_SCALE = 1e18;
    uint256 private constant SWAP_AMOUNT = 100;

    address private user = address(0xBEEF);

    IContrapartyV2 private contraparty;
    MockERC20 private weth;
    MockERC20 private usdc;

    function setUp() public {
        contraparty = IContrapartyV2(vm.deployCode("src/ContrapartyV2.vy"));
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);
    }

    function testSecondPrice_UsesSecondQuoteAtFullPenalty() public {
        MockConstantPropAMM winner = new MockConstantPropAMM(address(usdc), 150);
        MockConstantPropAMM runnerUp = new MockConstantPropAMM(address(usdc), 120);
        contraparty.register_amm(address(winner));
        contraparty.register_amm(address(runnerUp));

        usdc.mint(address(winner), 1_000_000);
        usdc.mint(address(runnerUp), 1_000_000);
        weth.mint(user, SWAP_AMOUNT);

        vm.startPrank(user);
        weth.approve(address(contraparty), SWAP_AMOUNT);
        uint256 amountOut = contraparty.swap(address(weth), address(usdc), SWAP_AMOUNT, 100, user);
        vm.stopPrank();

        // secondHighestScore = (120 - 100) * 1.0 = 20
        // secondHighestQuote = 100 + 20 = 120
        assertEq(amountOut, 120, "winner should be settled at second quote");
        assertEq(usdc.balanceOf(user), 120, "recipient should receive second-price amount");
    }

    function testSecondPrice_UsesPenalizedSecondScore() public {
        MockConstantPropAMM penalizedRunner = new MockConstantPropAMM(address(usdc), 220);
        MockConstantPropAMM winner = new MockConstantPropAMM(address(usdc), 150);

        contraparty.register_amm(address(penalizedRunner));
        contraparty.register_amm(address(winner));

        usdc.mint(address(penalizedRunner), 1_000_000);
        usdc.mint(address(winner), 1_000_000);
        weth.mint(user, SWAP_AMOUNT * 2);

        // First swap penalizes the high-quote AMM by making it revert.
        penalizedRunner.setMode(1);
        vm.startPrank(user);
        weth.approve(address(contraparty), SWAP_AMOUNT * 2);
        contraparty.swap(address(weth), address(usdc), SWAP_AMOUNT, 1, user);
        vm.stopPrank();

        uint256 penalized = contraparty.penalty_score(address(penalizedRunner));
        assertLt(penalized, PENALTY_SCALE, "runner should be penalized after revert");

        // Restore the runner and set a realistic quote for second-price calculation.
        penalizedRunner.setMode(0);
        penalizedRunner.setQuote(120);

        uint256 usdcBefore = usdc.balanceOf(user);
        vm.prank(user);
        uint256 amountOut = contraparty.swap(address(weth), address(usdc), SWAP_AMOUNT, 100, user);
        uint256 usdcDelta = usdc.balanceOf(user) - usdcBefore;

        // With penalty ~= 0.5:
        // secondHighestScore = (120 - 100) * 0.5 = 10
        // secondHighestQuote = 100 + 10 = 110
        assertEq(amountOut, 110, "settlement should use penalized second score");
        assertEq(usdcDelta, 110, "recipient should get penalized second-price amount");
    }

    function testSecondPrice_FloorsAtMinWhenSingleBid() public {
        MockConstantPropAMM onlyAmm = new MockConstantPropAMM(address(usdc), 130);
        contraparty.register_amm(address(onlyAmm));

        usdc.mint(address(onlyAmm), 1_000_000);
        weth.mint(user, SWAP_AMOUNT);

        vm.startPrank(user);
        weth.approve(address(contraparty), SWAP_AMOUNT);
        uint256 amountOut = contraparty.swap(address(weth), address(usdc), SWAP_AMOUNT, 100, user);
        vm.stopPrank();

        // No second bid => secondHighestScore = 0 => settlement = minAmountOut.
        assertEq(amountOut, 100, "single-bid auction should settle at user min");
    }

    function testSecondPrice_RevertsWhenNoQuoteMeetsMinOut() public {
        MockConstantPropAMM lowAmm = new MockConstantPropAMM(address(usdc), 99);
        contraparty.register_amm(address(lowAmm));

        usdc.mint(address(lowAmm), 1_000_000);
        weth.mint(user, SWAP_AMOUNT);

        vm.prank(user);
        weth.approve(address(contraparty), SWAP_AMOUNT);

        vm.prank(user);
        (bool ok,) = address(contraparty).call(
            abi.encodeWithSelector(
                IContrapartyV2.swap.selector, address(weth), address(usdc), SWAP_AMOUNT, 100, user
            )
        );
        assertTrue(!ok, "swap should fail if no candidate can satisfy minOut");
    }
}
