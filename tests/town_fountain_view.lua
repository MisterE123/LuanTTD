local base="mods/luanttd_core/"
local Sim={W=48,H=48,id=function(x,z) return (z-1)*48+x end}
local node_at,live,adds,deletes={},{},0,0
local function key(p) return p.x..":"..p.y..":"..p.z end
local core={
  get_node_or_nil=function(p) return node_at[key(p)] end,
  add_particlespawner=function(spec)
    assert(spec.time==0 and spec.amount==48 and spec.playername and spec.acc.y<0)
    assert(spec.texture.name=="bl_fountain_droplet.png" and spec.texture.alpha_tween[2]==0)
    -- Lowest/fastest-falling droplet still expires inside the basin's bowl.
    local y=spec.vel.min.y*spec.exptime.max+.5*spec.acc.y*spec.exptime.max^2
    assert(y>=-.70)
    adds=adds+1;live[adds]=spec;return adds
  end,
  delete_particlespawner=function(id,name)
    assert(live[id] and live[id].playername==name);live[id]=nil;deletes=deletes+1
  end,
}
local front={placement=function() return 1,0 end}
local F=dofile(base.."town_fountain_view.lua")(core,Sim,front)
local state={tiles={}}
local viewers={{name="Alice",x=20.5,y=4.375,z=20.5}}
local function place(x,z,complete,painted)
  local id=Sim.id(x,z)
  state.tiles[id]={h=3,house=true,source_house={id=0x0A,completed=complete}}
  if painted then node_at[key({x=2*x+1,y=4,z=2*z})]={name="luanttd_core:town_stock_0a"} end
  return id
end
local function step() F.step(.4,state,viewers) end
local id=place(10,10,true,false)
place(10,11,false,true)
step();assert(adds==0,"emitter started before a completed model was painted")
place(10,10,true,true)
step();assert(adds==1 and live[1].playername=="Alice")
assert(math.abs(live[1].pos.min.x-20.466)<.0001 and math.abs(live[1].pos.min.y-4.365)<.0001)
for i=1,5 do step() end
assert(adds==1 and deletes==0,"emitter refreshed while stationary")
viewers[1].x=49
step();assert(live[1],"leave radius lacks hysteresis")
viewers[1].y=44
step();assert(not live[1],"flyover left a live spawner beyond its rendering distance")
viewers[1].y=4.375
step();assert(adds==1,"entry radius is larger than advertised")
viewers[1].x=20.5
step();assert(adds==2 and live[2])
state.tiles[id]=nil
step();assert(not live[2],"projection removal must stop the spawner even if the old node persists")
for x=9,16 do place(x,10,true,true) end
viewers[2]={name="Bob",x=20.5,y=4.375,z=20.5}
step()
assert(adds==14,"world budget is not bounded to six spawners per viewer")
F.leave("Alice")
local n=0
for _,spec in pairs(live) do assert(spec.playername=="Bob");n=n+1 end
assert(n==6,"disconnect must only clear that viewer")
viewers={}
step();assert(not next(live))
print("PASS fountain spray: completed painted models, height/distance hysteresis, scene removal, per-client cap, no refresh churn")
-- RC1 shows the basin before population completion; a worker-projected
-- stage 2 starts the same water effect as 3, but stage 1 cannot.
state.tiles={}
local stage_id=place(10,10,false,true)
local stage=state.tiles[stage_id].source_house
stage.stage=1;viewers={{name="PhaseQA",x=20.5,y=4.375,z=20.5}}
local expect=adds
step();assert(adds==expect)
stage.stage=2
step();assert(adds==expect+1 and live[expect+1].playername=="PhaseQA")
stage.stage=3;stage.completed=true
step();assert(adds==expect+1,"Completion replaced an already painted basin emitter")
F.leave("PhaseQA")
print("PASS stock fountain: intact source phase-2 basin sprays without completing the house")
