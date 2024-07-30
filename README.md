
This project demonstrates the implementation, deployment, and testing of a reward-based NFT staking contract using Hardhat. Users can stake NFTs to earn rewards, claim those rewards, and unstake their NFTs.

The reward-based NFT staking contract  is the modified version of SmartChef - Contract because SmartChef is verified and secure contract so I utilize that contract to make NFT staking contract through which our contract is more secure and useful.

*NOTE -  Using chatgpt for meanningfull comments  in the smart contract


To execute this repo follow these steps - 

Step 1-    git clone https://github.com/theshivammaurya/NFT-Staking.git

Step 2-    cd NFT-Staking

Step 3-    npm i --legacy-peer-deps         // to install dependencies of the project

Step 4-    npx hardhat compile     // to compile the contract

Step 5-    npx hardhat run scripts/deploy.js  --network taral      // to deploy the Reward token and the Staking contract.

Step 6-    npx hardhat test  test/RewardNFTStaking.js        // to test the contract scripts








 
