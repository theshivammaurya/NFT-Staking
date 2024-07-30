const { expect } = require("chai");
const { ethers, upgrades} = require("hardhat");

describe("RewardNFTStaking", function () {
  let RewardNFTStaking, rewardNFTStaking;
  let owner, addr1, addr2;
  let stakingToken, nftContract;

  beforeEach(async function () {
    // Deploy  RewardToken token and NFT contract 
    const RewardToken = await ethers.getContractFactory("RewardToken");
    stakingToken = await RewardToken.deploy("StakingToken", "ST");
    await stakingToken.waitForDeployment();
    console.log("ERC20 Mock deployed to:", stakingToken.target);

    const NFTContract = await ethers.getContractFactory("NFT");
    nftContract = await NFTContract.deploy("NFT", "NFT");
    await nftContract.waitForDeployment();
    console.log("NFT Mock deployed to:", nftContract.target);

    // Deploy RewardNFTStaking contract
    const RewardNFTStakingFactory = await ethers.getContractFactory("RewardNFTStaking");

        // Define deployment parameters
    const rewardPerBlock = ethers.parseUnits("0.1", 18); 
    const startBlock = 153656;
    const endBlock = 953656;
    const claimIntervalInMinutes = 10;

    rewardNFTStaking = await upgrades.deployProxy(
      RewardNFTStakingFactory,
      [stakingToken.target, rewardPerBlock, startBlock,endBlock, claimIntervalInMinutes],
      { initializer: 'initialize' }
    );
    await rewardNFTStaking.waitForDeployment();
    console.log("RewardNFTStaking proxy deployed to:", rewardNFTStaking.target);

    [owner, addr1] = await ethers.getSigners();
  });

  it("Should stake and unstake NFTs", async function () {
    // Mint NFTs to addr1
    await nftContract.mint(addr1.address, 1);
 
    // Approve rewardNFTStaking contract to transfer NFT
    await nftContract.connect(addr1).approve(rewardNFTStaking.target, 1);

    // Stake NFT on staking contract
    await rewardNFTStaking.connect(addr1).stakeNFTs(nftContract.target, [1]);

    // Check if NFT are staked on contract
    const stakerInfo = await rewardNFTStaking.getStakerInfo(addr1.address);
    expect(stakerInfo[0].length).to.equal(1);
    
    // stake a non-existent NFT
    await expect(rewardNFTStaking.connect(addr1).stakeNFTs(nftContract.target, [3])).to.be.revertedWith("ERC721NonexistentToken(3)");

    // Unstake NFT
    await rewardNFTStaking.connect(addr1).unstakeNFTs(nftContract.target, [1]);

    // Check if NFT is unstaked
    const updatedStakerInfo = await rewardNFTStaking.getStakerInfo(addr1.address);
    expect(updatedStakerInfo[0].length).to.equal(0);
  });

 
});
