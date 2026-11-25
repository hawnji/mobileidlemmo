// Global world events (server clock, data-driven) and region presence.

function activeEvents() {
  var out = [];
  var now = nowSec();
  var evs = config("world_events", []);
  for (var i = 0; i < evs.length; i++) {
    var e = evs[i];
    // Repeating events: active for `duration` seconds out of every `period`.
    var phase = ((now - e.epoch) % e.period + e.period) % e.period;
    if (phase < e.duration) out.push({ id: e.id, name: e.name, description: e.description, effects: e.effects, ends_at: now - phase + e.duration });
  }
  return out;
}

function rpcWorldEvents(ctx, logger, nk, payload) {
  return JSON.stringify({ server_time: nowSec(), events: activeEvents() });
}

// One authoritative match per region relays where other players' heroes are.
// Clients send OP_POS {x, y, sprite, name} about once a second; the match
// broadcasts OP_STATE with every presence's last position once a second.
var OP_POS = 1, OP_STATE = 2;

function rpcRegionMatch(ctx, logger, nk, payload) {
  requireUser(ctx);
  var p = parsePayload(payload);
  var region = String(p.region || "");
  if (WB_DATA.regions.indexOf(region) < 0) throw wbError("Unknown region");
  // One live match per region. The match id is kept in system storage
  // because matchList's label index updates asynchronously, so two players
  // arriving together would otherwise each create their own match.
  var max = config("presence.max_per_match", 100);
  for (var attempt = 0; attempt < 4; attempt++) {
    var rec = readOne(nk, "presence", region, SYSTEM_USER);
    if (rec && rec.value.match_id) {
      var m = null;
      try { m = nk.matchGet(rec.value.match_id); } catch (e) { m = null; }
      if (m && m.size < max) return JSON.stringify({ match_id: rec.value.match_id });
    }
    var id = nk.matchCreate("region_presence", { region: region });
    try {
      writeOne(nk, "presence", region, SYSTEM_USER, { match_id: id }, rec ? rec.version : "*", 0);
      return JSON.stringify({ match_id: id });
    } catch (e) {
      // Another player registered a match first; the unused one closes
      // itself after its empty timeout. Read again and join theirs.
    }
  }
  throw wbError("Region is busy, try again");
}

function regionMatchInit(ctx, logger, nk, params) {
  return { state: { region: params.region, players: {}, empty_ticks: 0 }, tickRate: 1, label: "region:" + params.region };
}

function regionMatchJoinAttempt(ctx, logger, nk, dispatcher, tick, state, presence, metadata) {
  return { state: state, accept: Object.keys(state.players).length < config("presence.max_per_match", 100) };
}

function regionMatchJoin(ctx, logger, nk, dispatcher, tick, state, presences) {
  for (var i = 0; i < presences.length; i++) {
    state.players[presences[i].userId] = { name: presences[i].username, x: -1, y: -1, sprite: "", heroes: [] };
  }
  return { state: state };
}

function regionMatchLeave(ctx, logger, nk, dispatcher, tick, state, presences) {
  for (var i = 0; i < presences.length; i++) delete state.players[presences[i].userId];
  return { state: state };
}

function regionMatchLoop(ctx, logger, nk, dispatcher, tick, state, messages) {
  for (var i = 0; i < messages.length; i++) {
    var m = messages[i];
    if (m.opCode !== OP_POS || !state.players[m.sender.userId]) continue;
    try {
      var d = JSON.parse(nk.binaryToString(m.data));
      var heroes = [];
      var src = d.heroes || [];
      for (var j = 0; j < Math.min(src.length, 12); j++) {
        heroes.push({ id: String(src[j].id).slice(0, 40), x: intOr(src[j].x, -1), y: intOr(src[j].y, -1) });
      }
      state.players[m.sender.userId].heroes = heroes;
    } catch (e) {}
  }
  if (Object.keys(state.players).length === 0) {
    state.empty_ticks += 1;
    if (state.empty_ticks > config("presence.empty_seconds_before_close", 60)) return null;
  } else {
    state.empty_ticks = 0;
    dispatcher.broadcastMessage(OP_STATE, JSON.stringify({ region: state.region, players: state.players }), null, null, true);
  }
  return { state: state };
}

function regionMatchTerminate(ctx, logger, nk, dispatcher, tick, state, graceSeconds) {
  return { state: state };
}

function regionMatchSignal(ctx, logger, nk, dispatcher, tick, state, data) {
  return { state: state, data: data };
}
