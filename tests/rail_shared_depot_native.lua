-- Actual installation fixture only. Two passengers share a depot,
-- save with one train still inside, then both depart and earn.
local Rail=assert(api.rail_dispatch_controller)
local StockTrack=dofile(mod.."/openttd/rail_track.lua")
local StockSignal=dofile(mod.."/openttd/rail_signals.lua")(StockTrack)
local Own=assert(api.rail_owned)
core.after(0,function()
  local proof=S.rail_shared_depot_native
  if not proof then
    local g=assert(S.corner_grid)
    for i=1,#g.levels do g.levels[i]=0 end
    for i in ipairs(S.tiles) do S.tiles[i]={terrain="grass",h=0,variant=1} end
    proof=dofile(mod.."/qa_rail_shared_depot.lua")(Sim,S,api.trackworks,Own,Rail,StockTrack,StockSignal)
    for _=1,40 do
      Sim.daily(S)
      local d=assert(Rail.current(S))
      assert(not d.failure,d.failure)
      if not d.runs[1].consist.parts[1].hidden and d.runs[2].consist.parts[1].hidden then
        S.rail_shared_depot_native=proof
        api.save()
        core.log("action","SHARED_DEPOT_NATIVE_SAVED_ONE_WAITING")
        core.request_shutdown("Saved with second train still in the depot",false,0)
        return
      end
    end
    error("No state with one released and one held")
  end
  local d=assert(Rail.current(S))
  assert(not d.runs[1].consist.parts[1].hidden and d.runs[2].consist.parts[1].hidden)
  assert(d.life.trains[2].parts[1].in_depot)
  for _=1,150 do
    Sim.daily(S)
    assert(not d.failure,d.failure)
    local a,b=Sim.rail_paid_status(S,proof.a),Sim.rail_paid_status(S,proof.b)
    if a.fare>0 and b.fare>0 then
      assert(not d.runs[2].consist.parts[1].hidden and not d.life.claims[proof.depot])
      assert(S.companies[proof.owner].revenue==a.fare+b.fare)
      core.log("action",("SHARED_DEPOT_NATIVE_PASS one depot, two departures after SQLite restore, two paid trips $%d/$%d"):format(a.fare,b.fare))
      core.request_shutdown("Stock shared depot passed",false,0)
      return
    end
  end
  error("Shared depot trains failed to earn")
end)
