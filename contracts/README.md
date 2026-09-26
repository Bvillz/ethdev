# $GOOFER contracts

Smart contracts for $GOOFER and the Goofer Flywheel, built for **Ethereum** (Sepolia testnet first, then mainnet). They work unchanged on any EVM chain.

| Contract | What it does |
|---|---|
| `src/GooferToken.sol` | The $GOOFER ERC-20. Fixed supply, no minting. A fixed fee (max 5%) on DEX buys and sells goes to the flywheel. Keeps a running tree of holder balances so each holder's slice of the wheel equals their balance. |
| `src/GooferFlywheel.sol` | Holds the pot. Every `SPIN_INTERVAL` (3 minutes by default) anyone can call `spin()`. A random number picks one holder, weighted by holdings, and the whole pot goes to them. |
| `src/randomness/ChainlinkVRFProvider.sol` | Mainnet randomness from Chainlink VRF v2.5. Nobody can predict or rig it. |
| `src/randomness/ManualRandomnessProvider.sol` | **Testnet only.** The keeper supplies the random number, so it could pick the winner. |

## How a spin works

1. Every buy and sell through a registered DEX pool sends `FEE_BPS` of the trade to the flywheel.
2. Once `SPIN_INTERVAL` has passed, the keeper bot (or anyone) calls `spin()`.
3. The randomness provider returns a random number, and `holderAt()` turns it into a holder. Holding 2% of the $GOOFER on the wheel means a 2% chance.
4. The pot (paid in $GOOFER) goes straight to the winner.

**Who is on the wheel:** every wallet holding $GOOFER, except DEX pools, the flywheel itself, `0xdead`, and any wallet the owner excludes before renouncing.

**Anti-sniping:** a wallet that bought within `MIN_HOLD` seconds before the spin can't win. The wheel redraws up to 4 times, then the pot rolls over. Moving fresh buys to another wallet carries the buy time with them.

## Build and test

Install [Foundry](https://book.getfoundry.sh/getting-started/installation), then:

```bash
git submodule update --init --recursive
cd contracts
forge test -vv
```

## Launch checklist

### 1. Sepolia testnet (free test ETH)

```bash
cd contracts
cp .env.example .env         # RANDOMNESS=manual for the testnet
source .env
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --account deployer --broadcast --verify
```

`--account deployer` uses a key stored with `cast wallet import deployer --interactive`, so the key never sits in a file. `--verify` needs `ETHERSCAN_API_KEY`.

Then:

1. Create a Uniswap pool for $GOOFER / ETH and add liquidity from the deployer wallet.
2. `cast send <TOKEN> "setPair(address,bool)" <POOL> true`. The pool comes off the wheel and trades start paying the fee.
3. Run the keeper (`../keeper`) with `FLYWHEEL_ADDRESS` set, from the same wallet that deployed. On testnet the keeper supplies the random numbers.
4. Make some test trades and watch the spins in the keeper log.

### 2. Ethereum mainnet

1. Create a Chainlink VRF v2.5 subscription at vrf.chain.link and fund it. Copy the coordinator address, key hash and subscription ID for Ethereum mainnet from the Chainlink VRF docs, then put them in `.env` with `RANDOMNESS=chainlink`.
2. Deploy as above with your mainnet RPC. The script refuses to deploy the manual provider on mainnet.
3. On vrf.chain.link, add the deployed `ChainlinkVRFProvider` as a consumer of your subscription.
4. Add liquidity, then `setPair` as on testnet.
5. Exclude any team or treasury wallets with `setExcluded`, so they can't win their own pot.
6. When everything works, call `renounceOwnership()` on the token and the flywheel. After that nobody can change pools, exclusions or the randomness source. The fee is fixed at deploy either way.

## Costs on Ethereum mainnet

Measured in the tests with 2,000 holders:

| Action | Gas |
|---|---|
| A buy or sell | ~190,000 (a plain token is ~50,000, the extra is the wheel's holder tree) |
| Starting a spin | ~160,000 (more with Chainlink's request) |
| Picking the winner and paying out | ~110,000 |

A spin every 3 minutes is 480 spins a day. Each spin is a `spin()` transaction plus Chainlink's callback and fee, roughly 300,000–400,000 gas. At 2 gwei that's about **0.3–0.4 ETH a day** before Chainlink's premium, paid by the keeper wallet and the VRF subscription. A longer interval (set `SPIN_INTERVAL` at deploy) or a cheaper Ethereum L2 cuts that a lot.

## Before real money

- **Get an independent audit.** These contracts have tests but haven't been audited.
- **Check the law where you and your holders live.** A random prize paid to token holders can count as a lottery or gambling.
