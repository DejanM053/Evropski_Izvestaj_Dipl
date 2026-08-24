/// Public-testnet block explorers this app knows how to link to (Phase 12
/// only wires up Sepolia in hardhat.config.js — see PROGRESS.md — but Amoy
/// is kept here too since master_plan.md §2 allows either). Anything not in
/// this map (e.g. "localhost"/"hardhat" during local dev) gets no explorer
/// link, satisfying "when CHAIN_NETWORK is a public testnet". Shared by
/// ReportCompleteScreen and VerifyScreen so both stay in sync off the one
/// `CHAIN_NETWORK` value rather than each keeping its own copy.
const kExplorerTxBaseUrls = {
  'sepolia': 'https://sepolia.etherscan.io/tx/',
  'amoy': 'https://amoy.polygonscan.com/tx/',
  'polygon-amoy': 'https://amoy.polygonscan.com/tx/',
};

/// Returns the block-explorer URL for [txHash] on [network], or null when
/// [network] isn't a known public testnet or [txHash] is missing.
String? explorerTxUrl(String? network, String? txHash) {
  if (network == null || txHash == null) return null;
  final base = kExplorerTxBaseUrls[network.toLowerCase()];
  if (base == null) return null;
  return '$base$txHash';
}
