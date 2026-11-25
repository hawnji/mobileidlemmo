// Integration tests for the Worldbound Nakama module, run against a live
// server (see server/run_tests.sh). Node 22+, no dependencies.
//
//   WB_URL=http://127.0.0.1:7350 node server/tests/test_server.mjs
//
// The server must run with --runtime.env WB_BOSS_HP=300 so the world boss
// test can finish it off. Every run uses fresh random device ids, so the
// suite can run repeatedly against the same database.

const URL_BASE = process.env.WB_URL || "http://127.0.0.1:7350";
const SERVER_KEY = process.env.WB_SERVER_KEY || "wb-dev-server-key";
const RUN = Math.random().toString(36).slice(2, 8);

let passed = 0, failed = 0;
const failures = [];

function assert(cond, msg) {
  if (!cond) throw new Error(msg || "assertion failed");
}
function eq(a, b, msg) {
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg || "not equal"}: ${JSON.stringify(a)} != ${JSON.stringify(b)}`);
}

async function http(method, path, { token, body, basic } = {}) {
  const headers = { "Content-Type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  if (basic) headers.Authorization = "Basic " + Buffer.from(`${SERVER_KEY}:`).toString("base64");
  const res = await fetch(URL_BASE + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await res.text();
  let json = null;
  try { json = text ? JSON.parse(text) : null; } catch { json = text; }
  return { status: res.status, json };
}

async function login(name) {
  const r = await http("POST", `/v2/account/authenticate/device?create=true&username=${name}_${RUN}`, { basic: true, body: { id: `dev-${name}-${RUN}-device-id` } });
  assert(r.status === 200, `auth failed ${r.status} ${JSON.stringify(r.json)}`);
  const acct = await http("GET", "/v2/account", { token: r.json.token });
  return { token: r.json.token, id: acct.json.user.id, name: `${name}_${RUN}` };
}

// RPC with a JSON payload. Returns {ok, data, status, message}.
async function rpc(user, id, payload = {}) {
  const r = await http("POST", `/v2/rpc/${id}?unwrap`, { token: user.token, body: payload });
  if (r.status === 200) return { ok: true, data: r.json };
  return { ok: false, status: r.status, message: r.json && r.json.message };
}

async function rpcOk(user, id, payload) {
  const r = await rpc(user, id, payload);
  assert(r.ok, `${id} failed: ${r.status} ${r.message}`);
  return r.data;
}

// A minimal save in the client's format (only fields the server reads).
function makeSave({ simTime = 100, gold = 1000, items = {}, chars = ["brom_stonefist", "sylvara_moonleaf", "tamsin_reed"], earned = {}, spent = {}, seq = 0 } = {}) {
  const characters = {};
  for (const c of chars) characters[c] = { inventory: { items: {} }, equipment: {}, character_xp: 5000, stars: 1 };
  return {
    save_version: 1,
    world: {
      format: 3, sim_time: simTime, storage: { items }, characters, character_order: chars,
      wallet: { balances: { gold }, earned, spent }, armory: [], mailbox: {},
      town: { levels: { town_hall: 1 } }, unlocked_regions: ["greenvale"], server_ledger_seq: seq,
    },
  };
}

class Socket {
  constructor(user) {
    this.user = user;
    this.events = [];
    this.waiters = [];
    this.cid = 1;
    this.pending = new Map();
  }
  open() {
    const wsUrl = URL_BASE.replace(/^http/, "ws") + `/ws?token=${this.user.token}&format=json`;
    this.ws = new WebSocket(wsUrl);
    return new Promise((resolve, reject) => {
      this.ws.onopen = () => resolve();
      this.ws.onerror = (e) => reject(new Error("socket error"));
      this.ws.onmessage = (m) => {
        const msg = JSON.parse(m.data);
        if (msg.cid && this.pending.has(msg.cid)) {
          this.pending.get(msg.cid)(msg);
          this.pending.delete(msg.cid);
          return;
        }
        this.events.push(msg);
        this.waiters = this.waiters.filter((w) => !w(msg));
      };
    });
  }
  send(body) {
    const cid = String(this.cid++);
    this.ws.send(JSON.stringify({ cid, ...body }));
    return new Promise((resolve) => this.pending.set(cid, resolve));
  }
  sendNoReply(body) {
    this.ws.send(JSON.stringify(body));
  }
  waitFor(pred, ms = 5000) {
    const hit = this.events.find(pred);
    if (hit) return Promise.resolve(hit);
    return new Promise((resolve, reject) => {
      const t = setTimeout(() => reject(new Error("timed out waiting for a socket event")), ms);
      this.waiters.push((msg) => { if (pred(msg)) { clearTimeout(t); resolve(msg); return true; } return false; });
    });
  }
  close() { this.ws.close(); }
}

const tests = [];
function test(name, fn) { tests.push([name, fn]); }

// ------------------------------------------------------------------ profile

test("bootstrap gives the starting premium wallet once", async () => {
  const a = await login("boot");
  const b1 = await rpcOk(a, "wb_bootstrap");
  assert(b1.wallet.gems > 0, "starting gems");
  const b2 = await rpcOk(a, "wb_bootstrap");
  eq(b2.wallet, b1.wallet, "second bootstrap does not grant again");
  assert(b1.has_save === false);
  assert(Array.isArray(b1.events));
  assert(b1.boss && b1.boss.max_hp > 0);
});

test("first save is accepted and downloads unchanged", async () => {
  const a = await login("save");
  const s = makeSave({ items: { copper_ore: 40 } });
  const up = await rpcOk(a, "wb_save_upload", { save: s });
  assert(up.accepted, up.reason);
  const down = await rpcOk(a, "wb_save_download");
  assert(down.found);
  eq(down.save.world.storage.items, { copper_ore: 40 });
  eq(down.version, up.version);
});

test("implausible gold, items or clock are rejected", async () => {
  const a = await login("cheat");
  assert((await rpcOk(a, "wb_save_upload", { save: makeSave({ simTime: 100 }) })).accepted);
  const gold = await rpcOk(a, "wb_save_upload", { save: makeSave({ simTime: 150, gold: 50_000_000 }) });
  assert(!gold.accepted && /gold/i.test(gold.reason), gold.reason);
  const items = await rpcOk(a, "wb_save_upload", { save: makeSave({ simTime: 150, items: { mithril_bar: 100000 } }) });
  assert(!items.accepted && /mithril_bar/.test(items.reason), items.reason);
  const clock = await rpcOk(a, "wb_save_upload", { save: makeSave({ simTime: 100 + 86400 }) });
  assert(!clock.accepted && /real time/.test(clock.reason), clock.reason);
  const ok = await rpcOk(a, "wb_save_upload", { save: makeSave({ simTime: 140, items: { copper_ore: 20 } }) });
  assert(ok.accepted, ok.reason);
});

test("gacha characters the server never granted are rejected", async () => {
  const a = await login("chars");
  assert((await rpcOk(a, "wb_save_upload", { save: makeSave() })).accepted);
  const bad = await rpcOk(a, "wb_save_upload", { save: makeSave({ simTime: 120, chars: ["brom_stonefist", "sylvara_moonleaf", "tamsin_reed", "elowen_starweaver", "aurelia_dawnbringer"] }) });
  assert(!bad.accepted && /recruitment/.test(bad.reason), bad.reason);
  const unknown = await rpcOk(a, "wb_save_upload", { save: makeSave({ simTime: 120, chars: ["brom_stonefist", "not_a_hero"] }) });
  assert(!unknown.accepted && /Unknown character/.test(unknown.reason), unknown.reason);
});

test("stale cloud version is refused (another device saved first)", async () => {
  const a = await login("devices");
  const first = await rpcOk(a, "wb_save_upload", { save: makeSave() });
  await rpcOk(a, "wb_save_upload", { save: makeSave({ simTime: 110 }), expected_version: first.version });
  const stale = await rpc(a, "wb_save_upload", { save: makeSave({ simTime: 120 }), expected_version: first.version });
  assert(!stale.ok && /another device/.test(stale.message), stale.message);
});

test("premium currency earned in the simulation is credited, with a cap", async () => {
  const a = await login("earn");
  await rpcOk(a, "wb_bootstrap");
  assert((await rpcOk(a, "wb_save_upload", { save: makeSave({ earned: { gems: 0 } }) })).accepted);
  const w0 = (await rpcOk(a, "wb_bootstrap")).wallet.gems;
  const up = await rpcOk(a, "wb_save_upload", { save: makeSave({ simTime: 130, earned: { gems: 50 } }) });
  assert(up.accepted, up.reason);
  eq(up.wallet.gems, w0 + 50, "50 earned gems credited");
  const greedy = await rpcOk(a, "wb_save_upload", { save: makeSave({ simTime: 160, earned: { gems: 100050 } }) });
  assert(greedy.accepted);
  assert(greedy.wallet.gems - up.wallet.gems <= 200, `credit capped, got ${greedy.wallet.gems - up.wallet.gems}`);
});

test("visiting a synced town shows its buildings and roster", async () => {
  const a = await login("host");
  const b = await login("guest");
  await rpcOk(a, "wb_save_upload", { save: makeSave() });
  const town = await rpcOk(b, "wb_visit_town", { user_id: a.id });
  eq(town.buildings, { town_hall: 1 });
  eq(town.roster.length, 3);
  const none = await rpc(b, "wb_visit_town", { user_id: b.id });
  assert(!none.ok);
});

// ------------------------------------------------------------------ recruitment

test("server recruitment charges tokens, honours pity and grants characters", async () => {
  const a = await login("gacha");
  const boot = await rpcOk(a, "wb_bootstrap");
  const tokens = boot.wallet.recruitment_tokens;
  assert(tokens >= 10, "starter tokens");
  const r = await rpcOk(a, "wb_recruit", { banner: "standard", count: 10 });
  eq(r.results.length, 10);
  eq(r.cost, { recruitment_tokens: 10 });
  eq(r.wallet.recruitment_tokens, tokens - 10);
  const order = ["common", "uncommon", "rare", "epic", "legendary", "mythic"];
  assert(r.results.some((x) => order.indexOf(x.rarity) >= 2), "pity guarantees a rare or better in 10 pulls");
  const ids = [...new Set(r.results.map((x) => x.character_id))];
  // The recruited characters are now accepted in a save.
  await rpcOk(a, "wb_save_upload", { save: makeSave() });
  const up = await rpcOk(a, "wb_save_upload", { save: makeSave({ simTime: 120, chars: ["brom_stonefist", "sylvara_moonleaf", "tamsin_reed", ...ids] }) });
  assert(up.accepted, up.reason);
  const st = await rpcOk(a, "wb_recruit_state");
  eq(st.total.standard, 10);
});

test("recruitment without currency fails and changes nothing", async () => {
  const a = await login("broke");
  await rpcOk(a, "wb_bootstrap");
  let r;
  for (let i = 0; i < 30; i++) {
    r = await rpc(a, "wb_recruit", { banner: "standard", count: 10 });
    if (!r.ok) break;
  }
  assert(!r.ok && /Not enough/.test(r.message), r.message);
  const w = (await rpcOk(a, "wb_bootstrap")).wallet;
  assert(w.gems >= 0 && w.recruitment_tokens >= 0);
  const bad = await rpc(a, "wb_recruit", { banner: "nope", count: 1 });
  assert(!bad.ok);
  const badCount = await rpc(a, "wb_recruit", { banner: "standard", count: 3 });
  assert(!badCount.ok);
});

// ------------------------------------------------------------------ market

test("market: list, browse, buy, deliveries and fees", async () => {
  const s = await login("seller");
  const b = await login("buyer");
  await rpcOk(s, "wb_save_upload", { save: makeSave({ items: { copper_ore: 50 } }) });
  await rpcOk(b, "wb_save_upload", { save: makeSave({ gold: 5000 }) });
  const tooMany = await rpc(s, "wb_market_list", { item: "copper_ore", qty: 51, price: 100 });
  assert(!tooMany.ok && /only have 50/.test(tooMany.message), tooMany.message);
  const l = await rpcOk(s, "wb_market_list", { item: "copper_ore", qty: 20, price: 400 });
  assert(l.ledger_seq > 0);
  const seen = await rpcOk(b, "wb_market_browse", { item: "copper_ore" });
  assert(seen.listings.some((x) => x.id === l.listing.id));
  const own = await rpc(s, "wb_market_buy", { listing_id: l.listing.id });
  assert(!own.ok);
  const buy = await rpcOk(b, "wb_market_buy", { listing_id: l.listing.id });
  eq(buy.fee, 20);
  const again = await rpc(b, "wb_market_buy", { listing_id: l.listing.id });
  assert(!again.ok, "a listing sells once");
  const bd = await rpcOk(b, "wb_claim_deliveries");
  eq(bd.items, { copper_ore: 20 });
  const sd = await rpcOk(s, "wb_claim_deliveries");
  eq(sd.items, { gold: 380 });
  const none = await rpcOk(s, "wb_claim_deliveries");
  eq(none.items, {}, "deliveries are claimed once");
  // Both sides sync saves that reflect the trade.
  const bs = await rpcOk(b, "wb_save_upload", { save: makeSave({ simTime: 110, gold: 4600, items: { copper_ore: 20 }, seq: bd.ledger_seq }) });
  assert(bs.accepted, bs.reason);
  const ss = await rpcOk(s, "wb_save_upload", { save: makeSave({ simTime: 110, gold: 1380, items: { copper_ore: 30 }, seq: sd.ledger_seq }) });
  assert(ss.accepted, ss.reason);
});

test("market: a save that keeps sold items is rejected", async () => {
  const s = await login("duper");
  await rpcOk(s, "wb_save_upload", { save: makeSave({ items: { iron_bar: 600 } }) });
  const l = await rpcOk(s, "wb_market_list", { item: "iron_bar", qty: 500, price: 10 });
  const cheat = await rpcOk(s, "wb_save_upload", { save: makeSave({ simTime: 110, items: { iron_bar: 600 }, seq: l.ledger_seq }) });
  assert(!cheat.accepted && /iron_bar/.test(cheat.reason), cheat.reason);
  const honest = await rpcOk(s, "wb_save_upload", { save: makeSave({ simTime: 110, items: { iron_bar: 100 }, seq: l.ledger_seq }) });
  assert(honest.accepted, honest.reason);
});

test("market: only one of two simultaneous buyers gets the listing", async () => {
  const s = await login("hot");
  const b1 = await login("race1");
  const b2 = await login("race2");
  await rpcOk(s, "wb_save_upload", { save: makeSave({ items: { tin_ore: 10 } }) });
  await rpcOk(b1, "wb_save_upload", { save: makeSave({ gold: 1000 }) });
  await rpcOk(b2, "wb_save_upload", { save: makeSave({ gold: 1000 }) });
  const l = await rpcOk(s, "wb_market_list", { item: "tin_ore", qty: 5, price: 50 });
  const [r1, r2] = await Promise.all([rpc(b1, "wb_market_buy", { listing_id: l.listing.id }), rpc(b2, "wb_market_buy", { listing_id: l.listing.id })]);
  eq([r1.ok, r2.ok].filter(Boolean).length, 1, "exactly one purchase");
  const loser = r1.ok ? r2 : r1;
  assert(/sold|gone/.test(loser.message), "loser gets a clear message: " + loser.message);
  const d1 = await rpcOk(b1, "wb_claim_deliveries");
  const d2 = await rpcOk(b2, "wb_claim_deliveries");
  eq((d1.items.tin_ore || 0) + (d2.items.tin_ore || 0), 5, "five tin delivered in total");
});

test("direct trade is reserved for one player; cancel returns items", async () => {
  const s = await login("trader");
  const friend = await login("friend");
  const other = await login("other");
  await rpcOk(s, "wb_save_upload", { save: makeSave({ items: { oak_log: 30 } }) });
  await rpcOk(friend, "wb_save_upload", { save: makeSave({ gold: 500 }) });
  await rpcOk(other, "wb_save_upload", { save: makeSave({ gold: 500 }) });
  const l = await rpcOk(s, "wb_market_list", { item: "oak_log", qty: 10, price: 30, buyer: friend.id });
  const hidden = await rpcOk(other, "wb_market_browse", { item: "oak_log" });
  assert(!hidden.listings.some((x) => x.id === l.listing.id), "private trade hidden from others");
  const denied = await rpc(other, "wb_market_buy", { listing_id: l.listing.id });
  assert(!denied.ok);
  await rpcOk(friend, "wb_market_buy", { listing_id: l.listing.id });
  const l2 = await rpcOk(s, "wb_market_list", { item: "oak_log", qty: 5, price: 30 });
  await rpcOk(s, "wb_market_cancel", { listing_id: l2.listing.id });
  const back = await rpcOk(s, "wb_claim_deliveries");
  eq(back.items.oak_log, 5);
  eq(back.items.gold, 29);
});

// ------------------------------------------------------------------ social

test("friends: request, accept, list", async () => {
  const a = await login("fa");
  const b = await login("fb");
  eq((await http("POST", `/v2/friend?usernames=${b.name}`, { token: a.token })).status, 200);
  eq((await http("POST", `/v2/friend?ids=${a.id}`, { token: b.token })).status, 200);
  const list = await http("GET", "/v2/friend", { token: a.token });
  const f = list.json.friends.find((x) => x.user.id === b.id);
  assert(f && f.state === 0, "mutual friends (state 0)");
});

test("guilds: create, join, donate gold, level up and perks", async () => {
  const a = await login("gm");
  const b = await login("gmember");
  await rpcOk(a, "wb_save_upload", { save: makeSave({ gold: 30000 }) });
  const g = await http("POST", "/v2/group", { token: a.token, body: { name: `Guild ${RUN}`, open: true } });
  eq(g.status, 200);
  eq((await http("POST", `/v2/group/${g.json.id}/join`, { token: b.token })).status, 200);
  const info0 = await rpcOk(b, "wb_guild_info");
  assert(info0.in_guild && info0.level === 1);
  const tooMuch = await rpc(a, "wb_guild_donate", { gold: 50000 });
  assert(!tooMuch.ok);
  const d = await rpcOk(a, "wb_guild_donate", { gold: 25000 });
  eq(d.level, 3);
  assert(d.perks["xp.all"] > 1, "level 3 perks");
  const info = await rpcOk(b, "wb_guild_info");
  eq(info.xp, 25000);
  // The donation must show up in the donor's next save.
  const kept = await rpcOk(a, "wb_save_upload", { save: makeSave({ simTime: 110, gold: 30000, seq: d.ledger_seq }) });
  assert(!kept.accepted, "a save that keeps the donated gold is rejected");
  const paid = await rpcOk(a, "wb_save_upload", { save: makeSave({ simTime: 110, gold: 5000, seq: d.ledger_seq }) });
  assert(paid.accepted, "a save with the donation applied is accepted: " + paid.reason);
});

test("chat: guild channel messages reach other members in real time", async () => {
  const a = await login("chat1");
  const b = await login("chat2");
  const g = await http("POST", "/v2/group", { token: a.token, body: { name: `Chat ${RUN}`, open: true } });
  await http("POST", `/v2/group/${g.json.id}/join`, { token: b.token });
  const sa = new Socket(a), sb = new Socket(b);
  await sa.open(); await sb.open();
  const ja = await sa.send({ channel_join: { target: g.json.id, type: 3, persistence: true, hidden: false } });
  await sb.send({ channel_join: { target: g.json.id, type: 3, persistence: true, hidden: false } });
  await sa.send({ channel_message_send: { channel_id: ja.channel.id, content: JSON.stringify({ text: "hello guild" }) } });
  const got = await sb.waitFor((m) => m.channel_message && /hello guild/.test(m.channel_message.content));
  eq(got.channel_message.username, a.name);
  sa.close(); sb.close();
});

test("region presence: players in a region see each other's heroes", async () => {
  const a = await login("walker1");
  const b = await login("walker2");
  const m1 = await rpcOk(a, "wb_region_match", { region: "irondeep" });
  const m2 = await rpcOk(b, "wb_region_match", { region: "irondeep" });
  eq(m1.match_id, m2.match_id, "one shared match per region");
  const bad = await rpc(a, "wb_region_match", { region: "atlantis" });
  assert(!bad.ok);
  const sa = new Socket(a), sb = new Socket(b);
  await sa.open(); await sb.open();
  await sa.send({ match_join: { match_id: m1.match_id } });
  await sb.send({ match_join: { match_id: m1.match_id } });
  const data = Buffer.from(JSON.stringify({ heroes: [{ id: "brom_stonefist", x: 90, y: 20 }] })).toString("base64");
  sa.sendNoReply({ match_data_send: { match_id: m1.match_id, op_code: "1", data } });
  const st = await sb.waitFor((m) => {
    if (!m.match_data || String(m.match_data.op_code) !== "2") return false;
    const s = JSON.parse(Buffer.from(m.match_data.data, "base64").toString());
    return s.players[a.id] && s.players[a.id].heroes.length === 1;
  }, 6000);
  const s = JSON.parse(Buffer.from(st.match_data.data, "base64").toString());
  const h = s.players[a.id].heroes[0];
  eq([h.id, h.x, h.y], ["brom_stonefist", 90, 20]);
  sa.close(); sb.close();
});

// ------------------------------------------------------------------ world

test("world boss: cooldown, shared damage, defeat rewards everyone who fought", async () => {
  const a = await login("raid1");
  const b = await login("raid2");
  await rpcOk(a, "wb_save_upload", { save: makeSave() });
  await rpcOk(b, "wb_save_upload", { save: makeSave() });
  const noSave = await login("raid3");
  assert(!(await rpc(noSave, "wb_boss_attack")).ok, "a synced save is required");
  const before = await rpcOk(a, "wb_boss_status");
  const gemsA = (await rpcOk(a, "wb_bootstrap")).wallet.gems;
  const hitA = await rpcOk(a, "wb_boss_attack");
  assert(hitA.damage > 0);
  const cd = await rpc(a, "wb_boss_attack");
  assert(!cd.ok && /recovering/.test(cd.message), "cooldown");
  const st = await rpcOk(a, "wb_boss_status");
  assert(st.cooldown_remaining > 0);
  // Other fighters finish the boss (the test server runs with WB_BOSS_HP=300).
  let defeated = hitA.defeated;
  let fighters = [b];
  for (let i = 0; i < 20 && !defeated; i++) {
    const u = await login(`raider${i}`);
    await rpcOk(u, "wb_save_upload", { save: makeSave() });
    const r = await rpcOk(u, "wb_boss_attack");
    defeated = r.defeated;
    fighters.push(u);
  }
  assert(defeated, "boss falls");
  const after = await rpcOk(a, "wb_boss_status");
  assert(after.index > before.index, "a new boss spawned");
  const loot = await rpcOk(a, "wb_claim_deliveries");
  assert(loot.items.gold > 0, "rewards delivered to an earlier fighter");
  const gemsAfter = (await rpcOk(a, "wb_bootstrap")).wallet.gems;
  assert(gemsAfter > gemsA, "gem reward");
});

test("world events follow the server clock", async () => {
  const a = await login("events");
  const ev = await rpcOk(a, "wb_world_events");
  assert(Math.abs(ev.server_time - Date.now() / 1000) < 60);
  assert(Array.isArray(ev.events));
  for (const e of ev.events) assert(e.ends_at > ev.server_time && e.effects);
});

test("calls without a session are refused", async () => {
  const r = await http("POST", "/v2/rpc/wb_bootstrap?unwrap", { body: {} });
  assert(r.status === 401 || r.status === 400, `status ${r.status}`);
});

// ------------------------------------------------------------------ runner

const filter = process.argv[2] || "";
for (const [name, fn] of tests) {
  if (filter && !name.includes(filter)) continue;
  const t0 = Date.now();
  try {
    await fn();
    passed++;
    console.log(`  PASS  ${name} (${Date.now() - t0} ms)`);
  } catch (e) {
    failed++;
    failures.push(name);
    console.log(`  FAIL  ${name}\n        - ${e.message}`);
  }
}
console.log(`\n${passed + failed} server tests, ${failed} failed`);
process.exit(failed ? 1 : 0);
