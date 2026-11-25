function InitModule(ctx, logger, nk, initializer) {
  if (ctx.env && ctx.env.WB_BOSS_HP) logger.warn("World boss HP override active: %s (test setting)", ctx.env.WB_BOSS_HP);
  initializer.registerRpc("wb_bootstrap", rpcBootstrap);
  initializer.registerRpc("wb_save_upload", rpcSaveUpload);
  initializer.registerRpc("wb_save_download", rpcSaveDownload);
  initializer.registerRpc("wb_visit_town", rpcVisitTown);
  initializer.registerRpc("wb_recruit", rpcRecruit);
  initializer.registerRpc("wb_recruit_state", rpcRecruitState);
  initializer.registerRpc("wb_market_list", rpcMarketList);
  initializer.registerRpc("wb_market_browse", rpcMarketBrowse);
  initializer.registerRpc("wb_market_buy", rpcMarketBuy);
  initializer.registerRpc("wb_market_cancel", rpcMarketCancel);
  initializer.registerRpc("wb_claim_deliveries", rpcClaimDeliveries);
  initializer.registerRpc("wb_guild_info", rpcGuildInfo);
  initializer.registerRpc("wb_guild_donate", rpcGuildDonate);
  initializer.registerRpc("wb_boss_status", rpcBossStatus);
  initializer.registerRpc("wb_boss_attack", rpcBossAttack);
  initializer.registerRpc("wb_world_events", rpcWorldEvents);
  initializer.registerRpc("wb_region_match", rpcRegionMatch);
  initializer.registerMatch("region_presence", {
    matchInit: regionMatchInit,
    matchJoinAttempt: regionMatchJoinAttempt,
    matchJoin: regionMatchJoin,
    matchLeave: regionMatchLeave,
    matchLoop: regionMatchLoop,
    matchTerminate: regionMatchTerminate,
    matchSignal: regionMatchSignal
  });
  logger.info("Worldbound server module %s loaded (%d banners, %d items)", WB_DATA.version, WB_DATA.banners.length, Object.keys(WB_DATA.items).length);
}
