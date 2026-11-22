-- Straight raised-track signal commands and grade-aware mesh anchors.
-- OpenTTD 16.0-RC1 rail_cmd.cpp: CmdBuildSingleSignal and GetSafeSlopeZ.
local dir="mods/luanttd_core/"
local function m(f) return dofile(dir..f..".lua") end
local function up(f,...) return m("openttd/"..f)(...) end
local Sim,Track,Slope=m("sim"),m("openttd/rail_track"),m("openttd/slope")
local Signal=up("rail_signals",Track)
local Height=up("rail_height",Track,Slope)
local Quote=up("rail_construction",Track,Signal,Height)
local Art=m("rail_signal_art")
local tiles={
  [1]={kind="rail",owner="A",trackbits=1,rail_tracks=1,slope=3,base_level=2},
  [2]={kind="rail",owner="A",trackbits=2,rail_tracks=2,slope=6,base_level=3},
  [3]={kind="rail",owner="B",trackbits=1,rail_tracks=1,slope=3,base_level=2},
  [4]={kind="rail",owner="A",trackbits=3,slope=0,base_level=2},
}
local S=Sim.new(1751);S.tiles=tiles
local board={tile=function(id) return tiles[id] end}
local F={board=function() return board end}
local live={signals=Signal.new(),runs={}}
local Run={
  current=function() return live end,
  tick=function()end,
  place_signal=function(_,owner,id,td,kind)
    return Signal.place(board,live.signals,owner,id,Track.track(td),
      {kind=kind,copy_mask=Track.signal_along(td)},0,false)
  end,
}
local api={s=S,Sim=Sim,rail_block_tools=true,save=function()end,render={update=function()end}}
local B=m("rail_construction_tools")(api,F,Track,Run,{
  signal=function(t,d,one,o)
    local q,e=Quote.signal(t,d%2,{kind=one and Signal.PBS_ONEWAY or Signal.PBS},o)
    return q and q.cost,e
  end,
  clear_signal=function()return Quote.base_prices().clear_signal end,
})
local fund=Sim.company(S,"A").cash
for id,d in ipairs({Track.NE,Track.SE}) do
  local q=assert(B.quote_signal("A",id,d,true))
  assert(B.build("A",q))
  fund=fund-q.price
  assert(Sim.company(S,"A").cash==fund)
end
assert(not B.quote_signal("A",3,Track.NE,true))
assert(not B.quote_signal("A",4,Track.NE,true))
local placed={}
core={
  register_entity=function()end,
  add_entity=function(pos,name)
    placed[#placed+1]={pos=pos,name=name}
    return {get_pos=function()return pos end,move_to=function()end,set_rotation=function()end}
  end,
  get_connected_players=function()return {{get_pos=function()return {x=4,y=10,z=2}end}} end,
}
local pixel=Height.bind(board,function(id) return tiles[id].slope,tiles[id].base_level end)
local View=m("rail_dispatch_view").create(api,Run,Track,{},Art,1.25,nil,nil,pixel)
View.step(.5,true,1)
assert(#placed==2)
for id,d in ipairs({Track.NE,Track.SE}) do
  local x,z=Sim.xy(id)
  local td=Track.diagonal_trackdir(d)
  local u,v=Art.anchor(td,false)
  local y=pixel(id,u,v)/8+.5
  local found=false
  for _,row in ipairs(placed) do
    local pos=row.pos
    if pos.x==2*x-.5+u/8 and pos.z==2*z-.5+v/8 and pos.y==y then
      assert(row.name:match("^luanttd_core:dispatch_signal_"))
      found=true
    end
  end
  assert(found,"Signal mesh did not use its own grade height")
  assert(y~=tiles[id].base_level+.5)
end
print("PASS OpenTTD 16.0-RC1 straight X/Y signals on real grades, anchor heights, pricing and permission limits")
