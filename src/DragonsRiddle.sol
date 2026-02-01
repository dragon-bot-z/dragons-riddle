// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Dragon's Riddle
/// @author Dragon Bot Z 🐉
/// @notice An AI-curated riddle game where the first to solve wins the pot
/// @dev Uses commit-reveal pattern for fair riddle verification

contract DragonsRiddle {
    // ═══════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════
    
    struct Riddle {
        string question;           // The riddle text
        bytes32 answerHash;        // keccak256(lowercase answer)
        uint256 deadline;          // When riddle expires
        uint256 pot;               // Total ETH in pot
        address solver;            // Address that solved it (0 if unsolved)
        bool revealed;             // Whether answer was revealed (for expired riddles)
        string revealedAnswer;     // The answer (only set after reveal)
    }
    
    struct Entry {
        address player;
        string guess;
        uint256 timestamp;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════
    
    address public immutable dragon;
    uint256 public constant ENTRY_FEE = 0.001 ether;
    uint256 public constant DRAGON_CUT = 10; // 10%
    uint256 public constant RIDDLE_DURATION = 7 days;
    
    uint256 public currentRiddleId;
    mapping(uint256 => Riddle) public riddles;
    mapping(uint256 => Entry[]) public entries;
    mapping(uint256 => mapping(address => bool)) public hasEntered;
    
    uint256 public totalRiddles;
    uint256 public totalSolved;
    uint256 public totalPrizesPaid;
    
    // ═══════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════
    
    event RiddlePosted(uint256 indexed riddleId, string question, uint256 deadline);
    event GuessSubmitted(uint256 indexed riddleId, address indexed player, string guess);
    event RiddleSolved(uint256 indexed riddleId, address indexed solver, string answer, uint256 prize);
    event RiddleExpired(uint256 indexed riddleId, string answer, uint256 refundPerPlayer);
    event DragonWithdraw(uint256 amount);

    // ═══════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════
    
    error OnlyDragon();
    error NoActiveRiddle();
    error RiddleAlreadyActive();
    error RiddleExpiredError();
    error RiddleNotExpired();
    error AlreadySolved();
    error IncorrectFee();
    error AlreadyEntered();
    error TransferFailed();
    error EmptyAnswer();

    // ═══════════════════════════════════════════════════════════════════════
    // MODIFIERS
    // ═══════════════════════════════════════════════════════════════════════
    
    modifier onlyDragon() {
        if (msg.sender != dragon) revert OnlyDragon();
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════
    
    constructor() {
        dragon = msg.sender;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DRAGON FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════
    
    /// @notice Post a new riddle (only when no active riddle exists)
    /// @param question The riddle text
    /// @param answerHash keccak256 of the lowercase answer
    function postRiddle(string calldata question, bytes32 answerHash) external onlyDragon {
        // Check no active riddle
        if (currentRiddleId != 0) {
            Riddle storage current = riddles[currentRiddleId];
            if (current.solver == address(0) && block.timestamp <= current.deadline) {
                revert RiddleAlreadyActive();
            }
        }
        
        currentRiddleId++;
        totalRiddles++;
        
        riddles[currentRiddleId] = Riddle({
            question: question,
            answerHash: answerHash,
            deadline: block.timestamp + RIDDLE_DURATION,
            pot: 0,
            solver: address(0),
            revealed: false,
            revealedAnswer: ""
        });
        
        emit RiddlePosted(currentRiddleId, question, block.timestamp + RIDDLE_DURATION);
    }
    
    /// @notice Reveal answer for expired riddle and refund players
    /// @param answer The plaintext answer
    function revealAndRefund(string calldata answer) external onlyDragon {
        Riddle storage riddle = riddles[currentRiddleId];
        
        if (riddle.solver != address(0)) revert AlreadySolved();
        if (block.timestamp <= riddle.deadline) revert RiddleNotExpired();
        
        // Verify the answer matches
        require(keccak256(bytes(_toLower(answer))) == riddle.answerHash, "Answer mismatch");
        
        riddle.revealed = true;
        riddle.revealedAnswer = answer;
        
        // Refund all participants
        Entry[] storage riddleEntries = entries[currentRiddleId];
        uint256 numEntries = riddleEntries.length;
        
        if (numEntries > 0) {
            uint256 refundPerPlayer = riddle.pot / numEntries;
            
            for (uint256 i = 0; i < numEntries; i++) {
                (bool success,) = riddleEntries[i].player.call{value: refundPerPlayer}("");
                // Continue even if some refunds fail
            }
            
            emit RiddleExpired(currentRiddleId, answer, refundPerPlayer);
        } else {
            emit RiddleExpired(currentRiddleId, answer, 0);
        }
        
        riddle.pot = 0;
    }
    
    /// @notice Withdraw dragon's accumulated fees
    function withdrawFees() external onlyDragon {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success,) = dragon.call{value: balance}("");
            if (!success) revert TransferFailed();
            emit DragonWithdraw(balance);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PLAYER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════
    
    /// @notice Submit a guess for the current riddle
    /// @param guess Your answer (will be lowercased for comparison)
    function submitGuess(string calldata guess) external payable {
        if (bytes(guess).length == 0) revert EmptyAnswer();
        if (msg.value != ENTRY_FEE) revert IncorrectFee();
        if (currentRiddleId == 0) revert NoActiveRiddle();
        
        Riddle storage riddle = riddles[currentRiddleId];
        
        if (riddle.solver != address(0)) revert AlreadySolved();
        if (block.timestamp > riddle.deadline) revert RiddleExpiredError();
        if (hasEntered[currentRiddleId][msg.sender]) revert AlreadyEntered();
        
        // Record entry
        hasEntered[currentRiddleId][msg.sender] = true;
        entries[currentRiddleId].push(Entry({
            player: msg.sender,
            guess: guess,
            timestamp: block.timestamp
        }));
        
        // Add to pot
        riddle.pot += msg.value;
        
        emit GuessSubmitted(currentRiddleId, msg.sender, guess);
        
        // Check if correct
        bytes32 guessHash = keccak256(bytes(_toLower(guess)));
        if (guessHash == riddle.answerHash) {
            riddle.solver = msg.sender;
            riddle.revealedAnswer = guess;
            totalSolved++;
            
            // Calculate prize (90% to winner)
            uint256 prize = (riddle.pot * (100 - DRAGON_CUT)) / 100;
            totalPrizesPaid += prize;
            
            // Transfer prize
            (bool success,) = msg.sender.call{value: prize}("");
            if (!success) revert TransferFailed();
            
            // Dragon keeps the rest
            riddle.pot = 0;
            
            emit RiddleSolved(currentRiddleId, msg.sender, guess, prize);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════
    
    /// @notice Get the current riddle details
    function getCurrentRiddle() external view returns (
        uint256 riddleId,
        string memory question,
        uint256 deadline,
        uint256 pot,
        address solver,
        uint256 numGuesses,
        bool isActive
    ) {
        if (currentRiddleId == 0) {
            return (0, "", 0, 0, address(0), 0, false);
        }
        
        Riddle storage riddle = riddles[currentRiddleId];
        bool active = riddle.solver == address(0) && block.timestamp <= riddle.deadline;
        
        return (
            currentRiddleId,
            riddle.question,
            riddle.deadline,
            riddle.pot,
            riddle.solver,
            entries[currentRiddleId].length,
            active
        );
    }
    
    /// @notice Get all guesses for a riddle
    function getGuesses(uint256 riddleId) external view returns (Entry[] memory) {
        return entries[riddleId];
    }
    
    /// @notice Get game stats
    function getStats() external view returns (
        uint256 _totalRiddles,
        uint256 _totalSolved,
        uint256 _totalPrizesPaid,
        uint256 _currentPot
    ) {
        uint256 currentPot = currentRiddleId > 0 ? riddles[currentRiddleId].pot : 0;
        return (totalRiddles, totalSolved, totalPrizesPaid, currentPot);
    }
    
    /// @notice Check if an address has already guessed on current riddle
    function hasPlayerEntered(address player) external view returns (bool) {
        return hasEntered[currentRiddleId][player];
    }

    // ═══════════════════════════════════════════════════════════════════════
    // INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════
    
    /// @notice Convert string to lowercase for case-insensitive comparison
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
    
    receive() external payable {}
}
