# ERC-3643 Demo

A minimal, self-contained demonstration of the [ERC-3643 (T-REX)](https://eips.ethereum.org/EIPS/eip-3643) security-token standard built with [Hardhat v3](https://hardhat.org/) and [OpenZeppelin Contracts v5](https://docs.openzeppelin.com/contracts/5.x/).

## What is ERC-3643?

ERC-3643 (Token for Regulated EXchanges — T-REX) extends ERC-20 with on-chain
compliance rules for regulated securities:

| Component | Purpose |
|-----------|---------|
| **ClaimTopicsRegistry** | Defines which identity claims (e.g. KYC) are required to hold tokens |
| **TrustedIssuersRegistry** | Lists addresses authorised to issue those claims |
| **IdentityRegistry** | Maps each investor wallet to a verified on-chain identity |
| **ModularCompliance** | Pluggable rule engine that can block or allow individual transfers |
| **Token** | ERC-20 compatible token that enforces all the above on every transfer |

## Project layout

```
contracts/
  interfaces/          IERC3643, IIdentityRegistry, IModularCompliance, …
  registry/            ClaimTopicsRegistry, TrustedIssuersRegistry, IdentityRegistry
  compliance/          ModularCompliance
  token/               Token
scripts/
  deploy.ts            End-to-end deployment + smoke-test
test/
  erc3643.test.ts      Mocha / Chai test suite
hardhat.config.ts
tsconfig.json
```

## Prerequisites

- Node.js ≥ 18
- npm ≥ 9

## Setup

```bash
npm install
```

## Compile

```bash
npm run compile
```

## Test

```bash
npm test
```

## Deploy (local Hardhat network)

```bash
npm run deploy:local
```

## Deploy (Sepolia testnet)

Create a `.env` file (never commit it):

```
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/<your-key>
SEPOLIA_PRIVATE_KEY=0x<your-private-key>
```

Then run:

```bash
npm run deploy:sepolia
```

> **Note:** For a production deployment you would replace the `onchainID`
> placeholder (`address(0)`) with a real [ONCHAINID](https://onchainid.com/)
> contract address and integrate a full ERC-734 / ERC-735 identity system for
> verifying investor claims on-chain.
