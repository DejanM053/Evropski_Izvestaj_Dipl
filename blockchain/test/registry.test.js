const { expect } = require("chai");
const { ethers } = require("hardhat");

function toBytes32(input) {
  return ethers.keccak256(ethers.toUtf8Bytes(input));
}

describe("AccidentRegistry", function () {
  let registry;
  let submitter;

  beforeEach(async function () {
    [submitter] = await ethers.getSigners();
    const AccidentRegistry = await ethers.getContractFactory("AccidentRegistry");
    registry = await AccidentRegistry.deploy();
    await registry.waitForDeployment();
  });

  it("anchors a report and emits ReportAnchored", async function () {
    const reportId = toBytes32("report-1");
    const pdfHash = toBytes32("pdf-1");
    const bundleHash = toBytes32("bundle-1");

    const tx = await registry.anchor(reportId, pdfHash, bundleHash);
    const receipt = await tx.wait();
    const block = await ethers.provider.getBlock(receipt.blockNumber);

    await expect(tx)
      .to.emit(registry, "ReportAnchored")
      .withArgs(reportId, pdfHash, bundleHash, block.timestamp);

    const record = await registry.getRecord(reportId);
    expect(record[0]).to.equal(pdfHash);
    expect(record[1]).to.equal(bundleHash);
    expect(record[2]).to.equal(block.timestamp);
    expect(record[3]).to.equal(submitter.address);
  });

  it("rejects a duplicate anchor for the same reportId", async function () {
    const reportId = toBytes32("report-2");
    const pdfHash = toBytes32("pdf-2");
    const bundleHash = toBytes32("bundle-2");

    await registry.anchor(reportId, pdfHash, bundleHash);

    await expect(
      registry.anchor(reportId, toBytes32("pdf-2b"), toBytes32("bundle-2b"))
    ).to.be.revertedWith("already anchored");
  });

  it("verify() returns true for the correct hash and false for a tampered one", async function () {
    const reportId = toBytes32("report-3");
    const pdfHash = toBytes32("pdf-3");
    const bundleHash = toBytes32("bundle-3");
    const tamperedHash = toBytes32("pdf-3-tampered");

    await registry.anchor(reportId, pdfHash, bundleHash);

    expect(await registry.verify(reportId, pdfHash)).to.equal(true);
    expect(await registry.verify(reportId, tamperedHash)).to.equal(false);
  });

  it("getRecord() reverts for an unknown reportId", async function () {
    const unknownId = toBytes32("never-anchored");

    await expect(registry.getRecord(unknownId)).to.be.revertedWith("not found");
  });
});
