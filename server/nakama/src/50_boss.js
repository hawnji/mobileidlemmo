// Co-op world boss shared by every player. A player can strike once per
// cooldown; damage comes from the power of their best characters in their
// last synced save (computed here, never sent by the client). When the boss
// falls, everyone who hit it gets rewards by delivery and a new boss spawns.

function bossDefs() {
  return config("world_boss.bosses", []);
}

// Tests start the server with --runtime.env WB_BOSS_HP=<n> to get a boss
// they can defeat quickly. Never set in production. (Read from ctx.env each
// time: Nakama runs RPCs in a pool of JS VMs that do not share globals.)
function newBoss(index, ctx) {
  var defs = bossDefs();
  var d = defs[index % defs.length];
  var override = ctx && ctx.env ? intOr(ctx.env.WB_BOSS_HP, 0) : 0;
  var hp = override > 0 ? override : d.hp;
  return { index: index, id: d.id, name: d.name, max_hp: hp, hp: hp, spawned: nowSec(), hits: {}, rewards: d.rewards };
}

function bossObj(nk, ctx) {
  var obj = readOne(nk, "world_boss", "current", SYSTEM_USER);
  var override = ctx && ctx.env ? intOr(ctx.env.WB_BOSS_HP, 0) : 0;
  if (obj && override > 0 && obj.value.max_hp > override) {
    // Test server started on a database that already has a full-size boss.
    obj.value.max_hp = override;
    obj.value.hp = Math.min(obj.value.hp, override);
    try { writeOne(nk, "world_boss", "current", SYSTEM_USER, obj.value, obj.version, 2); } catch (e) {}
    obj = readOne(nk, "world_boss", "current", SYSTEM_USER);
  }
  if (obj) return obj;
  try {
    writeOne(nk, "world_boss", "current", SYSTEM_USER, newBoss(0, ctx), "*", 2);
  } catch (e) {}
  return readOne(nk, "world_boss", "current", SYSTEM_USER);
}

function bossPublic(nk, ctx) {
  var b = bossObj(nk, ctx).value;
  var top = [];
  for (var u in b.hits) top.push({ user_id: u, name: b.hits[u].name, damage: b.hits[u].damage });
  top.sort(function (a, c) { return c.damage - a.damage; });
  return { id: b.id, name: b.name, hp: b.hp, max_hp: b.max_hp, index: b.index, top: top.slice(0, 10), fighters: top.length };
}

// Damage per strike: sum of the best three characters' character levels and
// stars, scaled, with +-20% variance.
function strikePower(summarySave) {
  var chars = (summarySave.world && summarySave.world.characters) || {};
  var powers = [];
  for (var cid in chars) {
    var xp = Number(chars[cid].character_xp) || 0;
    var lv = 1;
    var table = WB_DATA.character_xp_table;
    for (var i = 0; i < table.length; i++) if (xp >= table[i]) lv = i + 1;
    powers.push(lv * 10 + intOr(chars[cid].stars, 1) * 25);
  }
  powers.sort(function (a, c) { return c - a; });
  var sum = 0;
  for (var j = 0; j < Math.min(3, powers.length); j++) sum += powers[j];
  return Math.max(1, Math.round(sum * (0.8 + Math.random() * 0.4)));
}

function rpcBossStatus(ctx, logger, nk, payload) {
  var uid = requireUser(ctx);
  var pub = bossPublic(nk, ctx);
  var cd = readOne(nk, "world_boss_cd", "last", uid);
  var wait = cd ? Math.max(0, cd.value.at + config("world_boss.cooldown_seconds", 600) - nowSec()) : 0;
  pub.cooldown_remaining = wait;
  return JSON.stringify(pub);
}

function rpcBossAttack(ctx, logger, nk, payload) {
  var uid = requireUser(ctx);
  var cooldown = config("world_boss.cooldown_seconds", 600);
  var cd = readOne(nk, "world_boss_cd", "last", uid);
  if (cd && nowSec() - cd.value.at < cooldown) throw wbError("Your heroes are still recovering", CODE.PRECONDITION);
  var save = readOne(nk, "saves", "main", uid);
  if (!save) throw wbError("Sync your save first", CODE.PRECONDITION);
  var dmg = strikePower(save.value.save);
  for (var attempt = 0; attempt < 8; attempt++) {
    var obj = bossObj(nk, ctx);
    var b = obj.value;
    var dealt = Math.min(dmg, b.hp);
    b.hp -= dealt;
    var h = b.hits[uid] || { name: ctx.username, damage: 0 };
    h.damage += dealt;
    b.hits[uid] = h;
    var defeated = b.hp <= 0;
    var next = defeated ? newBoss(b.index + 1, ctx) : b;
    try {
      writeOne(nk, "world_boss", "current", SYSTEM_USER, next, obj.version, 2);
    } catch (e) {
      continue; // someone else hit it at the same time; retry on fresh state
    }
    writeOne(nk, "world_boss_cd", "last", uid, { at: nowSec() }, undefined, 0);
    if (defeated) {
      for (var u in b.hits) deliver(nk, u, b.rewards, "Defeated " + b.name);
      var gemsEach = config("world_boss.gems_reward", 50);
      for (var u2 in b.hits) nk.walletUpdate(u2, { gems: gemsEach }, { reason: "world_boss", boss: b.id }, true);
    }
    return JSON.stringify({ damage: dealt, defeated: defeated, boss: bossPublic(nk, ctx), cooldown_seconds: cooldown });
  }
  throw wbError("Busy, try again", CODE.INTERNAL);
}
