// Player marketplace with escrow, plus direct trades between players
// (a listing reserved for one buyer). Gold is the currency; a fee is a gold
// sink. Items leave the seller when listed (ledger debit) and reach the
// buyer as a delivery that the client claims (ledger credit).

var MARKET = "market";

function tradeable(itemId) {
  var it = WB_DATA.items[itemId];
  return !!it && !it.untradeable;
}

function rpcMarketList(ctx, logger, nk, payload) {
  var uid = requireUser(ctx);
  var p = parsePayload(payload);
  var item = String(p.item || ""), qty = intOr(p.qty, 0), price = intOr(p.price, 0);
  if (!tradeable(item)) throw wbError("This item cannot be traded");
  if (qty <= 0 || qty > 100000) throw wbError("Quantity must be 1 to 100000");
  if (price <= 0 || price > 1000000000) throw wbError("Price must be positive");
  var save = readOne(nk, "saves", "main", uid);
  if (!save) throw wbError("Sync your save before trading", CODE.PRECONDITION);
  // The last synced save plus pending ops must still hold the items.
  var led = readOne(nk, "ledger", "pending", uid);
  var t = ledgerTotals(led ? led.value : null, -1);
  var have = (save.value.summary.items[item] || 0) - (t.debits[item] || 0) + (t.credits[item] || 0);
  if (have < qty) throw wbError("You only have " + have + " " + item + " (as of your last sync)", CODE.PRECONDITION);
  var mine = nk.storageList(uid, MARKET, 100, "");
  if (((mine && mine.objects) || []).length >= config("market.max_listings", 20)) throw wbError("Too many active listings", CODE.PRECONDITION);
  var id = nk.uuidv4();
  var seq = ledgerOp(nk, uid, "debit", item, qty);
  var listing = { id: id, seller: uid, seller_name: ctx.username, item: item, qty: qty, price: price,
    buyer: p.buyer ? String(p.buyer) : "", created: nowSec() };
  // Listings are owned by the seller and publicly readable, so browsing is a
  // plain storage list over the collection.
  writeOne(nk, MARKET, id, uid, listing, "*", 2);
  writeOne(nk, "market_index", id, SYSTEM_USER, { seller: uid, item: item, buyer: listing.buyer }, "*", 2);
  return JSON.stringify({ listing: listing, ledger_seq: seq });
}

function rpcMarketBrowse(ctx, logger, nk, payload) {
  var uid = requireUser(ctx);
  var p = parsePayload(payload);
  var out = [];
  var cursor = "";
  for (var page = 0; page < 10; page++) {
    var res = nk.storageList(SYSTEM_USER, "market_index", 100, cursor);
    var objs = (res && res.objects) || [];
    for (var i = 0; i < objs.length; i++) {
      var ix = objs[i].value;
      if (p.item && ix.item !== p.item) continue;
      if (ix.buyer && ix.buyer !== uid && ix.seller !== uid) continue;
      var l = readOne(nk, MARKET, objs[i].key, ix.seller);
      if (l) out.push(l.value);
    }
    cursor = res ? res.cursor : "";
    if (!cursor) break;
  }
  out.sort(function (a, b) { return a.price / a.qty - b.price / b.qty; });
  return JSON.stringify({ listings: out.slice(0, 100) });
}

function deliver(nk, userId, items, reason) {
  var id = nk.uuidv4();
  writeOne(nk, "deliveries", id, userId, { id: id, items: items, reason: reason, at: nowSec() }, "*", 1);
}

function rpcMarketBuy(ctx, logger, nk, payload) {
  var uid = requireUser(ctx);
  var p = parsePayload(payload);
  var ix = readOne(nk, "market_index", String(p.listing_id || ""), SYSTEM_USER);
  if (!ix) throw wbError("That listing is gone", CODE.NOT_FOUND);
  var lObj = readOne(nk, MARKET, ix.key, ix.value.seller);
  if (!lObj) throw wbError("That listing is gone", CODE.NOT_FOUND);
  var l = lObj.value;
  if (l.seller === uid) throw wbError("You cannot buy your own listing");
  if (l.buyer && l.buyer !== uid) throw wbError("This trade is reserved for another player", CODE.DENIED);
  var save = readOne(nk, "saves", "main", uid);
  if (!save) throw wbError("Sync your save before trading", CODE.PRECONDITION);
  var led = readOne(nk, "ledger", "pending", uid);
  var t = ledgerTotals(led ? led.value : null, -1);
  var gold = save.value.summary.gold - (t.debits.gold || 0) + (t.credits.gold || 0);
  if (gold < l.price) throw wbError("Not enough gold (as of your last sync)", CODE.PRECONDITION);
  // Remove the listing first: of two buyers racing, only one delete succeeds.
  try {
    nk.storageDelete([{ collection: "market_index", key: ix.key, userId: SYSTEM_USER, version: ix.version }]);
  } catch (e) {
    throw wbError("That listing was just sold or withdrawn", CODE.NOT_FOUND);
  }
  nk.storageDelete([{ collection: MARKET, key: lObj.key, userId: l.seller }]);
  var seq = ledgerOp(nk, uid, "debit", "gold", l.price);
  var fee = Math.floor(l.price * config("market.fee", 0.05));
  var items = {};
  items[l.item] = l.qty;
  deliver(nk, uid, items, "Bought from " + l.seller_name);
  deliver(nk, l.seller, { gold: l.price - fee }, "Sold " + l.qty + " " + l.item);
  return JSON.stringify({ bought: l, ledger_seq: seq, fee: fee });
}

function rpcMarketCancel(ctx, logger, nk, payload) {
  var uid = requireUser(ctx);
  var p = parsePayload(payload);
  var lObj = readOne(nk, MARKET, String(p.listing_id || ""), uid);
  if (!lObj) throw wbError("That listing is gone", CODE.NOT_FOUND);
  var ix = readOne(nk, "market_index", lObj.key, SYSTEM_USER);
  if (!ix) throw wbError("That listing is gone", CODE.NOT_FOUND);
  try {
    nk.storageDelete([{ collection: "market_index", key: ix.key, userId: SYSTEM_USER, version: ix.version }]);
  } catch (e) {
    throw wbError("That listing was just sold or withdrawn", CODE.NOT_FOUND);
  }
  nk.storageDelete([{ collection: MARKET, key: lObj.key, userId: uid }]);
  var items = {};
  items[lObj.value.item] = lObj.value.qty;
  deliver(nk, uid, items, "Listing cancelled");
  return JSON.stringify({ cancelled: lObj.value.id });
}

function countDeliveries(nk, uid) {
  var res = nk.storageList(uid, "deliveries", 100, "");
  return ((res && res.objects) || []).length;
}

// Hands every pending delivery to the client and records them as credits.
function rpcClaimDeliveries(ctx, logger, nk, payload) {
  var uid = requireUser(ctx);
  var res = nk.storageList(uid, "deliveries", 100, "");
  var objs = (res && res.objects) || [];
  var items = {}, notes = [], seq = 0;
  for (var i = 0; i < objs.length; i++) {
    // Deleting with the read version makes a double claim fail.
    try {
      nk.storageDelete([{ collection: "deliveries", key: objs[i].key, userId: uid, version: objs[i].version }]);
    } catch (e) {
      continue;
    }
    for (var it in objs[i].value.items) {
      addTo(items, it, objs[i].value.items[it]);
      seq = ledgerOp(nk, uid, "credit", it, objs[i].value.items[it]);
    }
    notes.push(objs[i].value.reason);
  }
  return JSON.stringify({ items: items, notes: notes, ledger_seq: seq });
}
