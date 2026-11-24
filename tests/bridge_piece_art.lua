local mod="mods/luanttd_core/"
local B=dofile(mod.."openttd/road_bridge.lua")(dofile(mod.."openttd/slope.lua"))
local function xy(n) return n%20,math.floor(n/20) end
local seen={}
local function architecture(node,file,palette)
  assert(node=="stock_"..file and palette=="native_suspension" and not seen[node])
  seen[node]=true;return node
end
local M=dofile(mod.."bridge_piece_art.lua")(architecture,B,xy)
local kit=M.mount("native_suspension",{
  pieces={"outer_n","outer_s","through"},bearing={outer_n=true,outer_s=true},
  choices={[0]="outer_n",[1]="outer_s",[2]="outer_s",[3]="outer_n",[4]="outer_n",[5]="through"},
})
local plan={start=21,axis=0,bridge_type=3,middle={22,23,24,25,26},
  middle_by_tile={[22]=true,[23]=true,[24]=true,[25]=true,[26]=true}}
-- Full projected registry has the serializable middle list/index even
-- when it omits the source command's separate count.
local a,b,c,d,mask=kit.models(plan,22)
assert(mask==3 and a:match("outer_n$") and b:match("road_clear$") and c:match("pier"))
assert(type(d.water)=="string")
a,b,c,d,mask=kit.models(plan,24)
assert(mask==0 and a:match("through$") and not b and not c and not d)
assert(kit.models(plan,21)==nil)
plan.start=21;plan.axis=1
plan.middle={41,61,81,101,121};plan.middle_by_tile={[41]=true,[61]=true,[81]=true,[101]=true,[121]=true}
a,b,c,d,mask=kit.models(plan,121)
assert(mask==9 and a:match("1_outer_s$"))
print("PASS bridge art resolves the pinned stock piece/orientation from detached terrain registries")

local called={}
local recolor=dofile(mod.."bridge_piece_art.lua")(function(node,file,palette)
  assert(palette=="yellow_suspension")
  assert(node==("stock_yellow_suspension"..file:sub(#"native_suspension"+1)))
  assert(file:match("^native_suspension_"))
  called[node]=file
  return node
end,B,xy)
local yellow=recolor.mount("yellow_suspension",{
  pieces={"outer_n","outer_s","through"},bearing={outer_n=true,outer_s=true},
  choices={[0]="outer_n",[1]="outer_s",[2]="outer_s",[3]="outer_n",[4]="outer_n",[5]="through"},
},"native_suspension")
local draw,under,pier,feet=yellow.models(plan,121)
assert(called[draw]=="native_suspension_span_1_outer_s")
assert(called[under]=="native_suspension_span_1_outer_s_road_clear")
assert(called[pier]=="native_suspension_pier_1_outer_s")
assert(called[feet.water]=="native_suspension_foot_1_outer_s_water")
print("PASS palette variants share original deck, clear span, pier, and foot geometry")
local styles=dofile("mods/luanttd_core/bridge_style_assets.lua")
for _,mode in ipairs{"road","rail"} do
  local list=styles.list(mode,0)
  assert(#list==10)
  for i=0,9 do assert(list[i+1]==i) end
  for i=6,8 do
    assert(styles.mesh_stem(mode,i)==mode.."_bridge_cantilever")
    local map=styles.pieces[i]
    assert(map.choices[0]=="clear" and not map.bearing.clear and map.bearing.minus)
    for j=1,5 do assert(map.choices[j]=="minus") end
  end
end
print("PASS both normal modes mount all ten opening-era offers; all cantilevers share stock bearing classes")
