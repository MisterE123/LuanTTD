-- Appended to the real game only for the isolated native client test.
local qa_early
core.register_on_joinplayer(function(p)
  local name=p:get_player_name()
  if qa_early then return end
  qa_early=true
  local function tile(x,z)return Sim.id(x,z) end
  local T=dofile(mod.."/openttd/terrain.lua")
  local g=S.corner_grid
  for z=1,g.depth+1 do for x=1,g.width+1 do
    g.levels[(z-1)*(g.width+1)+x]=(x==17) and 2 or 3
  end end
  for z=7,26 do for x=7,27 do
    local id=tile(x,z)
    local _,base=T.tile(g,x,z)
    S.tiles[id]={h=base,terrain=(x==16 or x==17) and "water" or "grass",variant=(x+z)%4}
  end end
  local style=tonumber(core.settings:get("luanttd_qa_bridge_style")) or 9
  local suspension=style==3 or style==4 or style==5
  local west,east,zr,zl=15,suspension and 21 or 18,13,19
  Sim.company(S,name).cash=80000
  local roads=assert(({Sim.road_bridge(S,name,tile(west,zr),tile(east,zr),style)})[3])
  local W=assert(api.rail_spans)
  local q=assert(W.quote_bridge(S,name,tile(west,zl),tile(east,zl),0,nil,style))
  local ok,why,rails=W.commit(S,name,q)
  assert(ok,why)
  local function at(x,z,y)return {x=2*x,y=y,z=2*z} end
  local function paint()
    render.raise_bound(q.deck)
    render.update(roads)
    render.update(rails)
    local function mesh_found(x,z,family,geometry)
      local key=family.."_span_0"..(geometry or "")
      local expect="luanttd_core:stock_"..key
      local node=core.get_node(at(x,z,q.deck))
      assert(node.name==expect,expect.." != "..node.name)
      local def=assert(core.registered_nodes[expect])
      local expected_geometry=style==5 and key:gsub("_steel_yellow_","_steel_") or key
      assert(def.drawtype=="mesh" and def.mesh=="bl_"..expected_geometry..".obj")
      local expected_atlas="bl_"..family..".png"
      local tx=def.tiles[1]
      assert((type(tx)=="table" and tx.name or tx)==expected_atlas)
    end
    if suspension then
      local variant=({[3]="concrete",[4]="steel",[5]="steel_yellow"})[style]
      for mode,z in pairs({road=zr,rail=zl}) do
        for at,section in pairs({[16]="plus",[18]="clear",[20]="minus"}) do
          mesh_found(at,z,mode.."_bridge_suspension_"..variant,"_"..section)
        end
      end
    else
      mesh_found(16,zr,"road_bridge_fast_girder")
      mesh_found(16,zl,"rail_bridge_fast_girder")
    end
    core.set_timeofday(.26)
    local player=assert(core.get_player_by_name(name))
    player:set_physics_override({gravity=0})
    player:override_day_night_ratio(.95)
    player:set_pos({x=21,y=q.deck+7,z=31})
    player:set_look_horizontal(-1.55)
    player:set_look_vertical(.49)
    core.log("action","FAST_GIRDER_NATIVE_SCENE_READY")
  end
  core.emerge_area(at(8,8,-1),at(26,25,9),function(_,action,left)
    assert(action~=core.EMERGE_CANCELLED and action~=core.EMERGE_ERRORED)
    if left==0 then core.after(0,paint) end
  end)
end)
