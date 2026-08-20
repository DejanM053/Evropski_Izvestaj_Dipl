const fs = require("fs");
const path = require("path");
const { ethers, artifacts } = require("hardhat");

async function main() {
  const AccidentRegistry = await ethers.getContractFactory("AccidentRegistry");
  const registry = await AccidentRegistry.deploy();
  await registry.waitForDeployment();

  const address = await registry.getAddress();
  console.log(`AccidentRegistry deployed to: ${address}`);

  const artifact = await artifacts.readArtifact("AccidentRegistry");
  const outDir = path.join(__dirname, "..", "..", "backend", "src", "abi");
  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(
    path.join(outDir, "AccidentRegistry.json"),
    JSON.stringify({ address, abi: artifact.abi }, null, 2)
  );
  console.log(`ABI written to: ${path.join(outDir, "AccidentRegistry.json")}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
