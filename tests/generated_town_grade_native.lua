-- Appended only to a disposable game. No terrain edits, structures, or
-- static scene assets are inserted. It moves the viewer to actual generated
-- public facilities once the production worker has painted the windows.
local checkpoints=dofile(mod.."/campaign_checkpoint.lua")(core,dofile(mod.."/packed_campaign.lua"),owner_filename)
local _,bridge=next(S.stock_road_bridges or {})
local _,bore=next(S.stock_road_tunnels or {})
assert(bridge and bore and bridge.town and bore.town,"Fixture seed did not generate public town spans")
local bpos=bridge.middle[math.ceil(#bridge.middle/2)]
local scenarios={
  town_bridge={span=bridge,id=bpos,height=bridge.deck,tag="stock_road_bridge",side=1},
  town_tunnel={span=bore,id=bore.start,height=bore.base+1,tag="stock_road_tunnel_portal",side=-1},
}
local active,viewed,at
local function camera(p,test)
  local x,z=Sim.xy(test.id)
  local e=test.span.head.inside_direction
  local dx,dz=({[0]=-1,0,1,0})[e],({[0]=0,1,0,-1})[e]
  local from={x=2*x-dx*9-dz*8*test.side,y=test.height+(test.side==1 and 11 or 4),z=2*z-dz*9+dx*8*test.side}
  p:set_pos(from)
  p:set_look_horizontal(math.atan2(from.x-2*x,2*z-from.z))
  p:set_look_vertical(math.atan2(from.y+1.625-test.height,math.sqrt((from.x-2*x)^2+(from.z-2*z)^2)))
  p:hud_set_flags({crosshair=false})
  p:override_day_night_ratio(.92)
end
core.register_globalstep(function()
  local p=core.get_player_by_name("PierQA")
  if not p or placement  then return end
  if not active then
    local state=checkpoints.read()
    if not (state and state.stock_road_bridges and state.stock_road_tunnels) then return end
    local _,b=next(state.stock_road_bridges)
    local _,t=next(state.stock_road_tunnels)
    assert(b and t and b.start==bridge.start and t.start==bore.start)
    active=true
    core.log("action","GENERATED_TOWN_SPANS_READY actual worker checkpoint has public bridge and bore")
  end
  local f=io.open(core.get_worldpath().."/pier-view.txt","r")
  if not f then return end
  local requested=f:read("*l");f:close()
  local t=scenarios[requested]
  if not t or viewed==requested then return end
  if at~=requested then at=requested;camera(p,t) end
  local x,z=Sim.xy(t.id)
  local node=core.get_node({x=2*x,y=t.height,z=2*z})
  if node.name:find(t.tag,1,true) then
    local def=assert(core.registered_nodes[node.name])
    assert(def.mesh and def.drawtype=="mesh",node.name)
    viewed=requested
    core.log("action","GENERATED_TOWN_SPANS_VIEW "..viewed.." "..node.name)
  end
end)
