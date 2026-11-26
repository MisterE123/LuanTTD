-- Build seven original limestone treads without duplicating internal
-- faces. Models and collision share the same canonical authored bounds.
local root="mods/luanttd_core/"
local S=dofile(root.."house_front_steps.lua")
for key=1,8 do
  local p=S.vertices(key)
  local out={"# LuanTTD outward limestone frontage stairs","o ReversibleCurbsideSteps"}
  local n=0
  local d=S.direction(key)
  local mirror=(key>4)
  local reverse=mirror==(d==1 or d==2)
  local function face(points,mode)
    local refs={}
    for i=1,#points do
      local at=points[reverse and (#points-i+1) or i]
      local u,y,v=unpack(at)
      local q=p(u,y,v)
      out[#out+1]=("v %.6f %.6f %.6f"):format(-q.x,q.y,q.z)
      local s,t=mode=="end" and v*2 or (u+.95)/1.9,mode=="top" and v*2 or y+1.5
      out[#out+1]=("vt %.6f %.6f"):format(.04+.92*s,.04+.92*t)
      n=n+1;refs[#refs+1]=n.."/"..n
    end
    out[#out+1]="f "..table.concat(refs," ")
  end
  for i=1,7 do
    local a,b,y=S.tread(i)
    local waist,base=.317,-1.5
    local former=base+(i-1)/7
    face({{a,y,0},{a,y,waist},{b,y,waist},{b,y,0}},"top")
    face({{a,y,waist},{a,base,waist},{b,base,waist},{b,y,waist}},"side")
    face({{a,y,0},{a,former,0},{a,former,waist},{a,y,waist}},"end")
    if i==7 then face({{b,y,waist},{b,base,waist},{b,base,0},{b,y,0}},"end") end
  end
  local data=table.concat(out,"\n").."\n"
  local name=root.."models/bl_town_front_steps_"..key..".obj"
  local check=arg[1]=="--check"
  local f=assert(io.open(name,check and "rb" or "wb"))
  if check then assert(f:read("*a")==data,name) else f:write(data) end
  f:close()
end
print("PASS original frontage stair meshes, both hands in all four directions")
