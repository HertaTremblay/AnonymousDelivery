import { ethers } from "hardhat";

async function main() {
  console.log("Deploying Anonymous Delivery Network contract...");

  const AnonymousDelivery = await ethers.getContractFactory("AnonymousDelivery");
  const contract = await AnonymousDelivery.deploy();

  await contract.deployed();

  console.log("✅ AnonymousDelivery contract deployed to:", contract.address);
  console.log("🔒 Contract supports FHE encryption for privacy-preserving deliveries");

  // Update the contract address in the frontend
  console.log("\n📝 Update the CONTRACT_ADDRESS in index.html to:");
  console.log(`const CONTRACT_ADDRESS = "${contract.address}";`);

  console.log("\n🌐 Network Information:");
  console.log("- Zama Devnet: https://devnet.zama.ai/");
  console.log("- Sepolia Testnet: https://rpc.sepolia.org");

  console.log("\n🚀 Deployment completed successfully!");
}

main().catch((error) => {
  console.error("❌ Deployment failed:", error);
  process.exitCode = 1;
});