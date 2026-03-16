/**
 * pnpm -C packages/tools install
  pnpm -C packages/tools exec tsc
  然后就能跑 node dist/tx-debug.js <hash>
 */

import { ethers } from "ethers";

function mustEnv(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing env: ${name}`);
  return v;
}

async function main() {
  const rpc = mustEnv("ETH_RPC_URL");
  const txHash = process.argv[2];
  if (!txHash) {
    console.error("Usage: ETH_RPC_URL=... node dist/tx-debug.js <txHash>");
    process.exit(1);
  }

  const provider = new ethers.JsonRpcProvider(rpc);

  const tx = await provider.getTransaction(txHash);
  if (!tx) throw new Error("Transaction not found");

  console.log("== TX ==");
  console.log({
    hash: tx.hash,
    from: tx.from,
    to: tx.to,
    nonce: tx.nonce,
    dataLen: tx.data?.length ?? 0,
    value: tx.value?.toString(),
    maxFeePerGas: tx.maxFeePerGas?.toString(),
    maxPriorityFeePerGas: tx.maxPriorityFeePerGas?.toString(),
    gasLimit: tx.gasLimit?.toString()
  });

  const receipt = await provider.getTransactionReceipt(txHash);
  if (!receipt) {
    console.log("Receipt not found (pending?).");
    return;
  }

  console.log("\n== RECEIPT ==");
  console.log({
    status: receipt.status, // 1 success, 0 failed
    blockNumber: receipt.blockNumber,
    gasUsed: receipt.gasUsed.toString(),
    effectiveGasPrice: receipt.gasPrice?.toString(),
    logs: receipt.logs.length,
    contractAddress: receipt.contractAddress
  });

  // 若失败：尝试用 eth_call 复现 revert 原因（在同一 block 上）
  if (receipt.status === 0) {
    console.log("\n== REVERT PROBE ==");
    try {
      // 关键：用 call 模拟执行，并指定 blockTag 为 receipt.blockNumber
      await provider.call(
        {
          from: tx.from,
          to: tx.to ?? undefined,
          data: tx.data,
          value: tx.value,
          blockTag: receipt.blockNumber
        },
      );
      console.log("call() did not throw (unexpected).");
    } catch (e: any) {
      // ethers v6 会把 revert reason 放在短消息里或 nested error
      console.log("call() reverted:");
      console.log(e?.shortMessage ?? e?.message ?? e);
    }
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});