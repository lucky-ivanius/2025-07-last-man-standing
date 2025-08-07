// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Game} from "../src/Game.sol";

contract GameTest is Test {
    Game public game;

    address public deployer;
    address public player1;
    address public player2;
    address public player3;
    address public maliciousActor;

    // Initial game parameters for testing
    uint256 public constant INITIAL_CLAIM_FEE = 0.1 ether; // 0.1 ETH
    uint256 public constant GRACE_PERIOD = 1 days; // 1 day in seconds
    uint256 public constant FEE_INCREASE_PERCENTAGE = 10; // 10%
    uint256 public constant PLATFORM_FEE_PERCENTAGE = 5; // 5%
    
    // Events for testing
    event GameEnded(
        address indexed winner,
        uint256 prizeAmount,
        uint256 timestamp,
        uint256 round
    );

    function setUp() public {
        deployer = makeAddr("deployer");
        player1 = makeAddr("player1");
        player2 = makeAddr("player2");
        player3 = makeAddr("player3");
        maliciousActor = makeAddr("maliciousActor");

        vm.deal(deployer, 10 ether);
        vm.deal(player1, 10 ether);
        vm.deal(player2, 10 ether);
        vm.deal(player3, 10 ether);
        vm.deal(maliciousActor, 10 ether);

        vm.startPrank(deployer);
        game = new Game(
            INITIAL_CLAIM_FEE,
            GRACE_PERIOD,
            FEE_INCREASE_PERCENTAGE,
            PLATFORM_FEE_PERCENTAGE
        );
        vm.stopPrank();
    }

    function testConstructor_RevertInvalidGracePeriod() public {
        vm.expectRevert("Game: Grace period must be greater than zero.");
        new Game(INITIAL_CLAIM_FEE, 0, FEE_INCREASE_PERCENTAGE, PLATFORM_FEE_PERCENTAGE);
    }

    function testClaimThrone_MultiplePlayersCanClaimSuccessively() public {
        // Initially, no one is the king (address(0))
        assertEq(game.currentKing(), address(0));
        assertEq(game.claimFee(), INITIAL_CLAIM_FEE);

        // Player1 claims the throne first
        vm.prank(player1);
        game.claimThrone{value: INITIAL_CLAIM_FEE}();

        assertEq(game.currentKing(), player1);
        assertEq(game.totalClaims(), 1);
        assertEq(game.playerClaimCount(player1), 1);

        // Calculate expected new claim fee after first claim (10% increase)
        uint256 expectedSecondClaimFee = INITIAL_CLAIM_FEE + (INITIAL_CLAIM_FEE * FEE_INCREASE_PERCENTAGE) / 100;
        assertEq(game.claimFee(), expectedSecondClaimFee);

        // Player2 claims the throne from player1
        vm.prank(player2);
        game.claimThrone{value: expectedSecondClaimFee}();

        assertEq(game.currentKing(), player2);
        assertEq(game.totalClaims(), 2);
        assertEq(game.playerClaimCount(player2), 1);

        // Calculate expected third claim fee
        uint256 expectedThirdClaimFee = expectedSecondClaimFee + (expectedSecondClaimFee * FEE_INCREASE_PERCENTAGE) / 100;
        assertEq(game.claimFee(), expectedThirdClaimFee);

        // Player3 claims the throne from player2
        vm.prank(player3);
        game.claimThrone{value: expectedThirdClaimFee}();

        assertEq(game.currentKing(), player3);
        assertEq(game.totalClaims(), 3);
        assertEq(game.playerClaimCount(player3), 1);

        // Verify that player1 can reclaim the throne (previously king can become king again)
        uint256 currentClaimFee = game.claimFee();
        vm.prank(player1);
        game.claimThrone{value: currentClaimFee}();

        assertEq(game.currentKing(), player1);
        assertEq(game.totalClaims(), 4);
        assertEq(game.playerClaimCount(player1), 2); // player1 has claimed twice now
    }

    function testClaimThrone_RevertWhenSamePlayerTriesToClaimTwiceInARow() public {
        // Player1 becomes king
        vm.prank(player1);
        game.claimThrone{value: INITIAL_CLAIM_FEE}();
        assertEq(game.currentKing(), player1);

        // Player1 tries to claim again immediately (should revert)
        uint256 newClaimFee = game.claimFee();
        vm.prank(player1);
        vm.expectRevert("Game: You are already the king. No need to re-claim.");
        game.claimThrone{value: newClaimFee}();

        // King should still be player1
        assertEq(game.currentKing(), player1);
        assertEq(game.totalClaims(), 1);
    }

    function testClaimThrone_RevertInsufficientPayment() public {
        // Try to claim with insufficient payment
        vm.prank(player1);
        vm.expectRevert("Game: Insufficient ETH sent to claim the throne.");
        game.claimThrone{value: INITIAL_CLAIM_FEE - 1}();

        // No one should be king yet
        assertEq(game.currentKing(), address(0));
        assertEq(game.totalClaims(), 0);
    }

    function testDeclareWinner_EmitsCorrectPrizeAmount() public {
        // Player1 claims throne to build up the pot
        vm.prank(player1);
        game.claimThrone{value: INITIAL_CLAIM_FEE}();
        
        // Player2 claims throne to increase pot further
        uint256 secondClaimFee = game.claimFee();
        vm.prank(player2);
        game.claimThrone{value: secondClaimFee}();
        
        uint256 expectedPrizeAmount = game.pot(); // Save actual pot amount
        assertGt(expectedPrizeAmount, 0); // Verify pot has funds
        
        // Fast forward past grace period
        vm.warp(block.timestamp + GRACE_PERIOD + 1);
        
        // Expect GameEnded event with correct prize amount (not 0)
        vm.expectEmit(true, false, false, true);
        emit GameEnded(player2, expectedPrizeAmount, block.timestamp, 1);
        
        game.declareWinner();
        
        // Verify pot is reset but winner has correct pending winnings
        assertEq(game.pot(), 0);
        assertEq(game.pendingWinnings(player2), expectedPrizeAmount);
    }
}
