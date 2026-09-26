// Goofer keeper: spins the flywheel whenever it's due (every 3 minutes by default).
// Anyone can call spin(), so this bot only needs a wallet with a little ETH for gas.
const crypto = require('crypto');
const { ethers } = require('ethers');

const {
  RPC_URL,
  KEEPER_PRIVATE_KEY,
  FLYWHEEL_ADDRESS,
  POLL_SECONDS = '15',
} = process.env;

const FLYWHEEL_ABI = [
  'function canSpin() view returns (bool)',
  'function spin() payable',
  'function spinPending() view returns (bool)',
  'function pendingRequestId() view returns (uint256)',
  'function pendingRequestedAt() view returns (uint256)',
  'function REQUEST_TIMEOUT() view returns (uint256)',
  'function clearStuckSpin()',
  'function randomness() view returns (address)',
  'function round() view returns (uint256)',
  'function pot() view returns (uint256)',
  'event SpinWon(uint256 indexed round, address indexed winner, uint256 amount)',
  'event SpinRolledOver(uint256 indexed round, uint256 pot)',
];
const PROVIDER_ABI = [
  'function requestFee() view returns (uint256)',
  'function owner() view returns (address)',
  'function pending(uint256) view returns (bool)',
  'function fulfill(uint256 requestId, uint256 randomWord)',
];

function log(...args) {
  console.log(new Date().toISOString(), ...args);
}

async function main() {
  for (const [name, value] of Object.entries({ RPC_URL, KEEPER_PRIVATE_KEY, FLYWHEEL_ADDRESS })) {
    if (!value) throw new Error(`Missing environment variable ${name}`);
  }

  const provider = new ethers.JsonRpcProvider(RPC_URL);
  const wallet = new ethers.Wallet(KEEPER_PRIVATE_KEY, provider);
  const flywheel = new ethers.Contract(FLYWHEEL_ADDRESS, FLYWHEEL_ABI, wallet);
  const network = await provider.getNetwork();
  log(`Keeper ${wallet.address} watching flywheel ${FLYWHEEL_ADDRESS} on chain ${network.chainId}`);

  let busy = false;
  const tick = async () => {
    if (busy) return;
    busy = true;
    try {
      await step(flywheel, wallet);
    } catch (err) {
      log('Error:', err.shortMessage || err.message);
    } finally {
      busy = false;
    }
  };

  await tick();
  setInterval(tick, Number(POLL_SECONDS) * 1000);
}

async function step(flywheel, wallet) {
  const rng = new ethers.Contract(await flywheel.randomness(), PROVIDER_ABI, wallet);

  if (await flywheel.spinPending()) {
    const requestId = await flywheel.pendingRequestId();

    // Testnet provider: the keeper supplies the random number (Chainlink does this itself on mainnet).
    const isManual = await rng.pending(requestId).then((p) => p, () => null);
    if (isManual) {
      const owner = await rng.owner();
      if (owner.toLowerCase() === wallet.address.toLowerCase()) {
        const word = BigInt('0x' + crypto.randomBytes(32).toString('hex'));
        const tx = await rng.fulfill(requestId, word);
        const receipt = await tx.wait();
        reportResult(flywheel, receipt);
        return;
      }
    }

    const [requestedAt, timeout, block] = await Promise.all([
      flywheel.pendingRequestedAt(), flywheel.REQUEST_TIMEOUT(), wallet.provider.getBlock('latest'),
    ]);
    if (BigInt(block.timestamp) >= requestedAt + timeout) {
      log('Randomness never arrived; clearing the stuck spin.');
      await (await flywheel.clearStuckSpin()).wait();
    }
    return;
  }

  if (!(await flywheel.canSpin())) return;

  const fee = await rng.requestFee();
  const pot = await flywheel.pot();
  const tx = await flywheel.spin({ value: fee });
  await tx.wait();
  log(`Spin ${await flywheel.round()} requested with a pot of ${ethers.formatEther(pot)} GOOFER (tx ${tx.hash})`);
}

function reportResult(flywheel, receipt) {
  for (const entry of receipt.logs) {
    let parsed;
    try { parsed = flywheel.interface.parseLog(entry); } catch { continue; }
    if (!parsed) continue;
    if (parsed.name === 'SpinWon') {
      log(`Spin ${parsed.args.round} won by ${parsed.args.winner}: ${ethers.formatEther(parsed.args.amount)} GOOFER`);
    } else if (parsed.name === 'SpinRolledOver') {
      log(`Spin ${parsed.args.round} rolled over (drawn wallets bought too recently).`);
    }
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
