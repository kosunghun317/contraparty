// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockLinearPropAMM} from "./mocks/MockPropAMMs.sol";

interface IContrapartyVyperFuzz {
    function register_amm(address amm) external;
    function swap(address token_in, address token_out, uint256 amount_in, uint256 min_amount_out, address recipient)
        external
        returns (uint256);
}

contract ContrapartyVyperFuzzTest is TestBase {
    IContrapartyVyperFuzz private contraparty;
    MockERC20 private weth;
    MockERC20 private usdc;
    MockLinearPropAMM private linearAmm;
    address private user = address(0xBEEF);

    function setUp() public {
        contraparty = IContrapartyVyperFuzz(vm.deployCode("src/Contraparty.vy"));
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        linearAmm = new MockLinearPropAMM(address(usdc), 10_000); // 1.0x by default.

        contraparty.register_amm(address(linearAmm));

        // Ensure AMM can always pay output in fuzz runs.
        usdc.mint(address(linearAmm), type(uint128).max);
    }

    function testFuzz_LinearRouteMatchesExpectedOutput(uint96 amountInRaw, uint16 bpsRaw) public {
        uint256 amountIn = _normalizeAmount(amountInRaw);
        uint256 quoteBps = uint256(bpsRaw % 20_000) + 1; // 0.01% .. 200%
        linearAmm.setQuoteBps(quoteBps);

        uint256 expectedOut = (amountIn * quoteBps) / 10_000;

        weth.mint(user, amountIn);
        vm.prank(user);
        weth.approve(address(contraparty), amountIn);

        if (expectedOut == 0) {
            vm.prank(user);
            (bool ok,) = address(contraparty).call(
                abi.encodeWithSelector(
                    IContrapartyVyperFuzz.swap.selector, address(weth), address(usdc), amountIn, 0, user
                )
            );
            assertTrue(!ok, "swap should fail when routed output rounds to zero");
            return;
        }

        vm.prank(user);
        uint256 amountOut = contraparty.swap(address(weth), address(usdc), amountIn, 0, user);

        assertEq(amountOut, expectedOut, "routed output should match linear quote math");
    }

    function testFuzz_MinAmountOutBoundary(uint96 amountInRaw, uint16 bpsRaw, uint96 extraRaw) public {
        uint256 amountIn = _normalizeAmount(amountInRaw);
        uint256 quoteBps = uint256(bpsRaw % 20_000) + 1;
        linearAmm.setQuoteBps(quoteBps);

        uint256 expectedOut = (amountIn * quoteBps) / 10_000;
        uint256 extra = uint256(extraRaw % 10_000);

        weth.mint(user, amountIn);
        vm.prank(user);
        weth.approve(address(contraparty), amountIn);

        uint256 minOut = expectedOut + extra;

        if (expectedOut == 0) {
            vm.prank(user);
            (bool okZeroQuote,) = address(contraparty).call(
                abi.encodeWithSelector(
                    IContrapartyVyperFuzz.swap.selector, address(weth), address(usdc), amountIn, minOut, user
                )
            );
            assertTrue(!okZeroQuote, "swap should fail when routed output rounds to zero");
            return;
        }

        if (minOut <= expectedOut) {
            vm.prank(user);
            uint256 amountOut = contraparty.swap(address(weth), address(usdc), amountIn, minOut, user);
            assertTrue(amountOut >= minOut, "successful swap must satisfy min out");
            return;
        }

        vm.prank(user);
        (bool okMinOut,) = address(contraparty).call(
            abi.encodeWithSelector(
                IContrapartyVyperFuzz.swap.selector, address(weth), address(usdc), amountIn, minOut, user
            )
        );
        assertTrue(!okMinOut, "swap should fail if minAmountOut is above possible output");
    }

    function _normalizeAmount(uint96 rawAmount) internal pure returns (uint256) {
        uint256 amount = uint256(rawAmount % 1_000_000_000_000);
        if (amount == 0) amount = 1;
        return amount;
    }
}
