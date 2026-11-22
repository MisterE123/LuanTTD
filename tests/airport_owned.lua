local root="mods/bayline/"
local src=root.."openttd/"
local Sim=dofile(root.."sim.lua")
local T=dofile(src.."terrain.lua")
local Small=dofile(src.."airport_small.lua")
local Motion=dofile(src.."airport_motion.lua")(Small)
local Net=dofile(root.."airport_network.lua")(Sim,T,Small)
local Cat=dofile(src.."airport_roster.lua")
local Run=dofile(root.."airport_preview_run.lua")(Sim,Net,Small,Motion,T,nil,Cat)
local good_art=true
local Owned=dofile(root.."airport_owned.lua")(Sim,Run,Cat,function(m)return good_art and (m==215 or m==216 or m==219) end)
local quote=assert(Cat.quote(215))
assert(quote.price==38281 and quote.annual_fp==816000 and quote.passengers==25)
quote=assert(Cat.quote(216))
assert(quote.price==41015 and quote.annual_fp==960000 and quote.passengers==65 and quote.mail==8)
assert(Cat.day_charge(960000,74)==2630 and Cat.day_charge(816000,74)==2235)
quote=assert(Cat.quote(219))
assert(quote.price==41015 and quote.annual_fp==940800 and quote.passengers==30 and quote.mail==6)
assert(Cat.day_charge(quote.annual_fp,74)==2577)
local function world()
  local s=Sim.new(1751)
  s.corner_grid=T.new(Sim.W,Sim.H,function()return 0 end)
  for _,t in ipairs(s.tiles) do
    t.terrain="grass";t.wood=nil;t.house=nil;t.site=nil;t.build=nil;t.owner=nil
  end
  s.air_owned_preview,s.air_paid_service,s.road_stock_house_supply=true,true,true
  return s,assert(Net.build(s,"A",Sim.id(6,6))),assert(Net.build(s,"A",Sim.id(31,20)))
end
local function copy(t)
  if type(t)~="table" then return t end
  local out={}
  for k,v in pairs(t) do out[k]=copy(v) end
  return out
end
for _,code in ipairs({215,216,219}) do
  local s,a,b=world()
  local cash=Sim.company(s,"A").cash
  assert(not Owned.quote(s,"B",a.id,code))
  assert(not Run.start(s,"A",a.id,b.id) and not Owned.start(s,"A",a.id,b.id))
  good_art=false;assert(not Owned.quote(s,"A",a.id,code));good_art=true
  local q=assert(Owned.quote(s,"A",a.id,code))
  local old=copy(q);old.price=old.price+1
  assert(not Owned.commit(s,"A",old) and Sim.company(s,"A").cash==cash)
  local c=Sim.company(s,"A")
  c.cash=q.price-1
  assert(not Owned.commit(s,"A",q) and not Owned.status(s));c.cash=cash
  local unit=assert(Owned.commit(s,"A",q))
  assert(unit.stock_id==code and unit.hangar==a.id and c.cash==cash-q.price)
  assert(not Owned.commit(s,"A",q) and Owned.owns_hangar(s,a.id))
  assert(not Owned.start(s,"A",b.id,a.id))
  s=copy(s);c=Sim.company(s,"A")
  s.air_paid_service=false
  local unavailable,why=Owned.start(s,"A",a.id,b.id)
  assert(not unavailable and why=="PURCHASED_AIRCRAFT_DISABLED" and Owned.status(s).status=="hangar")
  s.air_paid_service=true
  local p=assert(Owned.start(s,"A",a.id,b.id))
  assert(Owned.status(s).status=="dispatched" and p.engine_id==code)
  assert(not Run.clear(s,"A"))
  local callbacks={leave=function()return false end,arrive=function()return true end}
  for _=1,74 do Run.advance_paid(s,callbacks) end
  assert(p.finance.ticks==74)
  p.vehicle.stopped=true
  Run.advance_paid(s,callbacks)
  assert(p.finance.ticks==74)
  p.vehicle.stopped=false
  c.stock_money_fraction=112
  local expected=Cat.day_charge(q.annual_fp,74)
  local debit=-math.floor((112-expected)/256)
  local before=c.cash
  Run.settle_owned_day(s,p)
  assert(c.cash==before-debit and c.stock_money_fraction==(112-expected)%256 and p.finance.expense==debit)
  s=copy(s);p=Run.current(s);c=Sim.company(s,"A")
  Run.settle_owned_day(s,p)
  assert(p.finance.charged_ticks==74 and c.cash==before-debit,"Reload recharged already-settled stock ticks")
  local seen=0
  for _=1,6000 do
    Run.advance_paid(s,callbacks,function(ev)if ev=="terminal" then seen=seen+1 end end)
    assert(not p.failure,p.failure)
    if seen>0 then break end
  end
  assert(seen==1 and p.last_airfield==b.id)
end
local solo,a,b=world()
solo.air_fleet_preview=true
local bakewell=assert(Owned.commit(solo,"A",assert(Owned.quote(solo,"A",a.id,219))))
assert(bakewell.serial and not Owned.quote(solo,"A",b.id,215))
assert(Owned.start(solo,"A",a.id,b.id).engine_id==219)
local twins,c,d=world()
twins.air_fleet_preview=true
assert(Owned.commit(twins,"A",assert(Owned.quote(twins,"A",c.id,215))))
assert(not Owned.quote(twins,"A",d.id,219) and Owned.quote(twins,"A",d.id,215))
print("PASS: three original aircraft, balances and failed preflight, hangar save, 74 exact running ticks, no duplicate charge, stock terminal")
