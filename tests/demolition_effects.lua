local load=dofile("mods/luanttd_core/demolition_effects.lua")
local function player(n,x)
  return {get_player_name=function() return n end,get_pos=function() return {x=x,y=3,z=2.5} end}
end
local near,away=player("Builder",7),player("Elsewhere",255)
local fx,sound,now,queries={},{},0,0
local core={
  get_us_time=function() return now end,
  get_connected_players=function() return {near,away} end,
  add_particlespawner=function(x) fx[#fx+1]=x end,
}
local tiles={}
for i=1,12 do tiles[i]={h=2} end
local api={Sim={W=12,H=1,xy=function(i) return i,1 end},
  render={host_tile=function(id) queries=queries+1;return tiles[id] end,surface=function() return 2.5 end,
    host_deck=function() return 5 end},
  stock_audio={effect=function(name,options) sound[#sound+1]={name,options} end}}
local e=load(core,api)
assert(e.receipt(false,{1,2,3},2)==0 and e.receipt(true,{},2)==0 and e.receipt(true,nil,2)==0)
assert(queries==0 and #fx==0 and #sound==0,"preview, failure and noop did not consult the terrain")
local origin=e.origin(4,"road_bridge")
assert(origin.x==8.5 and origin.y==5.82)
assert(e.receipt(true,{4,5,6,4,7,8,9},4,origin)==3)
assert(#fx==9 and #sound==1 and sound[1][1]=="EXPLOSION" and sound[1][2].pos==origin)
for i=1,#fx do
  local p=fx[i]
  assert(p.playername=="Builder" and p.time>0 and p.time<.5 and p.exptime.max<1.5)
  assert(p.texture.alpha_tween[1]==1 and p.texture.alpha_tween[2]==0 and not p.collisiondetection)
  if p.texture.name=="bl_demolition_dust.png" then
    assert(p.vel.min.x>0 and p.vel.max.z<0 and p.vel.min.y>0 and p.texture.scale_tween[2]>1)
  end
end
assert(fx[1].pos.min.y>5.7 and fx[1].texture.name=="bl_demolition_flare.png")
for _=1,3 do assert(e.receipt(true,{1,2,3},1)==3) end
assert(e.receipt(true,{1},1)==0,"server-wide budget limits simultaneous actions")
now=1000000
assert(e.receipt(true,{1},1)==1 and #sound==5)
assert(e.receipt(true,{150000},1)==0,"non-authoritative ids cannot create effects")
print("Demolition effects: real changed IDs only, bounded near-player flash/chips/drifting dust, stock sound and area budget")

do
  -- Exercise the real layer confirmation client, including cancel, stale
  -- receipt and token consumption. Opening a valid quote is never a blast.
  local form,key,reply
  local c={get_modpath=function() return "mods/luanttd_core" end,
    formspec_escape=function(value) return value end,
    show_formspec=function(_,name,def) form,key=name,def:match(";(bulldoze_%d+_%d+);") end,
    close_formspec=function() end}
  local previous=_G.core
  _G.core=c
  local renders=#fx
  api.authority_handoff=true
  api.s={topology=5}
  api.demolition_effects=e
  api.worker_layer_client={query=function(r,callback)
    if r.kind=="demolition" then
      callback({ok=true,revision=4,value={token=8,options={
        {ok=true,key="road_bridge",title="Bridge",detail="Remove bridge"} }}})
    elseif r.kind=="command" then reply=callback end
    return true
  end}
  local layers=dofile("mods/luanttd_core/layer_bulldozer.lua")(api,function() end,function() end)
  local function open()
    reply=nil
    assert(layers.open(near,4) and form==layers.form and key)
    assert(#fx==renders)
  end
  open()
  layers.fields(near,{cancel_layers=true})
  layers.fields(near,{[key]=true})
  assert(not reply and #fx==renders)
  open()
  layers.fields(near,{[key]=true})
  assert(reply and #fx==renders)
  reply({ok=false,why="Stale tile",value={4}})
  assert(#fx==renders)
  open()
  layers.fields(near,{[key]=true})
  reply({ok=true,value={4}})
  assert(#fx==renders+3)
  reply=nil
  layers.fields(near,{[key]=true})
  assert(not reply and #fx==renders+3)
  _G.core=previous
  print("Layer effects: no burst on quote, cancel or stale authority response; one burst on confirmed successful removal")
end
