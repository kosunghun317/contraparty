// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface Vm {
    function startBroadcast() external;
    function stopBroadcast() external;
    function deployCode(string calldata path) external returns (address);
    function createDir(string calldata path, bool recursive) external;
    function readFile(string calldata path) external view returns (string memory);
    function writeFile(string calldata path, string calldata data) external;
}

interface IContraparty {
    function register_amm(address amm) external;
}

contract DeployBaseContrapartyQuoteOnly {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    string internal constant DEPLOYMENT_DIR = "deployments";
    string internal constant DEPLOYMENT_FILE = "deployments/base.toml";

    event ContrapartyDeployed(address contraparty, address uniswapV3Amm, address uniswapV2Amm, address aerodromeAmm);

    function run() external returns (address contraparty, address uniswapV3Amm, address uniswapV2Amm, address aerodromeAmm) {
        string memory existing = vm.readFile(DEPLOYMENT_FILE);
        uniswapV3Amm = _extractAddress(existing, "uniswap_v3");
        uniswapV2Amm = _extractAddress(existing, "uniswap_v2");
        aerodromeAmm = _extractAddress(existing, "aerodrome");

        vm.startBroadcast();
        contraparty = vm.deployCode("src/Contraparty.vy");
        IContraparty(contraparty).register_amm(uniswapV3Amm);
        IContraparty(contraparty).register_amm(uniswapV2Amm);
        IContraparty(contraparty).register_amm(aerodromeAmm);
        vm.stopBroadcast();

        _writeDeploymentFile(contraparty, uniswapV3Amm, uniswapV2Amm, aerodromeAmm);
        emit ContrapartyDeployed(contraparty, uniswapV3Amm, uniswapV2Amm, aerodromeAmm);
    }

    function _writeDeploymentFile(address contraparty, address uniswapV3Amm, address uniswapV2Amm, address aerodromeAmm)
        internal
    {
        vm.createDir(DEPLOYMENT_DIR, true);

        string memory toml = string(
            abi.encodePacked(
                "[base]\n",
                "chain = \"base\"\n",
                "chain_id = 8453\n",
                "contraparty = \"",
                _toHexString(contraparty),
                "\"\n",
                "deployed_at_unix = ",
                _toString(block.timestamp),
                "\n\n",
                "[base.amms]\n",
                "uniswap_v3 = \"",
                _toHexString(uniswapV3Amm),
                "\"\n",
                "uniswap_v2 = \"",
                _toHexString(uniswapV2Amm),
                "\"\n",
                "aerodrome = \"",
                _toHexString(aerodromeAmm),
                "\"\n"
            )
        );

        vm.writeFile(DEPLOYMENT_FILE, toml);
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

        while (foundAt < data.length && data[foundAt] != ":" && data[foundAt] != "=") {
            unchecked {
                ++foundAt;
            }
        }
        require(foundAt < data.length, "BAD_CONFIG");
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

    function _toHexString(address account) internal pure returns (string memory) {
        return _toHexString(uint256(uint160(account)), 20);
    }

    function _toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes16 symbols = 0x30313233343536373839616263646566;
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = symbols[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "HEX_LENGTH");
        return string(buffer);
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            unchecked {
                ++digits;
            }
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            unchecked {
                --digits;
            }
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
