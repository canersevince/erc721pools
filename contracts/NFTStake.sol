// SPDX-License-Identifier: UNLICENSED

import "./lib/@openzeppelin/contracts/access/Ownable.sol";
import "./lib/@openzeppelin/contracts/token/erc20/IERC20.sol";
import "./lib/@openzeppelin/contracts/token/erc721/IERC721.sol";
import "./lib/@openzeppelin/contracts/token/erc721/IERC721Receiver.sol";
import "./lib/@openzeppelin/contracts/utils/introspection/ERC165Storage.sol";

pragma solidity ^0.8.0;


// NFT Staking pools

/*
THIS CONTRACT CREATES NFT STAKING POOLS WITH FIXED REWARDS. REWARDS ARE CYCLE BASED AND MULTIPLIERS CAN BE IMPLEMENTED.


-CREATING POOL REQUIRES NFT CONTRACT AND ERC20 TOKEN CONTRACT AS ARGUMENTS
-NFT CONTRACT MUST BE ERC721
-EACH POOL HAS CYCLE AND MAX-CYCLE COUNTS. FOR EXAMPLE A POOL CAN REWARD 20 TOKENS EVERY 8 HOURS AND MAX 5 TIMES.
-USER CAN CLAIM ONE BY ONE OR MULTIPLE NFTS AT ONCE, REMANINING CLAIMS WILL BE KEPT.
-AN NFT CANNOT BE STAKED AGAIN IF IT IS CLAIMED MAX CYCLE AMOUNT, FOR EXAMPLE IF YOU CLAIM YOUR REWARD 10 CYCLES AND POOL HAS 10 CYCLE LIMIT, YOU CANNOT STAKE THAT NFT ANYMORE.
-INFINITE AMOUNT OF PAIRS CAN BE CREATED.

WIP: MULTIPLIER BY SIGNATURE.
-

*/


contract NFTStake is Ownable, ERC165Storage {

    constructor(){
        _registerInterface(IERC721Receiver.onERC721Received.selector);
    }

    uint256 public currentPoolId = 0;

    // pool id => pool
    mapping(uint256 => NFTPool) public Pools;

    // remaining pool rewards
    mapping(uint256 => uint256) public ClaimedPoolRewards;

    // pool id => tokenId => stake
    mapping(uint256 => mapping(uint256 => Stake)) public Stakes;




    struct NFTPool {
        IERC721 nftContract;
        IERC20 rewardContract;
        uint256 rewardSupply;
        uint256 cycle;
        uint256 rewardPerCycle;
        uint256 maxCycles;
        uint256 endingDate;
        bool isActive;
    }

    struct Stake {
        uint256 poolId;
        address beneficiary;
        uint256 startTime;
        IERC721 nftContract;
        uint256 tokenId;
        uint256 claimedTokens;
        uint256 lastCycle;
        bool isActive;
    }

    function createPool(NFTPool memory _pool) external onlyOwner {
        Pools[currentPoolId] = _pool;
        currentPoolId += 1;
        require(_pool.rewardContract.transferFrom(msg.sender, address(this), _pool.rewardSupply));
    }

    function updatePool(uint256 pid, uint256 endingDate, uint256 maxCycles) external onlyOwner {
        Pools[pid].endingDate = endingDate;
        Pools[pid].maxCycles = maxCycles;
    }

    function endPool(uint256 pid) external onlyOwner {
        // transfer remaining funds to owner
        require(Pools[pid].endingDate < block.timestamp || Pools[pid].rewardSupply >= ClaimedPoolRewards[pid], "CANNOT END POOL.");
        uint256 remainingTokens = Pools[pid].rewardSupply - ClaimedPoolRewards[pid];
        Pools[pid].rewardContract.transfer(owner(), remainingTokens);
        Pools[pid].isActive = false;
    }

    function enterStaking(uint256 pid, uint256[] memory tokenIds) external {
        require(Pools[pid].rewardSupply >= ClaimedPoolRewards[pid] && Pools[pid].endingDate > block.timestamp, "THIS REWARD POOL IS FINISHED OR TOKEN HIT MAX CYCLES");

        // transfer NFTs to contract
        uint256 poolMaxCycle = Pools[pid].maxCycles;
        for (uint256 i = 0; i < tokenIds.length; i++) {

            // check if token staked before
            require(Stakes[pid][tokenIds[i]].lastCycle < poolMaxCycle, "Cannot stake anymore");
            require(Stakes[pid][tokenIds[i]].isActive == false, "NFT already staked. ?!?!?");

            // bytes32 method = keccak256("transferFrom");
            // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
            (bool success,) = address(Pools[pid].nftContract).call(abi.encodeWithSelector(0x23b872dd, msg.sender, address(this), tokenIds[i]));
            require(success, "CANNOT TRANSFER NFT");
            // create stakes for each
            // pool id => tokenId => stake
            /*
            uint256 poolId;
            address beneficiary;
            uint256 startTime;
            IERC721 nftContract;
            uint256 tokenId;
            uint256 claimedTokens;
            uint256 lastCycle;
            bool isActive;
            */

            Stake memory newStake = Stake(
                pid,
                msg.sender,
                block.timestamp,
                Pools[pid].nftContract,
                tokenIds[i],
                Stakes[pid][tokenIds[i]].claimedTokens,
                Stakes[pid][tokenIds[i]].lastCycle,
                true
            );

            Stakes[pid][tokenIds[i]] = newStake;
        }
    }

    function leaveStaking(uint256 pid, uint256[] memory tokenIds) external {
        _claimRewards(pid, tokenIds);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            (bool success,) = address(Pools[pid].nftContract).call(abi.encodeWithSelector(0x23b872dd, address(this), msg.sender, tokenIds[i]));
            require(success, "CANNOT REFUND NFT? SOMETHING IS WRONG!!!!");
            Stakes[pid][tokenIds[i]].isActive = false;
        }
    }

    function claimReward(uint256 pid, uint256[] memory tokenIds) external {
        _claimRewards(pid, tokenIds);
    }

    function _claimRewards(uint256 pid, uint256[] memory tokenIds) internal {
        //        require(block.timestamp < Pools[pid].endingDate, "Pool is expired");
        uint256 poolMaxCycle = Pools[pid].maxCycles;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(Stakes[pid][tokenIds[i]].isActive, "Not staked");
            if (Stakes[pid][tokenIds[i]].lastCycle < poolMaxCycle) {
                _claim(pid, tokenIds[i], 0);
            }
        }
    }

    function _claim(uint256 pid, uint256 tokenId, uint256 _multiplier) internal {
        // calculate
        if (_multiplier == 0) {
            _multiplier = 1;
        }
        uint256 toBeClaimed = 0;
        uint256 poolMaxClaim = Pools[pid].maxCycles;
        uint256 cyclesSinceStart = ((block.timestamp - Stakes[pid][tokenId].startTime) / Pools[pid].cycle);
        if (cyclesSinceStart >= poolMaxClaim) {
            cyclesSinceStart = poolMaxClaim;
        }
        uint256 currentCycleCount = cyclesSinceStart - Stakes[pid][tokenId].lastCycle;

        require(currentCycleCount <= poolMaxClaim, "YOU CANNOT CLAIM THIS STAKE ANYMORE!");

        toBeClaimed += currentCycleCount * Pools[pid].rewardPerCycle;
        // increase amount and cycle count for that nft, prevent someone else buying it and staking again

        Stakes[pid][tokenId].claimedTokens += toBeClaimed;
        Stakes[pid][tokenId].lastCycle = Stakes[pid][tokenId].lastCycle + currentCycleCount;
        ClaimedPoolRewards[pid] += toBeClaimed;

        // transferToken
        if (toBeClaimed > 0) {
            require(Pools[pid].rewardContract.transfer(Stakes[pid][tokenId].beneficiary, toBeClaimed * _multiplier), "ERROR toBeClaimed");
        }
    }

    function calculateRewards(uint256 pid, uint256[] memory tokenIds, uint256 timestamp) public view returns (uint256) {
        uint256 totalClaimable = 0;
        uint256 poolMaxClaim = Pools[pid].maxCycles;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 cyclesSinceStart = (timestamp - Stakes[pid][tokenIds[i]].startTime) / Pools[pid].cycle;
            if (cyclesSinceStart > poolMaxClaim) {
                cyclesSinceStart = poolMaxClaim;
            }
            uint256 currentCycleCount = cyclesSinceStart - Stakes[pid][tokenIds[i]].lastCycle;
            totalClaimable = totalClaimable + (currentCycleCount * Pools[pid].rewardPerCycle);
        }
        return totalClaimable;
    }

    function getStakes(uint256 pid, uint256[] memory tokenIds) external view returns (Stake[] memory) {
        Stake[] memory stakes = new Stake[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            stakes[i] = Stakes[pid][tokenIds[i]];
        }
        return stakes;
    }
}