// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721ReceiverUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract RewardNFTStaking is Initializable, OwnableUpgradeable, PausableUpgradeable, IERC721ReceiverUpgradeable, UUPSUpgradeable {
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // Struct to store information about each user
    struct StakerInfo {
        uint256[] stakedNFTIds; // List of staked NFT IDs
        mapping(uint256 => address) nftContracts; // Mapping of NFT ID to its contract address
        uint256 pendingRewards;   // Reward debt
        uint256 lastRewardClaim; // Timestamp of last reward claim
    }

    // Struct to store information about the staking pool
    struct PoolDetails {
        uint256 allocationPoints;     // Allocation points assigned to the pool
        uint256 lastBlockReward;      // Last block number when rewards were distributed
        uint256 accumulatedRewardPerShare; // Accumulated rewards per share, multiplied by 1e12
    }

    // ERC20 token used for rewards
    IERC20Upgradeable public stakingToken;
    // Rewards created per block
    uint256 public rewardPerBlock;
    // Details of the staking pool
    PoolDetails public poolDetails;
    // Info about each staker
    mapping (address => StakerInfo) public stakers;
    // Total allocation points for all pools
    uint256 private totalAllocPoints;
    // Block number when staking starts
    uint256 public startBlock;
    // Block number when staking ends
    uint256 public endBlock;
    // claimInterval period in minutes
    uint256 public claimInterval;

    // Events to track staking actions
    event Staked(address indexed user, address indexed nftContract, uint256[] nftIds);
    event Unstaked(address indexed user, address indexed nftContract, uint256[] nftIds);
    event RewardClaimed(address indexed user, uint256 amount);
    event EmergencyUnstaked(address indexed user, address indexed nftContract, uint256[] nftIds);
    event RewardsStopped(address indexed user, uint256 _endBlock);

    /**
     * @dev Initializes the contract with the given parameters.
     * @param _stakingToken The ERC20 token used for rewards.
     * @param _rewardPerBlock The amount of rewards created per block.
     * @param _startBlock The block number when staking starts.
     * @param _endBlock The block number when staking ends.
     * @param _claimIntervalMinutes The claimInterval period between reward claims, in minutes.
     */
    function initialize(
        IERC20Upgradeable _stakingToken,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _endBlock,
        uint256 _claimIntervalMinutes
    ) public initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        __UUPSUpgradeable_init();

        stakingToken = _stakingToken;
        rewardPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        endBlock = _endBlock;
        claimInterval = _claimIntervalMinutes * 1 minutes;

        // Initialize the pool
        poolDetails = PoolDetails({
            allocationPoints: 1000,
            lastBlockReward: startBlock,
            accumulatedRewardPerShare: 0
        });

        totalAllocPoints = 1000;
    }

    /**
     * @dev Required by UUPSUpgradeable to authorize contract upgrades.
     * @param newImplementation The address of the new implementation.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev Stops the distribution of rewards by setting the end block to the current block.
     */
    function stopRewards() public onlyOwner {
        endBlock = block.number;
        emit RewardsStopped(msg.sender, endBlock);
    }

    /**
     * @dev Pauses or unpauses the contract.
     * @param _pauseState If true, pauses the contract. Otherwise, unpauses it.
     */
    function setPauseState(bool _pauseState) public onlyOwner {
        return (_pauseState) ? _pause() : _unpause();
    }

    /**
     * @dev Calculates the reward multiplier over a given range of blocks.
     * @param _from The starting block.
     * @param _to The ending block.
     * @return The reward multiplier.
     */
    function calculateMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to <= endBlock) {
            return _to.sub(_from);
        } else if (_from >= endBlock) {
            return 0;
        } else {
            return endBlock.sub(_from);
        }
    }

    /**
     * @dev Returns the pending rewards for a given staker.
     * @param _staker The address of the staker.
     * @return The amount of pending rewards.
     */
    function getPendingRewards(address _staker) external view returns (uint256) {
        PoolDetails storage pool = poolDetails;
        StakerInfo storage staker = stakers[_staker];
        uint256 accumulatedRewardPerShare = pool.accumulatedRewardPerShare;
        uint256 totalNFTs = staker.stakedNFTIds.length;
        if (block.number > pool.lastBlockReward && totalNFTs != 0) {
            uint256 multiplier = calculateMultiplier(pool.lastBlockReward, block.number);
            uint256 tokenReward = multiplier.mul(rewardPerBlock).mul(pool.allocationPoints).div(totalAllocPoints);
            accumulatedRewardPerShare = accumulatedRewardPerShare.add(tokenReward.mul(1e12).div(totalNFTs));
        }
        return totalNFTs.mul(accumulatedRewardPerShare).div(1e12).sub(staker.pendingRewards);
    }

    /**
     * @dev Returns the staking information for a given staker.
     * @param _staker The address of the staker.
     * @return An array of staked NFT IDs, the reward debt, and the last reward claim time.
     */
    function getStakerInfo(address _staker) external view returns (uint256[] memory, uint256, uint256) {
        StakerInfo storage staker = stakers[_staker];
        return (staker.stakedNFTIds, staker.pendingRewards, staker.lastRewardClaim);
    }

    /**
     * @dev Updates the reward variables of the staking pool.
     */
    function updatePool() public {
        PoolDetails storage pool = poolDetails;
        if (block.number <= pool.lastBlockReward) {
            return;
        }
        uint256 totalNFTs = 0;
        for (uint256 i = 0; i < stakers[msg.sender].stakedNFTIds.length; i++) {
            if (stakers[msg.sender].nftContracts[stakers[msg.sender].stakedNFTIds[i]] != address(0)) {
                totalNFTs++;
            }
        }
        if (totalNFTs == 0) {
            pool.lastBlockReward = block.number;
            return;
        }
        uint256 multiplier = calculateMultiplier(pool.lastBlockReward, block.number);
        uint256 tokenReward = multiplier.mul(rewardPerBlock).mul(pool.allocationPoints).div(totalAllocPoints);
        pool.accumulatedRewardPerShare = pool.accumulatedRewardPerShare.add(tokenReward.mul(1e12).div(totalNFTs));
        pool.lastBlockReward = block.number;
    }

    /**
     * @dev Stakes NFTs in the contract.
     * @param _nftContract The address of the NFT contract.
     * @param _nftIds The IDs of the NFTs to be staked.
     */
    function stakeNFTs(address _nftContract, uint256[] memory _nftIds) public whenNotPaused {
        PoolDetails storage pool = poolDetails;
        StakerInfo storage staker = stakers[msg.sender];

        updatePool();
        uint256 pending = staker.stakedNFTIds.length.mul(pool.accumulatedRewardPerShare).div(1e12).sub(staker.pendingRewards);
        if (pending > 0) {
            stakingToken.safeTransfer(address(msg.sender), pending);
        }
        for (uint256 i = 0; i < _nftIds.length; i++) {
            staker.stakedNFTIds.push(_nftIds[i]);
            staker.nftContracts[_nftIds[i]] = _nftContract;
            IERC721Upgradeable(_nftContract).safeTransferFrom(address(msg.sender), address(this), _nftIds[i]);
        }
        staker.pendingRewards = staker.stakedNFTIds.length.mul(pool.accumulatedRewardPerShare).div(1e12);

        emit Staked(msg.sender, _nftContract, _nftIds);
    }

    /**
     * @dev Claims rewards for staking NFTs.
     */
    function claimRewards() public whenNotPaused {
        StakerInfo storage staker = stakers[msg.sender];
        require(block.timestamp >= staker.lastRewardClaim + claimInterval, "claimRewards: cooldown period not yet over");

        updatePool();
        uint256 pending = staker.stakedNFTIds.length.mul(poolDetails.accumulatedRewardPerShare).div(1e12).sub(staker.pendingRewards);
        require(pending > 0, "claimRewards: no rewards to claim");

        stakingToken.safeTransfer(address(msg.sender), pending);
        staker.lastRewardClaim = block.timestamp;

        staker.pendingRewards = staker.stakedNFTIds.length.mul(poolDetails.accumulatedRewardPerShare).div(1e12);
        emit RewardClaimed(msg.sender, pending);
    }

    /**
     * @dev Unstakes NFTs from the contract.
     * @param _nftContract The address of the NFT contract.
     * @param _nftIds The IDs of the NFTs to be unstaked.
     */
    function unstakeNFTs(address _nftContract, uint256[] memory _nftIds) public whenNotPaused {
        PoolDetails storage pool = poolDetails;
        StakerInfo storage staker = stakers[msg.sender];
        require(staker.stakedNFTIds.length >= _nftIds.length, "unstakeNFTs: insufficient staked NFTs");

        updatePool();
        uint256 pending = staker.stakedNFTIds.length.mul(pool.accumulatedRewardPerShare).div(1e12).sub(staker.pendingRewards);
        if (pending > 0) {
            stakingToken.safeTransfer(address(msg.sender), pending);
        }
        for (uint256 i = 0; i < _nftIds.length; i++) {
            uint256 index = find(staker.stakedNFTIds, _nftIds[i]);
            require(index < staker.stakedNFTIds.length, "unstakeNFTs: NFT not staked");
            require(staker.nftContracts[_nftIds[i]] == _nftContract, "unstakeNFTs: incorrect contract");
            staker.stakedNFTIds[index] = staker.stakedNFTIds[staker.stakedNFTIds.length - 1];
            staker.stakedNFTIds.pop();
            delete staker.nftContracts[_nftIds[i]];
            IERC721Upgradeable(_nftContract).safeTransferFrom(address(this), address(msg.sender), _nftIds[i]);
        }
        staker.pendingRewards = staker.stakedNFTIds.length.mul(pool.accumulatedRewardPerShare).div(1e12);

        emit Unstaked(msg.sender, _nftContract, _nftIds);
    }

    /**
     * @dev Emergency unstake function to withdraw NFTs without rewards.
     * @param _nftContract The address of the NFT contract.
     */
    function emergencyUnstake(address _nftContract) public {
        StakerInfo storage staker = stakers[msg.sender];
        uint256[] memory nftIds = new uint256[](staker.stakedNFTIds.length);
        for (uint256 i = 0; i < staker.stakedNFTIds.length; i++) {
            if (staker.nftContracts[staker.stakedNFTIds[i]] == _nftContract) {
                nftIds[i] = staker.stakedNFTIds[i];
                IERC721Upgradeable(_nftContract).safeTransferFrom(address(this), address(msg.sender), staker.stakedNFTIds[i]);
            }
        }
        emit EmergencyUnstaked(msg.sender, _nftContract, nftIds);
        delete staker.stakedNFTIds; 
        staker.pendingRewards = 0;
    }

    /**
     * @dev Emergency function to withdraw staking tokens. Only callable by the owner.
     * @param _amount The amount of tokens to withdraw.
     */
    function emergencyTokenWithdraw(uint256 _amount) public onlyOwner {
        require(_amount < stakingToken.balanceOf(address(this)), 'emergencyTokenWithdraw: insufficient balance');
        stakingToken.safeTransfer(address(msg.sender), _amount);
    }

    /**
     * @dev Utility function to find the index of an NFT ID in an array.
     * @param array The array of NFT IDs.
     * @param value The NFT ID to find.
     * @return The index of the NFT ID in the array.
     */
    function find(uint256[] storage array, uint256 value) internal view returns (uint256) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == value) {
                return i;
            }
        }
        return type(uint256).max; // Return maximum uint256 value to indicate not found
    }

    /**
     * @dev To allow receiving ERC721 tokens.
     * @return The selector for the ERC721 receiver.
     */
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
