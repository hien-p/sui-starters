# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**@sui-starters** is an MVR (Move Version Registry) package ecosystem for the Sui blockchain. The strategy is to deploy reusable Move libraries that developers can import via MVR, scaffold starter projects using Sui CLI Web, and accumulate interoperating transactions.

## Package Architecture

### Tier 1: Core Libraries (Deploy First)
- `@sui-starters/core` - Math, strings, vectors, time utilities
- `@sui-starters/access` - Roles, permissions, admin caps, pausable
- `@sui-starters/events` - Standardized event structs for indexing

### Tier 2: Domain Libraries
- `@sui-starters/nft` - Collection, mint, display, royalties, attributes
- `@sui-starters/token` - Fungible tokens, vesting, airdrop
- `@sui-starters/defi` - Pool math, LP tokens, TWAP oracle
- `@sui-starters/escrow` - Atomic swaps, timelocks, multisig

### Tier 3: Full Templates
Templates combine packages above: Counter, NFT Collection, DeFi Token, Game Item, Marketplace, AMM Pool

## Build Commands

Move packages use standard Sui CLI:
```bash
sui move build
sui move test
sui client publish --gas-budget 100000000
```

## Code Style for Move Modules

- Use safe math operations from `sui_starters_core::math`
- All packages should be composable and work together
- Follow the module structure pattern shown in plan doc:
  - Structs section
  - Events section
  - Init function
  - Public entry functions
  - View functions

## MVR Dependencies Format

Projects importing these packages use:
```toml
[dependencies]
sui-starters-core = { mvr = "@sui-starters/core" }
sui-starters-nft = { mvr = "@sui-starters/nft" }
```

## Key Design Decisions

- Packages designed for maximum reuse across NFT, DeFi, and game projects
- Access control uses capability pattern (`AdminCap<T>`)
- Role-based access via bitfield flags (ADMIN=1, MINTER=2, PAUSER=4, OPERATOR=8)
- Standardized events for indexer compatibility
- Math uses basis points (bps) for percentages and fixed-point for DeFi precision
