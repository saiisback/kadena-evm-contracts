# Kadena Bounty Contracts

This repository contains a production-ready catalog of Solidity smart contract templates paired with a polished Next.js discovery experience. It is designed to accelerate development on Chainweb EVM compatible networks (Ethereum, Optimism, Base, Arbitrum) while reflecting Kadena’s design language. Every contract follows Solidity 0.8.x best practices and leans on OpenZeppelin security-hardened components.

Maintained by **saiisback**.

## Repository Layout

```
.
├── access/                # Access control and multisig templates
├── defi/                  # Treasury, auction, vesting, and distribution contracts
├── governance/            # DAO and timelock implementations
├── proxy/                 # UUPS-based upgradeability helpers
├── tokens/                # ERC20 / ERC721 / ERC1155 token blueprints
└── catalog/               # Next.js (App Router) catalog UI built with shadcn/ui
```

Each Solidity file is self-documented with NatSpec comments and relies on OpenZeppelin 5.x libraries. The `catalog` directory is a standalone TypeScript project that showcases every template with filtering, metadata, and code previews.

## Smart Contract Templates

| Category        | Contracts                                                                    | Highlights                                                                                               |
|-----------------|------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------|
| Tokens          | `StandardERC20.sol`, `StandardERC721.sol`, `StandardERC1155.sol`, `UpgradeableERC20.sol` | Permit + votes support, royalties, whitelist flows, supply guards, UUPS upgradeability.                   |
| Governance      | `GovernanceDAO.sol`, `TimeLock.sol`                                          | Hybrid voting strategies, delegation, EIP-712 signatures, configurable timelocks, batch execution.       |
| Treasury / Multisig | `MultiSigTreasury.sol`, `MultiSigWallet.sol`                            | Multi-role approvals, budgets, time-delayed large transfers, emergency recovery mechanisms.              |
| Auctions        | `EnglishAuction.sol`                                                         | NFT-friendly auctions with bid extensions, reserve pricing, ERC20 settlement, fee routing.               |
| Vesting & Airdrops | `TokenVesting.sol`, `MerkleAirdrop.sol`                                  | Multi-schedule vesting, revocation, batch operations, Merkle proof based distributions.                  |
| Access Control  | `AdvancedAccessControl.sol`                                                  | Role hierarchies, approvals, expirations, delegation, emergency pause controls.                          |
| Proxies         | `ProxyFactory.sol`                                                           | Deterministic CREATE2 factory for UUPS implementations with registry and allow listing.                  |

All templates compile against Solidity `^0.8.20` and assume the OpenZeppelin contracts dependency is available during compilation.

## Frontend Catalog (Next.js)

The `catalog` application provides:

- Kadena-inspired gradient UI with glassmorphism and responsive layout.
- Category, network, tag, and keyword filtering using local metadata.
- Inline code previews fetched from the filesystem through a Next.js route.
- Quick links to Remix and GitHub for each contract template.
- Built with Next.js App Router, Tailwind CSS, and shadcn/ui.

## Prerequisites

- Node.js 20.x recommended (matches Next.js 15 requirements).
- npm 10.x or later.
- pnpm or yarn can be used but npm lockfile is included.

Smart contract compilation and testing can be performed with Hardhat or Foundry. The repository is currently template-focused and does not ship with configuration files for those toolchains; adapt as needed for your environment.

## Getting Started

Clone the repository:

```bash
git clone https://github.com/<your-org>/kadena-bounty-contracts.git
cd kadena-bounty-contracts
```

Install dependencies and run the catalog UI:

```bash
cd catalog
npm install
npm run dev
```

The catalog will be available at `http://localhost:3000`. It loads contract source files directly from the parent directories for quick inspection.

## Working with the Contracts

1. Install OpenZeppelin contracts in your Hardhat or Foundry project:
   ```bash
   npm install @openzeppelin/contracts@^5
   ```
2. Copy the desired template(s) from this repository into your project’s `contracts/` directory.
3. Adjust constructor parameters, access control addresses, thresholds, and role assignments to match your deployment plan.
4. Run security tooling (slither, echidna, foundry tests) as required by your audit process.
5. Deploy via Remix, Hardhat, Foundry, or the Kadena deployment tooling of your choice.

## Customising the Catalog

- Metadata lives in `catalog/src/data/contracts.ts`. Update this file to add new templates, adjust descriptions, or tweak tags.
- Styling tokens are defined in `catalog/src/app/globals.css`; gradients and glass panel utilities can be tuned there.
- Components are located under `catalog/src/components/` and follow the shadcn/ui conventions.

## Contributing

1. Fork the repository and create a feature branch.
2. Update or add Solidity templates with full documentation and follow the file structure.
3. If you add a new template, update `contracts.ts` so it appears in the catalog UI.
4. Run `npm run lint` inside the `catalog` directory before submitting frontend changes.
5. Open a pull request describing the contract or UI enhancement.

## Security Notice

These templates follow industry best practices, but every deployment should undergo project-specific audits, threat modelling, and parameter review. Kadena and the maintainers do not guarantee suitability for production without additional due diligence.

## License

A formal license has not been declared. Until clarified, treat the contents as all rights reserved and request permission before reuse in commercial settings.

---

Made by saiisback.
