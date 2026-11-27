-- An ordinary generated Temperate world. All water, rocks and catchment
-- houses predate the test; only the normal priced company commands build.
local player_name="StockResidentialQA"
local begin
function begin()
  local player=core.get_player_by_name(player_name)
  if not (player and authority and authority.status()=="owned" and #world.hotbar_layout(player)>0) then
    core.after(.25,begin);return
  end
  -- Both docks and this west-of-Medinghead skerry come from the
  -- settled seed; the pregame tide leaves a different natural coast
  -- than the earlier un-settled map fixture did.
  local land_a,land_b,from,to=53956,61119,53954,61121
  local original_rocks={59842,60098,60354}
  local Track=dofile(mod.."/openttd/rail_track.lua")
  local Water=dofile(mod.."/openttd/ship_follow.lua")(Track)
  local Terrain=dofile(mod.."/openttd/terrain.lua")
  local Net=dofile(mod.."/ship_network.lua")(Sim,Terrain,Water,dofile(mod.."/openttd/ship_facilities.lua")(Track,Water))
  local Yapf=dofile(mod.."/openttd/ship_yapf.lua")(Track,Water,dofile(mod.."/openttd/yapf_road_search.lua"))
  local function inspect(s)
    assert(s.seed==1751 and s.corner_grid.width==256)
    local board=Net.board(s)
    for _,id in ipairs(original_rocks) do
      assert(s.tiles[id].stock_water_rocks and Water.at(board,id)==0,"Natural skerry is missing or navigable: "..id)
    end
    return board
  end
  local s=assert(OwnerCheckpoint.read())
  local board=inspect(s)
  local camera=original_rocks[2]
  local x,z=Sim.xy(camera)
  -- Look across the actual offshore lane toward the skerry and towns.
  player:set_pos({x=2*x-18,y=7,z=2*z-4})
  player:set_look_horizontal(math.atan2(-15,9));player:set_look_vertical(.38)
  local function ask(req,cb)
    req.player=player_name
    assert(authority.query(req,function(r)
      assert(r.ok,req.kind..": "..tostring(r.why));cb(r)
    end))
  end
  local function action(req,cb)
    ask({kind="transport_quote",request=req},function(q)
      assert(q.value.cost>0)
      ask({kind="command",command={kind="transport_commit",token=q.value.token,revision=q.revision}},cb)
    end)
  end
  local probe={ocean_speed_frac=0,canal_speed_frac=0}
  local clear=setmetatable({tile=function(id)
    local t=board.tile(id)
    if t and t.rocks then t.rocks=nil;t.is_water_tile=t.kind=="sea" end
    return t
  end},{__index=board})
  local function trace(b)
    local dest=Yapf.destination(b,probe,{kind="tile",tile=to})
    local found,goal=Yapf.find(b,probe,from,Water.at(b,from),dest)
    assert(found)
    return Yapf.trace(b,probe,dest,goal),goal.cost
  end
  local dry,short=trace(clear)
  local _,long=trace(board)
  assert(short==2913 and long==3197,"Unexpected reference path costs")
  local inlet={}
  for _,id in ipairs(original_rocks) do inlet[id]=true end
  local hits=0
  for _,step in ipairs(dry) do if inlet[step.tile] then hits=hits+1 end end
  assert(hits==#original_rocks,"No meaningful alternative route blocked by rocks")
  local reopened=core.settings:get_bool("luanttd_qa_rocky_ferry_reopen",false)
  local saved=reopened and assert(core.deserialize(storage:get_string("rocky_coast_ferry_qa"),true))
  local function watch(left,visual)
    local state=assert(OwnerCheckpoint.read())
    local p=state.ship_pilot
    local company=state.companies[player_name]
    if p then
      assert(not p.failure and p.phase~="blocked",p.failure)
      assert(not inlet[p.vehicle.tile],"Ferry entered a natural skerry")
      for _,step in ipairs(p.vehicle.path or {}) do
        assert(not state.tiles[step.tile].stock_water_rocks,"Live route entered a natural skerry")
      end
    end
    if not visual then
      for _,ref in ipairs(core.get_objects_inside_radius({x=2*x,y=1,z=2*z},45)) do
        local e=ref:get_luaentity()
        local pos=ref:get_pos()
        if e and e.name=="luanttd_core:stock_ffp_passenger_ferry" and pos and
          math.abs(pos.x-2*x)<16 and math.abs(pos.z-2*z)<9 then
          assert(ref:get_properties().mesh=="bl_ffp_passenger_ferry.obj")
          visual=true
          if not reopened then core.log("action","NATIVE ROCKY FERRY FRAME") end
        end
      end
    end
    local paid=company and (company.paid_units or 0)
    if p and visual and paid and paid>(saved and saved.paid or 0) and p.arrivals>=(saved and saved.arrivals+1 or 2) then
      assert(state.stock_owned_ferry.engine_id==207 and p.owned and company.revenue>0)
      inspect(state)
      if not reopened then storage:set_string("rocky_coast_ferry_qa",core.serialize({paid=paid,arrivals=p.arrivals})) end
      core.log("action",("PASS NATIVE ROCKY FERRY %s: alternative path %d -> %d, %d paid passengers, $%d")
        :format(reopened and "REOPEN" or "SERVICE",short,long,paid,company.revenue))
      return
    end
    assert(left>0,("No paid ferries passed the skerry, visual=%s visits=%s paid=%s"):format(tostring(visual),p and p.arrivals or "-",paid or "-"))
    core.after(.35,function()watch(left-1,visual)end)
  end
  if reopened then
    assert(s.ship_pilot and s.ship_pilot.arrivals>=saved.arrivals)
    watch(330,false)
    return
  end
  local dep,axis
  local u,v=Sim.xy(from)
  for j=v-3,v+3 do
    for i=u-3,u+3 do
      local id=Sim.id(i,j)
      for direction=0,1 do
        local d=Net.quote(s,player_name,"depot",id,direction)
        if d and not s.tiles[d.tiles[1]].stock_water_rocks and not s.tiles[d.tiles[2]].stock_water_rocks then
          local safe=true
          for _,tile in ipairs(d.tiles) do
            if tile==from or Sim.distance(tile,land_a)<3 then safe=false end
          end
          if safe then dep,axis=id,direction;break end
        end
      end
      if dep then break end
    end
    if dep then break end
  end
  assert(dep,"No ship depot placement near the first dock")
  action({mode="ship",operation="build",kind="dock",tile=land_a},function(a)
    action({mode="ship",operation="build",kind="dock",tile=land_b},function(b)
      action({mode="ship",operation="build",kind="depot",tile=dep,axis=axis},function(d)
        action({mode="ship",operation="buy",depot=d.value.id,engine=207},function(owned)
          assert(owned.value.id=="ferry")
          ask({kind="command",command={kind="transport_start",mode="ship",vehicle="ferry",depot=d.value.id,
            first=a.value.id,second=b.value.id,revision=owned.revision}},function() watch(330,false) end)
        end)
      end)
    end)
  end)
end
core.after(.25,begin)
