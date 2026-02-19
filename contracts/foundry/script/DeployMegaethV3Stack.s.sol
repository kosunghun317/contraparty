// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface Vm {
    function startBroadcast() external;
    function stopBroadcast() external;
    function deployCode(string calldata path) external returns (address);
    function deployCode(string calldata path, bytes calldata constructorArgs) external returns (address);
    function createDir(string calldata path, bool recursive) external;
    function writeFile(string calldata path, string calldata data) external;
}

interface IContraparty {
    function register_amm(address amm) external;
}

interface IUniswapV3PropAMM {
    function register_pool(address pool, uint24 fee) external;
}

contract DeployMegaethV3Stack {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    string internal constant DEPLOYMENT_DIR = "deployments";
    string internal constant DEPLOYMENT_FILE = "deployments/megaeth.yaml";

    address internal constant PRISM_FACTORY = 0x1adb8f973373505bB206e0E5D87af8FB1f5514Ef;
    address internal constant KUMBAYA_FACTORY = 0x68b34591f662508076927803c567Cc8006988a09;
    address internal constant PRISM_WETH_USDM_POOL = 0xC2FaC0B5B6C075819E654bcFbBBCda2838609d32;
    address internal constant KUMBAYA_WETH_USDM_POOL = 0x587F6eeAfc7Ad567e96eD1B62775fA6402164b22;
    uint24 internal constant V3_FEE_3000 = 3000;

    event MegaethStackDeployed(
        address contraparty, address prismQuoter, address kumbayaQuoter, address prismAmm, address kumbayaAmm
    );

    function run()
        external
        returns (address contraparty, address prismQuoter, address kumbayaQuoter, address prismAmm, address kumbayaAmm)
    {
        vm.startBroadcast();

        prismQuoter = vm.deployCode("src/MegaethViewQuoter.sol", abi.encode(PRISM_FACTORY));
        kumbayaQuoter = vm.deployCode("src/MegaethViewQuoter.sol", abi.encode(KUMBAYA_FACTORY));
        contraparty = vm.deployCode("src/Contraparty.vy");
        prismAmm = vm.deployCode("src/UniswapV3PropAMM.vy", abi.encode(prismQuoter));
        kumbayaAmm = vm.deployCode("src/UniswapV3PropAMM.vy", abi.encode(kumbayaQuoter));

        IUniswapV3PropAMM(prismAmm).register_pool(PRISM_WETH_USDM_POOL, V3_FEE_3000);
        IUniswapV3PropAMM(kumbayaAmm).register_pool(KUMBAYA_WETH_USDM_POOL, V3_FEE_3000);

        IContraparty(contraparty).register_amm(prismAmm);
        IContraparty(contraparty).register_amm(kumbayaAmm);

        vm.stopBroadcast();

        _writeDeploymentFile(contraparty, prismQuoter, kumbayaQuoter, prismAmm, kumbayaAmm);
        emit MegaethStackDeployed(contraparty, prismQuoter, kumbayaQuoter, prismAmm, kumbayaAmm);
    }

    function _writeDeploymentFile(
        address contraparty,
        address prismQuoter,
        address kumbayaQuoter,
        address prismAmm,
        address kumbayaAmm
    ) internal {
        vm.createDir(DEPLOYMENT_DIR, true);
        string memory yaml = "chain: megaeth\nchain_id: 4326\n";
        yaml = string.concat(yaml, "contraparty: \"", _toHexString(contraparty), "\"\n");
        yaml = string.concat(yaml, "factories:\n");
        yaml = string.concat(yaml, "  prism: \"", _toHexString(PRISM_FACTORY), "\"\n");
        yaml = string.concat(yaml, "  kumbaya: \"", _toHexString(KUMBAYA_FACTORY), "\"\n");
        yaml = string.concat(yaml, "quoters:\n");
        yaml = string.concat(yaml, "  prism: \"", _toHexString(prismQuoter), "\"\n");
        yaml = string.concat(yaml, "  kumbaya: \"", _toHexString(kumbayaQuoter), "\"\n");
        yaml = string.concat(yaml, "amms:\n");
        yaml = string.concat(yaml, "  prism_uniswap_v3: \"", _toHexString(prismAmm), "\"\n");
        yaml = string.concat(yaml, "  kumbaya_uniswap_v3: \"", _toHexString(kumbayaAmm), "\"\n");
        yaml = string.concat(yaml, "pools:\n");
        yaml = string.concat(yaml, "  prism_weth_usdm:\n");
        yaml = string.concat(yaml, "    address: \"", _toHexString(PRISM_WETH_USDM_POOL), "\"\n");
        yaml = string.concat(yaml, "    fee: ", _toString(V3_FEE_3000), "\n");
        yaml = string.concat(yaml, "  kumbaya_weth_usdm:\n");
        yaml = string.concat(yaml, "    address: \"", _toHexString(KUMBAYA_WETH_USDM_POOL), "\"\n");
        yaml = string.concat(yaml, "    fee: ", _toString(V3_FEE_3000), "\n");
        yaml = string.concat(yaml, "deployed_at_unix: ", _toString(block.timestamp), "\n");
        vm.writeFile(DEPLOYMENT_FILE, yaml);
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
