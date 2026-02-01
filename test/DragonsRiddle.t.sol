// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DragonsRiddle} from "../src/DragonsRiddle.sol";

contract DragonsRiddleTest is Test {
    DragonsRiddle public game;
    
    address dragon = makeAddr("dragon");
    address player1 = address(0x1);
    address player2 = address(0x2);
    address player3 = address(0x3);
    
    string constant RIDDLE = "I have cities, but no houses. I have mountains, but no trees. I have water, but no fish. What am I?";
    string constant ANSWER = "a map";
    bytes32 answerHash;
    
    function setUp() public {
        vm.prank(dragon);
        game = new DragonsRiddle();
        
        // Pre-compute answer hash
        answerHash = keccak256(bytes("a map"));
        
        // Fund test accounts
        vm.deal(player1, 10 ether);
        vm.deal(player2, 10 ether);
        vm.deal(player3, 10 ether);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // POST RIDDLE TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_PostRiddle() public {
        vm.prank(dragon);
        game.postRiddle(RIDDLE, answerHash);
        
        (
            uint256 riddleId,
            string memory question,
            uint256 deadline,
            uint256 pot,
            address solver,
            uint256 numGuesses,
            bool isActive
        ) = game.getCurrentRiddle();
        
        assertEq(riddleId, 1);
        assertEq(question, RIDDLE);
        assertEq(deadline, block.timestamp + 7 days);
        assertEq(pot, 0);
        assertEq(solver, address(0));
        assertEq(numGuesses, 0);
        assertTrue(isActive);
    }
    
    function test_OnlyDragonCanPost() public {
        vm.prank(player1);
        vm.expectRevert(DragonsRiddle.OnlyDragon.selector);
        game.postRiddle(RIDDLE, answerHash);
    }
    
    function test_CannotPostWhileActive() public {
        vm.prank(dragon);
        game.postRiddle(RIDDLE, answerHash);
        
        vm.prank(dragon);
        vm.expectRevert(DragonsRiddle.RiddleAlreadyActive.selector);
        game.postRiddle("Another riddle", keccak256("another answer"));
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // GUESS TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_SubmitGuess() public {
        vm.prank(dragon);
        game.postRiddle(RIDDLE, answerHash);
        
        vm.prank(player1);
        game.submitGuess{value: 0.001 ether}("wrong answer");
        
        (,,,uint256 pot,,uint256 numGuesses,) = game.getCurrentRiddle();
        assertEq(pot, 0.001 ether);
        assertEq(numGuesses, 1);
    }
    
    function test_IncorrectFee() public {
        vm.prank(dragon);
        game.postRiddle(RIDDLE, answerHash);
        
        vm.prank(player1);
        vm.expectRevert(DragonsRiddle.IncorrectFee.selector);
        game.submitGuess{value: 0.002 ether}("guess");
    }
    
    function test_CannotGuessWithNoRiddle() public {
        vm.prank(player1);
        vm.expectRevert(DragonsRiddle.NoActiveRiddle.selector);
        game.submitGuess{value: 0.001 ether}("guess");
    }
    
    function test_CannotGuessTwice() public {
        vm.prank(dragon);
        game.postRiddle(RIDDLE, answerHash);
        
        vm.prank(player1);
        game.submitGuess{value: 0.001 ether}("wrong");
        
        vm.prank(player1);
        vm.expectRevert(DragonsRiddle.AlreadyEntered.selector);
        game.submitGuess{value: 0.001 ether}("another guess");
    }
    
    function test_CannotGuessAfterDeadline() public {
        vm.prank(dragon);
        game.postRiddle(RIDDLE, answerHash);
        
        // Fast forward past deadline
        vm.warp(block.timestamp + 8 days);
        
        vm.prank(player1);
        vm.expectRevert(DragonsRiddle.RiddleExpiredError.selector);
        game.submitGuess{value: 0.001 ether}("guess");
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // SOLVE TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_SolveRiddle() public {
        vm.prank(dragon);
        game.postRiddle(RIDDLE, answerHash);
        
        // Add some wrong guesses to build pot
        vm.prank(player1);
        game.submitGuess{value: 0.001 ether}("the earth");
        
        vm.prank(player2);
        game.submitGuess{value: 0.001 ether}("the ocean");
        
        uint256 player3BalanceBefore = player3.balance;
        
        vm.prank(player3);
        game.submitGuess{value: 0.001 ether}("A Map"); // Case insensitive!
        
        // Check player3 won
        (,,,,address solver,,) = game.getCurrentRiddle();
        assertEq(solver, player3);
        
        // Check prize paid (90% of 0.003 ETH = 0.0027 ETH)
        // Player paid 0.001, won 0.0027, net gain = 0.0017
        uint256 expectedPrize = 0.003 ether * 90 / 100;
        assertEq(player3.balance, player3BalanceBefore - 0.001 ether + expectedPrize);
    }
    
    function test_CaseInsensitiveAnswer() public {
        vm.prank(dragon);
        game.postRiddle(RIDDLE, answerHash);
        
        vm.prank(player1);
        game.submitGuess{value: 0.001 ether}("A MAP");
        
        (,,,,address solver,,) = game.getCurrentRiddle();
        assertEq(solver, player1);
    }
    
    function test_CannotGuessAfterSolved() public {
        vm.prank(dragon);
        game.postRiddle(RIDDLE, answerHash);
        
        vm.prank(player1);
        game.submitGuess{value: 0.001 ether}("a map");
        
        vm.prank(player2);
        vm.expectRevert(DragonsRiddle.AlreadySolved.selector);
        game.submitGuess{value: 0.001 ether}("a map");
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // REVEAL & REFUND TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_RevealAndRefund() public {
        vm.prank(dragon);
        game.postRiddle(RIDDLE, answerHash);
        
        // Add some guesses
        vm.prank(player1);
        game.submitGuess{value: 0.001 ether}("wrong1");
        
        vm.prank(player2);
        game.submitGuess{value: 0.001 ether}("wrong2");
        
        uint256 player1Before = player1.balance;
        uint256 player2Before = player2.balance;
        
        // Fast forward past deadline
        vm.warp(block.timestamp + 8 days);
        
        vm.prank(dragon);
        game.revealAndRefund(ANSWER);
        
        // Each player should get 0.001 ETH back (0.002 / 2)
        assertEq(player1.balance, player1Before + 0.001 ether);
        assertEq(player2.balance, player2Before + 0.001 ether);
    }
    
    function test_CannotRevealBeforeDeadline() public {
        vm.prank(dragon);
        game.postRiddle(RIDDLE, answerHash);
        
        vm.prank(dragon);
        vm.expectRevert(DragonsRiddle.RiddleNotExpired.selector);
        game.revealAndRefund(ANSWER);
    }
    
    function test_CannotRevealAfterSolved() public {
        vm.prank(dragon);
        game.postRiddle(RIDDLE, answerHash);
        
        vm.prank(player1);
        game.submitGuess{value: 0.001 ether}("a map");
        
        vm.warp(block.timestamp + 8 days);
        
        vm.prank(dragon);
        vm.expectRevert(DragonsRiddle.AlreadySolved.selector);
        game.revealAndRefund(ANSWER);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // STATS TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_Stats() public {
        // Riddle 1: solved
        vm.prank(dragon);
        game.postRiddle(RIDDLE, answerHash);
        
        vm.prank(player1);
        game.submitGuess{value: 0.001 ether}("a map");
        
        // Riddle 2: post new one
        vm.prank(dragon);
        game.postRiddle("What is 2+2?", keccak256("four"));
        
        (
            uint256 totalRiddles,
            uint256 totalSolved,
            uint256 totalPrizesPaid,
            uint256 currentPot
        ) = game.getStats();
        
        assertEq(totalRiddles, 2);
        assertEq(totalSolved, 1);
        assertEq(totalPrizesPaid, 0.0009 ether); // 90% of 0.001
        assertEq(currentPot, 0);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // DRAGON WITHDRAW
    // ═══════════════════════════════════════════════════════════════════════
    
    function test_DragonWithdraw() public {
        vm.prank(dragon);
        game.postRiddle(RIDDLE, answerHash);
        
        // Multiple players guess wrong
        for (uint256 i = 1; i <= 10; i++) {
            address player = address(uint160(i));
            vm.deal(player, 1 ether);
            vm.prank(player);
            game.submitGuess{value: 0.001 ether}("wrong");
        }
        
        // Winner solves
        address winner = address(0x999);
        vm.deal(winner, 1 ether);
        vm.prank(winner);
        game.submitGuess{value: 0.001 ether}("a map");
        
        // Dragon should have 10% = 0.0011 ETH
        uint256 dragonBalanceBefore = dragon.balance;
        
        vm.prank(dragon);
        game.withdrawFees();
        
        assertEq(dragon.balance, dragonBalanceBefore + 0.0011 ether);
    }
    
    // ═══════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════
    
    function testFuzz_AnswerHashing(string memory answer) public {
        vm.assume(bytes(answer).length > 0);
        vm.assume(bytes(answer).length < 100);
        
        bytes32 hash = keccak256(bytes(_toLower(answer)));
        
        vm.prank(dragon);
        game.postRiddle("What is the answer?", hash);
        
        vm.prank(player1);
        game.submitGuess{value: 0.001 ether}(answer);
        
        (,,,,address solver,,) = game.getCurrentRiddle();
        assertEq(solver, player1);
    }
    
    function _toLower(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bLower = new bytes(bStr.length);
        
        for (uint256 i = 0; i < bStr.length; i++) {
            if ((bStr[i] >= 0x41) && (bStr[i] <= 0x5A)) {
                bLower[i] = bytes1(uint8(bStr[i]) + 32);
            } else {
                bLower[i] = bStr[i];
            }
        }
        return string(bLower);
    }
}
