# Goofer ($GOOFER)

Landing page for Goofer, the meme agent that signed up for X Money with no money to claim the benefits, and now gives back through the **Goofer Flywheel**.

The flywheel on the site is interactive: every holder gets a slice sized by their share of $GOOFER, visitors can type in a balance to see their own slice, and the wheel spins to a weighted random winner. Until the token launches it uses made-up demo wallets (see `DEMO_HOLDERS` in `public/app.js`).

## Run locally

```bash
npm start          # http://localhost:3000
npm test
```

No dependencies. Needs Node 18 or newer.

## Deploy on Railway

1. In Railway, choose **New Project → Deploy from GitHub repo** and pick this repo.
2. Railway detects Node and runs `npm start`. `railway.json` sets the health check to `/health`.
3. Under **Settings → Networking**, click **Generate Domain** (or add your own domain).
4. Under **Variables**, add any of the settings below. The site shows a placeholder for anything left blank.

| Variable | What it does |
|---|---|
| `CONTRACT_ADDRESS` | Token contract (`0x` + 40 hex characters). Enables the Copy button. |
| `CHAIN_NAME` | e.g. `Ethereum` |
| `TOTAL_SUPPLY` | e.g. `1,000,000,000` |
| `LAUNCH_DATE` | e.g. `1 Nov 2026` |
| `FEE_PERCENT` | Flywheel fee on trades, number only, e.g. `1` |
| `SPIN_SCHEDULE` | e.g. `Every 3 min` (default) |
| `MIN_HOLD_LABEL` | How long after buying a wallet sits out, e.g. `3 minutes` (default) |
| `X_HANDLE` | X account, without the `@` |
| `TELEGRAM_URL` | Telegram invite link (`https://` only) |
| `BUY_URL` | DEX link; shows a "Buy $GOOFER" button when set (`https://` only) |

See `.env.example` for the full list.

## Smart contracts and keeper

- `contracts/` – the $GOOFER token and the Goofer Flywheel (Foundry). See `contracts/README.md` for tests, costs and the launch checklist.
- `keeper/` – a bot that calls `spin()` every time a spin is due (every 3 minutes by default). Deploy it on Railway as a **second service** with its root directory set to `keeper`, and set the variables in `keeper/.env.example`. Use a separate wallet holding only a little ETH for gas.

## Files

- `server.js` – small static server, `/health`, and `/config.js` built from the variables above
- `public/` – the site (`index.html`, `styles.css`, `app.js`, `404.html`, `favicon.svg`)
- `test/` – server tests (`npm test`)
