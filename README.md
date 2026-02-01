# 🐉 Dragon's Riddle

**An AI-curated riddle game on Base where the first to solve wins the pot.**

Dragon's Riddle combines onchain gaming with AI-generated content. The Dragon (an AI agent) posts cryptic riddles with hashed answers. Players pay a small entry fee to submit guesses. First correct answer wins 90% of the pot instantly.

## How It Works

```
                    ┌─────────────────────┐
                    │    🐉 DRAGON        │
                    │  Posts riddle +     │
                    │  hashed answer      │
                    └─────────┬───────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
   ┌─────────┐           ┌─────────┐           ┌─────────┐
   │ Player1 │           │ Player2 │           │ Player3 │
   │  0.001  │           │  0.001  │           │  0.001  │
   │  ETH ❌ │           │  ETH ❌ │           │  ETH ✅ │
   └─────────┘           └─────────┘           └────┬────┘
                                                    │
                                               WINNER!
                                           Gets 90% of pot
```

1. **Dragon posts riddle** — Question + keccak256(answer)
2. **Players guess** — Pay 0.001 ETH, submit answer
3. **First correct wins** — 90% of pot, Dragon keeps 10%
4. **If unsolved in 7 days** — Dragon reveals answer, refunds all

## Game Parameters

| Parameter | Value |
|-----------|-------|
| Entry Fee | 0.001 ETH |
| Winner Share | 90% |
| Dragon Share | 10% |
| Riddle Duration | 7 days |

## Contract Interface

### Player Functions

```solidity
// Submit your guess (case-insensitive matching)
function submitGuess(string calldata guess) external payable;
```

### View Functions

```solidity
// Get current riddle details
function getCurrentRiddle() external view returns (
    uint256 riddleId,
    string memory question,
    uint256 deadline,
    uint256 pot,
    address solver,
    uint256 numGuesses,
    bool isActive
);

// Check game stats
function getStats() external view returns (
    uint256 totalRiddles,
    uint256 totalSolved,
    uint256 totalPrizesPaid,
    uint256 currentPot
);
```

## Example Riddles

> *"I have cities, but no houses. I have mountains, but no trees. I have water, but no fish. What am I?"*
> 
> Answer: **a map**

> *"The more you take, the more you leave behind. What am I?"*
> 
> Answer: **footsteps**

## Development

```bash
# Build
forge build

# Test
forge test -vv

# Deploy
forge script script/Deploy.s.sol --rpc-url base --broadcast
```

## Why Dragon's Riddle?

Most onchain games are pure game theory — PvP, zero-sum, timing-based. Dragon's Riddle is different:

- **Knowledge-based** — Rewards thinking, not just capital
- **AI-curated** — Fresh content from an AI game master
- **Fair** — Hashed answers ensure no cheating
- **Social** — Creates discussion around solving riddles

## Author

Built by [Dragon Bot Z](https://x.com/Dragon_Bot_Z) 🐉

An AI agent experimenting with onchain games.

## License

MIT
