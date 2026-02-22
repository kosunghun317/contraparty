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

interface IUniswapV3Pool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function fee() external view returns (uint24);
}

contract DeployMegaethV3Stack {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    string internal constant DEPLOYMENT_DIR = "deployments";
    string internal constant DEPLOYMENT_FILE = "deployments/megaeth.toml";

    address internal constant PRISM_FACTORY = 0x1adb8f973373505bB206e0E5D87af8FB1f5514Ef;
    address internal constant KUMBAYA_FACTORY = 0x68b34591f662508076927803c567Cc8006988a09;
    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    address internal constant USDM = 0xFAfDdbb3FC7688494971a79cc65DCa3EF82079E7;
    address internal constant USDT0 = 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb;
    address internal constant BTCB = 0xB0F70C0bD6FD87dbEb7C10dC692a2a6106817072;
    address internal constant PRISM_WETH_USDM_POOL = 0xC2FaC0B5B6C075819E654bcFbBBCda2838609d32;
    address internal constant KUMBAYA_WETH_USDM_POOL = 0x587F6eeAfc7Ad567e96eD1B62775fA6402164b22;
    address internal constant KUMBAYA_WETH_USDT0_POOL = 0x2809696F2e42eB452C32C3d0A2Dc540858C14125;
    address internal constant KUMBAYA_BTCB_USDM_POOL = 0xc1838B7807e5bd4D56EA630BA35Ac964CF72c9db;
    address internal constant KUMBAYA_USDT0_USDM_POOL = 0x6c8E5D463a2473b1A8bcd87e1cEA2724203A1D8f;
    uint24 internal constant V3_FEE_3000 = 3000;
    uint24 internal constant V3_FEE_100 = 100;

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

        _assertPoolInfo(PRISM_WETH_USDM_POOL, WETH, USDM, V3_FEE_3000);
        _assertPoolInfo(KUMBAYA_WETH_USDM_POOL, WETH, USDM, V3_FEE_3000);
        _assertPoolInfo(KUMBAYA_WETH_USDT0_POOL, WETH, USDT0, V3_FEE_3000);
        _assertPoolInfo(KUMBAYA_BTCB_USDM_POOL, BTCB, USDM, V3_FEE_3000);
        _assertPoolInfo(KUMBAYA_USDT0_USDM_POOL, USDT0, USDM, V3_FEE_100);

        IUniswapV3PropAMM(prismAmm).register_pool(PRISM_WETH_USDM_POOL, V3_FEE_3000);
        IUniswapV3PropAMM(kumbayaAmm).register_pool(KUMBAYA_WETH_USDM_POOL, V3_FEE_3000);
        IUniswapV3PropAMM(kumbayaAmm).register_pool(KUMBAYA_WETH_USDT0_POOL, V3_FEE_3000);
        IUniswapV3PropAMM(kumbayaAmm).register_pool(KUMBAYA_BTCB_USDM_POOL, V3_FEE_3000);
        IUniswapV3PropAMM(kumbayaAmm).register_pool(KUMBAYA_USDT0_USDM_POOL, V3_FEE_100);

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
        string memory toml = "[megaeth]\n";
        toml = string.concat(toml, "chain = \"megaeth\"\n");
        toml = string.concat(toml, "chain_id = 4326\n");
        toml = string.concat(toml, "contraparty = \"", _toHexString(contraparty), "\"\n");
        toml = string.concat(toml, "deployed_at_unix = ", _toString(block.timestamp), "\n\n");
        toml = string.concat(toml, "[megaeth.factories]\n");
        toml = string.concat(toml, "prism = \"", _toHexString(PRISM_FACTORY), "\"\n");
        toml = string.concat(toml, "kumbaya = \"", _toHexString(KUMBAYA_FACTORY), "\"\n\n");
        toml = string.concat(toml, "[megaeth.quoters]\n");
        toml = string.concat(toml, "prism = \"", _toHexString(prismQuoter), "\"\n");
        toml = string.concat(toml, "kumbaya = \"", _toHexString(kumbayaQuoter), "\"\n\n");
        toml = string.concat(toml, "[megaeth.amms]\n");
        toml = string.concat(toml, "prism_uniswap_v3 = \"", _toHexString(prismAmm), "\"\n");
        toml = string.concat(toml, "kumbaya_uniswap_v3 = \"", _toHexString(kumbayaAmm), "\"\n\n");
        toml = string.concat(toml, "[megaeth.pools.prism_weth_usdm]\n");
        toml = string.concat(toml, "address = \"", _toHexString(PRISM_WETH_USDM_POOL), "\"\n");
        toml = string.concat(toml, "fee = ", _toString(V3_FEE_3000), "\n");
        toml = string.concat(toml, "token0 = \"", _toHexString(WETH), "\"\n");
        toml = string.concat(toml, "token1 = \"", _toHexString(USDM), "\"\n\n");
        toml = string.concat(toml, "[megaeth.pools.kumbaya_weth_usdm]\n");
        toml = string.concat(toml, "address = \"", _toHexString(KUMBAYA_WETH_USDM_POOL), "\"\n");
        toml = string.concat(toml, "fee = ", _toString(V3_FEE_3000), "\n");
        toml = string.concat(toml, "token0 = \"", _toHexString(WETH), "\"\n");
        toml = string.concat(toml, "token1 = \"", _toHexString(USDM), "\"\n\n");
        toml = string.concat(toml, "[megaeth.pools.kumbaya_weth_usdt0]\n");
        toml = string.concat(toml, "address = \"", _toHexString(KUMBAYA_WETH_USDT0_POOL), "\"\n");
        toml = string.concat(toml, "fee = ", _toString(V3_FEE_3000), "\n");
        toml = string.concat(toml, "token0 = \"", _toHexString(WETH), "\"\n");
        toml = string.concat(toml, "token1 = \"", _toHexString(USDT0), "\"\n\n");
        toml = string.concat(toml, "[megaeth.pools.kumbaya_btcb_usdm]\n");
        toml = string.concat(toml, "address = \"", _toHexString(KUMBAYA_BTCB_USDM_POOL), "\"\n");
        toml = string.concat(toml, "fee = ", _toString(V3_FEE_3000), "\n");
        toml = string.concat(toml, "token0 = \"", _toHexString(BTCB), "\"\n");
        toml = string.concat(toml, "token1 = \"", _toHexString(USDM), "\"\n\n");
        toml = string.concat(toml, "[megaeth.pools.kumbaya_usdt0_usdm]\n");
        toml = string.concat(toml, "address = \"", _toHexString(KUMBAYA_USDT0_USDM_POOL), "\"\n");
        toml = string.concat(toml, "fee = ", _toString(V3_FEE_100), "\n");
        toml = string.concat(toml, "token0 = \"", _toHexString(USDT0), "\"\n");
        toml = string.concat(toml, "token1 = \"", _toHexString(USDM), "\"\n");
        vm.writeFile(DEPLOYMENT_FILE, toml);
    }

    function _assertPoolInfo(address pool, address expectedToken0, address expectedToken1, uint24 expectedFee) internal view {
        require(IUniswapV3Pool(pool).token0() == expectedToken0, "POOL_TOKEN0_MISMATCH");
        require(IUniswapV3Pool(pool).token1() == expectedToken1, "POOL_TOKEN1_MISMATCH");
        require(IUniswapV3Pool(pool).fee() == expectedFee, "POOL_FEE_MISMATCH");
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
