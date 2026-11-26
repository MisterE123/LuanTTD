-- Genuine ordinary worker-generated campaign, no town/road entities
-- injected. The native client showcases two source-driven frontage zones.
local D=dofile(mod.."/openttd/roadside_details.lua")
local show={"trees","street_lights"}
local next_=1
local focus,last_count
local function choose(s,next)
  for id,t in ipairs(s.tiles) do
    if t.roadside==next and t.build=="road" and t.road_town and not t.roadworks and not t.tram
        and not t.road_bridge_id and not t.road_tunnel_id and not (s.bridge_above and s.bridge_above[id]) then
      local rb=Sim.road_bits(s,id)
      local grade,base=Sim.road_surface(s,id)
      if grade==0 and D.points(next,rb,rb,false,base) then return {id=id,bits=rb,base=base} end
    end
  end
end
local function aim(p,q)
  local x,z=Sim.xy(q.id)
  local target={x=2*x+.5,y=q.base+.7,z=2*z+.5}
  local eye={x=target.x-3.1,y=q.base+2.45,z=target.z+4.0}
  p:set_pos(eye)
  local d={x=target.x-eye.x,y=target.y-eye.y-1.47,z=target.z-eye.z}
  p:set_look_horizontal(math.atan2(-d.x,d.z))
  p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
end
local function run()
  local p=core.get_player_by_name("SteelReview")
  if not (p and authority and authority.status()=="owned") then core.after(.2,run);return end
  local s=assert(OwnerCheckpoint.read())
  local type_=show[next_]
  if not focus or s.tiles[focus.id].roadside~=type_ then
    focus=choose(s,type_)
    if focus then
      core.log("action",("NATIVE ROADSIDE candidate %s tile %d at day %d"):format(type_,focus.id,s.day))
      aim(p,focus)
    elseif not last_count or s.day-last_count>=30 then
      local counts={}
      for _,t in ipairs(s.tiles) do if t.build=="road" then local k=t.roadside or "unvisited";counts[k]=(counts[k] or 0)+1 end end
      core.log("action",("NATIVE ROADSIDE awaiting %s at day %d; trees %d, lamps %d, paved %d"):format(type_,s.day,counts.trees or 0,counts.street_lights or 0,counts.paved or 0))
      last_count=s.day
    end
    core.after(.28,run)
    return
  end
  local x,z=Sim.xy(focus.id)
  local a=core.get_node({x=2*x+1,y=focus.base+1,z=2*z+1})
  local expected=("roadside_%s_%d_0"):format(type_,focus.bits)
  if a.name~="luanttd_core:"..expected then core.after(.28,run);return end
  local b=core.get_node({x=2*x,y=focus.base,z=2*z})
  assert(b.name:find("town_street_",1,true),b.name)
  aim(p,focus)
  core.log("action",("NATIVE ROADSIDE %s READY: source day %d, mesh %s, real paved shoulders")
    :format(type_,s.day,expected))
  if next_==#show then
    local phase=.5
    -- Keep only this disposable screenshot clock still. World fixtures,
    -- lamp zones, terrain and placement remain ordinary worker output.
    local real=core.get_timeofday
    local set=core.set_timeofday
    core.get_timeofday=function() return phase or real() end
    core.register_globalstep(function() if phase then set(phase) end end)
    local function count(kind)
      local n=0
      for _,ref in ipairs(core.get_objects_inside_radius({x=2*x+.5,y=focus.base+1,z=2*z+.5},3)) do
        local e=ref:get_luaentity()
        if e and e.name=="luanttd_core:street_light_"..kind then n=n+1 end
      end
      return n
    end
    render.step_lighthouse_beams(.5,{p:get_pos()})
    assert(count("cone")==0 and count("pool")==0,"daylight left lamp effects")
    phase=.91
    render.step_lighthouse_beams(.5,{p:get_pos()})
    assert(count("cone")>=1 and count("pool")>=1,"actual painted lamp did not light at night")
    for _,flag in ipairs({"hotbar","crosshair","wielditem","healthbar","basic_debug"}) do p:hud_set_flags({[flag]=false}) end
    core.log("action","NATIVE ROADSIDE NIGHT READY")
    core.after(3.5,function()
      phase=.5
      render.step_lighthouse_beams(.5,{p:get_pos()})
      assert(count("cone")==0 and count("pool")==0,"dawn left lamp effects")
      core.log("action","PASS NATIVE ROADSIDE: living worker town lamps glow at night and go out by day")
    end)
  else
    local function advance() next_=next_+1;focus=nil;run() end
    core.after(6,advance)
  end
end
core.after(.25,run)
