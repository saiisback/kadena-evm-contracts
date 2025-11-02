"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import {
  ArrowUpDown,
  Code,
  Filter,
  Github,
  Laptop,
  Rocket,
  Search,
  Sparkles,
} from "lucide-react";

import {
  categories,
  contractTemplates,
  type ContractTemplate,
  type Network,
  sortOptions,
} from "@/data/contracts";
import { cn } from "@/lib/utils";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

type SortValue = (typeof sortOptions)[number]["value"];

const ALL_NETWORKS: Network[] = [
  "Ethereum",
  "Base",
  "Optimism",
  "Arbitrum",
];

interface DetailState {
  code?: string;
  loading?: boolean;
  error?: string;
}

export function CatalogShell() {
  const [searchQuery, setSearchQuery] = useState("");
  const [activeCategory, setActiveCategory] = useState<
    (typeof categories)[number]["value"]
  >("All");
  const [activeNetworks, setActiveNetworks] = useState<Network[]>([]);
  const [activeTags, setActiveTags] = useState<string[]>([]);
  const [sortBy, setSortBy] = useState<SortValue>("popularity");
  const [selectedContract, setSelectedContract] = useState<ContractTemplate | null>(
    contractTemplates[0] ?? null,
  );
  const [detailMap, setDetailMap] = useState<Record<string, DetailState>>({});
  const loadingRef = useRef<Set<string>>(new Set());

  const tags = useMemo(() => {
    const all = new Set<string>();
    contractTemplates.forEach((template) => {
      template.tags.forEach((tag) => all.add(tag));
    });
    return Array.from(all).sort();
  }, []);

  useEffect(() => {
    if (!selectedContract) return;
    const slug = selectedContract.slug;
    const existing = detailMap[slug];
    if (existing?.code || existing?.loading || loadingRef.current.has(slug)) {
      return;
    }

    loadingRef.current.add(slug);

    queueMicrotask(() => {
      setDetailMap((prev) => ({
        ...prev,
        [slug]: { ...prev[slug], loading: true },
      }));
    });

    fetch(`/api/contracts/${slug}/code`)
      .then(async (res) => {
        if (!res.ok) {
          throw new Error((await res.json()).error ?? "Unknown error");
        }
        return res.json();
      })
      .then((data) => {
        loadingRef.current.delete(slug);
        setDetailMap((prev) => ({
          ...prev,
          [slug]: { code: data.code as string },
        }));
      })
      .catch((error: unknown) => {
        loadingRef.current.delete(slug);
        setDetailMap((prev) => ({
          ...prev,
          [slug]: {
            error:
              error instanceof Error ? error.message : "Failed to load contract",
          },
        }));
      });
  }, [detailMap, selectedContract]);

  const filteredContracts = useMemo(() => {
    const lowered = searchQuery.toLowerCase();

    const filtered = contractTemplates.filter((template) => {
      const matchesCategory =
        activeCategory === "All" || template.category === activeCategory;

      const matchesNetworks =
        activeNetworks.length === 0 ||
        activeNetworks.every((network) => template.networks.includes(network));

      const matchesTags =
        activeTags.length === 0 ||
        activeTags.every((tag) => template.tags.includes(tag));

      const matchesQuery =
        lowered.length === 0 ||
        [
          template.name,
          template.contractName,
          template.summary,
          template.type,
          ...template.tags,
          ...template.keywords,
        ]
          .join(" ")
          .toLowerCase()
          .includes(lowered);

      return matchesCategory && matchesNetworks && matchesTags && matchesQuery;
    });

    return filtered.sort((a, b) => {
      if (sortBy === "popularity") {
        return b.popularity - a.popularity;
      }

      if (sortBy === "alphabetical") {
        return a.name.localeCompare(b.name);
      }

      const aDate = new Date(a.lastUpdated).getTime();
      const bDate = new Date(b.lastUpdated).getTime();

      if (sortBy === "newest") {
        return bDate - aDate;
      }

      if (sortBy === "oldest") {
        return aDate - bDate;
      }

      return 0;
    });
  }, [activeCategory, activeNetworks, activeTags, searchQuery, sortBy]);

  const handleNetworkToggle = (network: Network) => {
    setActiveNetworks((prev) =>
      prev.includes(network)
        ? prev.filter((item) => item !== network)
        : [...prev, network],
    );
  };

  const handleTagToggle = (tag: string) => {
    setActiveTags((prev) =>
      prev.includes(tag)
        ? prev.filter((item) => item !== tag)
        : [...prev, tag],
    );
  };

  useEffect(() => {
    if (!selectedContract && filteredContracts.length > 0) {
      queueMicrotask(() => {
        setSelectedContract(filteredContracts[0]);
      });
    }
  }, [filteredContracts, selectedContract]);

  return (
    <div className="relative min-h-screen overflow-hidden bg-[#060714] text-slate-100">
      <div className="pointer-events-none absolute inset-0 -z-10">
        <div className="absolute -top-48 left-1/2 h-[520px] w-[520px] -translate-x-1/2 rounded-full bg-[radial-gradient(circle,rgba(140,76,255,0.45),transparent_60%)] blur-3xl" />
        <div className="absolute -bottom-48 right-[-15%] h-[520px] w-[520px] rounded-full bg-[radial-gradient(circle,rgba(53,195,255,0.35),transparent_60%)] blur-3xl" />
        <div className="absolute -bottom-32 left-[-10%] h-[480px] w-[480px] rounded-full bg-[radial-gradient(circle,rgba(255,76,191,0.32),transparent_60%)] blur-3xl" />
      </div>

      <div className="relative mx-auto flex min-h-screen w-full max-w-7xl flex-col px-6 pb-20 pt-8 md:pt-12">
        <nav className="flex flex-wrap items-center justify-between gap-4 rounded-2xl border border-white/10 bg-white/5 px-6 py-4 shadow-lg shadow-black/30 backdrop-blur-2xl">
          <div className="flex items-center gap-3">
            <div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-gradient-to-br from-[#8c4cff] via-[#ff4cbf] to-[#35c3ff] shadow-lg shadow-[#8c4cff35]">
              <Sparkles className="h-5 w-5 text-white" />
            </div>
            <div className="space-y-1">
              <p className="text-[0.65rem] uppercase tracking-[0.45em] text-slate-400">
                Kadena
              </p>
              <p className="text-lg font-semibold leading-tight kadena-gradient-text">
                Smart Contract Catalog
              </p>
            </div>
          </div>
          <div className="hidden items-center gap-3 sm:flex">
            <Button
              variant="ghost"
              asChild
              className="border border-white/10 bg-white/10 text-slate-100 transition hover:bg-white/20"
            >
              <a href="https://kadena.io" target="_blank" rel="noreferrer">
                Learn about Kadena
              </a>
            </Button>
            <Button
              asChild
              className="bg-gradient-to-r from-[#8c4cff] via-[#ff4cbf] to-[#35c3ff] text-white shadow-lg shadow-[#8c4cff33] transition hover:shadow-[#8c4cff55]"
            >
              <a href="https://github.com/" target="_blank" rel="noreferrer" className="flex items-center gap-2">
                <Github className="h-4 w-4" />
                View Repository
              </a>
            </Button>
          </div>
        </nav>

        <header className="mt-10 space-y-8 rounded-3xl border border-white/10 bg-white/5 p-10 shadow-[0_30px_70px_rgba(8,12,40,0.55)] backdrop-blur-2xl">
          <div className="flex flex-col gap-6 md:flex-row md:items-center md:justify-between">
            <div className="max-w-3xl space-y-6">
              <Badge className="w-fit border-white/20 bg-white/10 px-3 py-1 text-xs uppercase tracking-widest text-slate-100">
                Production-ready Solidity templates
              </Badge>
              <div className="space-y-4">
                <h1 className="text-4xl font-semibold tracking-tight md:text-5xl">
                  Build faster on Chainweb EVM with Kadena-grade smart contracts
                </h1>
                <p className="text-base text-slate-300 md:text-lg">
                  Explore audited-by-design blueprints for DAOs, treasuries, tokens, and airdrops. Curated for multi-chain deployments across Ethereum, Optimism, Base, and Arbitrum—ready for Remix, Hardhat, and Kadena’s developer tooling.
                </p>
              </div>
              <div className="flex flex-wrap items-center gap-3 text-sm text-slate-300">
                <span className="rounded-full bg-white/10 px-3 py-1">OpenZeppelin hardened</span>
                <span className="rounded-full bg-white/10 px-3 py-1">Composable templates</span>
                <span className="rounded-full bg-white/10 px-3 py-1">Remix + Hardhat ready</span>
              </div>
            </div>
            <div className="grid w-full gap-4 sm:grid-cols-3 md:max-w-md">
              <div className="rounded-2xl border border-white/10 bg-white/5 p-4 text-center shadow-inner shadow-black/20">
                <p className="text-xs uppercase tracking-[0.35em] text-slate-400">
                  Templates
                </p>
                <p className="mt-2 text-3xl font-semibold text-white">
                  {contractTemplates.length}
                </p>
                <p className="text-[0.7rem] text-slate-400">Curated blueprints</p>
              </div>
              <div className="rounded-2xl border border-white/10 bg-white/5 p-4 text-center shadow-inner shadow-black/20">
                <p className="text-xs uppercase tracking-[0.35em] text-slate-400">
                  Networks
                </p>
                <p className="mt-2 text-3xl font-semibold text-white">{ALL_NETWORKS.length}</p>
                <p className="text-[0.7rem] text-slate-400">EVM chains supported</p>
              </div>
              <div className="rounded-2xl border border-white/10 bg-white/5 p-4 text-center shadow-inner shadow-black/20">
                <p className="text-xs uppercase tracking-[0.35em] text-slate-400">
                  Tags
                </p>
                <p className="mt-2 text-3xl font-semibold text-white">{tags.length}</p>
                <p className="text-[0.7rem] text-slate-400">Discovery filters</p>
              </div>
            </div>
          </div>
          <div className="flex flex-wrap gap-3">
            <Button
              asChild
              className="bg-gradient-to-r from-[#8c4cff] via-[#ff4cbf] to-[#35c3ff] text-sm font-semibold text-white shadow-lg shadow-[#8c4cff33] transition hover:shadow-[#8c4cff55]"
            >
              <a href="https://remix.ethereum.org" target="_blank" rel="noreferrer" className="flex items-center gap-2">
                <Rocket className="h-4 w-4" />
                Launch in Remix
              </a>
            </Button>
            <Button
              variant="ghost"
              asChild
              className="border border-white/15 bg-white/10 text-sm text-slate-100 transition hover:bg-white/20"
            >
              <a href="https://kadena.io" target="_blank" rel="noreferrer">
                Discover Kadena grants
              </a>
            </Button>
          </div>
        </header>

        <div className="mt-10 flex flex-col gap-8 lg:grid lg:grid-cols-[310px_minmax(0,1fr)]">
          <aside className="flex flex-col gap-6">
            <div className="kadena-border-gradient glass-panel rounded-3xl p-6">
              <p className="text-xs uppercase tracking-[0.35em] text-slate-400">
                Categories
              </p>
              <div className="mt-5 flex flex-col gap-2">
                {categories.map((category) => {
                  const isActive = activeCategory === category.value;
                  return (
                    <Button
                      key={category.value}
                      variant="ghost"
                      onClick={() => setActiveCategory(category.value)}
                      className={cn(
                        "justify-start rounded-2xl border border-transparent bg-white/5 text-sm text-slate-200 transition-all hover:border-white/20 hover:bg-white/10",
                        isActive &&
                          "border-transparent bg-gradient-to-r from-[#8c4cff]/70 via-[#ff4cbf]/70 to-[#35c3ff]/70 text-white shadow-lg shadow-[#8c4cff33] hover:bg-gradient-to-r",
                      )}
                    >
                      <Filter className="mr-2 h-4 w-4" />
                      {category.label}
                    </Button>
                  );
                })}
              </div>
            </div>

            <div className="kadena-border-gradient glass-panel rounded-3xl p-6">
              <p className="text-xs uppercase tracking-[0.35em] text-slate-400">
                Networks
              </p>
              <div className="mt-5 flex flex-wrap gap-3">
                {ALL_NETWORKS.map((network) => {
                  const isActive = activeNetworks.includes(network);
                  return (
                    <Button
                      key={network}
                      size="sm"
                      variant="ghost"
                      onClick={() => handleNetworkToggle(network)}
                      className={cn(
                        "rounded-full border border-white/15 bg-white/5 px-4 text-xs text-slate-200 transition hover:bg-white/15",
                        isActive &&
                          "border-transparent bg-gradient-to-r from-[#8c4cff] to-[#ff4cbf] text-white shadow-md shadow-[#8c4cff44]",
                      )}
                    >
                      {network}
                    </Button>
                  );
                })}
              </div>
            </div>

            <div className="kadena-border-gradient glass-panel rounded-3xl p-6">
              <p className="text-xs uppercase tracking-[0.35em] text-slate-400">
                Tags
              </p>
              <div className="mt-5 flex flex-wrap gap-2">
                {tags.map((tag) => (
                  <Badge
                    key={tag}
                    variant={activeTags.includes(tag) ? "secondary" : "outline"}
                    className={cn(
                      "cursor-pointer rounded-full border border-white/15 bg-white/5 px-3 py-1 text-xs font-medium text-slate-200 transition hover:bg-white/15",
                      activeTags.includes(tag) &&
                        "border-transparent bg-gradient-to-r from-[#8c4cff] to-[#35c3ff] text-white shadow-md shadow-[#8c4cff44]",
                    )}
                    onClick={() => handleTagToggle(tag)}
                  >
                    #{tag}
                  </Badge>
                ))}
              </div>
            </div>
          </aside>

          <main className="kadena-border-gradient glass-panel rounded-3xl p-6 lg:p-8">
            <div className="flex flex-col gap-6">
              <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
                <div className="relative w-full lg:max-w-xl">
                  <Label htmlFor="search" className="sr-only">
                    Search contracts
                  </Label>
                  <Search className="pointer-events-none absolute left-4 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
                  <Input
                    id="search"
                    placeholder="Search by capability, keyword, or contract name"
                    value={searchQuery}
                    onChange={(event) => setSearchQuery(event.target.value)}
                    className="h-12 rounded-2xl border-white/15 bg-white/5 pl-11 text-sm text-slate-100 placeholder:text-slate-400 focus-visible:ring-[#8c4cff]/70"
                  />
                </div>
                <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:gap-4">
                  <div className="flex items-center gap-2">
                    <Label htmlFor="sort" className="text-xs uppercase tracking-[0.3em] text-slate-400">
                      Sort by
                    </Label>
                    <div className="relative">
                      <ArrowUpDown className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-400" />
                      <select
                        id="sort"
                        className="h-12 min-w-[180px] appearance-none rounded-2xl border border-white/15 bg-white/5 pl-10 pr-10 text-sm text-slate-100 outline-none transition focus:border-[#8c4cff]/60 focus:ring-2 focus:ring-[#8c4cff]/30"
                        value={sortBy}
                        onChange={(event) => setSortBy(event.target.value as SortValue)}
                      >
                        {sortOptions.map((option) => (
                          <option key={option.value} value={option.value}>
                            {option.label}
                          </option>
                        ))}
                      </select>
                    </div>
                  </div>
                  {(activeNetworks.length > 0 || activeTags.length > 0) && (
                    <Button
                      variant="ghost"
                      onClick={() => {
                        setActiveNetworks([]);
                        setActiveTags([]);
                      }}
                      className="self-start rounded-full border border-white/15 bg-white/5 px-4 text-xs text-slate-200 transition hover:bg-white/15"
                    >
                      Clear filters
                    </Button>
                  )}
                </div>
              </div>

              <div className="flex flex-col gap-3 lg:hidden">
                <div className="flex flex-wrap gap-2">
                  {ALL_NETWORKS.map((network) => {
                    const isActive = activeNetworks.includes(network);
                    return (
                      <Button
                        key={network}
                        size="sm"
                        variant="ghost"
                        onClick={() => handleNetworkToggle(network)}
                        className={cn(
                          "rounded-full border border-white/15 bg-white/5 px-3 text-xs text-slate-200 transition hover:bg-white/15",
                          isActive &&
                            "border-transparent bg-gradient-to-r from-[#8c4cff] to-[#ff4cbf] text-white",
                        )}
                      >
                        {network}
                      </Button>
                    );
                  })}
                </div>
                <div className="flex flex-wrap gap-2">
                  {tags.slice(0, 8).map((tag) => (
                    <Badge
                      key={tag}
                      variant={activeTags.includes(tag) ? "secondary" : "outline"}
                      className={cn(
                        "cursor-pointer rounded-full border border-white/15 bg-white/5 px-3 py-1 text-xs text-slate-200",
                        activeTags.includes(tag) &&
                          "border-transparent bg-gradient-to-r from-[#8c4cff] to-[#35c3ff] text-white",
                      )}
                      onClick={() => handleTagToggle(tag)}
                    >
                      #{tag}
                    </Badge>
                  ))}
                </div>
              </div>

              <div className="grid gap-6 xl:grid-cols-[minmax(0,1fr)_420px]">
                <div className="space-y-4">
                  {filteredContracts.length === 0 ? (
                    <div className="kadena-border-gradient glass-panel flex flex-col items-center gap-3 rounded-3xl px-10 py-16 text-center text-slate-300">
                      <Filter className="h-10 w-10 text-slate-400" />
                      <p className="text-lg font-semibold text-white">
                        No templates match your filters yet
                      </p>
                      <p className="text-sm text-slate-400">
                        Adjust your networks, tags, or search keywords to explore the full Kadena contract library.
                      </p>
                    </div>
                  ) : (
                    filteredContracts.map((template) => (
                      <Card
                        key={template.slug}
                        className={cn(
                          "group cursor-pointer overflow-hidden rounded-3xl border border-white/10 bg-white/5 transition-all duration-300 hover:-translate-y-1 hover:border-[#8c4cff]/60 hover:bg-white/10 hover:shadow-xl hover:shadow-[#8c4cff22]",
                          selectedContract?.slug === template.slug &&
                            "border-[#8c4cff]/70 bg-white/10 shadow-xl shadow-[#8c4cff33]",
                        )}
                        onClick={() => setSelectedContract(template)}
                      >
                        <CardContent className="space-y-4 p-6">
                          <div className="flex items-start justify-between gap-4">
                            <div className="space-y-2">
                              <h3 className="text-xl font-semibold leading-tight text-white">
                                {template.name}
                              </h3>
                              <p className="text-sm text-slate-300">
                                {template.summary}
                              </p>
                            </div>
                            <Badge className="rounded-full border-white/20 bg-white/10 px-3 py-1 text-xs uppercase tracking-wide text-slate-200">
                              {template.type}
                            </Badge>
                          </div>
                          <div className="flex flex-wrap gap-2">
                            {template.tags.slice(0, 4).map((tag) => (
                              <Badge key={tag} className="rounded-full border-white/15 bg-white/10 px-3 py-1 text-[0.7rem] text-slate-200">
                                #{tag}
                              </Badge>
                            ))}
                          </div>
                          <div className="flex flex-wrap items-center gap-4 text-xs text-slate-400">
                            <span>
                              Updated{" "}
                              {new Date(template.lastUpdated).toLocaleDateString("en-US", {
                                year: "numeric",
                                month: "short",
                                day: "numeric",
                              })}
                            </span>
                            <span>{template.networks.join(" • ")}</span>
                            <span>Popularity score {template.popularity}/100</span>
                          </div>
                        </CardContent>
                        <div className="pointer-events-none absolute inset-x-0 bottom-0 h-1 w-full bg-gradient-to-r from-transparent via-[#8c4cff]/60 to-transparent opacity-0 transition group-hover:opacity-100" />
                      </Card>
                    ))
                  )}
                </div>

                <div className="kadena-border-gradient glass-panel hidden h-full flex-col rounded-3xl xl:flex">
                  {selectedContract ? (
                    <div className="flex h-full flex-col gap-6 p-6 xl:p-8">
                      <div className="space-y-4">
                        <div className="flex flex-wrap items-center gap-3 text-xs uppercase tracking-[0.35em] text-slate-400">
                          <Laptop className="h-4 w-4" />
                          {selectedContract.networks.join(" • ")}
                        </div>
                        <div className="space-y-2">
                          <h2 className="text-3xl font-semibold text-white">
                            {selectedContract.name}
                          </h2>
                          <p className="text-sm text-slate-300">
                            {selectedContract.summary}
                          </p>
                        </div>
                        <div className="flex flex-wrap gap-2">
                          {selectedContract.features.map((feature) => (
                            <Badge key={feature} className="rounded-full border-white/15 bg-white/10 px-3 py-1 text-[0.7rem] text-slate-200">
                              {feature}
                            </Badge>
                          ))}
                        </div>
                      </div>

                      <div className="grid gap-3 text-sm text-slate-300">
                        <div className="flex items-center justify-between">
                          <span className="text-slate-400">Contract</span>
                          <span className="font-medium text-white">{selectedContract.contractName}</span>
                        </div>
                        <div className="flex items-center justify-between">
                          <span className="text-slate-400">Builder</span>
                          <span className="font-medium text-white">{selectedContract.builder}</span>
                        </div>
                        <div className="flex items-center justify-between">
                          <span className="text-slate-400">Repository path</span>
                          <span className="font-medium text-white">
                            {selectedContract.path.replace("../", "")}
                          </span>
                        </div>
                        <div className="flex items-center justify-between">
                          <span className="text-slate-400">Version</span>
                          <span className="font-medium text-white">{selectedContract.version}</span>
                        </div>
                      </div>

                      <div className="flex flex-wrap gap-3">
                        <Button
                          asChild
                          size="sm"
                          className="rounded-full bg-gradient-to-r from-[#8c4cff] via-[#ff4cbf] to-[#35c3ff] px-4 text-xs font-semibold text-white shadow-md shadow-[#8c4cff33]"
                        >
                          <a
                            href={`https://remix.ethereum.org/#load=https://raw.githubusercontent.com/your-org/kadena-bounty-contracts/main/${selectedContract.path.replace("../", "")}`}
                            target="_blank"
                            rel="noreferrer"
                          >
                            <Rocket className="mr-2 h-4 w-4" />
                            Open in Remix
                          </a>
                        </Button>
                        <Button
                          variant="ghost"
                          size="sm"
                          asChild
                          className="rounded-full border border-white/15 bg-white/10 px-4 text-xs text-slate-200 hover:bg-white/15"
                        >
                          <a
                            href={`https://github.com/your-org/kadena-bounty-contracts/blob/main/${selectedContract.path.replace("../", "")}`}
                            target="_blank"
                            rel="noreferrer"
                          >
                            <Code className="mr-2 h-4 w-4" />
                            View on GitHub
                          </a>
                        </Button>
                      </div>

                      <div className="flex-1 overflow-hidden rounded-2xl border border-white/10 bg-[#0c0f2a]/70">
                        <div className="flex items-center justify-between border-b border-white/10 px-4 py-2 text-[0.65rem] uppercase tracking-[0.35em] text-slate-500">
                          <span>{selectedContract.contractName}.sol</span>
                          <span>Read-only preview</span>
                        </div>
                        <CodePreview detail={detailMap[selectedContract.slug]} />
                      </div>
                    </div>
                  ) : (
                    <div className="flex h-full flex-col items-center justify-center gap-3 px-6 py-16 text-center text-slate-300">
                      <Laptop className="h-10 w-10 text-slate-400" />
                      <p className="text-sm">
                        Choose a template to inspect metadata, security features, and source code preview.
                      </p>
                    </div>
                  )}
                </div>
              </div>
            </div>
          </main>
        </div>
      </div>
    </div>
  );
}

function CodePreview({ detail }: { detail?: DetailState }) {
  if (!detail || detail.loading) {
    return (
      <div className="flex items-center justify-center gap-2 px-4 py-8 text-sm text-muted-foreground">
        <span className="h-2 w-2 animate-ping rounded-full bg-muted-foreground" />
        Loading code preview…
      </div>
    );
  }

  if (detail.error) {
    return (
      <div className="px-4 py-8 text-sm text-destructive">
        Unable to load contract preview: {detail.error}
      </div>
    );
  }

  return (
    <pre className="max-h-72 overflow-auto bg-transparent p-4 text-[0.78rem] leading-relaxed text-slate-100/90">
      <code>{detail.code}</code>
    </pre>
  );
}

