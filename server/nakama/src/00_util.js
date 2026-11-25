// Worldbound Nakama server module. Generated into ../modules/index.js by
// tools/build_server_module.py (which also embeds WB_DATA from data/).
//
// Nakama's JavaScript runtime (goja) needs every registered function to be a
// named top-level function, so the files below only declare functions and
// InitModule (99_init.js) registers them.

var SYSTEM_USER = "00000000-0000-0000-0000-000000000000";
var CODE = { INVALID: 3, NOT_FOUND: 5, EXISTS: 6, DENIED: 7, PRECONDITION: 9, INTERNAL: 13 };

function wbError(message, code) {
  return { message: message, code: code || CODE.INVALID };
}

function nowSec() {
  return Date.now() / 1000.0;
}

function parsePayload(payload) {
  if (!payload || payload === "") return {};
  try {
    var p = JSON.parse(payload);
    if (p === null || typeof p !== "object") throw wbError("Payload must be a JSON object");
    return p;
  } catch (e) {
    if (e && e.code) throw e;
    throw wbError("Payload is not valid JSON");
  }
}

function requireUser(ctx) {
  if (!ctx.userId) throw wbError("Sign in first", CODE.DENIED);
  return ctx.userId;
}

function readOne(nk, collection, key, userId) {
  var res = nk.storageRead([{ collection: collection, key: key, userId: userId }]);
  return res && res.length > 0 ? res[0] : null;
}

function writeOne(nk, collection, key, userId, value, version, permissionRead) {
  var obj = { collection: collection, key: key, userId: userId, value: value,
    permissionRead: permissionRead === undefined ? 1 : permissionRead, permissionWrite: 0 };
  if (version !== undefined && version !== null) obj.version = version;
  return nk.storageWrite([obj])[0];
}

function intOr(v, fallback) {
  var n = parseInt(v, 10);
  return isNaN(n) ? fallback : n;
}

function config(key, fallback) {
  var c = WB_DATA.server;
  var parts = key.split(".");
  for (var i = 0; i < parts.length; i++) {
    if (c === null || typeof c !== "object" || !(parts[i] in c)) return fallback;
    c = c[parts[i]];
  }
  return c;
}

// Pending adjustments the next uploaded save must reflect. Market sales take
// items or gold out ("debit"), purchases and boss rewards put them in
// ("credit"). Each op has a sequence number; the client stores the highest
// sequence it has applied in its save (world.server_ledger_seq) and an
// accepted upload clears only those ops.
function ledgerOp(nk, userId, kind, item, qty) {
  for (var attempt = 0; attempt < 5; attempt++) {
    var obj = readOne(nk, "ledger", "pending", userId);
    var led = obj ? obj.value : { seq: 0, ops: [] };
    led.seq += 1;
    led.ops.push({ seq: led.seq, kind: kind, item: item, qty: qty });
    try {
      writeOne(nk, "ledger", "pending", userId, led, obj ? obj.version : "*", 0);
      return led.seq;
    } catch (e) {
      // Concurrent write: retry with the fresh version.
    }
  }
  throw wbError("Busy, try again", CODE.INTERNAL);
}

function ledgerTotals(led, aboveSeq) {
  var t = { debits: {}, credits: {} };
  var ops = (led && led.ops) || [];
  for (var i = 0; i < ops.length; i++) {
    if (ops[i].seq <= aboveSeq) continue;
    addTo(ops[i].kind === "debit" ? t.debits : t.credits, ops[i].item, ops[i].qty);
  }
  return t;
}

function addTo(map, key, qty) {
  map[key] = (map[key] || 0) + qty;
}
