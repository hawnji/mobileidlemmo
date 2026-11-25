// Server-authoritative recruitment: the same algorithm as
// scripts/recruitment/recruitment_state.gd (the client's offline/dev
// reference), with the RNG, pity counters and history kept on the server.

function rarityRank(r) {
  return WB_DATA.rarity_order.indexOf(r);
}

function findBanner(id) {
  for (var i = 0; i < WB_DATA.banners.length; i++) if (WB_DATA.banners[i].id === id) return WB_DATA.banners[i];
  return null;
}

function rollBase(banner) {
  var r = Math.random();
  var acc = 0, last = "";
  for (var rarity in banner.rates) {
    acc += banner.rates[rarity];
    last = rarity;
    if (r < acc) return rarity;
  }
  return last;
}

function rollRarity(banner, counters) {
  var forced = "";
  var pity = banner.pity || [];
  for (var i = 0; i < pity.length; i++) {
    var tier = pity[i].rarity;
    if ((counters[tier] || 0) + 1 >= pity[i].guaranteed_on_pull) {
      if (forced === "" || rarityRank(tier) > rarityRank(forced)) forced = tier;
    }
  }
  var result = rollBase(banner);
  if (forced !== "" && rarityRank(result) < rarityRank(forced)) result = forced;
  for (var j = 0; j < pity.length; j++) {
    var t = pity[j].rarity;
    counters[t] = rarityRank(result) >= rarityRank(t) ? 0 : (counters[t] || 0) + 1;
  }
  return result;
}

function pickCharacter(banner, rarity) {
  var pool = (WB_DATA.gacha_by_rarity[rarity] || []).slice();
  var f = banner.featured;
  if (f && pool.indexOf(f.character_id) >= 0) {
    if (Math.random() < f.share || pool.length === 1) return f.character_id;
    pool.splice(pool.indexOf(f.character_id), 1);
  }
  if (pool.length === 0) return "";
  return pool[Math.floor(Math.random() * pool.length)];
}

// The cheapest way to pay: a banner token first, otherwise gems (10-pull discount).
function recruitCost(banner, count, wallet) {
  var costs = banner.costs || {};
  for (var cur in costs) {
    if (cur === "gems") continue;
    if ((wallet[cur] || 0) >= costs[cur] * count) {
      var c = {};
      c[cur] = costs[cur] * count;
      return c;
    }
  }
  if (costs.gems !== undefined) {
    var g = costs.gems * count;
    if (count === 10) g = Math.round(g * (banner.ten_pull_discount || 1));
    if ((wallet.gems || 0) >= g) return { gems: g };
  }
  return null;
}

function rpcRecruit(ctx, logger, nk, payload) {
  var uid = requireUser(ctx);
  ensureWallet(nk, uid);
  var p = parsePayload(payload);
  var banner = findBanner(String(p.banner || ""));
  if (!banner) throw wbError("Unknown banner", CODE.NOT_FOUND);
  var count = intOr(p.count, 1);
  if (count !== 1 && count !== 10) throw wbError("Pull 1 or 10");
  var cost = recruitCost(banner, count, walletOf(nk, uid));
  if (!cost) throw wbError("Not enough tokens or gems", CODE.PRECONDITION);
  var neg = {};
  for (var c in cost) neg[c] = -cost[c];
  // walletUpdate fails (and changes nothing) if a balance would go negative.
  nk.walletUpdate(uid, neg, { reason: "recruit", banner: banner.id, count: count }, true);
  var stateObj = readOne(nk, "recruitment", "state", uid);
  var st = stateObj ? stateObj.value : { pity: {}, total: {}, history: [] };
  var counters = st.pity[banner.id] || {};
  var results = [];
  for (var i = 0; i < count; i++) {
    var rarity = rollRarity(banner, counters);
    results.push({ character_id: pickCharacter(banner, rarity), rarity: rarity, banner: banner.id });
  }
  st.pity[banner.id] = counters;
  st.total[banner.id] = (st.total[banner.id] || 0) + count;
  st.history = results.concat(st.history).slice(0, 100);
  writeOne(nk, "recruitment", "state", uid, st, undefined, 1);
  var gObj = readOne(nk, "profile", "granted", uid);
  var ids = gObj ? gObj.value.ids : [];
  for (var k = 0; k < results.length; k++) if (results[k].character_id && ids.indexOf(results[k].character_id) < 0) ids.push(results[k].character_id);
  writeOne(nk, "profile", "granted", uid, { ids: ids }, undefined, 1);
  return JSON.stringify({ results: results, cost: cost, wallet: walletOf(nk, uid), pity: counters, total: st.total[banner.id] });
}

function rpcRecruitState(ctx, logger, nk, payload) {
  var uid = requireUser(ctx);
  var stateObj = readOne(nk, "recruitment", "state", uid);
  return JSON.stringify(stateObj ? stateObj.value : { pity: {}, total: {}, history: [] });
}
