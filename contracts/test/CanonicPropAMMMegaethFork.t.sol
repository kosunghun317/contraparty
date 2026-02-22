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

interface ICanonicPropAMM {
    function register_market(address market) external;
    function market_count() external view returns (uint256);
    function quote(address token_in, address token_out, uint256 amount_in) external view returns (uint256);
    function quote_haircut_bps() external view returns (uint256);
    function set_quote_haircut_bps(uint256 new_haircut_bps) external;
}

contract CanonicPropAMMMegaethForkTest is TestBase {
    address private constant WETH = 0x4200000000000000000000000000000000000006;
    address private constant USDM = 0xFAfDdbb3FC7688494971a79cc65DCa3EF82079E7;
    address private constant CANONIC_MAOB_WETH_USDM = 0x23469683e25b780DFDC11410a8e83c923caDF125;

    uint256 private constant INITIAL_WETH = 20 ether;
    uint256 private constant SWAP_AMOUNT = 0.1 ether;

    address private user = address(0xCAFE);
    address private contrapartyAddr;
    IContrapartyVyper private contraparty;
    address private canonicAmm;

    function setUp() public {
        vm.createSelectFork("megaeth");

        vm.label(WETH, "WETH_MEGAETH");
        vm.label(USDM, "USDM_MEGAETH");
        vm.label(CANONIC_MAOB_WETH_USDM, "CANONIC_MAOB_WETH_USDM");
        vm.label(user, "USER_MEGAETH");

        contrapartyAddr = vm.deployCode("src/Contraparty.vy");
        contraparty = IContrapartyVyper(contrapartyAddr);
        canonicAmm = vm.deployCode("src/CanonicPropAMM.vy");

        vm.label(contrapartyAddr, "CONTRAPARTY");
        vm.label(canonicAmm, "CANONIC_PROP_AMM");

        ICanonicPropAMM(canonicAmm).register_market(CANONIC_MAOB_WETH_USDM);
        contraparty.register_amm(canonicAmm);
        _fundUserWeth();
    }

    function testForkMegaeth_CanonicQuoteWethUsdm() public view {
        uint256 quotedOut = contraparty.quote(WETH, USDM, SWAP_AMOUNT);
        assertGt(quotedOut, 0, "canonic quote is zero");
    }

    function testForkMegaeth_CanonicSwapWethToUsdm() public {
        uint256 quotedOut = contraparty.quote(WETH, USDM, SWAP_AMOUNT);
        assertGt(quotedOut, 0, "canonic quote is zero");

        uint256 usdmBefore = IERC20(USDM).balanceOf(user);
        uint256 wethBefore = IERC20(WETH).balanceOf(user);

        vm.startPrank(user);
        IERC20(WETH).approve(contrapartyAddr, SWAP_AMOUNT);
        uint256 amountOut = contraparty.swap(WETH, USDM, SWAP_AMOUNT, (quotedOut * 99) / 100, user);
        vm.stopPrank();

        uint256 usdmAfter = IERC20(USDM).balanceOf(user);
        uint256 wethAfter = IERC20(WETH).balanceOf(user);

        assertEq(wethAfter, wethBefore - SWAP_AMOUNT, "incorrect WETH spent");
        assertGt(amountOut, 0, "swap amount out is zero");
        assertGt(usdmAfter, usdmBefore, "user USDM not increased");
    }

    function testForkMegaeth_CanonicHaircutCanBeTightened() public {
        ICanonicPropAMM amm = ICanonicPropAMM(canonicAmm);
        assertEq(amm.market_count(), 1, "expected one registered market");
        uint256 beforeBps = amm.quote_haircut_bps();
        uint256 quoteBefore = amm.quote(WETH, USDM, SWAP_AMOUNT);
        assertGt(quoteBefore, 0, "pre-quote is zero");

        amm.set_quote_haircut_bps(10_000);
        uint256 afterBps = amm.quote_haircut_bps();
        uint256 quoteAfter = amm.quote(WETH, USDM, SWAP_AMOUNT);

        assertEq(beforeBps, 9_990, "unexpected default haircut");
        assertEq(afterBps, 10_000, "haircut update failed");
        assertTrue(quoteAfter >= quoteBefore, "quote should not decrease after reducing haircut");
    }

    function _fundUserWeth() internal {
        deal(WETH, user, INITIAL_WETH);
    }
}
