local root="mods/luanttd_core/"
local function m(x) return dofile(root..x..".lua") end
local before=arg and arg[1] and (arg[1]:gsub("/$","").."/")
local P,R,I=m("openttd/passengers"),m("openttd/station_rating"),m("openttd/income")
local C=m("openttd/station_catchment")(P,R)
local Coal=m("openttd/coal_industry")(P,R,C,I)
local Timber=m("openttd/timber_industry")(P,C,R,I,Coal,m("openttd/town_goods"))
local FC=m("openttd/farm_factory_industry")
local Farm=FC(P,C,R,I,Coal,Timber)
local Oil=m("openttd/oil_industry")(FC,P,C,R,I,Coal,Timber)
local Fields=m("openttd/farm_factory_fields")(Coal)
local constructor={{"forest",Timber},{"sawmill",Timber},{"farm",Farm},{"factory",Farm},{"oil_well",Oil},{"oil_refinery",Oil}}
local industries,stations={},{}
for i=1,768 do
  local b=constructor[(i-1)%#constructor+1]
  local x,z=(i-1)%32*16+3,math.floor((i-1)/32)*16+3
  industries[i]=b[2].new(b[1],i,x,z,{completed=true,original=true,generating_world=true})
  if i%6==0 then stations[#stations+1]={id=i,x=x,z=z,tiles={{x=x,y=z,kind="truck"}}} end
end
local ctx={width=512,height=512,xy=function(n) return n%512,math.floor(n/512) end,industries=industries,stations=stations}
local function prepare(path)
  local _,A=dofile(path.."combined_industry_runtime.lua")(Timber,Farm,Oil,Fields,
    dofile(path.."timber_industry_runtime.lua"),C)
  local s,ledger={},A.new()
  return function() return A.bind(s,ledger,ctx) end
end
local baseline,candidate=before and prepare(before),prepare(root)
local function same(a,b)
  if a==b then return true end
  if type(a)~="table" or type(b)~="table" then return false end
  for k,v in pairs(a) do if not same(v,b[k]) then return false end end
  for k in pairs(b) do if a[k]==nil then return false end end
  return true
end
local function probe()
  local a,b=baseline and baseline(),candidate()
  if not a then return b end
  assert(same(a.landscape(512,512),b.landscape(512,512)))
  for _,st in ipairs(stations) do
    for _,c in ipairs({"oil","wood","goods","grain","livestock"}) do
      assert(same(a.report(st.id,c),b.report(st.id,c)))
    end
  end
  return b
end
local first=probe()
local grid=first.landscape(512,512)
assert(candidate().landscape(512,512)==grid)
local chosen=industries[1]
local key=chosen.tiles[1].z*512+chosen.tiles[1].x
assert(grid[key].tile==chosen.tiles[1])
chosen.tiles[1].animated=true
assert(candidate().landscape(512,512)[key].tile.animated)
chosen.removed=true
local closed=probe()
assert(not closed.landscape(512,512)[key] and grid[key] and candidate().landscape(512,512)==closed.landscape(512,512))
industries[1]=Timber.new("forest",1,4,5,{completed=true})
local rebuilt=probe()
assert(rebuilt.landscape(512,512)[key]==nil)
assert(rebuilt.landscape(512,512)[5*512+4].ind==industries[1])
print("PASS stock footprint reused, animation read live, closure and replacement rebuild")
if not baseline then return end
local function measure(make)
  collectgarbage("collect")
  local start=os.clock()
  for i=1,160 do assert(make().landscape(512,512)) end
  return (os.clock()-start)*1000
end
for batch=1,4 do
  local a,b
  if batch%2==1 then a=measure(baseline);b=measure(candidate)
  else b=measure(candidate);a=measure(baseline) end
  print(("FOOTPRINT BIND batch=%d cpu=%.3f/%.3f ms (160 day binds)"):format(batch,a,b))
end
