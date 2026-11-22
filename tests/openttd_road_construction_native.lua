-- SPDX-License-Identifier: GPL-2.0-only
-- The disposable lab binds one actual snapshot gap to the existing OpenTTD
-- 14.1 road slope/cost/drag kernels. No .sav editing or live game mutation.
local root=core.get_modpath(core.get_current_modname())
local function load(n) return dofile(root.."/"..n..".lua") end
local file=assert(io.open(root.."/input.json","rb"))
local input=assert(core.parse_json(file:read("*a")));file:close()
local S=load("road_slope")
local F=load("yapf_road_follow")
local R=load("road_oneway")(S,F)
local Prices=load("road_bridge")(S)
local function quote(q)
  assert(q.schema=="luanttd-stock-road-construction-input/1"
    and q.start==44640 and q.goal==44641 and q.stop==44642 and q.axis==0
    and q.mask==10 and q.owner==0 and q.width==256 and q.inflation==65536)
  local left,middle,right=q.tiles[1],q.tiles[2],q.tiles[3]
  assert(#q.tiles==3 and left.kind=="road" and left.road_bits==15 and left.roadtype==0
    and left.owner==q.owner and left.slope==0 and (left.disallowed or 0)==0)
  assert(middle.kind=="clear" and middle.slope==0 and middle.owner==nil
    and middle.density>=0 and middle.density<=3 and math.floor(middle.density)==middle.density)
  assert(right.kind=="bay_stop" and right.owner==q.owner and right.roadtype==0
    and right.slope==0 and right.road_bits==8)
  local function xy(id) return id%q.width,math.floor(id/q.width) end
  local board={xy=xy,adjacent=function(id,d) return id+({[0]=-1,q.width,1,-q.width})[d] end}
  local rows={[q.start]=left,[q.goal]=middle,[q.stop]=right}
  board.tile=function(id) return rows[id] end
  local factor=assert(({[0]=6,8,9})[q.construction_difficulty])
  local piece=math.floor(Prices.road_build_cost(0)*factor/8)
  local clear=middle.density==0 and 0 or math.floor(20*factor/8)
  assert(R.can_connect(board,q.goal,0) and R.can_connect(board,q.goal,2))
  assert(not R.can_connect(board,q.start,2),"source bridge to stop is already connected")
  local opts={company=q.owner,toggle=0,ai=true,start_half=false,end_half=true,piece_cost=piece,
    clear=function(t,id) assert(id==q.goal and t==middle);return clear end}
  local plan=assert(R.plan(board,q.start,q.goal,q.axis,opts))
  local edit=assert(plan.changes[1])
  assert(#plan.changes==1 and edit.tile==q.goal and edit.road_bits==q.mask and edit.added==q.mask
    and edit.owner==q.owner and not edit.foundation and edit.disallowed==0
    and #plan.skipped==1 and plan.skipped[1].tile==q.start and plan.skipped[1].reason=="ALREADY_BUILT"
    and plan.cost==2*piece+clear and edit.cost==plan.cost)
  rows[q.goal]=edit
  assert(R.can_connect(board,q.start,2) and R.can_connect(board,q.stop,0)
    and F.has_trackdir(F.status(edit,false),8))
  assert(q.tiles[2]==middle and middle.kind=="clear","quote mutated immutable input")
  return {schema="luanttd-stock-road-construction-quote/1", source_sha256=q.source_sha256,
    original_tick=q.original_tick, owner=q.owner,start=q.start,goal=q.goal,stop=q.stop,
    piece_cost=piece,clear_cost=clear,cost=plan.cost,mask=edit.road_bits}
end
local function copy(t)
  if type(t)~="table" then return t end
  local r={}
  for k,v in pairs(t) do r[k]=copy(v) end
  return r
end
local result=quote(input)
local rejected=0
for _,mutate in ipairs({
  function(q) q.goal=q.goal+1 end,
  function(q) q.tiles[1].owner=1 end,
  function(q) q.tiles[1].disallowed=1 end,
  function(q) q.tiles[2].slope=1 end,
  function(q) q.tiles[2].kind="field" end,
  function(q) q.tiles[3].road_bits=1 end,
  function(q) q.inflation=65537 end,
}) do
  local q=copy(input);mutate(q);assert(not pcall(quote,q),"bad quote was accepted");rejected=rejected+1
end
result.rejected_lab_inputs=rejected
local body=assert(core.write_json(result))
core.log("action","LuanTTD stock road construction quote "..assert(core.write_json({
  body=body,sha256=core.sha256(body)})))
core.register_on_mods_loaded(function()
  core.after(.05,function() core.request_shutdown("road construction quote complete",false,0) end)
end)
