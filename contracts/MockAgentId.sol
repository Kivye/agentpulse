// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Test-only mock of the SPACE ID Agent ID contract
///         (BSC: 0x60b9262456de011f7d15a54cdd8c48baaa8b022f).
/// @dev Mirrors the three read functions verified on-chain for the real
///      registry: balanceOf(address), handleOf(address) -> handle without the
///      ".ai" suffix, and ownerOfHandle(string) -> owner address. Setters let
///      tests stage every failure mode independently: no balance, empty
///      handle, and handle-owner mismatch.
contract MockAgentId {
    mapping(address => uint256) private _balances;
    mapping(address => string) private _handles;
    mapping(string => address) private _handleOwners;

    function balanceOf(address who) external view returns (uint256) {
        return _balances[who];
    }

    function handleOf(address who) external view returns (string memory) {
        return _handles[who];
    }

    function ownerOfHandle(string calldata handle) external view returns (address) {
        return _handleOwners[handle];
    }

    // --- test setters ---
    function setBalance(address who, uint256 v) external {
        _balances[who] = v;
    }

    function setHandle(address who, string calldata handle) external {
        _handles[who] = handle;
    }

    function setOwnerOfHandle(string calldata handle, address owner_) external {
        _handleOwners[handle] = owner_;
    }

    /// @notice Stage a fully consistent holder: balance 1, handle set, and
    ///         ownerOfHandle(handle) == who.
    function setAgent(address who, string calldata handle) external {
        _balances[who] = 1;
        _handles[who] = handle;
        _handleOwners[handle] = who;
    }
}
