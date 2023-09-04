// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";

contract OperationTest is Setup {
    function setUp() public override {
        super.setUp();
    }

    function testSetupStrategyOK() public {
        console.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        // TODO: add additional check on strat params
    }

    function test_operation(uint256 _amount) public {
        vm.assume(_amount != buyIn);

        uint256 start = strategy.start();

        assertGt(start, block.timestamp);

        airdrop(asset, user, buyIn);
        vm.prank(user);
        asset.approve(address(strategy), buyIn);

        vm.prank(user);
        vm.expectRevert("!activated");
        strategy.deposit(buyIn, user);

        vm.prank(management);
        strategy.activateNewPlayer(user);

        vm.prank(user);
        vm.expectRevert("Wrong amount");
        strategy.deposit(_amount, user);

        vm.prank(user);
        strategy.deposit(buyIn, user);

        vm.prank(user);
        vm.expectRevert("Already payed");
        strategy.deposit(buyIn, user);

        checkStrategyTotals(strategy, buyIn, buyIn, 0);

        vm.prank(management);
        strategy.activateNewPlayer(management);

        airdrop(asset, management, buyIn);
        vm.prank(management);
        asset.approve(address(strategy), buyIn);

        vm.prank(management);
        strategy.deposit(buyIn, management);

        assertGt(strategy.balanceOf(management), 0);

        vm.prank(management);
        strategy.activateNewPlayer(performanceFeeRecipient);

        uint256 diff = start - block.timestamp;

        skip(diff + 1);

        vm.prank(performanceFeeRecipient);
        vm.expectRevert("ERC4626: deposit more than max");
        strategy.deposit(buyIn, performanceFeeRecipient);

        diff = strategy.end() - block.timestamp;

        skip(diff + 1);
        vm.prank(management);
        strategy.winnerWinnerChickenDinner(user);

        assertGt(strategy.balanceOf(user), 0);
        assertEq(strategy.balanceOf(management), 0);

        skip(20);

        assertGt(strategy.totalAssets(), buyIn * 2);
        assertEq(strategy.management(), user);

        uint256 before = asset.balanceOf(user);

        vm.prank(user);
        strategy.redeem(buyIn, user, user);

        assertGt(asset.balanceOf(user), before + (buyIn * 2));
    }
}
