# Temperate farm-to-factory road workbench

Set `bayline_scenario = farm` before creating a new 1751
campaign, then enter **Freight Roadworks**. Buy trucks in your depot
and add actual station orders directly in the 3D world.

## Verified native region, seed 1751

Enable only the separately named Farm workbench on a fresh 1751
campaign. Do not mount a separate Sawmill Goods handler in the same
world. Coal can coexist: the same untouched seed and original inland
Eastbank mine/Riverbend plant were used during proof. Optional
designer investments and all legacy business production stay separate.

* Highfield Farm: (12,1), stock layout 0 (three by three, 9 occupied
  cells), IndustryID 8192. Truck stop (13,4), immediately adjacent to
  the southern rest of the farm. Both Grain and Livestock actually
  originate there. Three-pitch artwork offset keys are the original
  local cell offsets, not the cell graphics IDs.
* Westfield Factory: (15,16), stock layout 0 (12 actual cells, four
  gaps), IndustryID 8193. East loading apron (18,17), truck stop
  (19,17). Both Farm cargoes accepted; this same stop is the source
  for proper processed Goods, not itself a Goods destination.
* Town Goods: (14,8), 9 acceptance eighths from original HouseIDs
  (3 Port Alder, 6 Mason Quay); town receiver is the station's
  associated municipality as in the source. Road depot (11,12).
* Build these four ordinary directed-compatible street chunks; no
  special U-turns at the through stops:

  1. (11,4) → (16,4) → (16,7) → (15,7) → (15,8) → (12,8) →
     (12,14) → (13,14) → (13,15) → (19,15) → (19,20)
  2. (11,4) → (11,5) → (16,5)
  3. (15,8) → (15,12) → (12,12)
  4. (19,15) → (20,15) → (20,20) → (19,20)

  The source road planner returns ordinary repeated Farm↔Factory
  469/530 frames and Factory↔Goods 401/308 frames using the previous
  arrival's actual face. Some adjacent woods/field overlays are
  converted by explicit road work; no roads are installed on seed.

## Factory/field world

The factory function takes Sim, Terrain, FarmFactoryRules, Fields and
Catchment. Register W.facilities in Sim before running its world; their
legacy production and acceptance maps are intentionally empty.
W.default_1751(s,random_u32) needs source Houses already stamped and
the existing globally shared RNG, not a new per-farm random stream.
It preflights both valid physical footprints/catchments, stale
quotes, protected cells and future IDs before touching or drawing;
preserves original houses, terrain heights, roads, water and other
industries; commits genuine terrain field planting after placement.
Host IDs 8192/8193 are allocated via the farm IndustryID band.
W.record(s,id) yields exact stock footprint metadata, chain=farm;
style=industry_farm or industry_factory; mesh bl_<style>_<x>_<z>.obj,
atlas bl_<style>_atlas.png. Four unoccupied factory corner cells
remain ordinary land. W.field(s,id) exposes only a current visible
field; an overlaid road/structure or altered surface slope immediately
masks the field. W.field_board(s) adapts the real power-of-two planting
board to the finite campaign, without clipping targets onto edge
businesses, buildings or rail reservations.

Fields are saved separately in S.stock_farm_fields by host tile ID:
variant 0–8 (stock clear-field look), counter 0–7, producing industry,
terrain grade/slope, fences keyed 0=west, 1=south, 2=east, 3=north.
Original terrain revisits update missing perimeter fences to type 3,
increase crop stage once every 8 visits, and turn an orphaned late-stage
field to grass. Duplicate field tick effects are rejected. No field
can affect production rate by itself.

## Road mounting

Instantiate road_farm_service.lua with Sim, FarmFactoryRules, its
adapter, Packets, Income, Rating and Station. Call R.bind(s,options)
with field_board=W.field_board(s); options.random_u32 optionally
overrides Station.random_u32, but must remain the common world stream.
Raw slots, clock and producer state live in S.stock_farm_industries,
S.farm_transactions and actual per-station stock_farm queues.
The one canonical Goods handler is selected at workbench mount.

R.supported_vehicle maps grain_truck→grain, livestock_van→livestock,
goods_truck→goods; no legacy cargo prototype is recognized.
B.report(st,cargo[,tick]) returns producer IDs, eighths, accepts
and near stock processor IDs. B.display_waiting includes physically
reserved cargo; B.timing(v) returns the original load slice/cargo age.
Hook B.tile_visit into the one common cursor and B.after_vehicle_tick
after the real station/vehicle phase; don't add a daily producer.
B.step_rating(st[,waiting_changed]) visits stock CargoIDs 4,5,6 and
hands back whether any waiting queue changed. B.month delegates actual
production history and removal decisions.

B.ops(tick,emit) wraps the existing road execution and produces normal
board/fare events. Call pickup/drop with the actual occupied stop
frame; rebuilding a station-label position is not a fallback for these
shipments. B.ops.station_done(st) fires once after the whole actual
station scan; multiple trucks/cargoes can stage input in the same
scan. The warehouse updates company fares only through the stock
packet loader, exact Factory receipts when the scan finishes, and
final Goods town receipts when accepted. It does not pay at conversion.

tests/road_farm_service.lua proves fixed-site safety, exact stock
footprints, untouched original houses/coal, 178 planted source fields,
source field aging/replay, all directional road paths on untouched
terrain, and real stock vehicle loading with actual stop frames:
20 Grain/$218, 14 Livestock/$135, 14 Goods/$145. The service fixture
uses route frame duration, not renderer-driven moving vehicles; the
integrated native runs use the actual road controller.
