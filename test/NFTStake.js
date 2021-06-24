const NFTStake = artifacts.require("NFTStake");
const TestERC20 = artifacts.require("TestERC20");
const NFTERC721 = artifacts.require("NFTERC721");
const helper = require("./truffleTestHelper");

let NFTStakeContract;
let NFTContract;
let ERC20Contract;

contract('NFTStakeContract', (accounts) => {
    let deployer = accounts[0];
    let tokens = [0, 1, 2, 3, 4, 5]
    // let tokens = [0]

    console.log({deployer})
    it('should deploy contracts and mint tokens', async () => {
        NFTStakeContract = await NFTStake.deployed()
        NFTContract = await NFTERC721.deployed()
        ERC20Contract = await TestERC20.deployed()
        await ERC20Contract.mint("1000000000000000000", {from: deployer})
        await NFTContract.mintNFT({from: deployer})
    })

    let endingDate = parseInt((((new Date()).getTime() / 1000) + 20000).toString())

    it('should create a pool', async () => {
        const poolArgs = {
            nftContract: NFTContract.address,
            rewardContract: ERC20Contract.address,
            rewardSupply: "1000000000000000000",
            cycle: "1000",
            rewardPerCycle: "1",
            maxCycles: "10",
            endingDate: endingDate,
            isActive: true,
        }
        const approved = await ERC20Contract.approve(NFTStakeContract.address, "10000000000000000000");
        const tx = await NFTStakeContract.createPool(poolArgs, {from: deployer})
        const pool = await NFTStakeContract.Pools(0)
        console.log({pool})
    });

    it('should stake NFT', async () => {
        // approve
        await NFTContract.setApprovalForAll(NFTStakeContract.address, true, {from: deployer});
        const tx = await NFTStakeContract.enterStaking(0, tokens, {from: deployer})
        const myStakes = await NFTStakeContract.getStakes(0, tokens)
        let preBalance = await ERC20Contract.balanceOf(deployer)
        console.log("preBalance")
        console.log(parseInt(preBalance))
        console.log("stakes:")
        console.log(myStakes)
        // let advtime = (parseInt(endingDate) + 20);
        let advtime = 2000
        console.log({advtime})
        await helper.advanceTime(advtime, NFTStake.web3)
        console.log('CLAIMABLE:', await NFTStakeContract.calculateRewards(0, tokens))

    })

    it('should unstake NFT 2 times', async () => {
        await NFTStakeContract.claimReward(0, tokens)
        let afterBalance = await ERC20Contract.balanceOf(deployer)
        console.log("afterBalance")
        console.log(parseInt(afterBalance))

        const myStakes = await NFTStakeContract.getStakes(0, tokens)
        console.log(myStakes)

        let advtime = 1000
        console.log({advtime})
        await helper.advanceTime(advtime, NFTStake.web3)
        console.log('CLAIMABLE:', await NFTStakeContract.calculateRewards(0, tokens))
        await NFTStakeContract.claimReward(0, tokens)
        let afterBalance2 = await ERC20Contract.balanceOf(deployer)
        console.log("afterBalance2")
        console.log(parseInt(afterBalance2))

        const myStakes2 = await NFTStakeContract.getStakes(0, tokens)
        console.log(myStakes2)


        let advtime2 = 9000
        console.log({advtime2})
        await helper.advanceTime(advtime2, NFTStake.web3)
        console.log('CLAIMABLE:', await NFTStakeContract.calculateRewards(0, tokens))

        const rewardCalculationFuture3 = await NFTStakeContract.calculateRewards(0, tokens)
        console.log("rewardCalculationFuture3:")
        console.log(rewardCalculationFuture3)
        await NFTStakeContract.claimReward(0, tokens)
        let afterBalance3 = await ERC20Contract.balanceOf(deployer)
        console.log("afterBalance3")
        console.log(parseInt(afterBalance3))

        const myStakes3 = await NFTStakeContract.getStakes(0, tokens)
        console.log(myStakes3)
        let advtime3 = 9000
        console.log({advtime3})
        await helper.advanceTime(advtime3, NFTStake.web3)

        const rewardCalculationFuture4 = await NFTStakeContract.calculateRewards(0, tokens)
        console.log("rewardCalculationFuture4:")
        console.log(rewardCalculationFuture4)
        console.log('Total rewards distributed: ', await NFTStakeContract.ClaimedPoolRewards(0))

        await NFTStakeContract.claimReward(0, tokens)
        let afterBalance4 = await ERC20Contract.balanceOf(deployer)
        console.log("afterBalance4")
        console.log(parseInt(afterBalance4))

        const myStakes4 = await NFTStakeContract.getStakes(0, tokens)
        console.log(myStakes4)
    })
});
