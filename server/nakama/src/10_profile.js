// Profile, wallet and cloud saves.
//
// Authority split (see docs/TECHNICAL_ARCHITECTURE.md section 6):
//  * server-authoritative: premium currencies (gems, recruitment and event
//    tokens) in the Nakama wallet, recruitment RNG/pity, market escrow,
//    guilds, the world boss, region presence;
//  * client-simulated, server-validated: the idle simulation itself. Every
//    uploaded save is compared with the last accepted one; gains above the
//    configured rate caps, characters the server never granted, or clocks
//    that run ahead of real time are rejected.

var PREMIUM = ["gems", "recruitment_tokens", "event_tokens"];

function ensureWallet(nk, userId) {
  var flag = readOne(nk, "profile", "init", userId);
  if (flag) return;
  var start = config("starting_wallet", {});
  var change = {};
  for (var i = 0; i < PREMIUM.length; i++) change[PREMIUM[i]] = intOr(start[PREMIUM[i]], 0);
  nk.walletUpdate(userId, change, { reason: "starting_wallet" }, true);
  writeOne(nk, "profile", "init", userId, { at: nowSec() }, "*", 0);
}

function walletOf(nk, userId) {
  var acc = nk.accountGetId(userId);
  var w = acc.wallet || {};
  if (typeof w === "string") w = JSON.parse(w);
  var out = {};
  for (var i = 0; i < PREMIUM.length; i++) out[PREMIUM[i]] = intOr(w[PREMIUM[i]], 0);
  return out;
}

function rpcBootstrap(ctx, logger, nk, payload) {
  var uid = requireUser(ctx);
  ensureWallet(nk, uid);
  var save = readOne(nk, "saves", "main", uid);
  var granted = readOne(nk, "profile", "granted", uid);
  return JSON.stringify({
    server_time: nowSec(),
    user_id: uid,
    username: ctx.username,
    wallet: walletOf(nk, uid),
    has_save: !!save,
    save_version: save ? save.version : "",
    saved_at: save ? save.value.saved_at : 0,
    granted_characters: granted ? granted.value.ids : [],
    events: activeEvents(),
    boss: bossPublic(nk, ctx),
    pending_deliveries: countDeliveries(nk, uid)
  });
}

// --- Save summaries -----------------------------------------------------------

function itemTotals(world) {
  var t = {};
  var st = (world.storage || {}).items || {};
  for (var k in st) addTo(t, k, intOr(st[k], 0));
  var chars = world.characters || {};
  for (var cid in chars) {
    var inv = (chars[cid].inventory || {}).items || {};
    for (var k2 in inv) addTo(t, k2, intOr(inv[k2], 0));
    var eq = chars[cid].equipment || {};
    for (var slot in eq) if (eq[slot] && eq[slot].item_id) addTo(t, eq[slot].item_id, 1);
  }
  var arm = world.armory || [];
  for (var i = 0; i < arm.length; i++) if (arm[i] && arm[i].item_id) addTo(t, arm[i].item_id, 1);
  var mb = world.mailbox || {};
  for (var k3 in mb) addTo(t, k3, intOr(mb[k3], 0));
  return t;
}

function summarize(world, savedAt) {
  var w = world.wallet || {};
  return {
    saved_at: savedAt,
    sim_time: Number(world.sim_time) || 0,
    gold: intOr((w.balances || {}).gold, 0),
    earned: w.earned || {},
    spent: w.spent || {},
    items: itemTotals(world),
    characters: Object.keys(world.characters || {})
  };
}

// Ops up to the save's sequence are reflected in it: drop them.
function clearAppliedOps(nk, uid, seq) {
  for (var attempt = 0; attempt < 5; attempt++) {
    var obj = readOne(nk, "ledger", "pending", uid);
    if (!obj) return;
    var led = obj.value;
    led.ops = led.ops.filter(function (o) { return o.seq > seq; });
    try {
      writeOne(nk, "ledger", "pending", uid, led, obj.version, 0);
      return;
    } catch (e) {}
  }
}

// a - b per key (entries of a only).
function diffMaps(a, b) {
  var out = {};
  for (var k in a) out[k] = a[k] - (b[k] || 0);
  return out;
}

function sumValues(m) {
  var s = 0;
  for (var k in m) s += m[k];
  return s;
}

// Returns "" when the new save is plausible after the previous one.
function validateSave(prev, next, granted, ledger, elapsed) {
  var hours = Math.max(elapsed, 60) / 3600.0;
  var nChars = Math.max(next.characters.length, 1);
  if (next.sim_time + 1 < prev.sim_time) return "Save is older than the last synced save";
  var maxSim = elapsed + config("validation.clock_slack_seconds", 600);
  if (next.sim_time - prev.sim_time > maxSim) return "Simulation ran ahead of real time";
  var itemCap = config("validation.items_per_character_hour", 2500) * nChars * hours;
  var deb = ledger.debits || {}, cred = ledger.credits || {};
  var gain = 0;
  for (var it in next.items) {
    var d = next.items[it] - (prev.items[it] || 0) - (cred[it] || 0) + (deb[it] || 0);
    if (d > itemCap) return "Too many " + it + " gained since the last sync";
    if (d > 0) gain += d;
  }
  if (gain > itemCap * 1.5) return "Too many items gained since the last sync";
  var goldCap = config("validation.gold_per_character_hour", 40000) * nChars * hours + config("validation.gold_slack", 5000);
  if (next.gold - prev.gold - (cred.gold || 0) + (deb.gold || 0) > goldCap) return "Too much gold gained since the last sync";
  var gachaIds = WB_DATA.gacha_ids;
  var grantedSet = {};
  for (var i = 0; i < granted.length; i++) grantedSet[granted[i]] = true;
  var prevSet = {};
  for (var j = 0; j < prev.characters.length; j++) prevSet[prev.characters[j]] = true;
  var unexplained = 0;
  for (var c = 0; c < next.characters.length; c++) {
    var cid = next.characters[c];
    if (!WB_DATA.character_rarity[cid]) return "Unknown character " + cid;
    if (gachaIds[cid] && !grantedSet[cid] && !prevSet[cid]) unexplained += 1;
  }
  // Wandering-hero encounters can recruit gacha characters without the server.
  if (unexplained > Math.max(1, Math.floor(hours / config("validation.hours_per_encounter_hero", 6)))) return "Characters were added without recruitment";
  return "";
}

// Premium earnings found in the save are credited to the server wallet
// (capped); premium spends made by the simulation are debited.
function premiumDelta(prev, next, hours) {
  var delta = {};
  var cap = config("validation.premium_per_hour", { gems: 200, recruitment_tokens: 6, event_tokens: 6 });
  for (var i = 0; i < PREMIUM.length; i++) {
    var c = PREMIUM[i];
    var earned = Math.max(intOr(next.earned[c], 0) - intOr(prev.earned[c], 0), 0);
    var spent = Math.max(intOr(next.spent[c], 0) - intOr(prev.spent[c], 0), 0);
    earned = Math.min(earned, Math.ceil((cap[c] || 0) * Math.max(hours, 1)));
    if (earned - spent !== 0) delta[c] = earned - spent;
  }
  return delta;
}

function rpcSaveUpload(ctx, logger, nk, payload) {
  var uid = requireUser(ctx);
  ensureWallet(nk, uid);
  var p = parsePayload(payload);
  var save = p.save;
  if (!save || typeof save !== "object" || !save.world) throw wbError("Missing save.world");
  if (JSON.stringify(save).length > config("validation.max_save_bytes", 4000000)) throw wbError("Save is too large");
  var now = nowSec();
  var next = summarize(save.world, now);
  var prevObj = readOne(nk, "saves", "main", uid);
  if (p.expected_version && prevObj && prevObj.version !== p.expected_version) {
    throw wbError("The cloud save changed on another device", CODE.PRECONDITION);
  }
  var walletChange = {};
  if (prevObj) {
    var prev = prevObj.value.summary;
    var grantedObj = readOne(nk, "profile", "granted", uid);
    var ledObj = readOne(nk, "ledger", "pending", uid);
    // Only ops the save says it applied (seq <= server_ledger_seq) are in it.
    var ledger = ledgerTotals(ledObj ? ledObj.value : null, -1);
    var unapplied = ledgerTotals(ledObj ? ledObj.value : null, intOr(save.world.server_ledger_seq, 0));
    ledger = { debits: diffMaps(ledger.debits, unapplied.debits), credits: diffMaps(ledger.credits, unapplied.credits) };
    var elapsed = now - prev.saved_at;
    var why = validateSave(prev, next, grantedObj ? grantedObj.value.ids : [], ledger, elapsed);
    if (why !== "") {
      logger.warn("save rejected for %s: %s", uid, why);
      return JSON.stringify({ accepted: false, reason: why, wallet: walletOf(nk, uid) });
    }
    walletChange = premiumDelta(prev, next, elapsed / 3600.0);
  }
  var w = walletOf(nk, uid);
  for (var c in walletChange) {
    if (w[c] + walletChange[c] < 0) walletChange[c] = -w[c];
  }
  if (Object.keys(walletChange).length > 0) nk.walletUpdate(uid, walletChange, { reason: "save_sync" }, true);
  var ack = writeOne(nk, "saves", "main", uid, { saved_at: now, summary: next, save: save }, prevObj ? prevObj.version : "*", 1);
  clearAppliedOps(nk, uid, intOr(save.world.server_ledger_seq, 0));
  writePublicTown(nk, uid, ctx.username, save.world);
  return JSON.stringify({ accepted: true, version: ack.version, saved_at: now, wallet: walletOf(nk, uid) });
}

function rpcSaveDownload(ctx, logger, nk, payload) {
  var uid = requireUser(ctx);
  var obj = readOne(nk, "saves", "main", uid);
  if (!obj) return JSON.stringify({ found: false });
  return JSON.stringify({ found: true, version: obj.version, saved_at: obj.value.saved_at, save: obj.value.save, wallet: walletOf(nk, uid) });
}

// --- Shared towns ---------------------------------------------------------------

function writePublicTown(nk, uid, username, world) {
  var roster = [];
  var chars = world.characters || {};
  for (var cid in chars) {
    roster.push({ id: cid, stars: intOr(chars[cid].stars, 1), xp: Number(chars[cid].character_xp) || 0 });
  }
  writeOne(nk, "town", "public", uid, {
    username: username,
    updated: nowSec(),
    buildings: ((world.town || {}).levels) || {},
    regions: world.unlocked_regions || [],
    roster: roster
  }, undefined, 2);
}

function rpcVisitTown(ctx, logger, nk, payload) {
  requireUser(ctx);
  var p = parsePayload(payload);
  if (!p.user_id) throw wbError("user_id is required");
  var obj = readOne(nk, "town", "public", String(p.user_id));
  if (!obj) throw wbError("That player has not synced a town yet", CODE.NOT_FOUND);
  return JSON.stringify(obj.value);
}
