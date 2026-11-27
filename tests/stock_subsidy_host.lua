-- Ordinary RC1 generation, not manually seeded streets or infrastructure.
local root="mods/luanttd_core/"
local function load(name) return dofile(root..name..".lua") end
local Sim,Terrain,Codec=load("sim"),load("openttd/terrain"),load("packed_campaign")
local Follow=load("openttd/yapf_road_follow")
local Read=load("road_yapf_board")
local Generation=load("campaign_generation")({settings={get=function() return nil end},
  get_dir_list=function(path)
    local names={}
    local p=assert(io.popen("ls -1 "..path))
    for n in p:lines() do names[#names+1]=n end
    p:close()
    return names
  end},root:gsub("/$",""),Sim,load("world_setup"))
local s=Generation.run({width=64,depth=64,seed=1751})
local G=load("openttd/town_growth")
local Rules=load("openttd/subsidy")(G.range,G.chance)
local Host=load("stock_subsidy_host")(Sim,Rules,load("openttd/town_passengers"),{
  passenger=load("road_station_service")().house_passenger_acceptance,
  mail=load("road_mail_runtime")().house_acceptance,
  goods=load("openttd/town_goods").house_acceptance,
},load("openttd/town_cargo_stats"))
local book=Host.new()
local b=Host.board(s,book)
assert(#b.towns==s.stock_generated_profile.towns and #b.industries==#s.stock_generated_profile.industries)
for i,rec in ipairs(b.industries) do assert(rec.id==i-1 and b.source("industry",rec.native,rec.chain)==rec) end
local picked
for i,src in ipairs(b.industries) do
  local slots=b.industry_produced(src)
  for k,c in ipairs(slots) do
    if c.production>0 and c.transported_pct<=42 then
      for j,dst in ipairs(b.industries) do
        if i~=j and b.industry_accepts(dst,c.cargo) and math.abs(src.x-dst.x)+math.abs(src.z-dst.z)<=70 then
          picked={i,k,j,c,src,dst,#slots};break
        end
      end
    end
    if picked then break end
  end
  if picked then break end
end
assert(picked)
local function pick(i,count) return math.ceil((i-1)*4294967296/count) end
local i,k,j,c,src,dst,n=unpack(picked)
local words={3*2^28,pick(i,#b.industries),pick(k,n),4294967295,pick(j,#b.industries)}
local draw=0
local offer,entry=Rules.month(book.subsidies,b,1,function()draw=draw+1;return assert(words[draw])end)
assert(offer and draw==5 and entry.cargo==c.cargo and entry.src.id==src.id and entry.dst.id==dst.id)
local dst_tile
for id,tile in ipairs(s.tiles) do
  local m=tile.stock_industry
  if m and (m.chain or "coal")==dst.chain and m.id==dst.native then dst_tile=id-1;break end
end
assert(dst_tile)
local packet={source=src.native,source_type="industry"}
local cargo=Host.types[c.cargo]
assert(Host.deliver(s,book,cargo,"Company A",packet,101,{},src.chain)==101)
assert(entry.awarded==nil)
assert(Host.deliver(s,book,cargo,"Company A",packet,101,{[dst_tile]=true},"unrecognized")==101)
assert(Host.deliver(s,book,cargo,"Company A",packet,101,{[dst_tile]=true},src.chain)==303)
assert(entry.awarded=="Company A")
assert(Host.deliver(s,book,cargo,"Company B",packet,101,{[dst_tile]=true},src.chain)==101)
dst.firm.removed=true
assert(Host.deliver(s,book,cargo,"Company A",packet,101,{[dst_tile]=true},src.chain)==101)
b=Host.board(s,book)
assert(not b.source("industry",dst.native,dst.chain) and book.subsidies.count==0)
dst.firm.removed=nil
local reopened=Codec.decode(Codec.encode({stock=s,subsidy=book}))
b=Host.board(reopened.stock,reopened.subsidy)
assert(b.source("industry",dst.native,dst.chain).id==dst.id and b.source("industry",src.native,src.chain).id==src.id)

-- An authority or geometry adapter must never confuse the station's town
-- with a physical house. At the boundary catchment can contain two towns
-- (and even unfinished house parts); award both but multiply fare once.
local ta,tb,tc=unpack(b.towns)
local a=Rules.create(reopened.subsidy.subsidies,Host.cargo.passenger,ta,tb)
local b_offer=Rules.create(reopened.subsidy.subsidies,Host.cargo.passenger,ta,tc)
local covered={}
for id,tile in ipairs(reopened.stock.tiles) do
  local house=tile.house and tile.source_house
  if house and (house.town==tb.site or house.town==tc.site) then covered[id-1]=true end
end
assert(Host.deliver(reopened.stock,reopened.subsidy,"passenger","Company C",{source=ta.site},101,{})==101)
assert(a.awarded==nil and b_offer.awarded==nil)
assert(Host.deliver(reopened.stock,reopened.subsidy,"passenger","Company C",{source=ta.site,source_type="headquarters"},101,covered)==101)
assert(Host.deliver(reopened.stock,reopened.subsidy,"passenger","Company C",{source=ta.site},101,covered)==303)
assert(a.awarded=="Company C" and b_offer.awarded=="Company C")

-- Worker-authority wrapper: real month advances once; a compatible
-- packet consumes lazy station geometry once, a losing owner never does.
local Control=load("stock_subsidy_runtime")(Rules,Host)
local notifications={}
local function news(_,event,row) notifications[#notifications+1]={event,row.id} end
local w=reopened.stock
local account=assert(Control.mount(w,{event=news}))
draw=0
local function next_word()draw=draw+1;return assert(words[draw])end
assert(Control.month(w,1950*12+4,next_word) and draw==5)
assert(not Control.month(w,1950*12+4,function()error("Duplicate stock month consumed RNG")end))
local reads=0
local function station()
  reads=reads+1
  return {[dst_tile]=true}
end
assert(Control.pay(w,cargo,"Company D",packet,101,station)==303 and reads==1)
assert(Control.pay(w,cargo,"Company E",packet,101,station,src.chain)==101 and reads==1)
assert(account.subsidies.count==1 and notifications[1][1]=="offer" and notifications[2][1]=="awarded")
w=Codec.decode(Codec.encode(w))
Control.mount(w,{event=news})
assert(Control.entries(w)[1].awarded=="Company D")
assert(Control.pay(w,cargo,"Company D",packet,101,station,src.chain)==303 and reads==2)
assert(#notifications==2)
assert(Control.removed(w,dst.chain,dst.native)==dst.id and #Control.entries(w)==0)
assert(Control.placed(w,dst.chain,dst.native)==dst.id)
print(("PASS real generated subsidy board: %d towns, %d stock industries, %s -> %s; persistent IDs, exclusive award and closure"):format(#b.towns,#b.industries,src.firm.kind,dst.firm.kind))
