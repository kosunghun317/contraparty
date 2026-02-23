// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface Vm {
    function startBroadcast() external;
    function stopBroadcast() external;
    function deployCode(string calldata path, bytes calldata constructorArgs) external returns (address);
    function createDir(string calldata path, bool recursive) external;
    function writeFile(string calldata path, string calldata data) external;
}

interface IContraparty {
    function register_amm(address amm) external;
    function amms(uint256 index) external view returns (address);
}

contract RedeployMegaethContrapartyV2 {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    string internal constant DEPLOYMENT_DIR = "deployments";
    string internal constant DEPLOYMENT_FILE = "deployments/megaeth_contraparty_redeploy.toml";

    uint256 internal constant MAX_AMMS_SCAN = 16;

    address internal constant OLD_CONTRAPARTY = 0x1F60E7d203dA3161AcFb22D005551F0Ed86d6552;
    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    address internal constant PRISM_AMM = 0xecD83A2405eAC09aF50665ad42DBDbB48BEABdD8;
    address internal constant KUMBAYA_AMM = 0x7d70c03422d5850c9141336b16221ae13CabdD2a;
    address internal constant CANONIC_AMM = 0x4C1D51334521C78812B26d4C90d74c37A1431B6E;

    event MegaethContrapartyRedeployed(address oldContraparty, address newContraparty);

    function run() external returns (address newContraparty) {
        require(_isAmmRegistered(OLD_CONTRAPARTY, PRISM_AMM), "OLD_PRISM_AMM_MISSING");
        require(_isAmmRegistered(OLD_CONTRAPARTY, KUMBAYA_AMM), "OLD_KUMBAYA_AMM_MISSING");
        require(_isAmmRegistered(OLD_CONTRAPARTY, CANONIC_AMM), "OLD_CANONIC_AMM_MISSING");

        vm.startBroadcast();

        newContraparty = vm.deployCode("src/ContrapartyV2.vy", abi.encode(WETH));
        IContraparty(newContraparty).register_amm(PRISM_AMM);
        IContraparty(newContraparty).register_amm(KUMBAYA_AMM);
        IContraparty(newContraparty).register_amm(CANONIC_AMM);

        vm.stopBroadcast();

        _writeDeploymentFile(newContraparty);
        emit MegaethContrapartyRedeployed(OLD_CONTRAPARTY, newContraparty);
    }

    function _isAmmRegistered(address contraparty, address amm) internal view returns (bool) {
        for (uint256 i = 0; i < MAX_AMMS_SCAN; ++i) {
            try IContraparty(contraparty).amms(i) returns (address candidate) {
                if (candidate == amm) return true;
            } catch {
                return false;
            }
        }
        return false;
    }

    function _writeDeploymentFile(address newContraparty) internal {
        vm.createDir(DEPLOYMENT_DIR, true);

        string memory toml = "[megaeth_contraparty_redeploy]\n";
        toml = string.concat(toml, "old_contraparty = \"", _toHexString(OLD_CONTRAPARTY), "\"\n");
        toml = string.concat(toml, "new_contraparty = \"", _toHexString(newContraparty), "\"\n");
        toml = string.concat(toml, "weth = \"", _toHexString(WETH), "\"\n");
        toml = string.concat(toml, "prism_amm = \"", _toHexString(PRISM_AMM), "\"\n");
        toml = string.concat(toml, "kumbaya_amm = \"", _toHexString(KUMBAYA_AMM), "\"\n");
        toml = string.concat(toml, "canonic_amm = \"", _toHexString(CANONIC_AMM), "\"\n");
        toml = string.concat(toml, "deployed_at_unix = ", _toString(block.timestamp), "\n");

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
