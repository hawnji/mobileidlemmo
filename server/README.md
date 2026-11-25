# Worldbound server (Phase 4)

The online services run as a JavaScript module inside [Nakama](https://heroiclabs.com/nakama/)
3.22 with PostgreSQL. Nakama provides accounts, sessions, friends, groups (guilds), chat, the
wallet, storage and realtime matches; the module adds the Worldbound rules on top.

```
server/
  nakama/src/*.js         module source, one file per service (concatenated in name order)
  nakama/modules/index.js built module (generated, committed so the server can run without Python)
  tests/test_server.mjs   20 integration tests (Node 22+, plain fetch + WebSocket)
  run_local.sh            start Nakama for development
  run_tests.sh            server tests + Godot client tests against a running server
data/server/server_config.json   validation caps, market, guild, world boss and event settings
tools/build_server_module.py     builds index.js and embeds game data the server needs
docker-compose.yml               production-style stack (written, not yet run; see below)
```

## Run it locally

You need PostgreSQL 12+ and the Nakama binary
([releases](https://github.com/heroiclabs/nakama/releases), tested with 3.22.0 for linux/amd64).

```bash
createdb nakama        # or: psql -c "CREATE DATABASE nakama"
NAKAMA_BIN=/path/to/nakama WB_DB="postgres:PASSWORD@127.0.0.1:5432/nakama" server/run_local.sh
```

`run_local.sh` rebuilds the module, runs the database migrations and starts Nakama on port 7350
with the development keys `wb-dev-server-key` / `wb-dev-http-key`.

In the game, open **Social > Account**, enter `http://YOUR_PC_IP:7350`, the server key
`wb-dev-server-key`, a player name, and press **Go online**. The setting is stored in
`user://online.cfg`; **Play offline** turns it off again.

## Run the tests

```bash
WB_RUNTIME_ENV=WB_BOSS_HP=300 NAKAMA_BIN=... WB_DB=... server/run_local.sh &   # small boss for the defeat test
server/run_tests.sh
```

This runs the 20 Node tests in `server/tests/test_server.mjs` and the 9 Godot client tests in
`tests/online/` (the Godot test runner includes `tests/online` only when `WB_NAKAMA_URL` is set).
Every test makes new accounts, so the suite can be re-run against the same database.
`WB_BOSS_HP` is a test-only setting; the server logs a warning when it is set.

## What the server owns

| Service | RPCs | What it enforces |
|---|---|---|
| Profile and cloud save | `wb_bootstrap`, `wb_save_upload`, `wb_save_download`, `wb_visit_town` | One cloud save per account with optimistic versioning (a second device must load first). Each upload is checked against the last accepted one: the sim clock may not run ahead of real time, item and gold gains must fit per-hour caps for the roster size, recruited characters must have been granted by the server, and escrowed items and gold must be gone. A public town summary is written for visitors. |
| Premium wallet | (inside the above) | Gems, recruitment tokens and festival tokens live in the Nakama wallet. Earned amounts in an accepted save are credited up to a per-hour cap; spends are debited. |
| Recruitment | `wb_recruit`, `wb_recruit_state` | Rolls, pity, featured share and cost run on the server (a port of `RecruitmentState`). The client only displays results. |
| Market and trades | `wb_market_list`, `wb_market_browse`, `wb_market_buy`, `wb_market_cancel`, `wb_claim_deliveries` | Listings escrow items (a ledger debit), at most 20 per player. Buying is atomic: of two buyers racing, one wins. Sellers are paid price minus a 5% fee. Private trades name one buyer. Everything is paid out as deliveries the client claims. |
| Guilds | Nakama groups + `wb_guild_info`, `wb_guild_donate` | Gold donations level the guild (5 levels); each level gives members an XP / gathering bonus. Guild chat is a Nakama group channel. |
| World boss | `wb_boss_status`, `wb_boss_attack` | One shared boss. Strike once per 10 minutes; damage comes from the strongest three heroes in your synced save (never from the client). When it falls every fighter gets gold, items and 50 gems; the next boss spawns. |
| World events | `wb_world_events` | Recurring events on the server clock (Weekend Bounty +10% XP, Market Day +5% gathering), applied as account effects. |
| Region presence | `wb_region_match` + realtime match `region_presence` | One shared match per region; clients send their heroes' tiles about every 2 seconds and see other players' heroes. |

### Ledger of server-side changes

Market listings and donations remove items or gold that the client also holds in its save. Each
such change is a ledger op with a sequence number; the client stores the last op it applied in
the save (`server_ledger_seq`). When a save is uploaded the server subtracts only the ops that the
save does not reflect yet, then drops the applied ones. Deliveries (purchases, sales, returned
listings, boss loot) work the same way as credits.

## Honest limits

- **The world simulation runs on the device, not on the server.** The server validates every
  upload against plausible rates, so cheating is bounded (you cannot conjure 50,000 bars or a
  mythic hero), but a modified client could still play "optimally" within the caps. Running the
  Godot simulation headless on the server (the plan in TECHNICAL_ARCHITECTURE §6) is not done.
- **Offline progress is still computed by the client** on resume and then validated on upload.
  There is no server-side offline simulation yet.
- The first upload of an account is trusted as its baseline. Premium currency earned while
  never online is not carried into the server wallet.
- If the app is killed between a market listing and the next local save, the escrowed items can
  reappear locally; the upload check then allows them only within the normal hourly gain cap.
- Speed-up (x5/x20) and the developer time-skip are disabled online, because the server refuses
  a sim clock ahead of real time.
- `docker-compose.yml` is written but was not run: the build machine had no Docker daemon. The
  same Nakama version and module were tested with `run_local.sh` against PostgreSQL 16.
- No Apple / Google sign-in, push notifications (FCM/APNs), rate limiting or moderation of chat
  and player names yet.
