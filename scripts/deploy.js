const hre = require("hardhat");

async function main() {
  console.log("Starting deployment...");

  try {
    // Get the contract factories
    const RewardToken = await hre.ethers.getContractFactory("RewardToken");
    const RewardNFTStaking = await hre.ethers.getContractFactory("RewardNFTStaking");

    // Deploy the RewardToken contract
    let rewardToken;
    try {
      rewardToken = await RewardToken.deploy("StakingToken", "ST");
      await rewardToken.waitForDeployment();
      console.log("RewardToken deployed to:", rewardToken.target);
    } catch (error) {
      console.error("Error deploying RewardToken:", error);
      throw new Error("RewardToken deployment failed");
    }

    // Define deployment parameters
    const stakingTokenAddress = rewardToken.target;
    const rewardPerBlock = hre.ethers.parseUnits("0.1", 18); 
    const startBlock = 153656;
    const endBlock = 953656;
    const claimIntervalInMinutes = 10;

    // Deploy the proxy contract
    let staking;
    try {
      staking = await hre.upgrades.deployProxy(
        RewardNFTStaking,
        [stakingTokenAddress, rewardPerBlock, startBlock, endBlock, claimIntervalInMinutes],
        { initializer: 'initialize' }
      );
      console.log("Deploying RewardNFTStaking contract...");
      await staking.waitForDeployment();
      console.log("RewardNFTStaking deployed to:", staking.target);
    } catch (error) {
      console.error("Error deeploying RewardNFTStaking:", error);
      throw new Error("Staking contract deployment failed");
    }

    // Transfer tokens to the staking contract
    console.log("Transferings ST token to RewardNFTStaking contract... ");
    try {
      const transferAmount = hre.ethers.parseUnits("1000000000", 18); 
      const transferTx = await rewardToken.transfer(staking.target, transferAmount);
      await transferTx.wait();
      console.log(`Transferred ${hre.ethers.formatUnits(transferAmount, 18)} ST to RewardNFTStaking contract`);
    } catch (error) {
      console.error("Error transferring RewardToken to staking contract:", error);
      throw new Error("Token transfer to staking contract failed");
    }

  } catch (error) {
    console.error("Deployment script failed:", error);
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error("Unexpected error:", error);
  process.exitCode = 1;
});
