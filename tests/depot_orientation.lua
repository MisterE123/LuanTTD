local m="mods/luanttd_core/"
local function load(p) return dofile(m..p..".lua") end
local Sim=load("sim")
local s=Sim.new(1751)
local look,yaw={x=1,z=0},0
local P={get_look_dir=function()return look end,get_look_horizontal=function()return yaw end,
  get_player_name=function()return "Viewer" end,get_player_control=function()return {} end}
local form,markup
core={get_modpath=function()return m:sub(1,-2) end,formspec_escape=function(x)return x end,
  get_us_time=function()return 0 end,show_formspec=function(_,a,b)form,markup=a,b end,
  close_formspec=function(_,a)assert(a==form);form=nil end}
local q,b
local ui=load("ui")({Sim=Sim,s=s,render={},authority_handoff=true,worker_build={
  preview=function(_,kind,req)q={kind=kind,request=req};return {cost=0} end,
  commit=function(_,kind,req)b={kind=kind,request=req};return true end}})
local tile=Sim.id(10,10)
local helper=load("depot_orientation")
local function aim(x,z) look={x=x,z=z} end
local function call(tool,kind,key,wanted)
  q,b=nil,nil
  ui.select_tool(P,tool)
  local _,ok,title=ui.preview(P,tile);assert(ok,title)
  ui.build_world(P,tile)
  assert(q.kind==kind and b.kind==kind)
  assert(q.request[key]==wanted and b.request[key]==wanted,tool..":"..tostring(b.request[key]))
  return title
end
local cardinal={{1,0},{0,-1},{-1,0},{0,1}}
for i,v in ipairs(cardinal) do
  aim(unpack(v))
  local d=i-1
  assert(helper.facing(P)==d)
  local hint=call("rail_depot_tool","rail","direction",d)
  assert(hint:find(({"West","South","East","North"})[i],1,true))
  call("tram_depot","road","direction",d)
  call("ship_depot","transport","axis",d%2)
  call("road_depot","road","preferred_direction",d)
end
aim(0,0);yaw=math.pi/2
assert(helper.facing(P)==2)
aim(-.48,.49)
assert(helper.facing(P)==3)
ui.open_depot_direction(P,"rail_depot_tool")
assert(markup:find("rail_door_auto",1,true))
assert(ui.depot_direction_fields(P,{rail_door_0=true}))
call("rail_depot_tool","rail","direction",0)
call("tram_depot","road","direction",3)
ui.open_depot_direction(P,"rail_depot_tool")
assert(ui.depot_direction_fields(P,{rail_door_auto=true}))
call("rail_depot_tool","rail","direction",3)
ui.open_depot_direction(P,"tram_depot")
assert(ui.depot_direction_fields(P,{rail_door_2=true}))
call("tram_depot","road","direction",2)
call("rail_depot_tool","rail","direction",3)
print("PASS camera-facing rail/tram/ship selection; road tie-break; identical preview and placement requests, isolated manual choices")
