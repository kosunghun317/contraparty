// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

interface IContrapartySwap {
    function swap(address token_in, address token_out, uint256 amount_in, uint256 min_amount_out, address recipient)
        external
        returns (uint256);
}

contract MockConstantPropAMM {
    // Mode values:
    // 0 = full fill + approval
    // 1 = revert
    // 2 = underfill + approval
    // 3 = skip approval (Contraparty pull should fail)
    // 4 = pull then revert (to validate rollback semantics)
    uint8 public mode;
    uint256 public quoteAmount;
    uint256 public underfillBps = 5000;
    IERC20 public immutable tokenOut;

    constructor(address tokenOut_, uint256 quoteAmount_) {
        tokenOut = IERC20(tokenOut_);
        quoteAmount = quoteAmount_;
    }

    function setMode(uint8 mode_) external {
        mode = mode_;
    }

    function setQuote(uint256 quoteAmount_) external {
        quoteAmount = quoteAmount_;
    }

    function setUnderfillBps(uint256 bps) external {
        require(bps <= 10_000, "BPS");
        underfillBps = bps;
    }

    function quote(address, address, uint256) external view returns (uint256) {
        return quoteAmount;
    }

    function swap(address tokenIn, address, uint256 amountIn, uint256) external returns (uint256) {
        if (mode == 1) revert("MOCK_REVERT");

        if (mode == 4) {
            require(IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn), "TRANSFER_IN");
            revert("MOCK_REVERT_AFTER_PULL");
        }

        require(IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn), "TRANSFER_IN");

        uint256 amountOut = quoteAmount;
        if (mode == 2) {
            amountOut = (quoteAmount * underfillBps) / 10_000;
        }

        if (mode != 3) {
            _approveOut(msg.sender, amountOut);
        }

        return amountOut;
    }

    function _approveOut(address spender, uint256 amount) internal {
        uint256 current = tokenOut.allowance(address(this), spender);
        if (current != 0) {
            require(tokenOut.approve(spender, 0), "APPROVE_RESET");
        }
        if (amount != 0) {
            require(tokenOut.approve(spender, amount), "APPROVE_OUT");
        }
    }
}

contract MockLinearPropAMM {
    IERC20 public immutable tokenOut;
    uint256 public quoteBps;

    constructor(address tokenOut_, uint256 quoteBps_) {
        tokenOut = IERC20(tokenOut_);
        quoteBps = quoteBps_;
    }

    function setQuoteBps(uint256 quoteBps_) external {
        require(quoteBps_ <= 20_000, "BPS");
        quoteBps = quoteBps_;
    }

    function quote(address, address, uint256 amountIn) external view returns (uint256) {
        return (amountIn * quoteBps) / 10_000;
    }

    function swap(address tokenIn, address, uint256 amountIn, uint256) external returns (uint256) {
        require(IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn), "TRANSFER_IN");

        uint256 amountOut = (amountIn * quoteBps) / 10_000;
        uint256 current = tokenOut.allowance(address(this), msg.sender);
        if (current != 0) {
            require(tokenOut.approve(msg.sender, 0), "APPROVE_RESET");
        }
        if (amountOut != 0) {
            require(tokenOut.approve(msg.sender, amountOut), "APPROVE_OUT");
        }

        return amountOut;
    }
}

contract MockReentrantPropAMM {
    IContrapartySwap public immutable contraparty;
    IERC20 public immutable tokenOut;
    uint256 public immutable quoteAmount;

    constructor(address contraparty_, address tokenOut_, uint256 quoteAmount_) {
        contraparty = IContrapartySwap(contraparty_);
        tokenOut = IERC20(tokenOut_);
        quoteAmount = quoteAmount_;
    }

    function quote(address, address, uint256) external view returns (uint256) {
        return quoteAmount;
    }

    function swap(address tokenIn, address tokenOutAddr, uint256 amountIn, uint256) external returns (uint256) {
        require(IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn), "TRANSFER_IN");

        // Try to re-enter while contraparty.swap is still executing.
        (bool ok,) = address(contraparty).call(
            abi.encodeWithSelector(IContrapartySwap.swap.selector, tokenIn, tokenOutAddr, 1, 0, address(this))
        );
        require(!ok, "REENTRY_SUCCEEDED");

        uint256 current = tokenOut.allowance(address(this), msg.sender);
        if (current != 0) {
            require(tokenOut.approve(msg.sender, 0), "APPROVE_RESET");
        }
        require(tokenOut.approve(msg.sender, quoteAmount), "APPROVE_OUT");

        return quoteAmount;
    }
}
