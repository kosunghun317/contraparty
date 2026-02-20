// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";

interface IViewQuoter {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
        external
        view
        returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate);
}

contract MegaethQuoterForkTest is TestBase {
    address private constant WETH = 0x4200000000000000000000000000000000000006;
    address private constant USDM = 0xFAfDdbb3FC7688494971a79cc65DCa3EF82079E7;
    address private constant PRISM_FACTORY = 0x1adb8f973373505bB206e0E5D87af8FB1f5514Ef;

    function testForkMegaeth_QuoterSingleQuoteTinyAmount() public {
        vm.createSelectFork("megaeth");
        IViewQuoter quoter = IViewQuoter(vm.deployCode("src/MegaethViewQuoter.sol", abi.encode(PRISM_FACTORY)));

        IViewQuoter.QuoteExactInputSingleParams memory params = IViewQuoter.QuoteExactInputSingleParams({
            tokenIn: WETH,
            tokenOut: USDM,
            amountIn: 1 gwei,
            fee: 3000,
            sqrtPriceLimitX96: 0
        });

        (uint256 amountOut,,,) = quoter.quoteExactInputSingle(params);
        assertGt(amountOut, 0, "zero quote");
    }
}
