-- SPDX-License-Identifier: GPL-2.0-only
local mod="mods/luanttd_core/"
local src=mod.."openttd/"
local Sim=dofile(mod.."sim.lua")
local T=dofile(src.."rail_track.lua")
local Follow=dofile(src.."rail_follow.lua")(T)
local Lab=dofile(mod.."trackworks.lua")(Sim,T,Follow)
local Roster=dofile(src.."rail_roster.lua")
local Fleet=dofile(mod.."rail_depot_fleet.lua")(Sim,Lab,Roster)
local Owned=dofile(mod.."rail_owned_service.lua")(Fleet,Roster,{owned_passenger_engine=function(n)return n==0 end})
local function copy(x)
  if type(x)~="table" then return x end
  assert(not getmetatable(x))
  local t={}
  for k,v in pairs(x) do t[k]=copy(v) end
  return t
end
local function make(max,pool,trains)
  local s=Sim.new(1853)
  s.rail_owned_service=true
  for z=4,6 do
    local owner=z==6 and "Bob" or "Alice"
    Sim.company(s,owner)
    for x=2,5 do
      local tile=s.tiles[Sim.id(x,z)]
      tile.rail_tracks,tile.owner,tile.build=1,owner,"stock_rail"
    end
    assert(Lab.depot(s,owner,Sim.id(2,z),T.SW))
  end
  assert(Owned.initialize(s,{starting_year=1950,generation_seed=s.seed,startup_random=9001,
    max_train_tiles=max,vehicle_pool=pool,max_trains=trains}))
  return s,Sim.id(2,4),Sim.id(2,5),Sim.id(2,6)
end
local function read(s,id,unit)
  return assert(Owned.get(s,"Alice",unit.id or unit))
end
local function buy(s,id,stock)
  local q=assert(Owned.quote_part(s,"Alice",id,stock))
  local c=s.companies.Alice
  local cash,exp,mo=c.cash,c.expense,c.month_exp
  local p=assert(Owned.commit(s,"Alice",q))
  assert(c.cash==cash-q.price and c.expense==exp+q.price and c.month_exp==mo+q.price)
  local dup,why=Owned.commit(s,"Alice",q)
  assert(not dup and why=="STALE_RAIL_FLEET_QUOTE" and c.cash==cash-q.price)
  return p
end
local function move(s,id,a,b,tail)
  local _,rev=Owned.loose_wagons(s,"Alice",id)
  local cash=s.companies.Alice.cash
  local ok,why=Owned.move_wagon(s,"Alice",id,a,b,tail,rev)
  assert(s.companies.Alice.cash==cash)
  return ok,why,rev
end
local s,d,other,foreign=make()
local a,b=buy(s,d,27),buy(s,d,27)
local c=buy(s,d,29)
assert(a.kind=="wagon" and a.body_id~=b.body_id and b.body_id~=c.body_id and not a.coupled_to)
local free=Owned.loose_wagons(s,"Alice",d)
assert(#free==2 and #free[1].parts==2 and free[1].id==a.body_id and free[1].parts[2].body_id==b.body_id)
assert(#Owned.list(s,"Alice",d)==0 and Owned.occupies_depot(s,d))
assert(not Owned.quote_part(s,"Alice",foreign,27))
s=copy(s)
local train=buy(s,d,0)
assert(train.unit_number==1 and #Owned.loose_wagons(s,"Alice",d)==0)
assert(table.concat(train.stock_ids,",")=="0,29,27,27" and train.parts[2].body_id==c.body_id)
assert(train.parts[3].body_id==a.body_id and train.parts[4].body_id==b.body_id)
local only=train.parts[1].body_id
local ok,why,prior=move(s,d,c.body_id,nil,false)
assert(ok and why=="WAGON_MOVED")
assert(#Owned.loose_wagons(s,"Alice",d)==1 and table.concat(read(s,d,train).stock_ids,",")=="0,27,27")
assert(Fleet.prepare_dispatch(s,"Alice",train.id).stats.cargo_capacity.passenger==80)
local stale,err=Owned.move_wagon(s,"Alice",d,c.body_id,only,false,prior)
assert(not stale and err=="STALE_RAIL_FLEET_QUOTE")
local invisible,denied=move(s,other,c.body_id,nil,false)
assert(not invisible and denied=="SELECT_DEPOT_WAGON")
assert(move(s,d,b.body_id,only,false))
assert(read(s,d,train).parts[2].body_id==b.body_id)
assert(move(s,d,b.body_id,nil,true))
assert(#read(s,d,train).parts==1)
local coaches
for _,row in ipairs(Owned.loose_wagons(s,"Alice",d)) do
  if #row.parts==2 then coaches=row end
end
assert(coaches and coaches.parts[1].body_id==b.body_id and coaches.parts[2].body_id==a.body_id)
assert(move(s,d,b.body_id,only,true))
assert(read(s,d,train).parts[2].body_id==b.body_id and read(s,d,train).parts[3].body_id==a.body_id)
-- The only stopped engine gets JUST the newly purchased wagon, even
-- though the stock free-row phase puts it into the earlier coal row.
local new=buy(s,d,29)
assert(new.coupled_to==train.unit_number and read(s,d,train).parts[4].body_id==new.body_id)
free=Owned.loose_wagons(s,"Alice",d)
assert(#free==1 and #free[1].parts==1 and free[1].parts[1].body_id==c.body_id)
local second=buy(s,d,0)
assert(second.unit_number==2 and second.parts[2].body_id==c.body_id)
local unassigned=buy(s,d,27)
assert(not unassigned.coupled_to and #Owned.loose_wagons(s,"Alice",d)==1)
assert(Fleet.bind_dispatch(s,"Alice",train.id,train.id))
local blocked,reason=move(s,d,b.body_id,second.parts[1].body_id,false)
assert(not blocked and reason=="SELECT_DEPOT_WAGON")
blocked,reason=move(s,d,unassigned.body_id,only,false)
assert(not blocked and reason=="SELECT_DEPOT_DESTINATION")
-- Physical pool counts loose cars, but unlimited wagon purchases don't
-- consume an engine/unit number. Failed automatic moves keep a paid loose row.
s,d=make(1,5,1)
local limited=buy(s,d,0)
buy(s,d,27)
local too_long=buy(s,d,27)
assert(not too_long.coupled_to and #Owned.loose_wagons(s,"Alice",d)==1)
blocked,reason=move(s,d,too_long.body_id,limited.parts[1].body_id,false)
assert(not blocked and reason=="TRAIN_TOO_LONG")
assert(#read(s,d,limited).parts==2)
buy(s,d,27);buy(s,d,29)
assert(#Owned.loose_wagons(s,"Alice",d)==2)
blocked,reason=Owned.quote_part(s,"Alice",d,27)
assert(not blocked and reason=="TOO_MANY_VEHICLES_IN_GAME")
-- GUI uses the same authority and charges once, then discards old action keys.
s,d=make()
local shown,fields,saves
saves=0
core={formspec_escape=function(x)return x:gsub(",", "\\,")end,
  register_on_player_receive_fields=function(f)fields=f end,
  register_on_leaveplayer=function()end,close_formspec=function()end,
  show_formspec=function(_,k,form)shown=form end}
local p={get_player_name=function()return "Alice" end}
local api={s=s,Sim=Sim,rail_owned=Owned,save=function()saves=saves+1 end}
local UI=dofile(mod.."rail_owned_ui.lua")(api,function()end)
local function submit(key,values)
  local f=values or {};f[key]=true
  assert(fields(p,"luanttd_core:rail_fleet",f))
end
local function key(k) local found=assert(shown:match("(assembly_%d+_"..k..");"),k);return found end
assert(UI.open(p,d))
submit("assemble")
assert(shown:find("Separate purchases and wagon assembly",1,true))
local first_cash=s.companies.Alice.cash
submit(key("pick_wagon"))
local wagon=key("pick_row1")
assert(shown:find("tooltip["..wagon..";",1,true))
submit(wagon)
assert(saves==0 and s.companies.Alice.cash==first_cash)
local old=key("buy_wagon")
submit(old)
assert(saves==1 and shown:find("Stored loose.",1,true) and s.companies.Alice.cash<first_cash)
submit(old)
assert(saves==1)
submit(key("buy_engine"))
assert(saves==2 and #Owned.list(s,"Alice",d)==1 and #Owned.loose_wagons(s,"Alice",d)==0)
submit(key("buy_wagon"))
assert(saves==3 and #Owned.list(s,"Alice",d)[1].parts==3 and shown:find("Coupled to train 1",1,true))
submit(key("pick_body"))
submit(key("pick_row2"))
submit(key("loose"),{[key("tail")]="false"})
assert(saves==4 and #Owned.loose_wagons(s,"Alice",d)==1 and #Owned.list(s,"Alice",d)[1].parts==2)
print("PASS RC1 separate depot purchases, stock autoattachment, individual/chain moves, exact cash and ownership, save restore, and stock depot forms")
local escrow
api.authority_handoff=true
api.worker_rail_assembly={query=function(q,done)
  assert(not escrow)
  escrow={q,done}
  return true
end}
local function respond(kind,value)
  local q,f=unpack(assert(escrow));escrow=nil
  assert(q.kind==kind and q.player=="Alice")
  f(value)
  return q
end
local balance=s.companies.Alice.cash
assert(UI.assemble(p,d) and shown:find("Reading your rail depot",1,true))
local DTO={token=49,depot=d,revision=11,engines={{id=0,name="Locomotive",quote={price=6120}}},
  wagons={{id=27,name="Passenger car",quote={price=1421}}},bodies={},destinations={},units={}}
respond("rail_assembly",{ok=true,value=DTO,revision=22})
assert(shown:find("Separate purchases and wagon assembly",1,true))
local click=key("buy_wagon")
submit(click);submit(click)
local q=respond("command",{ok=true,why="Worker purchased the coach."})
assert(q.command.kind=="rail_assembly" and q.command.operation=="wagon"
  and q.command.stock==27 and q.command.token==49 and q.command.revision==22)
respond("rail_assembly",{ok=true,value=DTO,revision=23})
assert(shown:find("Worker purchased the coach.",1,true) and balance==s.companies.Alice.cash and saves==4)
print("PASS worker-backed depot assembly uses the same native form without changing the host ledger")
