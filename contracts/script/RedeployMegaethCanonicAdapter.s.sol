// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface Vm {
    function startBroadcast() external;
    function stopBroadcast() external;
    function deployCode(string calldata path) external returns (address);
    function createDir(string calldata path, bool recursive) external;
    function writeFile(string calldata path, string calldata data) external;
}

interface IContraparty {
    function register_amm(address amm) external;
    function remove_amm(address amm) external;
    function amms(uint256 index) external view returns (address);
}

interface ICanonicPropAMM {
    function register_market(address market) external;
}

contract RedeployMegaethCanonicAdapter {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    string internal constant DEPLOYMENT_DIR = "deployments";
    string internal constant DEPLOYMENT_FILE = "deployments/megaeth_canonic_redeploy.toml";

    uint256 internal constant MAX_AMMS_SCAN = 16;
    uint256 internal constant DEFAULT_HAIRCUT_BPS = 9_999;

    address internal constant CONTRAPARTY = 0x2Ede240d8E64e7Be3B103d9434733D56caFd9059;
    address internal constant OLD_CANONIC_AMM = 0xc2c7bA229221ec2920291Cf7d383f0816B67DdC0;

    address internal constant CANONIC_MAOB_WETH_USDM = 0x23469683e25b780DFDC11410a8e83c923caDF125;
    address internal constant CANONIC_MAOB_BTCB_USDM = 0xaD7e5CBfB535ceC8d2E58Dca17b11d9bA76f555E;
    address internal constant CANONIC_MAOB_USDT0_USDM = 0xDf1576c3C82C9f8B759C69f4cF256061C6Fe1f9e;

    event MegaethCanonicAdapterRedeployed(address contraparty, address oldCanonicAmm, address newCanonicAmm);

    function run() external returns (address newCanonicAmm) {
        require(_isAmmRegistered(OLD_CANONIC_AMM), "OLD_CANONIC_NOT_REGISTERED");

        vm.startBroadcast();

        newCanonicAmm = vm.deployCode("src/CanonicPropAMM.vy");
        ICanonicPropAMM(newCanonicAmm).register_market(CANONIC_MAOB_WETH_USDM);
        ICanonicPropAMM(newCanonicAmm).register_market(CANONIC_MAOB_BTCB_USDM);
        ICanonicPropAMM(newCanonicAmm).register_market(CANONIC_MAOB_USDT0_USDM);

        IContraparty(CONTRAPARTY).register_amm(newCanonicAmm);
        IContraparty(CONTRAPARTY).remove_amm(OLD_CANONIC_AMM);

        vm.stopBroadcast();

        _writeDeploymentFile(newCanonicAmm);
        emit MegaethCanonicAdapterRedeployed(CONTRAPARTY, OLD_CANONIC_AMM, newCanonicAmm);
    }

    function _isAmmRegistered(address amm) internal view returns (bool) {
        for (uint256 i = 0; i < MAX_AMMS_SCAN; ++i) {
            try IContraparty(CONTRAPARTY).amms(i) returns (address candidate) {
                if (candidate == amm) {
                    return true;
                }
            } catch {
                return false;
            }
        }
        return false;
    }

    function _writeDeploymentFile(address newCanonicAmm) internal {
        vm.createDir(DEPLOYMENT_DIR, true);

        string memory toml = "[megaeth_canonic_redeploy]\n";
        toml = string.concat(toml, "contraparty = \"", _toHexString(CONTRAPARTY), "\"\n");
        toml = string.concat(toml, "old_canonic_amm = \"", _toHexString(OLD_CANONIC_AMM), "\"\n");
        toml = string.concat(toml, "new_canonic_amm = \"", _toHexString(newCanonicAmm), "\"\n");
        toml = string.concat(toml, "default_quote_haircut_bps = ", _toString(DEFAULT_HAIRCUT_BPS), "\n");
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
