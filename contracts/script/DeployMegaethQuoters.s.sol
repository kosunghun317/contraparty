// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface Vm {
    function startBroadcast() external;
    function stopBroadcast() external;
    function deployCode(string calldata path, bytes calldata constructorArgs) external returns (address);
    function createDir(string calldata path, bool recursive) external;
    function writeFile(string calldata path, string calldata data) external;
}

contract DeployMegaethQuoters {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    string internal constant DEPLOYMENT_DIR = "deployments";
    string internal constant DEPLOYMENT_FILE = "deployments/megaeth_quoters.toml";

    address internal constant PRISM_FACTORY = 0x1adb8f973373505bB206e0E5D87af8FB1f5514Ef;
    address internal constant KUMBAYA_FACTORY = 0x68b34591f662508076927803c567Cc8006988a09;

    event MegaethQuotersDeployed(address prismQuoter, address kumbayaQuoter);

    function run() external returns (address prismQuoter, address kumbayaQuoter) {
        vm.startBroadcast();
        prismQuoter = vm.deployCode("src/MegaethViewQuoter.sol", abi.encode(PRISM_FACTORY));
        kumbayaQuoter = vm.deployCode("src/MegaethViewQuoter.sol", abi.encode(KUMBAYA_FACTORY));
        vm.stopBroadcast();

        _writeDeploymentFile(prismQuoter, kumbayaQuoter);
        emit MegaethQuotersDeployed(prismQuoter, kumbayaQuoter);
    }

    function _writeDeploymentFile(address prismQuoter, address kumbayaQuoter) internal {
        vm.createDir(DEPLOYMENT_DIR, true);
        string memory toml = "[megaeth]\n";
        toml = string.concat(toml, "chain = \"megaeth\"\n");
        toml = string.concat(toml, "chain_id = 4326\n");
        toml = string.concat(toml, "deployed_at_unix = ", _toString(block.timestamp), "\n\n");
        toml = string.concat(toml, "[megaeth.factories]\n");
        toml = string.concat(toml, "prism = \"", _toHexString(PRISM_FACTORY), "\"\n");
        toml = string.concat(toml, "kumbaya = \"", _toHexString(KUMBAYA_FACTORY), "\"\n\n");
        toml = string.concat(toml, "[megaeth.quoters]\n");
        toml = string.concat(toml, "prism = \"", _toHexString(prismQuoter), "\"\n");
        toml = string.concat(toml, "kumbaya = \"", _toHexString(kumbayaQuoter), "\"\n");
        vm.writeFile(DEPLOYMENT_FILE, toml);
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
