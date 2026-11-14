# Vendored dependencies

Dependencies are copied as ordinary files, with no submodules or install-time
downloads. Project contracts and tests are licensed under MIT; third-party
sources retain their original notices and licenses.

| Dependency | Pinned release | Included files | License |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.1.0) | `v5.1.0` | ERC20, IERC20, IERC20Metadata, Context, draft-IERC6093, LICENSE | MIT |
| [Forge Standard Library](https://github.com/foundry-rs/forge-std/tree/v1.9.7) | `v1.9.7` | Complete `src/` and license files | Apache-2.0 or MIT |

OpenZeppelin supplies the production ERC-20 implementation. Forge Standard
Library is used only by tests. No dependency source files were modified.

Downloaded release archives and SHA-256 hashes:

- `https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.1.0`
  — `8a3b08cfc756437ba3343901565b18182adb42ec1e621960240a19da5d738686`
- `https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7`
  — `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`

Individual copied files are pinned in `lib/SHA256SUMS`. Verify them locally from
the repository root with `sha256sum --check lib/SHA256SUMS`.

Behavior references:

- [ERC-20 specification](https://eips.ethereum.org/EIPS/eip-20).
- [Exact OpenZeppelin ERC20 source used here](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.1.0/contracts/token/ERC20/ERC20.sol).
