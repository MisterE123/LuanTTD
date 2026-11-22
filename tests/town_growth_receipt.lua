-- Actual native service, stock TownTick and landscape house writer;
-- only the fixture substitutes the landscape walker and adds receipts.
local p="mods/bayline/"
local function m(n) return dofile(p..n..".lua") end
local H,T,G=m("openttd/town_passengers"),m("openttd/terrain"),m("openttd/town_growth")
local IA=m("openttd/landscape_index")
local DA=m("openttd/landscape_dynamic")(IA)
local A=m("openttd/landscape_authority")
local Receipt=m("openttd/town_growth_receipt")(A)
local B=m("openttd/town_growth_build")(G,m("openttd/town_growth_houses"))
local fixture=dofile("tests/town_growth_live_fixture.lua")
local slicer
local substituted={}
for k,v in pairs(H) do substituted[k]=v end
function substituted.advance_houses(c,ticks,house,settings,rnd,emit,before,land)
  if not slicer then return H.advance_houses(c,ticks,house,settings,rnd,emit,before,land) end
  assert(ticks==1 and slicer.s.passenger_house_clock==c)
  slicer.calls=slicer.calls+slicer.D.advance(c,1,function(id,tick,slot,x,z)
    if land then land(x,z,tick) end
    local row=house(x,z)
    if row then H.produce_tile(id,tick,row,settings,rnd,function(name,n) emit(name,n,x,z,row,tick) end) end
    local new=slicer.created[id+1]
    if new and not new.visit then new.visit,new.slot=tick,slot;assert(tick>new.built) end
  end,before)
end
local loaded=assert(loadfile(p.."sim.lua"))
setfenv(loaded,setmetatable({dofile=function(path)
  if path:match("openttd/town_passengers%.lua$") then return substituted end
  return dofile(path)
end},{__index=_G}))
local Sim=loaded()
local Native=m("town_growth_runtime")(Sim,T,G,B,H)

local function eq(a,b,n) assert(a==b,(n or "")..": "..tostring(a).." != "..tostring(b)) end
local function cp(t,seen)
  if type(t)~="table" then return t end
  seen=seen or {}
  if seen[t] then return seen[t] end
  local out={};seen[t]=out
  for k,v in pairs(t) do out[k]=cp(v,seen) end
  return out
end
local function same(a,b,n,seen)
  n=n or ""
  eq(type(a),type(b),n)
  if type(a)~="table" then eq(a,b,n);return end
  seen=seen or {};if seen[a]==b then return end;seen[a]=b
  for k,v in pairs(a) do same(v,b[k],n.."/"..k,seen) end
  for k in pairs(b) do assert(a[k]~=nil,n.."/"..k) end
end
local function bigger()
  -- Preserve the existing authored service fixture and original town-road
  -- layout; place it in a real 128-square landscape/corner lattice.
  -- This does not claim a new source-generated region.
  local s=Sim.new(1751)
  local sx,sz=Sim.W,Sim.H
  m("town_layout")(Sim,s)
  local old=s.tiles
  Sim.W,Sim.H=128,128
  for _,site in ipairs(s.sites) do
    local x,z=(site.tile-1)%sx+1,math.floor((site.tile-1)/sx)+1
    site.tile=Sim.id(x,z)
  end
  s.tiles={}
  for z=1,Sim.H do for x=1,Sim.W do
    s.tiles[Sim.id(x,z)]=(x<=sx and z<=sz and old[(z-1)*sx+x]) or {terrain="hill",h=2,variant=0}
  end end
  s.corner_grid=m("terrain_preview")(Sim,T,s)
  s.road_stock_loading,s.road_stock_clock,s.road_stock_house_supply,s.road_economy=true,true,true,true
  s.passenger_house_clock=H.new_clock(7,7,6090)
  s.changed={7,999,7,15840}
  Sim.mount_stock_town_growth(s,Native,true)
  local q=fixture.prepare(Sim,s)
  assert(Sim.toggle(s,"GrowthQA",q.id))
  return s,q
end

local function next_visit(c,id)
  local local_clock=cp(c)
  local first
  H.advance(local_clock,256,function(k,tick)
    if k+1==id and not first then first=tick end
  end)
  return assert(first)
end
local function mount(s,created)
  local D=DA.new(7,7)
  for id,t in ipairs(s.tiles) do if t.house then D.set(id-1,true) end end
  local O=A.new({world="wide-town",log_x=7,log_z=7,width=128,depth=128},D,function(id,x,z,host)
    eq(id+1,host);return s.tiles[host].house==true
  end)
  local apply=Receipt.bind(s,"wide-town",O)
  local adapter={}
  for k,v in pairs(Native) do adapter[k]=v end
  function adapter.tick(state,tick,random)
    local draws=0
    return Native.tick(state,tick,function()
      draws=draws+1
      return random()
    end,function(st,f,write)
      assert(draws>0,"Native house candidate did not use actual stock draws")
      eq(created[f.tile],nil)
      eq(D.contains(f.tile-1),false)
      eq(s.passenger_house_clock.counter,tick)
      local quoted_tick=next_visit(s.passenger_house_clock,f.tile)
      eq(apply(st,f,write),true)
      assert(D.contains(f.tile-1))
      local vehicle=s.fleet[1]
      created[f.tile]={built=tick,next_slot=quoted_tick,draws=draws,board=vehicle and vehicle.last_board and vehicle.last_board.tick,
        fare=vehicle and vehicle.last_fare and vehicle.last_fare.tick,
        reason=s.stock_town_growth.towns[f.town].reason}
      return true
    end)
  end
  Sim.mount_stock_town_growth(s,adapter,true)
  return {s=s,D=D,O=O,calls=0,created=created}
end

local slow,qa=bigger()
local fast=cp(slow)
local tracked={}
local sparse=mount(fast,tracked)
local qualify,h,failed_input
local old_done=false
for day=1,220 do
  local before_first
  if not qualify then before_first=cp(slow) end
  Sim.daily(slow)
  slicer=sparse
  Sim.daily(fast)
  slicer=nil
  same(slow,fast)
  if not qualify then
    for id,r in pairs(tracked) do
      if fast.tiles[id].source_house.town==qa.town then
        qualify=id
        failed_input=before_first
        h=fast.tiles[id].source_house
        assert(r.board and r.board<h.built_tick and r.reason=="serviced", tostring(r.board).."/"..tostring(r.fare).."/"..r.reason)
        assert(h.stage==0 and h.counter==0 and not h.completed and not h.first_cargo_tick,
          "Fixture needs a completed tick boundary before the first landscape visit to the new house")
        assert(r.next_slot>fast.passenger_house_clock.counter and not r.visit)
        break
      end
    end
  elseif not old_done and tracked[qualify].visit then
    local r=tracked[qualify]
    eq(r.visit,r.next_slot);assert(r.slot>=0)
    eq(h.counter,1);eq(h.stage,0);assert(not h.completed and not h.first_cargo_tick)
    -- Simulate a save/reload after the exact first construction slot.
    local cursor=cp(fast.passenger_house_clock)
    fast,slow=cp(fast),cp(slow)
    Sim.mount_stock_town_growth(slow,Native,true)
    sparse=mount(fast,tracked)
    same(cursor,fast.passenger_house_clock)
    h=fast.tiles[qualify].source_house
    old_done=true
  elseif old_done and h.first_cargo_tick then
    assert(h.completed and h.completed_tick<h.first_cargo_tick)
    assert(h.completed_tick-h.built_tick>11*256 and h.completed_tick-h.built_tick<=12*256)
    assert(fast.stock_town_growth.towns[qa.town].population>=H.specs[h.id][1])
    break
  end
end
assert(qualify and h.first_cargo_tick and old_done and failed_input and fast.fleet[qa.id].last_fare)
local r=tracked[qualify]
print(("128² live bus-backed house %d (type %d): built after tick %d; first physical slot tick %d/slot %d; complete %d, first cargo %d; carried head and RNG match dense state")
 :format(qualify,h.id,r.built,r.visit,r.slot,h.completed_tick,h.first_cargo_tick))

-- Run the same real day with an unreviewed provider. We must stop after
-- exact candidate RNG, before touching the selected tile/town house count.
do
  local w=failed_input
  local S=DA.new(7,7)
  for id,t in ipairs(w.tiles) do if t.house then S.set(id-1,true) end end
  local O=A.new({world="wide-town",log_x=7,log_z=7,width=128,depth=128},S,function(id,x,z,host)
    return w.tiles[host].house==true
  end)
  local wanted=false
  local apply=Receipt.bind(w,"wide-town",O,function() return true end)
  local adapter={}
  for k,v in pairs(Native) do adapter[k]=v end
  function adapter.tick(st,tick,random)
    local draws=0
    return Native.tick(st,tick,function()
      draws=draws+1
      return random()
    end,function(state,f,write)
      assert(draws>0)
      eq(f.tile,qualify)
      local n=w.stock_town_growth.towns[f.town].num_houses
      local tile=cp(w.tiles[f.tile])
      local before=cp(w.passenger_rating_rng)
      local invoked=false
      local ok,reason=pcall(apply,state,f,function() invoked=true;return write() end)
      assert(not ok and reason:match("Unreviewed native growth substrate") and not invoked)
      same(tile,w.tiles[f.tile]);same(before,w.passenger_rating_rng)
      eq(n,w.stock_town_growth.towns[f.town].num_houses)
      assert(not S.contains(f.tile-1))
      eq(O.revision(),0);wanted=true
      error("No whole-tick retry after native plan RNG")
    end)
  end
  Sim.mount_stock_town_growth(w,adapter,true)
  local ok,reason=pcall(Sim.daily,w)
  assert(not ok and wanted and reason:match("No whole%-tick retry"))
end
print("Rejected unreviewed writer before any tile, membership, or house-count write; no retry after source candidate RNG")
