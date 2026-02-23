// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockConstantPropAMM} from "./mocks/MockPropAMMs.sol";
import {MockWETH9} from "./mocks/MockWETH9.sol";

interface IContrapartyV2 {
    function register_amm(address amm) external;
    function quote(address token_in, address token_out, uint256 amount_in) external view returns (uint256);
    function penalty_score(address amm) external view returns (uint256);
    function WETH_ADDRESS() external view returns (address);
    function swap(
        address token_in,
        address token_out,
        uint256 amount_in,
        uint256 min_amount_out,
        address recipient,
        uint256 deadline
    ) external payable returns (uint256);
}

contract ContrapartyV2Test is TestBase {
    uint256 private constant PENALTY_SCALE = 1e18;
    uint256 private constant SWAP_AMOUNT = 100;
    address private constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address private user = address(0xBEEF);

    IContrapartyV2 private contraparty;
    MockWETH9 private weth;
    MockERC20 private usdc;

    function setUp() public {
        weth = new MockWETH9();
        usdc = new MockERC20("USD Coin", "USDC", 6);
        contraparty = IContrapartyV2(vm.deployCode("src/ContrapartyV2.vy", abi.encode(address(weth))));
    }

    function testConstructor_SetsWethAddress() public view {
        assertEq(contraparty.WETH_ADDRESS(), address(weth), "unexpected weth address");
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
        uint256 amountOut =
            contraparty.swap(address(weth), address(usdc), SWAP_AMOUNT, 100, user, block.timestamp + 1);
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
        contraparty.swap(address(weth), address(usdc), SWAP_AMOUNT, 1, user, block.timestamp + 1);
        vm.stopPrank();

        uint256 penalized = contraparty.penalty_score(address(penalizedRunner));
        assertLt(penalized, PENALTY_SCALE, "runner should be penalized after revert");

        // Restore the runner and set a realistic quote for second-price calculation.
        penalizedRunner.setMode(0);
        penalizedRunner.setQuote(120);

        uint256 usdcBefore = usdc.balanceOf(user);
        vm.prank(user);
        uint256 amountOut =
            contraparty.swap(address(weth), address(usdc), SWAP_AMOUNT, 100, user, block.timestamp + 1);
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
        uint256 amountOut =
            contraparty.swap(address(weth), address(usdc), SWAP_AMOUNT, 100, user, block.timestamp + 1);
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
                IContrapartyV2.swap.selector, address(weth), address(usdc), SWAP_AMOUNT, 100, user, block.timestamp + 1
            )
        );
        assertTrue(!ok, "swap should fail if no candidate can satisfy minOut");
    }

    function testQuote_ReturnsSecondHighestBid() public {
        MockConstantPropAMM high = new MockConstantPropAMM(address(usdc), 170);
        MockConstantPropAMM mid = new MockConstantPropAMM(address(usdc), 150);
        MockConstantPropAMM low = new MockConstantPropAMM(address(usdc), 90);
        contraparty.register_amm(address(high));
        contraparty.register_amm(address(mid));
        contraparty.register_amm(address(low));

        uint256 quoted = contraparty.quote(address(weth), address(usdc), SWAP_AMOUNT);
        assertEq(quoted, 150, "quote should return second-highest bid");
    }

    function testDeadline_ExpiredSwapReverts() public {
        MockConstantPropAMM amm = new MockConstantPropAMM(address(usdc), 130);
        contraparty.register_amm(address(amm));

        usdc.mint(address(amm), 1_000_000);
        weth.mint(user, SWAP_AMOUNT);

        vm.prank(user);
        weth.approve(address(contraparty), SWAP_AMOUNT);

        vm.prank(user);
        (bool ok,) = address(contraparty).call(
            abi.encodeWithSelector(
                IContrapartyV2.swap.selector, address(weth), address(usdc), SWAP_AMOUNT, 100, user, block.timestamp - 1
            )
        );
        assertTrue(!ok, "swap should fail after deadline");
    }

    function testSwap_RefundsLeftoverInputToCaller() public {
        MockConstantPropAMM partialPullAmm = new MockConstantPropAMM(address(usdc), 130);
        partialPullAmm.setMode(5);
        partialPullAmm.setInputPullBps(7000); // Pull only 70% of input.
        contraparty.register_amm(address(partialPullAmm));

        usdc.mint(address(partialPullAmm), 1_000_000);
        weth.mint(user, SWAP_AMOUNT);

        uint256 userWethBefore = weth.balanceOf(user);

        vm.startPrank(user);
        weth.approve(address(contraparty), SWAP_AMOUNT);
        uint256 amountOut = contraparty.swap(address(weth), address(usdc), SWAP_AMOUNT, 100, user, block.timestamp + 1);
        vm.stopPrank();

        uint256 expectedPulled = (SWAP_AMOUNT * 7000) / 10_000;
        uint256 expectedRefund = SWAP_AMOUNT - expectedPulled;

        assertEq(amountOut, 100, "single-bid settlement should still clear at user min");
        assertEq(weth.balanceOf(user), userWethBefore - expectedPulled, "user should be refunded leftover input");
        assertEq(weth.balanceOf(address(partialPullAmm)), expectedPulled, "amm should only hold the pulled portion");
        assertEq(weth.balanceOf(address(contraparty)), 0, "contraparty should not retain token_in leftovers");
        assertEq(expectedRefund, 30, "sanity-check expected refund");
    }

    function testSwap_WrapsEthInputWhenTokenInIsNative() public {
        uint256 nativeAmount = 1 ether;

        MockConstantPropAMM onlyAmm = new MockConstantPropAMM(address(usdc), 130);
        contraparty.register_amm(address(onlyAmm));

        usdc.mint(address(onlyAmm), 1_000_000);
        vm.deal(user, nativeAmount);

        vm.prank(user);
        uint256 amountOut =
            contraparty.swap{value: nativeAmount}(NATIVE_TOKEN, address(usdc), 0, 100, user, block.timestamp + 1);

        assertEq(amountOut, 100, "single-bid settlement should still clear at user min");
        assertEq(weth.balanceOf(address(onlyAmm)), nativeAmount, "amm should receive wrapped eth input");
        assertEq(weth.balanceOf(user), 0, "user should not gain weth during wrap path");
    }

    function testSwap_RevertsWhenNativeTokenInHasNonZeroAmountParam() public {
        uint256 nativeAmount = 60;

        MockConstantPropAMM onlyAmm = new MockConstantPropAMM(address(usdc), 130);
        contraparty.register_amm(address(onlyAmm));

        usdc.mint(address(onlyAmm), 1_000_000);
        vm.deal(user, nativeAmount);

        vm.prank(user);
        (bool ok,) = address(contraparty).call{value: nativeAmount}(
            abi.encodeWithSelector(
                IContrapartyV2.swap.selector, NATIVE_TOKEN, address(usdc), 1, 100, user, block.timestamp + 1
            )
        );

        assertTrue(!ok, "swap should fail when amount_in is nonzero for native token input");
    }

    function testSwap_UnwrapsNativeOutputWhenTokenOutIsNative() public {
        uint256 usdcIn = 1_000_000;
        uint256 minNativeOut = 1 ether;
        uint256 backingNative = 5 ether;

        MockConstantPropAMM onlyAmm = new MockConstantPropAMM(address(weth), 2 ether);
        contraparty.register_amm(address(onlyAmm));

        vm.deal(address(onlyAmm), backingNative);
        vm.prank(address(onlyAmm));
        weth.deposit{value: backingNative}();

        usdc.mint(user, usdcIn);
        uint256 userEthBefore = user.balance;

        vm.startPrank(user);
        usdc.approve(address(contraparty), usdcIn);
        uint256 amountOut =
            contraparty.swap(address(usdc), NATIVE_TOKEN, usdcIn, minNativeOut, user, block.timestamp + 1);
        vm.stopPrank();

        assertEq(amountOut, minNativeOut, "single-bid settlement should clear at user min");
        assertEq(user.balance, userEthBefore + minNativeOut, "recipient should receive native ETH output");
    }

    function testSwap_RevertsWhenEthSentForNonNativeInput() public {
        MockConstantPropAMM onlyAmm = new MockConstantPropAMM(address(usdc), 130);
        contraparty.register_amm(address(onlyAmm));

        usdc.mint(address(onlyAmm), 1_000_000);
        usdc.mint(user, SWAP_AMOUNT);

        vm.startPrank(user);
        usdc.approve(address(contraparty), SWAP_AMOUNT);
        (bool ok,) = address(contraparty).call{value: 1}(
            abi.encodeWithSelector(
                IContrapartyV2.swap.selector, address(usdc), address(weth), SWAP_AMOUNT, 1, user, block.timestamp + 1
            )
        );
        vm.stopPrank();

        assertTrue(!ok, "swap should fail when native value is sent for non-weth token_in");
    }
}
