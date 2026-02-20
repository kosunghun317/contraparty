// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface Vm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function createSelectFork(string calldata rpcUrl) external returns (uint256);
    function deployCode(string calldata path) external returns (address);
    function deployCode(string calldata path, bytes calldata constructorArgs) external returns (address);
    function deal(address account, uint256 newBalance) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
    function load(address target, bytes32 slot) external view returns (bytes32 data);
    function store(address target, bytes32 slot, bytes32 value) external;
    function prank(address sender) external;
    function startPrank(address sender) external;
    function stopPrank() external;
    function label(address account, string calldata label) external;
}

interface IERC20Balance {
    function balanceOf(address account) external view returns (uint256);
}

abstract contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 internal constant MAX_STORAGE_SLOTS_TO_SCAN = 128;

    /// @dev Local `deal` helper for ERC20 balances on forks when token-level `vm.deal` cheatcode is unavailable.
    /// It finds the balance mapping slot by probing common storage slots and setting `keccak256(user, slot)`.
    function deal(address token, address to, uint256 amount) internal {
        for (uint256 slot = 0; slot < MAX_STORAGE_SLOTS_TO_SCAN; ++slot) {
            bytes32 balanceSlot = keccak256(abi.encode(to, slot));
            bytes32 prevValue = vm.load(token, balanceSlot);

            vm.store(token, balanceSlot, bytes32(amount));
            if (IERC20Balance(token).balanceOf(to) == amount) {
                return;
            }

            vm.store(token, balanceSlot, prevValue);
        }
        revert("ERC20_DEAL_FAILED");
    }

    function assertTrue(bool condition, string memory message) internal pure {
        require(condition, message);
    }

    function assertGt(uint256 left, uint256 right, string memory message) internal pure {
        require(left > right, message);
    }

    function assertLt(uint256 left, uint256 right, string memory message) internal pure {
        require(left < right, message);
    }

    function assertEq(uint256 left, uint256 right, string memory message) internal pure {
        require(left == right, message);
    }

    function assertEq(address left, address right, string memory message) internal pure {
        require(left == right, message);
    }
}
