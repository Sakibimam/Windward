// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title HookMiner
/// @notice Finds a CREATE2 salt whose resulting address carries exactly the hook permission
/// bits Uniswap v4 requires.
///
/// @dev **Attribution.** This is a reimplementation of the same well-known search that
/// v4-periphery ships at `test/shared/HookMiner.sol`, and the `find` signature matches theirs.
/// It was rewritten rather than imported because that file lives under `test/`, and because this
/// version bounds the loop explicitly and returns `(salt, address)`. Credit for the approach
/// belongs upstream.
///
/// @dev v4 encodes a hook's permissions in the low 14 bits of its ADDRESS
/// (`Hooks.sol:27-47`), and `Hooks.validateHookPermissions` — which `WindwardHook`'s
/// constructor calls — reverts unless those bits match the declared permission set exactly.
/// So the address is not incidental: it is part of the interface, and it has to be mined.
///
/// **The bytecode must be the bytecode you will actually deploy.** A CREATE2 address is
/// `keccak256(0xff ++ deployer ++ salt ++ keccak256(initCode))`, so init code compiled under a
/// different profile yields a different address. `DECISIONS.md` D-0006 records this as a
/// deployment-breaking trap: mine and deploy both under `FOUNDRY_PROFILE=deploy`, whose
/// `via_ir = true` and `optimizer_runs = 44444444` produce different bytecode from the
/// default profile.
library HookMiner {
    /// @dev Foundry routes `new C{salt: s}()` inside a script through this deterministic
    /// deployer. It is the canonical Arachnid CREATE2 factory and is present on Unichain
    /// Sepolia (verified on-chain before mining).
    address internal constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @dev Only the low 14 bits carry permissions.
    uint160 internal constant FLAG_MASK = uint160((1 << 14) - 1);

    /// @notice Search for a salt whose CREATE2 address has exactly `flags` in its low 14 bits.
    /// @param deployer  The CREATE2 factory that will perform the deployment.
    /// @param flags     The exact low-14-bit pattern required.
    /// @param creationCode  Contract creation bytecode, from the profile you will deploy with.
    /// @param constructorArgs  ABI-encoded constructor arguments.
    /// @return salt The salt to deploy with.
    /// @return hookAddress The address that salt produces.
    function find(address deployer, uint160 flags, bytes memory creationCode, bytes memory constructorArgs)
        internal
        pure
        returns (bytes32 salt, address hookAddress)
    {
        bytes32 initCodeHash = keccak256(abi.encodePacked(creationCode, constructorArgs));

        // One in 2^14 salts matches, so ~16k iterations is the expected cost and 160k is a
        // very generous ceiling. Bounded so a mistake fails loudly instead of hanging.
        for (uint256 i = 0; i < 160_000; i++) {
            address candidate = computeAddress(deployer, bytes32(i), initCodeHash);
            if (uint160(candidate) & FLAG_MASK == flags) {
                return (bytes32(i), candidate);
            }
        }
        revert("HookMiner: no salt found within bound");
    }

    /// @notice The standard CREATE2 address derivation.
    function computeAddress(address deployer, bytes32 salt, bytes32 initCodeHash) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash)))));
    }
}
