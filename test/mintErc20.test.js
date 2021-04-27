
const { expectEvent, BN, constants } = require('@openzeppelin/test-helpers');
const { web3 } = require('@openzeppelin/test-environment');


const expectRevert = require('./utils/expectRevert');
const { expect } = require('chai');
// const { ethers } = require("hardhat");
const ganache = require("ganache-core");
web3.setProvider(ganache.provider());

const BigNumber = require('bignumber.js');


const MockErc20TokenContract = artifacts.require('MockERC20');
const UnnErc20Contract = artifacts.require('UnnErc20');
const InterestRateModelContract = artifacts.require('JumpRateModel');



// let MockErc20TokenContract;
// let UnnErc20Contract;
const initialExchangeRateMutiplier = etherUnsigned(1);

function etherUnsigned(num) {
  return new BigNumber(num);
}

function dfn(val, def) {
  return isFinite(val) ? val : def;
}

function etherMantissa(num, scale = 1e18) {
  if (num < 0)
    return new BigNumber(2).pow(256).plus(num);
  return new BigNumber(num).times(scale);
}

const exchangeRate = 50e3;
const mintAmount = etherUnsigned(10e4);
const mintTokens = mintAmount.dividedBy(exchangeRate);

let dist, token, interestRateModel;
contract('UnnErc20', (accounts) => {
	describe('mint erc20 token', function () {
		beforeEach('setup contracts', async function () {
			// MockErc20TokenContract = await ethers.getContractFactory('MockERC20');
			// UnnErc20Contract = await ethers.getContractFactory('UnnErc20');

			// const accounts = await ethers.getSigners(10);
			owner = accounts[0];
			account1 = accounts[1];
			console.log(owner);
			token = await MockErc20TokenContract.new(1000000000000000);
			// await token.deployed();

			const totalSupply = await token.totalSupply();
			console.log(totalSupply.toString());


			const baseRate = etherMantissa(dfn(.05, 0));
		    const multiplier = etherMantissa(dfn(.45, 1e-18));
		    const jump = etherMantissa(dfn(5, 0));
		    const kink = etherMantissa(dfn(.95, 0));
			interestRateModel = await InterestRateModelContract.new(baseRate, multiplier, jump, kink);

			dist = await UnnErc20Contract.new();
			// await dist.deployed();
			await dist.initialize(token.address, interestRateModel.address, 'SAMPLE TOKEN', 'ST', 9, initialExchangeRateMutiplier);

			await token.approve(dist.address, '10000000');
		});

		describe('When fresh', function ()  {
			it('Should succeed minting', async function() {
				// b = await dist.call.accrualBlkNo;
				// console.log(b);

				const beforeBalance = await dist.balanceOf(owner);
				console.log(beforeBalance.toString());

				r = await dist.mint(etherUnsigned(10));
			
				const afteBalance = await dist.balanceOf(owner);
				console.log(afteBalance.toString());

				console.log(etherUnsigned(await dist.balanceOfUnderlying(owner).toString()));
			});
			it('transfers the underlying cash, tokens and emits Mint and Transfer events', async () => {
				const beforeBalance = await dist.balanceOf(owner);
				const exchangeRate = await dist.exchangeRateStored();

				console.log(exchangeRate.toString());

				const r = await dist.mint(etherUnsigned(100));
				const afteBalance = await dist.balanceOf(owner);
				expectEvent(r, 'Mint', {
					minter: owner,
					mintAmount: mintAmount.toString,
					mintTokens: etherMantissa(100).toString()
				});
			});
		});
	});
});

