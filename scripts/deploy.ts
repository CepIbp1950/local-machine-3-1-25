/**
 * deploy.ts
 *
 * Deploys the full ERC-3643 (T-REX) suite to the selected network:
 *
 *   1. ClaimTopicsRegistry  – required claim topics (e.g. KYC)
 *   2. TrustedIssuersRegistry – addresses authorised to issue claims
 *   3. IdentityRegistry     – maps investor wallets → on-chain identities
 *   4. ModularCompliance    – pluggable transfer-rule engine
 *   5. Token                – the ERC-3643 security token
 *
 * After deployment the script wires everything together and mints a small
 * allocation to the deployer as a smoke-test.
 *
 * Usage:
 *   npx hardhat run scripts/deploy.ts               # in-process Hardhat network
 *   npx hardhat run scripts/deploy.ts --network sepolia
 */

import { network } from "hardhat";

const KYC_CLAIM_TOPIC = 1n; // numeric identifier for a KYC claim

async function main() {
  const { ethers } = await network.connect();
  const [deployer] = await ethers.getSigners();
  const deployerAddr = await deployer.getAddress();

  console.log("─────────────────────────────────────────────────");
  console.log("ERC-3643 demo deployment");
  console.log("Network  :", network.name);
  console.log("Deployer :", deployerAddr);
  console.log("─────────────────────────────────────────────────");

  // 1. ClaimTopicsRegistry
  console.log("\n[1/5] Deploying ClaimTopicsRegistry …");
  const ctr = await ethers.deployContract("ClaimTopicsRegistry");
  await ctr.waitForDeployment();
  const ctrAddr = await ctr.getAddress();
  console.log("      ClaimTopicsRegistry :", ctrAddr);

  // Register KYC as a required claim topic
  await (await ctr.addClaimTopic(KYC_CLAIM_TOPIC)).wait();
  console.log("      Added KYC claim topic:", KYC_CLAIM_TOPIC.toString());

  // 2. TrustedIssuersRegistry
  console.log("\n[2/5] Deploying TrustedIssuersRegistry …");
  const tir = await ethers.deployContract("TrustedIssuersRegistry");
  await tir.waitForDeployment();
  const tirAddr = await tir.getAddress();
  console.log("      TrustedIssuersRegistry :", tirAddr);

  // Use the deployer as the demo trusted issuer
  await (await tir.addTrustedIssuer(deployerAddr, [KYC_CLAIM_TOPIC])).wait();
  console.log("      Trusted issuer (deployer):", deployerAddr);

  // 3. IdentityRegistry
  console.log("\n[3/5] Deploying IdentityRegistry …");
  const ir = await ethers.deployContract("IdentityRegistry", [ctrAddr, tirAddr]);
  await ir.waitForDeployment();
  const irAddr = await ir.getAddress();
  console.log("      IdentityRegistry :", irAddr);

  // 4. ModularCompliance
  console.log("\n[4/5] Deploying ModularCompliance …");
  const compliance = await ethers.deployContract("ModularCompliance");
  await compliance.waitForDeployment();
  const complianceAddr = await compliance.getAddress();
  console.log("      ModularCompliance :", complianceAddr);

  // 5. Token
  console.log("\n[5/5] Deploying Token …");
  const token = await ethers.deployContract("Token", [
    irAddr,
    complianceAddr,
    "Demo Security Token",
    "DST",
    18,
    ethers.ZeroAddress, // onchainID placeholder — replace with real ONCHAINID in production
  ]);
  await token.waitForDeployment();
  const tokenAddr = await token.getAddress();
  console.log("      Token :", tokenAddr);

  // ── Wire compliance to the token ──────────────────────────────────────────
  console.log("\n── Wiring contracts …");
  await (await compliance.bindToken(tokenAddr)).wait();
  console.log("   Compliance bound to token");

  // ── Register the deployer as a verified investor (demo) ──────────────────
  // In production every investor wallet would be registered here after KYC.
  await (await ir.registerIdentity(deployerAddr, deployerAddr, 840 /* USA */)).wait();
  console.log("   Deployer registered as verified investor (country: USA)");

  // ── Mint initial supply to the deployer ──────────────────────────────────
  const initialSupply = ethers.parseUnits("1000000", 18); // 1 million DST
  await (await token.mint(deployerAddr, initialSupply)).wait();
  console.log("   Minted", ethers.formatUnits(initialSupply, 18), "DST to deployer");

  console.log("\n─────────────────────────────────────────────────");
  console.log("Deployment complete — contract addresses:");
  console.log("  ClaimTopicsRegistry    :", ctrAddr);
  console.log("  TrustedIssuersRegistry :", tirAddr);
  console.log("  IdentityRegistry       :", irAddr);
  console.log("  ModularCompliance      :", complianceAddr);
  console.log("  Token (DST)            :", tokenAddr);
  console.log("─────────────────────────────────────────────────");
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
