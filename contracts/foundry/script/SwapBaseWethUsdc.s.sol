// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface Vm {
    function startBroadcast() external;
    function stopBroadcast() external;
    function readFile(string calldata path) external view returns (string memory);
    function envUint(string calldata name) external returns (uint256);
}

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IWETH is IERC20 {
    function deposit() external payable;
}

interface IContrapartySwap {
    function quote(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256);
    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut, address recipient)
        external
        returns (uint256);
}

contract SwapBaseWethUsdc {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    string internal constant DEPLOYMENT_FILE = "deployments/base.yaml";

    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    uint256 internal constant QUOTE_GAS_LIMIT = 1_000_000;
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    event SwapExecuted(
        address contraparty, uint256 amountIn, uint256 quotedAmountOut, uint256 minAmountOut, uint256 amountOut
    );

    function run() external returns (uint256 amountOut) {
        address contraparty = _extractAddress(vm.readFile(DEPLOYMENT_FILE), "contraparty");
        require(contraparty.code.length > 0, "CONTRAPARTY_NOT_DEPLOYED");
        uint256 amountIn = vm.envUint("SWAP_AMOUNT_IN_WEI");
        uint256 slippageBps = vm.envUint("SWAP_SLIPPAGE_BPS");
        require(slippageBps <= BPS_DENOMINATOR, "SLIPPAGE_BPS");
        uint256 quotedAmountOut = IContrapartySwap(contraparty).quote{gas: QUOTE_GAS_LIMIT}(WETH, USDC, amountIn);
        require(quotedAmountOut > 0, "ZERO_QUOTE");
        uint256 minAmountOut = (quotedAmountOut * (BPS_DENOMINATOR - slippageBps)) / BPS_DENOMINATOR;
        address recipient = tx.origin;

        vm.startBroadcast();

        IWETH(WETH).deposit{value: amountIn}();
        require(IERC20(WETH).approve(contraparty, amountIn), "APPROVE_FAIL");
        amountOut = IContrapartySwap(contraparty).swap(WETH, USDC, amountIn, minAmountOut, recipient);

        vm.stopBroadcast();

        emit SwapExecuted(contraparty, amountIn, quotedAmountOut, minAmountOut, amountOut);
    }

    function _extractAddress(string memory fileContent, string memory field) internal pure returns (address) {
        bytes memory data = bytes(fileContent);
        bytes memory key = bytes(field);
        uint256 foundAt = type(uint256).max;

        for (uint256 i = 0; i + key.length <= data.length; ++i) {
            bool matched = true;
            for (uint256 j = 0; j < key.length; ++j) {
                if (data[i + j] != key[j]) {
                    matched = false;
                    break;
                }
            }
            if (!matched) continue;
            foundAt = i + key.length;
            break;
        }

        require(foundAt != type(uint256).max, "FIELD_NOT_FOUND");

        while (foundAt < data.length && data[foundAt] != ":") {
            unchecked {
                ++foundAt;
            }
        }
        require(foundAt < data.length, "BAD_YAML");
        unchecked {
            ++foundAt;
        }

        while (foundAt < data.length) {
            bytes1 ch = data[foundAt];
            if (ch == " " || ch == "\"" || ch == "\t") {
                unchecked {
                    ++foundAt;
                }
                continue;
            }
            break;
        }

        require(foundAt + 42 <= data.length, "BAD_ADDRESS");
        require(data[foundAt] == "0", "BAD_ADDRESS");
        require(data[foundAt + 1] == "x" || data[foundAt + 1] == "X", "BAD_ADDRESS");

        uint160 value = 0;
        for (uint256 i = 0; i < 40; ++i) {
            value = (value << 4) | _fromHexChar(uint8(data[foundAt + 2 + i]));
        }
        return address(value);
    }

    function _fromHexChar(uint8 c) internal pure returns (uint160) {
        if (c >= uint8(bytes1("0")) && c <= uint8(bytes1("9"))) return uint160(c - uint8(bytes1("0")));
        if (c >= uint8(bytes1("a")) && c <= uint8(bytes1("f"))) return uint160(c - uint8(bytes1("a")) + 10);
        if (c >= uint8(bytes1("A")) && c <= uint8(bytes1("F"))) return uint160(c - uint8(bytes1("A")) + 10);
        revert("BAD_HEX");
    }
}
