local m="mods/luanttd_core/"
local function load(p) return dofile(m..p..".lua") end
local Sim,Terrain,Slope=load("sim"),load("openttd/terrain"),load("openttd/slope")
local Track,Flood=load("openttd/rail_track"),load("openttd/water_flood")
local W=load("openttd/rail_half_water")(Track,Slope)
local Coast=load("water_flood_world")(Sim,Terrain,Flood,Track,Slope,W)
local Water=load("openttd/ship_follow")(Track)
local Net=load("ship_network")(Sim,Terrain,Water,{})
local fixtures={{9,16},{7,8},{11,16},{13,4},{14,32},{23,8},{27,16},{29,4},{30,32}}
local heights={{8,8,8},{9,8,1},{9,9,2},{8,9,4}}
for _,v in ipairs(fixtures) do
  local shape,bits=v[1],v[2]
  local s=Sim.new(19)
  local actual={}
  local high,hx,hz
  if shape>16 then high=({[23]=1,[27]=0,[29]=3,[30]=2})[shape] end
  for _,corner in ipairs(heights) do
    local x,z,flag=unpack(corner)
    local use=Track.intersect(shape%16,flag)~=0
    actual[z*100+x]=use and (2^((high or -1))==flag and 2 or 1) or 0
    if actual[z*100+x]==2 then hx,hz=x,z end
  end
  s.corner_grid=Terrain.new(Sim.W,Sim.H,function(x,z)
      return actual[z*100+x] or (hx and math.max(0,2-math.abs(x-hx)-math.abs(z-hz)) or 0)
    end,
    {freeform_edges=true})
  for i=1,Sim.W*Sim.H do s.tiles[i]={terrain="grass",h=0,variant=0} end
  local id=Sim.id(8,8)
  local t={terrain="grass",h=0,variant=0,rail_tracks=bits,rail_ground=1,build="stock_rail",owner="Builder"}
  s.tiles[id]=t
  local B=Coast.board(s)
  local q=B.tile(8,8)
  assert(q.kind=="rail" and q.slope==shape and q.foundation_base==0)
  local sx,sz,source
  for d=0,7 do
    local u,z=Flood.offset(d)
    local a,b=8+u,8+z
    local k=Sim.id(a,b)
    source=s.tiles[k]
    source.terrain,source.water_class="water","sea"
    local possible=false
    for _,c in ipairs(Flood.visit(B,a,b)) do if c.x==8 and c.z==8 then possible=true end end
    if possible then sx,sz=a,b;break end
    source.terrain,source.water_class="grass",nil
  end
  assert(sx,"Expected a water direction for shape "..shape)
  assert(Coast.visit(s,sx,sz)>0 and t.rail_ground==13 and t.rail_tracks==bits)
  assert(Water.at(Net.board(s),id)==0)
  assert(Coast.visit(s,8,8)==0,"Wet rail holds while active water remains")
  -- Remove the contributing shore only; adjacent flood products are a
  -- separate fixture concern. The same directed scan must now dry it.
  for d=0,7 do
    local u,z=Flood.offset(d)
    local neighbor=s.tiles[Sim.id(8+u,8+z)]
    neighbor.terrain,neighbor.coastal_water,neighbor.water_class="grass",nil,nil
  end
  assert(Coast.visit(s,8,8)==1 and t.rail_ground==W.dry_ground(bits))
  assert(t.rail_tracks==bits and t.owner=="Builder")
end
print("PASS multi-corner coast: source special and steep profiles flood, preserve rail, block ship shortcuts and dry to the right fence")
