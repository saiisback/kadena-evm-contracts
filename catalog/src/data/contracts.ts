export type Network = "Ethereum" | "Base" | "Optimism" | "Arbitrum";

export type ContractCategory =
  | "Tokens"
  | "Governance"
  | "Treasury"
  | "Access Control"
  | "Auctions"
  | "Airdrops"
  | "Vesting"
  | "Proxies";

export interface ContractTemplate {
  slug: string;
  name: string;
  contractName: string;
  category: ContractCategory;
  type: string;
  summary: string;
  builder: string;
  path: string;
  tags: string[];
  features: string[];
  networks: Network[];
  lastUpdated: string;
  version: string;
  popularity: number;
  keywords: string[];
}

export const contractTemplates: ContractTemplate[] = [
  {
    slug: "standard-erc20",
    name: "Standard ERC20",
    contractName: "StandardERC20",
    category: "Tokens",
    type: "ERC20",
    summary:
      "Fully featured ERC20 token with permit, votes, fee routing, and anti-whale controls built on OpenZeppelin primitives.",
    builder: "Kadena Bounty Team",
    path: "../tokens/StandardERC20.sol",
    tags: ["erc20", "token", "governance", "defi"],
    features: [
      "EIP-2612 permit",
      "EIP-5805 votes",
      "Transfer fee routing",
      "Max transaction guards",
      "Emergency pause",
    ],
    networks: ["Ethereum", "Base", "Optimism", "Arbitrum"],
    lastUpdated: "2024-10-01",
    version: "1.0.0",
    popularity: 92,
    keywords: ["erc20", "votes", "permit", "treasury", "governance"],
  },
  {
    slug: "standard-erc721",
    name: "Standard ERC721",
    contractName: "StandardERC721",
    category: "Tokens",
    type: "ERC721",
    summary:
      "Production-grade ERC721 NFT collection with whitelist phases, reveal controls, and EIP-2981 royalties.",
    builder: "Kadena Bounty Team",
    path: "../tokens/StandardERC721.sol",
    tags: ["erc721", "nft", "royalties", "whitelist"],
    features: [
      "Whitelist and public mint phases",
      "Metadata reveal toggles",
      "Per-wallet limits",
      "EIP-2981 royalties",
      "Batch minting",
    ],
    networks: ["Ethereum", "Base", "Optimism", "Arbitrum"],
    lastUpdated: "2024-10-02",
    version: "1.0.0",
    popularity: 88,
    keywords: ["nft", "erc721", "royalty", "mint", "whitelist"],
  },
  {
    slug: "standard-erc1155",
    name: "Standard ERC1155",
    contractName: "StandardERC1155",
    category: "Tokens",
    type: "ERC1155",
    summary:
      "Advanced ERC1155 multi-token implementation with creator royalties, platform fees, and whitelist minting.",
    builder: "Kadena Bounty Team",
    path: "../tokens/StandardERC1155.sol",
    tags: ["erc1155", "multi-token", "royalties", "whitelist"],
    features: [
      "Creator royalty routing",
      "Per-token max supply",
      "Whitelist mint flows",
      "Platform fee distribution",
      "Batch mint APIs",
    ],
    networks: ["Ethereum", "Base", "Optimism", "Arbitrum"],
    lastUpdated: "2024-10-03",
    version: "1.0.0",
    popularity: 84,
    keywords: ["erc1155", "multi-token", "royalty", "creator", "marketplace"],
  },
  {
    slug: "governance-dao",
    name: "Governance DAO",
    contractName: "GovernanceDAO",
    category: "Governance",
    type: "DAO",
    summary:
      "Compound-style governance engine with token/NFT voting, EIP-712 signatures, and timelocked execution.",
    builder: "Kadena Bounty Team",
    path: "../governance/GovernanceDAO.sol",
    tags: ["dao", "governance", "voting", "timelock"],
    features: [
      "Snapshot-based voting power",
      "Hybrid voting strategies",
      "EIP-712 vote signatures",
      "Delegation tracking",
      "Guardian permissions",
    ],
    networks: ["Ethereum", "Base", "Optimism", "Arbitrum"],
    lastUpdated: "2024-10-05",
    version: "1.0.0",
    popularity: 95,
    keywords: ["dao", "governance", "delegation", "proposal", "voting"],
  },
  {
    slug: "timelock-controller",
    name: "Timelock Controller",
    contractName: "TimeLock",
    category: "Governance",
    type: "Timelock",
    summary:
      "Secure timelock controller providing delayed execution, batch queueing, and emergency cancellation hooks.",
    builder: "Kadena Bounty Team",
    path: "../governance/TimeLock.sol",
    tags: ["timelock", "governance", "security"],
    features: [
      "Configurable delay windows",
      "Grace period enforcement",
      "Batch queue & execute",
      "Admin transfer flow",
      "Emergency recovery",
    ],
    networks: ["Ethereum", "Base", "Optimism", "Arbitrum"],
    lastUpdated: "2024-10-04",
    version: "1.0.0",
    popularity: 89,
    keywords: ["timelock", "dao", "queue", "governance"],
  },
  {
    slug: "multisig-treasury",
    name: "MultiSig Treasury",
    contractName: "MultiSigTreasury",
    category: "Treasury",
    type: "Treasury",
    summary:
      "Operator-friendly multi-signature treasury with budgets, token support, and timelocked large transfers.",
    builder: "Kadena Bounty Team",
    path: "../defi/MultiSigTreasury.sol",
    tags: ["multisig", "treasury", "budgets", "security"],
    features: [
      "Configurable confirmation threshold",
      "Budgeting per asset",
      "Time delay for high value",
      "ERC20 safe transfers",
      "Emergency pause",
    ],
    networks: ["Ethereum", "Base", "Optimism", "Arbitrum"],
    lastUpdated: "2024-10-06",
    version: "1.0.0",
    popularity: 91,
    keywords: ["multisig", "treasury", "dao", "budget"],
  },
  {
    slug: "english-auction",
    name: "English Auction",
    contractName: "EnglishAuction",
    category: "Auctions",
    type: "Auction",
    summary:
      "NFT-friendly English auction with bid extensions, ETH/ERC20 support, and platform fee routing.",
    builder: "Kadena Bounty Team",
    path: "../defi/EnglishAuction.sol",
    tags: ["auction", "nft", "marketplace", "fees"],
    features: [
      "Bid extension anti-sniping",
      "Reserve price enforcement",
      "ERC20 payments",
      "Fee recipient routing",
      "Emergency cancellation",
    ],
    networks: ["Ethereum", "Base", "Optimism", "Arbitrum"],
    lastUpdated: "2024-10-07",
    version: "1.0.0",
    popularity: 86,
    keywords: ["auction", "nft", "marketplace", "fees"],
  },
  {
    slug: "token-vesting",
    name: "Token Vesting",
    contractName: "TokenVesting",
    category: "Vesting",
    type: "Vesting",
    summary:
      "Flexible token vesting manager supporting multiple schedules, cliffs, and revocable grants.",
    builder: "Kadena Bounty Team",
    path: "../defi/TokenVesting.sol",
    tags: ["vesting", "token", "team", "treasury"],
    features: [
      "Multiple schedules per user",
      "Linear release with cliffs",
      "Batch creation helper",
      "Revocation support",
      "Withdrawable surplus",
    ],
    networks: ["Ethereum", "Base", "Optimism", "Arbitrum"],
    lastUpdated: "2024-10-08",
    version: "1.0.0",
    popularity: 90,
    keywords: ["vesting", "treasury", "token", "cliff"],
  },
  {
    slug: "merkle-airdrop",
    name: "Merkle Airdrop",
    contractName: "MerkleAirdrop",
    category: "Airdrops",
    type: "Airdrop",
    summary:
      "Gas-efficient Merkle-tree airdrop manager supporting multiple campaigns and batch claims.",
    builder: "Kadena Bounty Team",
    path: "../defi/MerkleAirdrop.sol",
    tags: ["airdrop", "merkle", "distribution", "campaign"],
    features: [
      "Multiple campaign registry",
      "Proof verification",
      "Batch claims",
      "Claim window management",
      "Emergency recovery",
    ],
    networks: ["Ethereum", "Base", "Optimism", "Arbitrum"],
    lastUpdated: "2024-10-09",
    version: "1.0.0",
    popularity: 83,
    keywords: ["airdrop", "merkle", "distribution", "campaign"],
  },
  {
    slug: "advanced-access-control",
    name: "Advanced Access Control",
    contractName: "AdvancedAccessControl",
    category: "Access Control",
    type: "Access Control",
    summary:
      "Role orchestration layer with multi-approver workflows, delegation, and timeboxed assignments.",
    builder: "Kadena Bounty Team",
    path: "../access/AdvancedAccessControl.sol",
    tags: ["access-control", "roles", "security"],
    features: [
      "Hierarchical roles",
      "Approval workflows",
      "Role expirations",
      "Delegation",
      "Emergency pause",
    ],
    networks: ["Ethereum", "Base", "Optimism", "Arbitrum"],
    lastUpdated: "2024-10-10",
    version: "1.0.0",
    popularity: 82,
    keywords: ["access", "roles", "security", "delegation"],
  },
  {
    slug: "multisig-wallet",
    name: "MultiSig Wallet",
    contractName: "MultiSigWallet",
    category: "Treasury",
    type: "MultiSig",
    summary:
      "Lightweight multisig wallet with whitelist transfers, daily limits, and emergency recovery hooks.",
    builder: "Kadena Bounty Team",
    path: "../access/MultiSigWallet.sol",
    tags: ["multisig", "wallet", "security", "treasury"],
    features: [
      "Owner time-lock changes",
      "Whitelist instant transfers",
      "Daily spend limits",
      "Emergency recovery",
      "Transaction history",
    ],
    networks: ["Ethereum", "Base", "Optimism", "Arbitrum"],
    lastUpdated: "2024-10-08",
    version: "1.0.0",
    popularity: 87,
    keywords: ["multisig", "wallet", "treasury", "security"],
  },
  {
    slug: "upgradeable-erc20",
    name: "Upgradeable ERC20",
    contractName: "UpgradeableERC20",
    category: "Tokens",
    type: "UUPS ERC20",
    summary:
      "UUPS upgradeable ERC20 token with fee routing, blacklist, and pause controls using OZ Upgradeable suite.",
    builder: "Kadena Bounty Team",
    path: "../proxy/UpgradeableERC20.sol",
    tags: ["erc20", "uups", "upgradeable", "defi"],
    features: [
      "UUPS upgrade hooks",
      "Fee recipient routing",
      "Blacklist enforcement",
      "Anti-whale limits",
      "Emergency pause",
    ],
    networks: ["Ethereum", "Base", "Optimism", "Arbitrum"],
    lastUpdated: "2024-10-09",
    version: "1.0.0",
    popularity: 93,
    keywords: ["erc20", "uups", "upgradeable", "defi", "fee"],
  },
  {
    slug: "proxy-factory",
    name: "Proxy Factory",
    contractName: "ProxyFactory",
    category: "Proxies",
    type: "UUPS Factory",
    summary:
      "CREATE2-based proxy factory for deploying deterministic UUPS proxies with implementation allow lists.",
    builder: "Kadena Bounty Team",
    path: "../proxy/ProxyFactory.sol",
    tags: ["proxy", "factory", "create2", "uups"],
    features: [
      "Implementation allow list",
      "Proxy registry",
      "Batch deployments",
      "Address prediction",
      "User deployment tracking",
    ],
    networks: ["Ethereum", "Base", "Optimism", "Arbitrum"],
    lastUpdated: "2024-10-11",
    version: "1.0.0",
    popularity: 85,
    keywords: ["proxy", "create2", "deployment", "factory"],
  },
];

export const categories: { label: string; value: "All" | ContractCategory }[] = [
  { label: "All", value: "All" },
  { label: "Tokens", value: "Tokens" },
  { label: "Governance", value: "Governance" },
  { label: "Treasury", value: "Treasury" },
  { label: "Access Control", value: "Access Control" },
  { label: "Auctions", value: "Auctions" },
  { label: "Airdrops", value: "Airdrops" },
  { label: "Vesting", value: "Vesting" },
  { label: "Proxies", value: "Proxies" },
];

export const sortOptions = [
  { label: "Most Used", value: "popularity" },
  { label: "Newest", value: "newest" },
  { label: "Oldest", value: "oldest" },
  { label: "Alphabetical", value: "alphabetical" },
];

export function getContractBySlug(slug: string) {
  return contractTemplates.find((template) => template.slug === slug);
}

