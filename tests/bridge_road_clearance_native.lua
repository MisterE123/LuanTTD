-- Appended to a disposable exact game's init by the native fixture.
local terrain_mod=dofile(mod.."/openttd/terrain.lua")
local profile_grid=S.corner_grid
local heights,dirty={},{}

-- Four production builds across a channel cut into high ground. Top 3 and
-- base 2 under the first middle support: deck 4 leaves no intermediate
-- pier module (only the posts hanging from the span itself).
local function at(x,z)return assert(Sim.id(x,z))end
local function distance_to_rows(z,a,b)return math.max(0,a-z,z-b)end
for z=1,Sim.H+1 do for x=1,Sim.W+1 do
  local h=math.min(3,math.max(0,3-math.min(x-21,32-x)))
  -- The stock concrete and girder have much shorter maximum spans.
  local concrete=(x==22 and 2 or 3)-distance_to_rows(z,25,27)
  local girder=({[22]=2,[23]=1,[24]=2})[x] or 3
  -- Four corners under a girder pier read [2,1,3,2].
  if z>=34 and (x==22 or x==23) then girder=girder+1 end
  girder=girder-distance_to_rows(z,32,34)
  heights[(z-1)*(Sim.W+1)+x]=math.max(h,concrete,girder)
end end
for idx,h in pairs(heights) do profile_grid.levels[idx]=h end
for z=1,Sim.H do for x=1,Sim.W do
  local id=at(x,z)
  local _,base,top=terrain_mod.tile(profile_grid,x,z)
  S.tiles[id]={terrain=base==0 and top==0 and "water" or "grass",variant=(x+z)%4,h=base}
  if x>=16 and x<=36 and z>=15 and z<=46 then dirty[#dirty+1]=id end
end end
S.speed=0
local owner="PierQA"
local reference=core.settings:get_bool("bayline_bridge_road_reference",false)
local c=Sim.company(S,owner);c.cash=200000
local function road(x,z)
  for nz=z-3,z+3 do S.tiles[at(x,nz)].terrain="grass" end
  local ok,why,changed=Sim.build(S,owner,"road",Sim.line(at(x,z-3),at(x,z+3)))
  assert(ok,why)
  assert(Sim.road_connected(S,at(x,z),1) and Sim.road_connected(S,at(x,z),3))
  return changed
end
-- Both span types are allowed to cross an already built ordinary road.
road(24,19)
road(24,40)
-- Keep a second neighboring corridor dry for the late-build reload check.
for z=16,22 do S.tiles[at(26,z)].terrain="grass" end
local kits={{"road_bridge_wood",19,0,32},{"road_bridge_concrete",26,1,23},
  {"road_bridge_girder",33,2,26},{"rail_bridge_wood",40,false,32}}
for _,kit in ipairs(kits) do
  local a,b=at(20,kit[2]),at(kit[4],kit[2])
  local ok,note,changed,deck
  if kit[3] then
    ok,note,changed,deck=Sim.road_bridge(S,owner,a,b,kit[3])
  else
    local price=assert(api.rail_spans.quote_bridge(S,owner,a,b))
    ok,note,changed,deck=api.rail_spans.commit(S,owner,price)
  end
  assert(ok,tostring(note));assert(deck==4,tostring(deck))
  api.render.raise_bound(deck)
end
local function node(x,y,z,dx,dz)
  return core.get_node({x=x*2+dx,y=y,z=z*2+dz}).name
end
local ready=false
core.register_on_joinplayer(function(p)
  if p:get_player_name()~=owner then return end
  core.emerge_area({x=32,y=-1,z=27},{x=73,y=12,z=96},function(_,_,left)
    if left~=0 then return end
    api.render.update(dirty)
    local function check_under(x,z,family)
      assert(Sim.road_connected(S,at(x,z),1) and Sim.road_connected(S,at(x,z),3))
      local a,b={tile=at(x,z-2),owner=owner,mode="road"},{tile=at(x,z+2),owner=owner,mode="road"}
      -- Plain command graph: exclude nothing, use endpoints on ordinary
      -- road rather than requiring fictional commercial stations here.
      local path=Sim.path(S,a,b,"road",owner,{})
      assert(path and #path==5)
      assert(path[3]==at(x,z))
      assert(node(x,0,z,0,0):match("bayline:road_5_plain"))
      assert(node(x,4,z,0,0)=="bayline:stock_"..family.."_span_0"..(reference and "" or "_road_clear"))
      for y=1,3 do
        assert(node(x,y,z,0,0)==(reference and "bayline:stock_"..family.."_pier_0" or "air"))
        assert(node(x,y,z,1,1)=="air")
      end
      assert(node(25,0,z,1,1):match("ocean_top"))
      assert(node(25,1,z,1,1)=="bayline:stock_"..family.."_foot_0_water")
      assert(node(25,3,z,0,0)=="bayline:stock_"..family.."_pier_0")
      assert(node(21,3,z,1,1)=="bayline:stock_"..family.."_foot_0_1")
    end
    check_under(24,19,"road_bridge_wood")
    check_under(24,40,"rail_bridge_wood")
    assert(node(26,4,19,0,0)=="bayline:stock_road_bridge_wood_span_0")
    api.render.update(road(26,19))
    check_under(26,19,"road_bridge_wood")
    local ok,note,changed=Sim.build(S,owner,"clear",{at(26,19)})
    assert(ok,note)
    api.render.update(changed)
    assert(node(26,4,19,0,0)=="bayline:stock_road_bridge_wood_span_0")
    assert(node(26,1,19,0,0)=="bayline:stock_road_bridge_wood_pier_0")

    ready=true
    core.log("action","BRIDGE_PIER_RENDER_NATIVE_READY clear render; intact ground road routing, dry slopes and submerged adjacent piers")
  end)
end)
-- Move only the QA camera. The bridge geometry still uses actual company
-- construction and the live engine renderer on the ordinary world.
local prior
core.register_globalstep(function()
  if not ready then return end
  local f=io.open(core.get_worldpath().."/pier-view.txt","r")
  if not f then return end
  local mode=f:read("*l"); f:close()
  if mode==prior then return end
  local z=({wood=19,rail=40,water=19})[mode]
  local p=core.get_player_by_name(owner)
  if not z or not p then return end
  prior=mode
  local from={x=48.50,y=.85,z=z*2-5.5}
  local to={x=48.50,y=1.95,z=z*2+.5}
  if mode=="water" then
    from={x=48,y=1.85,z=z*2-6.0}
    to={x=53,y=1.65,z=z*2+.5}
  end
  p:set_pos(from)
  local dx,dy,dz=to.x-from.x,to.y-from.y-1.625,to.z-from.z
  p:set_look_horizontal(math.atan2(-dx,dz))
  p:set_look_vertical(math.atan2(-dy,math.sqrt(dx*dx+dz*dz)))
  p:hud_set_flags({hotbar=false,crosshair=false})
  core.log("action","BRIDGE_PIER_VIEW "..mode)
end)
