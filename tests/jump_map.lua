local Sim={W=64,H=64,tools={road={mode="road"}}}
function Sim.id(x,z)
  if x>=1 and z>=1 and x<=Sim.W and z<=Sim.H then return (z-1)*Sim.W+x end
end
function Sim.xy(id) return (id-1)%Sim.W+1,math.floor((id-1)/Sim.W)+1 end
local S={tiles={},sites={}}
local function reset(n,m)
  Sim.W,Sim.H=n,m or n
  S.tiles,S.sites={},{}
  for i=1,Sim.W*Sim.H do S.tiles[i]={terrain="grass",h=1} end
end
local M=dofile("mods/luanttd_core/jump_map.lua")({Sim=Sim,s=S})
reset(64)
local p=M.snapshot(false,Sim.id(58,61))
assert(p.pixel_cols==64 and p.pixel_rows==64 and p.raster_stride==1 and not p.wide)
assert(p.cols*p.rows<576 and p.targets[1]==Sim.id(2,2))
assert(p.marker[1]==57.5/64 and p.marker[2]==60.5/64)
for z=1,3 do for x=1,3 do S.tiles[Sim.id(x,z)].stock_void=true end end
p=M.snapshot(false,nil)
assert(not p.targets[1],"wholly void area is clickable")
reset(128)
local corner=Sim.id(128,128)
S.tiles[corner].build="road"
local marker=Sim.id(40,40)
p=M.snapshot(false,marker)
assert(p.pixel_cols==128 and p.pixel_rows==128 and #p.pixels==128^2 and p.raster_stride==1 and p.wide)
assert(p.cols*p.rows<=576 and p.targets[1]==Sim.id(3,3))
assert(p.pixels:byte(corner)~=p.pixels:byte(corner-1),"one-tile road vanished in the full overview")
local field=Sim.id(120,123)
S.tiles[field].water_class="river"
S.tiles[field-1].h=12
local overview=M.snapshot(false,marker)
assert(overview.pixels:byte(field)~=p.pixels:byte(field) and overview.pixels:byte(field-1)~=p.pixels:byte(field-1))
-- Raster exposes an isolated playable pixel that the 3×3 candidate
-- probes around this approximate destination would otherwise all miss.
for z=1,5 do for x=1,5 do S.tiles[Sim.id(x,z)].stock_void=true end end
local outcrop=Sim.id(2,2)
S.tiles[outcrop].stock_void=nil
assert(M.snapshot(false,nil).targets[1]==outcrop)
local d=M.snapshot(true,marker,corner)
assert(d.x==65 and d.z==65 and d.w==64 and d.h==64 and not d.marker)
assert(d.pixel_cols==64 and d.pixel_rows==64 and d.raster_stride==1 and d.cols*d.rows<=576)
assert(d.pixels:byte(4096)==overview.pixels:byte(corner))
local V={map_targets=p.targets,map_sites={[1]=corner},map_zoom=true,map_packet=d}
assert(M.pick(V,{jump_1=true})==p.targets[1] and not M.pick(V,{jump_4097=true}))
assert(M.pick(V,{jump_site_1=true})==corner and M.pick(V,{jump_place_1=true})==corner)
assert(M.pan(V,"map_west") and Sim.xy(V.map_center)==50)
assert(M.pick_coordinates("128","128")==corner)
assert(M.pick_coordinates(" 42 ","49")==Sim.id(42,49))
S.tiles[1].stock_void=true
for _,pair in ipairs({{"1","1"},{"129","5"},{"22","0"},{"1.5","2"},{"1e2","2"},{"1",false},{"-1","2"}}) do
  assert(not M.pick_coordinates(pair[1],pair[2]))
end
print("PASS finer terrain/road/water pixels independently of compact area clicks, exact coordinates, void protection, focus and pan")

reset(128,64)
local each={{"Westhaven",6,20,23},{"Tideway",55,23,430},{"Near Collision",56,22,4},
            {"Edge Quay",128,64,122},{"Closed Place",47,44,860,true},{"Southwick",50,61,121}}
for _,t in ipairs(each) do
  S.sites[#S.sites+1]={name=t[1],kind="town",tile=Sim.id(t[2],t[3]),population=t[4],closed=t[5]}
end
S.sites[#S.sites+1]={name="Factory",kind="industry",tile=Sim.id(44,44)}
p=M.snapshot(false,nil)
assert(p.pixel_cols==128 and p.pixel_rows==64 and p.cols<=24 and p.rows<=24)
assert(#p.towns==4 and p.towns[1].name=="Tideway","local town candidate sorting is not stable or crowded")
d=M.snapshot(true,nil,Sim.id(126,61))
assert(#d.towns==1 and d.towns[1].name=="Edge Quay","remote crop must label its own towns")
local marks=M.labels(p,1,2,13,6.5)
assert(#marks>=3)
for i,a in ipairs(marks) do
  assert(a.left>=1 and a.top>=2 and a.left+a.w<=14 and a.top+a.h<=8.5)
  for j=1,i-1 do
    local b=marks[j]
    assert(a.left>=b.left+b.w or b.left>=a.left+a.w or a.top>=b.top+b.h or b.top>=a.top+a.h)
  end
end
local form={}
local buttons,encoded,shown={},{},{}
core={
  formspec_escape=function(v) return v end,
  encode_base64=function(v) return v end,
  encode_png=function(w,h,raw)
    assert(#raw==w*h*4);encoded={w,h};return "raster"
  end,
}
local f={
  push=function(s) form[#form+1]=s end,rect=function() end,
  label=function(_,_,s) shown[s]=true end,
  button=function(_,_,_,_,k) buttons[k]=true end,
}
V={}
M.draw(V,{get_pos=function()return nil end},f,p)
assert(encoded[1]==128 and encoded[2]==64 and shown.Tideway and shown.Westhaven)
assert(not shown["Closed Place"] and not shown.Factory)
assert(table.concat(form):find(";bl_map_clear.png;jump_place_1;",1,true) and buttons.map_inspect)
print("PASS authoritative place names are detached, geographically anchored, kept within map bounds, clickable and non-overlapping")

-- A large sparse map must not touch or serialize its 16.8 million tiles.
Sim.W,Sim.H=4096,4096
local reads=0
S.tiles=setmetatable({},{
  __index=function()
    reads=reads+1
    return {terrain="grass",h=0}
  end,
})
S.sites={}
for i=1,5072 do
  S.sites[i]={kind="town",name="Town "..i,tile=Sim.id((i*29)%4096+1,(i*67)%4096+1),population=i}
end
p=M.snapshot(false,Sim.id(4096,4096))
assert(reads<=4*144^2+9*24^2,"unbounded survey read work")
assert(#p.pixels<=144^2 and p.cols*p.rows<=576 and #p.towns<=96)
assert(#p.pixels>#p.targets*25 and p.marker[1]>.99 and p.marker[2]>.99)
Sim.W=64
S.sites={{name="Long Coast",tile=Sim.id(32,2048),kind="town",population=100}}
p=M.snapshot(false,nil)
assert(#M.labels(p,6.5,2.46,.16,10.38,{.52,2.46,13.76,12.84})==1,
  "narrow rectangular world cannot lose all map labels")
print("PASS 4096²: bounded tile reads, 20.8 KiB max raster, at most 576 area buttons and 96 detached labels")
