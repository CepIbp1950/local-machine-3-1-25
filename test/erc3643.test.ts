/**
 * ERC-3643 test suite
 *
 * Covers the core ERC-3643 lifecycle:
 *   • Registry management (claim topics, trusted issuers, identity)
 *   • Compliance contract setup
 *   • Token minting only to verified investors
 *   • Transfer compliance (verified ↔ unverified)
 *   • Pause / freeze / partial-freeze
 *   • Batch operations
 *   • Address recovery
 */

import { expect } from "chai";
import { network } from "hardhat";

const KYC_TOPIC = 1n;

describe("ERC-3643 Demo", function () {
  // Shared fixtures resolved once per `describe` block via lazy init
  async function deployAll() {
    const { ethers } = await network.connect();
    const [owner, issuer, alice, bob, charlie] = await ethers.getSigners();

    // ── registries ────────────────────────────────────────────────────────
    const ctr = await ethers.deployContract("ClaimTopicsRegistry");
    await ctr.waitForDeployment();

    const tir = await ethers.deployContract("TrustedIssuersRegistry");
    await tir.waitForDeployment();

    const ir = await ethers.deployContract("IdentityRegistry", [
      await ctr.getAddress(),
      await tir.getAddress(),
    ]);
    await ir.waitForDeployment();

    // ── compliance ────────────────────────────────────────────────────────
    const compliance = await ethers.deployContract("ModularCompliance");
    await compliance.waitForDeployment();

    // ── token ─────────────────────────────────────────────────────────────
    const token = await ethers.deployContract("Token", [
      await ir.getAddress(),
      await compliance.getAddress(),
      "Demo Security Token",
      "DST",
      18,
      ethers.ZeroAddress,
    ]);
    await token.waitForDeployment();

    // bind compliance → token
    await compliance.bindToken(await token.getAddress());

    return { ethers, owner, issuer, alice, bob, charlie, ctr, tir, ir, compliance, token };
  }

  // ── helper: fully onboard a KYC'd investor ──────────────────────────────
  async function onboard(
    fixtures: Awaited<ReturnType<typeof deployAll>>,
    investorAddress: string,
    country = 840,
  ) {
    const { ctr, tir, ir, issuer } = fixtures;
    // Ensure KYC topic + issuer are set up
    if (!(await ctr.isClaimTopicRequired(KYC_TOPIC))) {
      await ctr.addClaimTopic(KYC_TOPIC);
    }
    const issuerAddr = await issuer.getAddress();
    if (!(await tir.isTrustedIssuer(issuerAddr))) {
      await tir.addTrustedIssuer(issuerAddr, [KYC_TOPIC]);
    }
    if (!(await ir.contains(investorAddress))) {
      await ir.registerIdentity(investorAddress, investorAddress, country);
    }
  }

  // =========================================================================
  describe("ClaimTopicsRegistry", function () {
    it("owner can add and remove claim topics", async function () {
      const { ctr } = await deployAll();

      await ctr.addClaimTopic(KYC_TOPIC);
      expect(await ctr.isClaimTopicRequired(KYC_TOPIC)).to.be.true;
      expect((await ctr.getClaimTopics()).length).to.equal(1);

      await ctr.removeClaimTopic(KYC_TOPIC);
      expect(await ctr.isClaimTopicRequired(KYC_TOPIC)).to.be.false;
      expect((await ctr.getClaimTopics()).length).to.equal(0);
    });

    it("reverts when adding a duplicate topic", async function () {
      const { ctr } = await deployAll();
      await ctr.addClaimTopic(KYC_TOPIC);
      await expect(ctr.addClaimTopic(KYC_TOPIC)).to.be.revertedWith(
        "ClaimTopicsRegistry: topic already exists",
      );
    });

    it("non-owner cannot add a claim topic", async function () {
      const { ctr, alice, ethers } = await deployAll();
      await expect(ctr.connect(alice).addClaimTopic(KYC_TOPIC)).to.revert(ethers);
    });
  });

  // =========================================================================
  describe("TrustedIssuersRegistry", function () {
    it("owner can add a trusted issuer", async function () {
      const { tir, issuer } = await deployAll();
      const issuerAddr = await issuer.getAddress();
      await tir.addTrustedIssuer(issuerAddr, [KYC_TOPIC]);

      expect(await tir.isTrustedIssuer(issuerAddr)).to.be.true;
      expect(await tir.hasClaimTopic(issuerAddr, KYC_TOPIC)).to.be.true;
    });

    it("owner can remove a trusted issuer", async function () {
      const { tir, issuer } = await deployAll();
      const issuerAddr = await issuer.getAddress();
      await tir.addTrustedIssuer(issuerAddr, [KYC_TOPIC]);
      await tir.removeTrustedIssuer(issuerAddr);

      expect(await tir.isTrustedIssuer(issuerAddr)).to.be.false;
    });

    it("reverts when adding an issuer with no claim topics", async function () {
      const { tir, issuer } = await deployAll();
      await expect(
        tir.addTrustedIssuer(await issuer.getAddress(), []),
      ).to.be.revertedWith("TrustedIssuersRegistry: empty claim topics");
    });
  });

  // =========================================================================
  describe("IdentityRegistry", function () {
    it("registers and verifies an investor when all setup is correct", async function () {
      const { alice } = await deployAll();
      const fixtures = await deployAll();
      await onboard(fixtures, await alice.getAddress());

      expect(await fixtures.ir.contains(await alice.getAddress())).to.be.true;
      expect(await fixtures.ir.isVerified(await alice.getAddress())).to.be.true;
    });

    it("returns false for unregistered investor", async function () {
      const { ir, bob } = await deployAll();
      expect(await ir.isVerified(await bob.getAddress())).to.be.false;
    });

    it("agent can delete an identity", async function () {
      const fixtures = await deployAll();
      const { ir, alice } = fixtures;
      await onboard(fixtures, await alice.getAddress());
      await ir.deleteIdentity(await alice.getAddress());
      expect(await ir.contains(await alice.getAddress())).to.be.false;
    });
  });

  // =========================================================================
  describe("Token – minting", function () {
    it("mints to a verified investor", async function () {
      const fixtures = await deployAll();
      const { token, alice, ethers } = fixtures;
      const aliceAddr = await alice.getAddress();
      await onboard(fixtures, aliceAddr);

      const amount = ethers.parseUnits("1000", 18);
      await token.mint(aliceAddr, amount);

      expect(await token.balanceOf(aliceAddr)).to.equal(amount);
    });

    it("reverts when minting to an unverified address", async function () {
      const { token, bob, ethers } = await deployAll();
      await expect(
        token.mint(await bob.getAddress(), ethers.parseUnits("100", 18)),
      ).to.be.revertedWith("Token: identity not verified");
    });
  });

  // =========================================================================
  describe("Token – transfers", function () {
    it("allows transfer between two verified investors", async function () {
      const fixtures = await deployAll();
      const { token, alice, bob, ethers } = fixtures;
      const aliceAddr = await alice.getAddress();
      const bobAddr = await bob.getAddress();
      await onboard(fixtures, aliceAddr);
      await onboard(fixtures, bobAddr);

      const amount = ethers.parseUnits("500", 18);
      await token.mint(aliceAddr, amount);
      await token.connect(alice).transfer(bobAddr, amount);

      expect(await token.balanceOf(bobAddr)).to.equal(amount);
    });

    it("reverts when recipient is not verified", async function () {
      const fixtures = await deployAll();
      const { token, alice, bob, ethers } = fixtures;
      const aliceAddr = await alice.getAddress();
      await onboard(fixtures, aliceAddr);

      const amount = ethers.parseUnits("100", 18);
      await token.mint(aliceAddr, amount);

      await expect(
        token.connect(alice).transfer(await bob.getAddress(), amount),
      ).to.be.revertedWith("Token: recipient identity not verified");
    });
  });

  // =========================================================================
  describe("Token – pause", function () {
    it("owner can pause and unpause the token", async function () {
      const fixtures = await deployAll();
      const { token, alice, bob, ethers } = fixtures;
      const aliceAddr = await alice.getAddress();
      const bobAddr = await bob.getAddress();
      await onboard(fixtures, aliceAddr);
      await onboard(fixtures, bobAddr);

      const amount = ethers.parseUnits("100", 18);
      await token.mint(aliceAddr, amount);

      await token.pause();
      expect(await token.paused()).to.be.true;

      await expect(
        token.connect(alice).transfer(bobAddr, amount),
      ).to.be.revertedWith("Token: token is paused");

      await token.unpause();
      await token.connect(alice).transfer(bobAddr, amount);
      expect(await token.balanceOf(bobAddr)).to.equal(amount);
    });
  });

  // =========================================================================
  describe("Token – freeze", function () {
    it("frozen address cannot send tokens", async function () {
      const fixtures = await deployAll();
      const { token, alice, bob, ethers } = fixtures;
      const aliceAddr = await alice.getAddress();
      await onboard(fixtures, aliceAddr);
      await onboard(fixtures, await bob.getAddress());

      const amount = ethers.parseUnits("200", 18);
      await token.mint(aliceAddr, amount);
      await token.setAddressFrozen(aliceAddr, true);

      await expect(
        token.connect(alice).transfer(await bob.getAddress(), amount),
      ).to.be.revertedWith("Token: sender is frozen");
    });

    it("partial freeze reduces transferable balance", async function () {
      const fixtures = await deployAll();
      const { token, alice, bob, ethers } = fixtures;
      const aliceAddr = await alice.getAddress();
      const bobAddr = await bob.getAddress();
      await onboard(fixtures, aliceAddr);
      await onboard(fixtures, bobAddr);

      const total = ethers.parseUnits("500", 18);
      const frozen = ethers.parseUnits("300", 18);
      const transferable = total - frozen;

      await token.mint(aliceAddr, total);
      await token.freezePartialTokens(aliceAddr, frozen);

      // Trying to transfer more than unfrozen balance should revert
      await expect(
        token.connect(alice).transfer(bobAddr, total),
      ).to.be.revertedWith("Token: amount exceeds available (unfrozen) balance");

      // Transferring exactly the unfrozen portion succeeds
      await token.connect(alice).transfer(bobAddr, transferable);
      expect(await token.balanceOf(bobAddr)).to.equal(transferable);
    });
  });

  // =========================================================================
  describe("Token – batch operations", function () {
    it("batchMint distributes tokens to multiple verified investors", async function () {
      const fixtures = await deployAll();
      const { token, alice, bob, ethers } = fixtures;
      const aliceAddr = await alice.getAddress();
      const bobAddr = await bob.getAddress();
      await onboard(fixtures, aliceAddr);
      await onboard(fixtures, bobAddr);

      const amt = ethers.parseUnits("100", 18);
      await token.batchMint([aliceAddr, bobAddr], [amt, amt]);

      expect(await token.balanceOf(aliceAddr)).to.equal(amt);
      expect(await token.balanceOf(bobAddr)).to.equal(amt);
    });

    it("batchBurn removes tokens from multiple addresses", async function () {
      const fixtures = await deployAll();
      const { token, alice, bob, ethers } = fixtures;
      const aliceAddr = await alice.getAddress();
      const bobAddr = await bob.getAddress();
      await onboard(fixtures, aliceAddr);
      await onboard(fixtures, bobAddr);

      const amt = ethers.parseUnits("200", 18);
      await token.batchMint([aliceAddr, bobAddr], [amt, amt]);
      await token.batchBurn([aliceAddr, bobAddr], [amt, amt]);

      expect(await token.balanceOf(aliceAddr)).to.equal(0n);
      expect(await token.balanceOf(bobAddr)).to.equal(0n);
    });
  });

  // =========================================================================
  describe("Token – recovery", function () {
    it("agent can recover tokens from a lost wallet to a new wallet", async function () {
      const fixtures = await deployAll();
      const { token, alice, charlie, ethers } = fixtures;
      const aliceAddr = await alice.getAddress();
      const charlieAddr = await charlie.getAddress();
      await onboard(fixtures, aliceAddr);
      await onboard(fixtures, charlieAddr);

      const amount = ethers.parseUnits("1000", 18);
      await token.mint(aliceAddr, amount);

      await token.recoveryAddress(aliceAddr, charlieAddr, aliceAddr);

      expect(await token.balanceOf(aliceAddr)).to.equal(0n);
      expect(await token.balanceOf(charlieAddr)).to.equal(amount);
    });
  });

  // =========================================================================
  describe("ModularCompliance", function () {
    it("reports canTransfer = true when no modules are bound", async function () {
      const fixtures = await deployAll();
      const { compliance, alice, bob } = fixtures;
      const result = await compliance.canTransfer(
        await alice.getAddress(),
        await bob.getAddress(),
        1n,
      );
      expect(result).to.be.true;
    });

    it("only owner can add a module", async function () {
      const { compliance, alice, ethers } = await deployAll();
      await expect(compliance.connect(alice).addModule(alice.getAddress())).to.revert(ethers);
    });
  });
});
