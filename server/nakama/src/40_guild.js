// Guilds are Nakama groups (create, join, members, group chat are built in).
// The module adds guild progression: members donate gold (recorded as a
// ledger debit), the guild levels up, and each level gives every member an
// account-wide bonus the client applies (see WB_DATA.server.guild.perks).

function guildOf(nk, uid) {
  var res = nk.userGroupsList(uid, 10, null, "");
  var gs = (res && res.userGroups) || [];
  for (var i = 0; i < gs.length; i++) {
    // state: 0 superadmin, 1 admin, 2 member, 3 join request
    if (gs[i].state <= 2) return gs[i].group;
  }
  return null;
}

function guildLevel(xp) {
  var levels = config("guild.level_xp", [0, 5000, 20000, 60000, 150000]);
  var lv = 1;
  for (var i = 0; i < levels.length; i++) if (xp >= levels[i]) lv = i + 1;
  return lv;
}

function guildState(nk, groupId) {
  var obj = readOne(nk, "guild", groupId, SYSTEM_USER);
  var v = obj ? obj.value : { xp: 0, donations: {} };
  var lv = guildLevel(v.xp);
  var perks = config("guild.perks", {});
  return { group_id: groupId, xp: v.xp, level: lv, donations: v.donations, perks: perks[String(lv)] || {}, version: obj ? obj.version : "*" };
}

function rpcGuildInfo(ctx, logger, nk, payload) {
  var uid = requireUser(ctx);
  var g = guildOf(nk, uid);
  if (!g) return JSON.stringify({ in_guild: false });
  var st = guildState(nk, g.id);
  delete st.version;
  st.in_guild = true;
  st.name = g.name;
  return JSON.stringify(st);
}

function rpcGuildDonate(ctx, logger, nk, payload) {
  var uid = requireUser(ctx);
  var p = parsePayload(payload);
  var gold = intOr(p.gold, 0);
  if (gold <= 0) throw wbError("Donate a positive amount of gold");
  var g = guildOf(nk, uid);
  if (!g) throw wbError("Join a guild first", CODE.PRECONDITION);
  var save = readOne(nk, "saves", "main", uid);
  if (!save) throw wbError("Sync your save first", CODE.PRECONDITION);
  var led = readOne(nk, "ledger", "pending", uid);
  var t = ledgerTotals(led ? led.value : null, -1);
  if (save.value.summary.gold - (t.debits.gold || 0) + (t.credits.gold || 0) < gold) throw wbError("Not enough gold (as of your last sync)", CODE.PRECONDITION);
  var seq = ledgerOp(nk, uid, "debit", "gold", gold);
  for (var attempt = 0; attempt < 5; attempt++) {
    var st = guildState(nk, g.id);
    st.donations[uid] = (st.donations[uid] || 0) + gold;
    try {
      writeOne(nk, "guild", g.id, SYSTEM_USER, { xp: st.xp + gold, donations: st.donations }, st.version, 2);
      var after = guildState(nk, g.id);
      delete after.version;
      after.ledger_seq = seq;
      return JSON.stringify(after);
    } catch (e) {}
  }
  throw wbError("Busy, try again", CODE.INTERNAL);
}
