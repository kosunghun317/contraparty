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

contract ContrapartyMegaethForkTest is TestBase {
    address private constant WETH = 0x4200000000000000000000000000000000000006;
    address private constant USDM = 0xFAfDdbb3FC7688494971a79cc65DCa3EF82079E7;
    uint256 private constant LARGE_SWAP_AMOUNT = 10 ether;
    uint256 private constant INITIAL_WETH = 20 ether;

    address private constant PRISM_FACTORY = 0x1adb8f973373505bB206e0E5D87af8FB1f5514Ef;
    address private constant KUMBAYA_FACTORY = 0x68b34591f662508076927803c567Cc8006988a09;
    address private constant PRISM_WETH_USDM_POOL = 0xC2FaC0B5B6C075819E654bcFbBBCda2838609d32;
    address private constant KUMBAYA_WETH_USDM_POOL = 0x587F6eeAfc7Ad567e96eD1B62775fA6402164b22;
    uint24 private constant V3_FEE_3000 = 3000;
    address private prismViewQuoter;
    address private kumbayaViewQuoter;

    address private user = address(0xA11CE);

    address private contrapartyAddr;
    IContrapartyVyper private contraparty;
    address private prismAmm;
    address private kumbayaAmm;
    function setUp() public {
        vm.createSelectFork("megaeth");

        vm.label(WETH, "WETH_MEGAETH");
        vm.label(USDM, "USDM_MEGAETH");
        vm.label(user, "USER_MEGAETH");

        prismViewQuoter = vm.deployCode("src/MegaethViewQuoter.sol", abi.encode(PRISM_FACTORY));
        kumbayaViewQuoter = vm.deployCode("src/MegaethViewQuoter.sol", abi.encode(KUMBAYA_FACTORY));
        vm.label(prismViewQuoter, "PRISM_VIEW_QUOTER_LOCAL");
        vm.label(kumbayaViewQuoter, "KUMBAYA_VIEW_QUOTER_LOCAL");

        contrapartyAddr = vm.deployCode("src/Contraparty.vy");
        contraparty = IContrapartyVyper(contrapartyAddr);
        prismAmm = vm.deployCode("src/UniswapV3PropAMM.vy", abi.encode(prismViewQuoter));
        kumbayaAmm = vm.deployCode("src/UniswapV3PropAMM.vy", abi.encode(kumbayaViewQuoter));

        IUniswapV3PropAMM(prismAmm).register_pool(PRISM_WETH_USDM_POOL, V3_FEE_3000);
        IUniswapV3PropAMM(kumbayaAmm).register_pool(KUMBAYA_WETH_USDM_POOL, V3_FEE_3000);

        contraparty.register_amm(prismAmm);
        contraparty.register_amm(kumbayaAmm);

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

    function _fundUserWeth() internal {
        deal(WETH, user, INITIAL_WETH);
    }

}
