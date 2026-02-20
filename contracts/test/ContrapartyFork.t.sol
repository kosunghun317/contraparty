// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TestBase} from "./TestBase.sol";

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IContrapartyVyper {
    function register_amm(address amm) external;
    function quote(address token_in, address token_out, uint256 amount_in) external view returns (uint256);
    function swap(address token_in, address token_out, uint256 amount_in, uint256 min_amount_out, address recipient)
        external
        returns (uint256);
}

interface IUniswapV3PropAMM {
    function register_pool(address pool, uint24 fee) external;
}

contract ContrapartyForkTest is TestBase {
    address private constant WETH = 0x4200000000000000000000000000000000000006;
    address private constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    address private constant UNISWAP_V3_VIEW_QUOTER =
        0x222cA98F00eD15B1faE10B61c277703a194cf5d2;
    address private constant UNISWAP_V3_WETH_USDC_POOL_500 =
        0xd0b53D9277642d899DF5C87A3966A349A798F224;
    address private constant UNISWAP_V3_WETH_USDC_POOL_3000 =
        0x6c561B446416E1A00E8E93E221854d6eA4171372;
    uint24 private constant V3_FEE_500 = 500;
    uint24 private constant V3_FEE_3000 = 3000;
    address private constant UNISWAP_V2_FACTORY =
        0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6;
    address private constant AERODROME_FACTORY =
        0x420DD381b31aEf6683db6B902084cB0FFECe40Da;

    address private user = address(0xBEEF);

    address private contrapartyAddr;
    IContrapartyVyper private contraparty;
    address private uniswapAmm;
    address private uniswapV2Amm;
    address private aerodromeAmm;

    function setUp() public {
        vm.createSelectFork("base");

        vm.label(WETH, "WETH_BASE");
        vm.label(USDC, "USDC_BASE");
        vm.label(user, "USER");

        contrapartyAddr = vm.deployCode("src/Contraparty.vy");
        contraparty = IContrapartyVyper(contrapartyAddr);
        uniswapAmm = vm.deployCode("src/UniswapV3PropAMM.vy", abi.encode(UNISWAP_V3_VIEW_QUOTER));
        IUniswapV3PropAMM(uniswapAmm).register_pool(UNISWAP_V3_WETH_USDC_POOL_500, V3_FEE_500);
        IUniswapV3PropAMM(uniswapAmm).register_pool(UNISWAP_V3_WETH_USDC_POOL_3000, V3_FEE_3000);
        uniswapV2Amm = vm.deployCode("src/UniswapV2PropAMM.vy", abi.encode(UNISWAP_V2_FACTORY));
        aerodromeAmm = vm.deployCode("src/AerodromePropAMM.vy", abi.encode(AERODROME_FACTORY));

        contraparty.register_amm(uniswapAmm);
        contraparty.register_amm(uniswapV2Amm);
        contraparty.register_amm(aerodromeAmm);

        _fundUserWeth();
    }

    function testFork_ContrapartyQuoteWethUsdc() public view {
        uint256 amountIn = 0.01 ether;
        uint256 quoteOut = contraparty.quote(WETH, USDC, amountIn);
        assertGt(quoteOut, 0, "contraparty quote is zero");
    }

    function testFork_ContrapartySwapWethToUsdcAndBack() public {
        uint256 amountIn = 0.02 ether;
        uint256 usdcBefore = IERC20(USDC).balanceOf(user);
        uint256 wethBefore = IERC20(WETH).balanceOf(user);
        uint256 wethExpectedFloor = wethBefore - amountIn;
        uint256 minUsdcOut = (contraparty.quote(WETH, USDC, amountIn) * 995) / 1000;

        vm.startPrank(user);
        IERC20(WETH).approve(contrapartyAddr, amountIn);
        uint256 usdcOut = contraparty.swap(WETH, USDC, amountIn, minUsdcOut, user);

        uint256 usdcBackIn = usdcOut / 2;
        uint256 minWethOut = (contraparty.quote(USDC, WETH, usdcBackIn) * 995) / 1000;
        IERC20(USDC).approve(contrapartyAddr, usdcBackIn);
        uint256 wethOut = contraparty.swap(USDC, WETH, usdcBackIn, minWethOut, user);
        vm.stopPrank();

        uint256 usdcAfter = IERC20(USDC).balanceOf(user);
        uint256 wethAfter = IERC20(WETH).balanceOf(user);

        assertGt(usdcOut, 0, "weth->usdc zero out");
        assertGt(wethOut, 0, "usdc->weth zero out");
        assertGt(usdcAfter, usdcBefore, "no net USDC received");
        assertGt(wethAfter, wethExpectedFloor, "no WETH received on way back");
    }

    function _fundUserWeth() internal {
        deal(WETH, user, 1 ether);
    }
}
