const fs = require("fs");
const path = require("path");
const { ethers } = require("ethers");
const config = require("../config");

const { abi } = JSON.parse(
  fs.readFileSync(path.join(__dirname, "..", "abi", "AccidentRegistry.json"), "utf8")
);

const provider = new ethers.JsonRpcProvider(config.RPC_URL);
const contract = new ethers.Contract(config.CONTRACT_ADDRESS, abi, provider);

// Cheap read-only call that never reverts, used to prove the RPC connection
// and the deployed contract are both reachable.
async function checkChain() {
  await contract.verify(ethers.ZeroHash, ethers.ZeroHash);
}

// The signer + write-capable contract instance are built lazily, not at
// module load: `config.PRIVATE_KEY` is a syntactically-present-but-invalid
// placeholder (all zeros) in both .env.example and the test env
// (test/setupEnv.js), and `ethers.Wallet` throws immediately for that value.
// Every route/test that only reads (health, sessions, reports, uploads) or
// exercises the socket/patch layer requires this module transitively via
// app.js and would otherwise crash at require-time before Phase 10 ever
// touches the chain. Constructing the wallet on first actual use means only
// a real finalize() call (i.e. `anchorReport`) needs a real funded key.
let signerContract = null;
function getSignerContract() {
  if (!signerContract) {
    const wallet = new ethers.Wallet(config.PRIVATE_KEY, provider);
    signerContract = contract.connect(wallet);
  }
  return signerContract;
}

// §5.4 step 8: reportId32 = bytes32 derived from the Mongo _id, deterministic
// and reproducible at verify time (Phase 11). Chosen derivation:
// keccak256(utf8Bytes(reportId.toString())) — i.e. ethers' own `id()`
// helper over the 24-char hex ObjectId string. Hashing (rather than simply
// left-padding the 12 raw ObjectId bytes out to 32) avoids any ambiguity
// about byte order/padding side and needs no on-chain-specific encoding
// knowledge to reproduce: any caller that has the report's string id can
// recompute the exact same bytes32 with nothing else. Documented again in
// PROGRESS.md under Decisions.
function deriveReportId32(reportId) {
  return ethers.id(String(reportId));
}

// Submits anchor(reportId32, pdfHash32, bundleHash32) and waits for the
// receipt — never resolves until the transaction is actually mined, per
// §5.4 step 9 ("await the receipt"). Throws on revert/RPC failure; the
// caller (finalize.service.js) is responsible for leaving the report in
// "finalizing" with the error stored, not for retrying itself.
async function anchorReport(reportId32, pdfHash32, bundleHash32) {
  const tx = await getSignerContract().anchor(reportId32, pdfHash32, bundleHash32);
  const receipt = await tx.wait();
  return {
    txHash: receipt.hash,
    blockNumber: receipt.blockNumber,
    contractAddress: config.CONTRACT_ADDRESS,
  };
}

// Read-only lookup for verify (§5.5 step 3), via the same read-only
// `contract` instance `checkChain` uses (no signer needed). The contract's
// own `getRecord` reverts with "not found" for an id that was never
// anchored — caught here and turned into `null` rather than propagated, so
// verify.service.js can treat "not anchored" and "RPC/contract read failed"
// the same way (report NOT_ANCHORED) without a try/catch of its own.
async function getOnChainRecord(reportId32) {
  try {
    const [pdfHash, bundleHash, timestamp, submitter] = await contract.getRecord(reportId32);
    if (timestamp === 0n) return null;
    return { pdfHash, bundleHash, timestamp, submitter };
  } catch (err) {
    return null;
  }
}

module.exports = { provider, contract, checkChain, deriveReportId32, anchorReport, getOnChainRecord };
