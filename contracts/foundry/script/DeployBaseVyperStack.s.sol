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

contract DeployBaseVyperStack {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    string internal constant DEPLOYMENT_DIR = "deployments";
    string internal constant DEPLOYMENT_FILE = "deployments/base.yaml";

    address internal constant UNISWAP_V3_VIEW_QUOTER = 0x222cA98F00eD15B1faE10B61c277703a194cf5d2;
    address internal constant UNISWAP_V3_WETH_USDC_POOL_500 = 0xd0b53D9277642d899DF5C87A3966A349A798F224;
    address internal constant UNISWAP_V3_WETH_USDC_POOL_3000 = 0x6c561B446416E1A00E8E93E221854d6eA4171372;
    uint24 internal constant V3_FEE_500 = 500;
    uint24 internal constant V3_FEE_3000 = 3000;
    address internal constant UNISWAP_V2_FACTORY = 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6;
    address internal constant AERODROME_FACTORY = 0x420DD381b31aEf6683db6B902084cB0FFECe40Da;

    event StackDeployed(address contraparty, address uniswapV3Amm, address uniswapV2Amm, address aerodromeAmm);

    function run() external returns (address contraparty, address uniswapV3Amm, address uniswapV2Amm, address aerodromeAmm) {
        vm.startBroadcast();

        contraparty = vm.deployCode("src/Contraparty.vy");
        uniswapV3Amm = vm.deployCode("src/UniswapV3PropAMM.vy", abi.encode(UNISWAP_V3_VIEW_QUOTER));
        IUniswapV3PropAMM(uniswapV3Amm).register_pool(UNISWAP_V3_WETH_USDC_POOL_500, V3_FEE_500);
        IUniswapV3PropAMM(uniswapV3Amm).register_pool(UNISWAP_V3_WETH_USDC_POOL_3000, V3_FEE_3000);
        uniswapV2Amm = vm.deployCode("src/UniswapV2PropAMM.vy", abi.encode(UNISWAP_V2_FACTORY));
        aerodromeAmm = vm.deployCode("src/AerodromePropAMM.vy", abi.encode(AERODROME_FACTORY));

        IContraparty(contraparty).register_amm(uniswapV3Amm);
        IContraparty(contraparty).register_amm(uniswapV2Amm);
        IContraparty(contraparty).register_amm(aerodromeAmm);

        vm.stopBroadcast();
        _writeDeploymentFile(contraparty, uniswapV3Amm, uniswapV2Amm, aerodromeAmm);

        emit StackDeployed(contraparty, uniswapV3Amm, uniswapV2Amm, aerodromeAmm);
    }

    function _writeDeploymentFile(address contraparty, address uniswapV3Amm, address uniswapV2Amm, address aerodromeAmm)
        internal
    {
        vm.createDir(DEPLOYMENT_DIR, true);

        string memory yaml = "chain: base\nchain_id: 8453\n";
        yaml = string.concat(yaml, "contraparty: \"", _toHexString(contraparty), "\"\n");
        yaml = string.concat(yaml, "amms:\n");
        yaml = string.concat(yaml, "  uniswap_v3: \"", _toHexString(uniswapV3Amm), "\"\n");
        yaml = string.concat(yaml, "  uniswap_v2: \"", _toHexString(uniswapV2Amm), "\"\n");
        yaml = string.concat(yaml, "  aerodrome: \"", _toHexString(aerodromeAmm), "\"\n");
        yaml = string.concat(yaml, "v3_quoter: \"", _toHexString(UNISWAP_V3_VIEW_QUOTER), "\"\n");
        yaml = string.concat(yaml, "pools:\n");
        yaml = string.concat(yaml, "  uniswap_v3_weth_usdc_500:\n");
        yaml = string.concat(yaml, "    address: \"", _toHexString(UNISWAP_V3_WETH_USDC_POOL_500), "\"\n");
        yaml = string.concat(yaml, "    fee: ", _toString(V3_FEE_500), "\n");
        yaml = string.concat(yaml, "  uniswap_v3_weth_usdc_3000:\n");
        yaml = string.concat(yaml, "    address: \"", _toHexString(UNISWAP_V3_WETH_USDC_POOL_3000), "\"\n");
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
