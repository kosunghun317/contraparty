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

interface IUniswapV3Pool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function fee() external view returns (uint24);
}

interface ICanonicMAOB {
    function baseToken() external view returns (address);
    function quoteToken() external view returns (address);
    function marketState() external view returns (uint8);
}

contract ContrapartyMegaethForkTest is TestBase {
    address private constant WETH = 0x4200000000000000000000000000000000000006;
    address private constant USDM = 0xFAfDdbb3FC7688494971a79cc65DCa3EF82079E7;
    address private constant USDT0 = 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb;
    address private constant BTCB = 0xB0F70C0bD6FD87dbEb7C10dC692a2a6106817072;
    uint256 private constant LARGE_SWAP_AMOUNT = 10 ether;
    uint256 private constant INITIAL_WETH = 20 ether;

    address private constant PRISM_FACTORY = 0x1adb8f973373505bB206e0E5D87af8FB1f5514Ef;
    address private constant KUMBAYA_FACTORY = 0x68b34591f662508076927803c567Cc8006988a09;
    address private constant PRISM_WETH_USDM_POOL = 0xC2FaC0B5B6C075819E654bcFbBBCda2838609d32;
    address private constant KUMBAYA_WETH_USDM_POOL = 0x587F6eeAfc7Ad567e96eD1B62775fA6402164b22;
    address private constant KUMBAYA_WETH_USDT0_POOL = 0x2809696F2e42eB452C32C3d0A2Dc540858C14125;
    address private constant KUMBAYA_BTCB_USDM_POOL = 0xc1838B7807e5bd4D56EA630BA35Ac964CF72c9db;
    address private constant KUMBAYA_USDT0_USDM_POOL = 0x6c8E5D463a2473b1A8bcd87e1cEA2724203A1D8f;
    address private constant CANONIC_MAOB_WETH_USDM = 0x23469683e25b780DFDC11410a8e83c923caDF125;
    address private constant CANONIC_MAOB_BTCB_USDM = 0xaD7e5CBfB535ceC8d2E58Dca17b11d9bA76f555E;
    address private constant CANONIC_MAOB_USDT0_USDM = 0xDf1576c3C82C9f8B759C69f4cF256061C6Fe1f9e;
    uint24 private constant V3_FEE_3000 = 3000;
    uint24 private constant V3_FEE_100 = 100;
    address private prismViewQuoter;
    address private kumbayaViewQuoter;

    address private user = address(0xA11CE);

    address private contrapartyAddr;
    IContrapartyVyper private contraparty;
    address private prismAmm;
    address private kumbayaAmm;
    address private canonicWethUsdmAmm;
    address private canonicBtcbUsdmAmm;
    address private canonicUsdt0UsdmAmm;
    function setUp() public {
        vm.createSelectFork("megaeth");

        vm.label(WETH, "WETH_MEGAETH");
        vm.label(USDM, "USDM_MEGAETH");
        vm.label(USDT0, "USDT0_MEGAETH");
        vm.label(BTCB, "BTCB_MEGAETH");
        vm.label(user, "USER_MEGAETH");
        vm.label(CANONIC_MAOB_WETH_USDM, "CANONIC_MAOB_WETH_USDM");
        vm.label(CANONIC_MAOB_BTCB_USDM, "CANONIC_MAOB_BTCB_USDM");
        vm.label(CANONIC_MAOB_USDT0_USDM, "CANONIC_MAOB_USDT0_USDM");

        _assertPoolInfo();
        _assertCanonicMarkets();

        prismViewQuoter = vm.deployCode("src/MegaethViewQuoter.sol", abi.encode(PRISM_FACTORY));
        kumbayaViewQuoter = vm.deployCode("src/MegaethViewQuoter.sol", abi.encode(KUMBAYA_FACTORY));
        vm.label(prismViewQuoter, "PRISM_VIEW_QUOTER_LOCAL");
        vm.label(kumbayaViewQuoter, "KUMBAYA_VIEW_QUOTER_LOCAL");

        contrapartyAddr = vm.deployCode("src/Contraparty.vy");
        contraparty = IContrapartyVyper(contrapartyAddr);
        prismAmm = vm.deployCode("src/UniswapV3PropAMM.vy", abi.encode(prismViewQuoter));
        kumbayaAmm = vm.deployCode("src/UniswapV3PropAMM.vy", abi.encode(kumbayaViewQuoter));
        canonicWethUsdmAmm = vm.deployCode("src/CanonicPropAMM.vy", abi.encode(CANONIC_MAOB_WETH_USDM));
        canonicBtcbUsdmAmm = vm.deployCode("src/CanonicPropAMM.vy", abi.encode(CANONIC_MAOB_BTCB_USDM));
        canonicUsdt0UsdmAmm = vm.deployCode("src/CanonicPropAMM.vy", abi.encode(CANONIC_MAOB_USDT0_USDM));
        vm.label(canonicWethUsdmAmm, "CANONIC_PROP_AMM_WETH_USDM");
        vm.label(canonicBtcbUsdmAmm, "CANONIC_PROP_AMM_BTCB_USDM");
        vm.label(canonicUsdt0UsdmAmm, "CANONIC_PROP_AMM_USDT0_USDM");

        IUniswapV3PropAMM(prismAmm).register_pool(PRISM_WETH_USDM_POOL, V3_FEE_3000);
        IUniswapV3PropAMM(kumbayaAmm).register_pool(KUMBAYA_WETH_USDM_POOL, V3_FEE_3000);
        IUniswapV3PropAMM(kumbayaAmm).register_pool(KUMBAYA_WETH_USDT0_POOL, V3_FEE_3000);
        IUniswapV3PropAMM(kumbayaAmm).register_pool(KUMBAYA_BTCB_USDM_POOL, V3_FEE_3000);
        IUniswapV3PropAMM(kumbayaAmm).register_pool(KUMBAYA_USDT0_USDM_POOL, V3_FEE_100);

        contraparty.register_amm(prismAmm);
        contraparty.register_amm(kumbayaAmm);
        contraparty.register_amm(canonicWethUsdmAmm);
        contraparty.register_amm(canonicBtcbUsdmAmm);
        contraparty.register_amm(canonicUsdt0UsdmAmm);

        _fundUserWeth();
    }

    function testForkMegaeth_ContrapartyQuoteWethUsdm() public view {
        uint256 amountIn = 0.1 ether;
        uint256 quoteOut = contraparty.quote(WETH, USDM, amountIn);
        assertGt(quoteOut, 0, "contraparty quote is zero");
    }

    function testForkMegaeth_ContrapartySwapWethToUsdmLarge() public {
        uint256 amountIn = LARGE_SWAP_AMOUNT;
        uint256 usdmBefore = IERC20(USDM).balanceOf(user);
        uint256 wethBefore = IERC20(WETH).balanceOf(user);
        uint256 quotedOut = contraparty.quote(WETH, USDM, amountIn);
        assertGt(quotedOut, 0, "zero quote");
        uint256 minUsdmOut = (quotedOut * 995) / 1000;

        vm.startPrank(user);
        IERC20(WETH).approve(contrapartyAddr, amountIn);
        uint256 usdmOut = contraparty.swap(WETH, USDM, amountIn, minUsdmOut, user);
        vm.stopPrank();

        uint256 usdmAfter = IERC20(USDM).balanceOf(user);
        uint256 wethAfter = IERC20(WETH).balanceOf(user);

        assertEq(wethAfter, wethBefore - amountIn, "incorrect WETH spent");
        assertGt(usdmOut, 0, "weth->usdm zero out");
        assertGt(usdmAfter, usdmBefore, "no net USDM received");
    }

    function testForkMegaeth_ContrapartyQuoteUsdt0ToUsdm() public view {
        uint256 amountIn = 1_000 * 1e6;
        uint256 quoteOut = contraparty.quote(USDT0, USDM, amountIn);
        assertGt(quoteOut, 0, "contraparty USDT0->USDM quote is zero");
    }

    function testForkMegaeth_ContrapartyQuoteBtcbToUsdm() public view {
        uint256 amountIn = 1 * 1e8;
        uint256 quoteOut = contraparty.quote(BTCB, USDM, amountIn);
        assertGt(quoteOut, 0, "contraparty BTCB->USDM quote is zero");
    }

    function _fundUserWeth() internal {
        deal(WETH, user, INITIAL_WETH);
    }

    function _assertPoolInfo() internal view {
        assertEq(IUniswapV3Pool(PRISM_WETH_USDM_POOL).token0(), WETH, "prism pool token0 mismatch");
        assertEq(IUniswapV3Pool(PRISM_WETH_USDM_POOL).token1(), USDM, "prism pool token1 mismatch");
        assertEq(IUniswapV3Pool(PRISM_WETH_USDM_POOL).fee(), V3_FEE_3000, "prism pool fee mismatch");

        assertEq(IUniswapV3Pool(KUMBAYA_WETH_USDM_POOL).token0(), WETH, "kumbaya weth/usdm token0 mismatch");
        assertEq(IUniswapV3Pool(KUMBAYA_WETH_USDM_POOL).token1(), USDM, "kumbaya weth/usdm token1 mismatch");
        assertEq(IUniswapV3Pool(KUMBAYA_WETH_USDM_POOL).fee(), V3_FEE_3000, "kumbaya weth/usdm fee mismatch");

        assertEq(IUniswapV3Pool(KUMBAYA_WETH_USDT0_POOL).token0(), WETH, "kumbaya weth/usdt0 token0 mismatch");
        assertEq(IUniswapV3Pool(KUMBAYA_WETH_USDT0_POOL).token1(), USDT0, "kumbaya weth/usdt0 token1 mismatch");
        assertEq(IUniswapV3Pool(KUMBAYA_WETH_USDT0_POOL).fee(), V3_FEE_3000, "kumbaya weth/usdt0 fee mismatch");

        assertEq(IUniswapV3Pool(KUMBAYA_BTCB_USDM_POOL).token0(), BTCB, "kumbaya btcb/usdm token0 mismatch");
        assertEq(IUniswapV3Pool(KUMBAYA_BTCB_USDM_POOL).token1(), USDM, "kumbaya btcb/usdm token1 mismatch");
        assertEq(IUniswapV3Pool(KUMBAYA_BTCB_USDM_POOL).fee(), V3_FEE_3000, "kumbaya btcb/usdm fee mismatch");

        assertEq(IUniswapV3Pool(KUMBAYA_USDT0_USDM_POOL).token0(), USDT0, "kumbaya usdt0/usdm token0 mismatch");
        assertEq(IUniswapV3Pool(KUMBAYA_USDT0_USDM_POOL).token1(), USDM, "kumbaya usdt0/usdm token1 mismatch");
        assertEq(IUniswapV3Pool(KUMBAYA_USDT0_USDM_POOL).fee(), V3_FEE_100, "kumbaya usdt0/usdm fee mismatch");
    }

    function _assertCanonicMarkets() internal view {
        assertEq(ICanonicMAOB(CANONIC_MAOB_WETH_USDM).baseToken(), WETH, "canonic weth/usdm base mismatch");
        assertEq(ICanonicMAOB(CANONIC_MAOB_WETH_USDM).quoteToken(), USDM, "canonic weth/usdm quote mismatch");
        assertEq(ICanonicMAOB(CANONIC_MAOB_WETH_USDM).marketState(), 0, "canonic weth/usdm halted");

        assertEq(ICanonicMAOB(CANONIC_MAOB_BTCB_USDM).baseToken(), BTCB, "canonic btcb/usdm base mismatch");
        assertEq(ICanonicMAOB(CANONIC_MAOB_BTCB_USDM).quoteToken(), USDM, "canonic btcb/usdm quote mismatch");
        assertEq(ICanonicMAOB(CANONIC_MAOB_BTCB_USDM).marketState(), 0, "canonic btcb/usdm halted");

        assertEq(ICanonicMAOB(CANONIC_MAOB_USDT0_USDM).baseToken(), USDT0, "canonic usdt0/usdm base mismatch");
        assertEq(ICanonicMAOB(CANONIC_MAOB_USDT0_USDM).quoteToken(), USDM, "canonic usdt0/usdm quote mismatch");
        assertEq(ICanonicMAOB(CANONIC_MAOB_USDT0_USDM).marketState(), 0, "canonic usdt0/usdm halted");
    }

}
