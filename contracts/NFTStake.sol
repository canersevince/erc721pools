// SPDX-License-Identifier: UNLICENSED

import "./lib/@openzeppelin/contracts/access/Ownable.sol";
import "./lib/@openzeppelin/contracts/token/erc20/IERC20.sol";
import "./lib/@openzeppelin/contracts/token/erc721/IERC721.sol";
import "./lib/@openzeppelin/contracts/token/erc721/IERC721Receiver.sol";
import "./lib/@openzeppelin/contracts/utils/introspection/ERC165Storage.sol";
import "./lib/@openzeppelin/contracts/utils/Strings.sol";

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
-REWARD MULTIPLIER BY POOL SIGNER
*/



contract NFTStake is Ownable, ERC165Storage {
    using Strings for uint256;
    address public signer;

    constructor(/*address _signer*/){
        _registerInterface(IERC721Receiver.onERC721Received.selector);
        //        signer = _signer;
    }

    uint256 public currentPoolId = 0;

    // pool id => pool
    mapping(uint256 => NFTPool) public Pools;

    // remaining pool rewards
    mapping(uint256 => uint256) public ClaimedPoolRewards;

    // pool id => tokenId => stake
    mapping(uint256 => mapping(uint256 => Stake)) public Stakes;

    // mapping of active staking count by wallet. poolid => address =>  active stake count. will be used with pool parameter: maxStakePerWallet
    mapping(uint256 => mapping(address => uint256)) public ActiveStakes;

    event PoolCreated(uint256 pid, address nftContract,
        address rewardContract,
        uint256 rewardSupply,
        uint256 cycle,
        uint256 rewardPerCycle,
        uint256 maxCycles,
        uint256 endingDate);

    event PoolEnded(uint256 pid);

    event Staked(uint256 pid,
        uint256[] tokenIds);

    event UnStaked(uint256 pid,
        uint256[] tokenIds);

    event Claimed(uint256 pid,
        uint256[] tokenIds,
        uint256 amount);

    struct NFTPool {
        IERC721 nftContract;
        IERC20 rewardContract;
        uint256 rewardSupply;
        uint256 cycle;
        uint256 rewardPerCycle;
        uint256 maxCycles;
        uint256 endingDate;
        bool isActive;
        address multiplierSigner;
        uint256 maxStakePerWallet;
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
        require(_pool.rewardContract.transferFrom(msg.sender, address(this), _pool.rewardSupply));

        emit PoolCreated(currentPoolId,
            address(_pool.nftContract),
            address(_pool.rewardContract),
            _pool.rewardSupply,
            _pool.cycle,
            _pool.rewardPerCycle,
            _pool.maxCycles,
            _pool.endingDate);
        currentPoolId += 1;
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

        emit PoolEnded(pid);
    }

    function enterStaking(uint256 pid, uint256[] memory tokenIds) external {
        require(Pools[pid].rewardSupply >= ClaimedPoolRewards[pid] && Pools[pid].endingDate > block.timestamp, "THIS REWARD POOL IS FINISHED OR TOKEN HIT MAX CYCLES");
        require(ActiveStakes[pid][msg.sender] <= Pools[pid].maxStakePerWallet, "ALREADY STAKED MAX. AMOUNT OF NFT ON THIS POOL.");
        require(tokenIds.length <= Pools[pid].maxStakePerWallet, "ALREADY STAKED MAX. AMOUNT OF NFT ON THIS POOL.");
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
            ActiveStakes[pid][msg.sender] += 1;
        }

        emit Staked(pid, tokenIds);
    }
    // @param multiplier should be calculated like this: pid + sum of tokenIds + multiplier. so this way we will generate unique signatures each time.
    // @param multiplier must be signed by pool signer.
    function leaveStaking(uint256 pid, uint256[] memory tokenIds, uint256 multiplier, uint256 timestamp, bytes32 hash, bytes memory signature) external {
        _isValidMultiplier(pid, multiplier, timestamp, hash, signature);
        uint256 _multiplier = multiplier - _sumTokenIdsAndPid(pid, tokenIds);
        _claimRewards(pid, tokenIds, _multiplier);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(Stakes[pid][tokenIds[i]].beneficiary == msg.sender, "Not the stake owner");
            // transferFrom(address,address,uint256) = 0x23b872dd
            Stakes[pid][tokenIds[i]].isActive = false;
            (bool success,) = address(Pools[pid].nftContract).call(abi.encodeWithSelector(0x23b872dd, address(this), msg.sender, tokenIds[i]));
            require(success, "CANNOT REFUND NFT? SOMETHING IS WRONG!!!!");
        }
    }

    // rescue your tokens, for emergency purposes. don't care about rewards, reset reward timer.
    function unStakeWithoutRewards(uint256 pid, uint256[] memory tokenIds) external {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(Stakes[pid][tokenIds[i]].beneficiary == msg.sender, "Not the stake owner");
            Stakes[pid][tokenIds[i]].isActive = false;
            Stakes[pid][tokenIds[i]].startTime = block.timestamp;
            // transferFrom(address,address,uint256) = 0x23b872dd
            (bool success,) = address(Pools[pid].nftContract).call(abi.encodeWithSelector(0x23b872dd, address(this), msg.sender, tokenIds[i]));
            require(success, "CANNOT REFUND NFT? SOMETHING IS WRONG!!!!");
        }
    }

    function claimReward(uint256 pid, uint256[] memory tokenIds, uint256 multiplier, uint256 timestamp, bytes32 hash, bytes memory signature) external {
        _isValidMultiplier(pid, multiplier, timestamp, hash, signature);
        uint256 _multiplier = multiplier - _sumTokenIdsAndPid(pid, tokenIds);
        _claimRewards(pid, tokenIds, _multiplier);
    }

    function _isValidMultiplier(uint256 pid, uint256 multiplier, uint256 timestamp, bytes32 hash, bytes memory sig) internal view returns (bool) {
        bytes32 _hash = toEthSignedMessageHash(multiplier, timestamp);
        require(hash == _hash, "INVALID SIGNATURE. YOU CANNOT TRICK ME KEK");
        require(Pools[pid].multiplierSigner == recoverSigner(_hash, sig), "HASH IS NOT SIGNED BY POOL OWNER");
        return true;
    }

    function _sumTokenIdsAndPid(uint256 pid, uint256[] memory tokenIds) internal pure returns (uint256) {
        uint256 sum = 0;
        for (uint256 i; i < tokenIds.length; i++) {
            sum += tokenIds[i];
        }
        return sum + pid;
    }

    function _claimRewards(uint256 pid, uint256[] memory tokenIds, uint256 multiplier) internal {
        //        require(block.timestamp < Pools[pid].endingDate, "Pool is expired");
        uint256 poolMaxCycle = Pools[pid].maxCycles;
        uint256 _total = 0;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(Stakes[pid][tokenIds[i]].beneficiary == msg.sender, "Not the stake owner");
            require(Stakes[pid][tokenIds[i]].isActive, "Not staked");
            if (Stakes[pid][tokenIds[i]].lastCycle < poolMaxCycle) {
                (uint256 toBeClaimed, uint256 currentCycleCount) = _claimCalculate(pid, tokenIds[i]);
                _claim(pid, tokenIds[i], toBeClaimed, currentCycleCount, 0);
                _total += toBeClaimed * multiplier;
            }
        }
        emit Claimed(pid, tokenIds, _total);
    }


    function _claimCalculate(uint256 pid, uint256 tokenId) internal view returns (uint256, uint256){
        uint256 toBeClaimed = 0;
        uint256 poolMaxClaim = Pools[pid].maxCycles;
        uint256 cyclesSinceStart = ((block.timestamp - Stakes[pid][tokenId].startTime) / Pools[pid].cycle);
        if (cyclesSinceStart >= poolMaxClaim) {
            cyclesSinceStart = poolMaxClaim;
        }
        uint256 currentCycleCount = cyclesSinceStart - Stakes[pid][tokenId].lastCycle;
        require(currentCycleCount <= poolMaxClaim, "YOU CANNOT CLAIM THIS STAKE ANYMORE!");
        toBeClaimed += currentCycleCount * Pools[pid].rewardPerCycle;
        return (toBeClaimed, currentCycleCount);
    }

    function _claim(uint256 pid, uint256 tokenId, uint256 toBeClaimed, uint256 currentCycleCount, uint256 _multiplier) internal {
        // calculate
        if (_multiplier == 0) {
            _multiplier = 1;
        }
        // increase amount and cycle count for that nft, prevent someone else buying it and staking again
        Stakes[pid][tokenId].claimedTokens += toBeClaimed;
        Stakes[pid][tokenId].lastCycle = Stakes[pid][tokenId].lastCycle + currentCycleCount;
        ClaimedPoolRewards[pid] += toBeClaimed;
        ActiveStakes[pid][msg.sender] -= 1;
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

    function splitSignature(bytes memory sig)
    internal
    pure
    returns (uint8, bytes32, bytes32)
    {
        require(sig.length == 65);

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
        // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
        // second 32 bytes
            s := mload(add(sig, 64))
        // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }

        return (v, r, s);
    }

    function recoverSigner(bytes32 message, bytes memory sig)
    internal
    pure
    returns (address)
    {
        uint8 v;
        bytes32 r;
        bytes32 s;

        (v, r, s) = splitSignature(sig);

        return ecrecover(message, v, r, s);
    }

    function stringToBytes32(string memory source) public pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(source, 32))
        }
    }

    function checkSignature(bytes32 multiplier, bytes memory sig) internal pure returns (address){
        return recoverSigner(multiplier, sig);
    }

    function toEthSignedMessageHash(uint256 _multiplier, uint256 timestamp) internal pure returns (bytes32) {
        return keccak256(toSignMessage(_multiplier, timestamp));
    }

    function toSignMessage(uint256 _multiplier, uint256 timestamp) public pure returns (bytes memory) {
        bytes memory message = abi.encodePacked(_multiplier.toString(),"-",timestamp.toString());
        uint _len = message.length;
        return abi.encodePacked("\x19Ethereum Signed Message:\n",_len.toString(),message);
    }

    function _getLen(uint256 _len) internal pure returns(uint256) {
        return bytes(_len.toString()).length;
    }

    /*function msgText (uint256 _multiplier, uint256 timestamp) external view returns (string memory){
                uint _len = _getLen(_multiplier);
        return string(abi.encodePacked("\x19Ethereum Signed Message:\n",_len.toString(),"-",_multiplier.toString(),"-",timestamp.toString()));
    }*/


    /*function _isValidMultiplier2(uint256 pid, uint256 multiplier, uint256 timestamp, bytes32 hash, bytes memory sig) public view returns (address) {
        bytes32 _hash = toEthSignedMessageHash(multiplier, timestamp);
        require(hash == _hash, "WRONG MSG");
        return recoverSigner(hash, sig);
    }*/


}