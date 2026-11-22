local H=dofile("mods/luanttd_core/openttd/town_passengers.lua")
local function same(a,b) assert(a==b,("%.17g != %.17g"):format(a,b)) end
assert(H.specs[0x06][1]==30 and H.specs[0x06][2]==12)
assert(H.specs[0x07][1]==140 and H.specs[0x08][1]==0 and H.specs[0x08][2]==22)
assert(H.specs[0x07][7]==1 and H.specs[0x07][8]==2 and H.specs[0x08][7]==0)
assert(H.specs[0x6D] and not H.specs[0x6E])
assert(H.single_tile_catchment(3,-3,H.bus_catchment))
assert(not H.single_tile_catchment(4,0,H.bus_catchment))
assert(H.single_tile_catchment(4,4,H.unmodified_catchment))
same(H.original(30,29,1,1),4)
same(H.original(30,30,1,1),0)
same(H.binominal(30,0xFF,1,1),4)
same(H.binominal(250,0xFFFFFFFF,1,1),32)

local function visits(lx,lz)
  local K=H.new_clock(lx,lz)
  local n,seen,before=0,{},0
  H.advance(K,256,function(tile,tick)
    same(tick,before)
    if tile==0 then same(tick,256) end
    assert(not seen[tile] and tile>=0 and tile<2^(lx+lz))
    seen[tile]=true;n=n+1
  end,function(tick) before=tick end)
  same(n,2^(lx+lz));same(K.head,1);same(K.counter,256)
end
visits(6,6)
visits(7,6)
visits(6,7)

local function rolls(list)
  local count=0
  local function random()
    count=count+1
    local v=list[count]
    assert(v~=nil,"Unexpected RNG call")
    return v
  end
  return random,function() return count end
end

local r,draw=rolls({23,0xFFFFFFFF,0xFFFFFFFF})
local output={}
local function emit(kind,n) output[#output+1]=kind..":"..n end
same(H.produce_tile(1,256,{id=0x06,completed=true},{},r,emit),23)
same(draw(),3)
assert(output[1]=="passenger:4" and output[2]=="mail:2")
output={}
r,draw=rolls({99})
same(H.produce_tile(1,512,{id=0x06,completed=true},{},r,emit),99)
same(draw(),1);same(#output,0)
r,draw=rolls({})
assert(not H.produce_tile(1,256,{id=0x06,completed=false},{},r,emit))
same(draw(),0)
r,draw=rolls({0,888,0xFFFFFFFF,0xFFFFFFFF})
local started=0
same(H.produce_tile(1,256,{id=0x04,completed=true},{
  start_lift=function() started=started+1 end},r,emit),888)
same(draw(),4);same(started,1)
-- The secondary tile of a stock hotel produces only mail, not fake
-- duplicate population. Recession and scale draw rounding are applied.
output={}
r,draw=rolls({77,0,0x3F,65535})
same(H.produce_tile(1,256,{id=0x08,completed=true},{recession=true,percentage=25},r,emit),77)
same(draw(),4)
assert(#output==1 and output[1]=="mail:0")
r,draw=rolls({77,0,0x3F,0})
output={}
H.produce_tile(1,256,{id=0x08,completed=true},{recession=true,percentage=25},r,emit)
assert(#output==1 and output[1]=="mail:1")

-- Actual schedules depend on stock binary coordinates. Different houses
-- produce on different subcycles; batching and copying clock state on save
-- cannot change callback positions, tick order, or RNG.
local function trace(batch,reload)
  local K=H.new_clock(6,6)
  local log,rng={},0
  local houses={[5]={id=0x06,completed=true,town=1},
                [6]={id=0x19,completed=true,town=2},
                [67]={id=0x0B,completed=true,town=2},
                [70]={id=0x14,completed=false,town=2}}
  local function random()
    rng=rng+1
    return 0xFFFFFFFF
  end
  for n=1,1024/batch do
    H.advance_houses(K,batch,function(x,z) return houses[z*64+x] end,{},random,
      function(kind,amount,x,z,house,tick)
        log[#log+1]=table.concat({kind,amount,x,z,house.town,tick},":")
      end)
    if reload and n==2 then K=H.new_clock(K.log_x,K.log_y,K.head,K.counter) end
  end
  same(rng,18) -- 3 completed houses * 4 unconditional draws + 3 * 2 cargo draws
  return table.concat(log,"|")
end
local got=trace(1024)
assert(got~="" and got==trace(128,true))
print("PASS: exact stock house rates, default subcycle, recession/scale, completion, lift draws, map coverage and saved cadence")
