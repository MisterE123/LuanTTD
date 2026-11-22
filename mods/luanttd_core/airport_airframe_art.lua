-- Native presentation only. Country Airport source movement is always
-- evaluated at its original coordinates and altitude. The same Sampson
-- scale everywhere clears the real two-aircraft taxi/stand envelope.
return {
  bakewell_cotswald = {
    id=219,
    entity="luanttd_core:stock_bakewell_cotswald",
    mesh="bl_bakewell_cotswald.obj",
    flight="bl_bakewell_cotswald_flight.obj",
    atlas="bl_bakewell_cotswald_atlas.png",
    scale=1,
  },
  coleman = {
    id=216,
    entity="luanttd_core:stock_coleman_count",
    mesh="bl_coleman_count.obj",
    flight="bl_coleman_count_flight.obj",
    atlas="bl_coleman_count_atlas.png",
    scale=1,
  },
  sampson = {
    id=215,
    entity="luanttd_core:stock_bayshore_trimotor",
    mesh="bl_bayshore_trimotor.obj",
    atlas="bl_bayshore_trimotor_palette.png",
    scale=.88,
  },
}
