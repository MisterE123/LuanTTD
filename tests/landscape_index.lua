-- Pinned landscape compatibility and sparse replay, no live mounting.
local path="mods/bayline/openttd/"
local function m(n) return dofile(path..n..".lua") end
local H=m("town_passengers")
local J=m("landscape_index")
local Random=m("terragenesis")(m("slope"))
local function eq(a,b) assert(a==b,tostring(a).." != "..tostring(b)) end
local function same(a,b)
  for _,k in ipairs{"head","counter","log_x","log_y"} do eq(a[k],b[k]) end
end

local pairs_checked,stock_records=0,0
-- Compare every stock exponent pair, different absolute counter positions
-- and the zero exception. Only a handful of far-region IDs are active.
for lx=6,12 do for lz=6,12 do
  local I=J.new(lx,lz)
  local area=2^(lx+lz)
  local width=2^lx
  local head=math.floor(area*.61)+lx
  local cycle=math.floor((lx*127+lz*31)/5)
  local start=H.new_clock(lx,lz,head,256*cycle-2)
  local stock=H.new_clock(lx,lz,head,start.counter)
  local ids,seen={},{}
  local function add(id)
    if not seen[id] then seen[id]=true;ids[#ids+1]=id end
  end
  add(0);add(1);add(area-1);add(head)
  local trace,last,slot={},nil,0
  local taken={ [0]=true,[4]=true,[10]=true,[15]=true }
  H.advance_houses(stock,4,function(x,z)
    eq(x>=0 and x<width and z>=0 and z<2^lz,true)
  end,{},function() error("Unscheduled house RNG") end,function() error("Unscheduled cargo") end,nil,
  function(x,z,t)
    local tile=x+z*width
    if last~=t then slot,last=0,t end
    if taken[slot] or slot==I.tiles_per_tick-1 then add(tile) end
    -- Capture tuples once the active coverage above becomes known.
    if seen[tile] then trace[#trace+1]={tile,t,slot,x,z} end
    slot=slot+1
    stock_records=stock_records+1
  end)
  -- A window of 4 stock ticks cannot revisit a nonzero tile.
  local compiled=I.compile(ids)
  local it,final=I.window(start,4,compiled)
  same(final,stock);same(I.skip(start,4),stock)
  local index=0
  for tile,t,q,x,z in it do
    index=index+1
    local r=assert(trace[index])
    eq(tile,r[1]);eq(t,r[2]);eq(q,r[3]);eq(x,r[4]);eq(z,r[5])
    if tile~=0 then
      eq(I.at(I.index(tile)),tile)
      eq(I.step(I.unstep(tile)),tile);eq(I.unstep(I.step(tile)),tile)
    else eq(t%256,0);eq(q,0) end
  end
  eq(index,#trace)
  -- Stock time can also be resumed after applying the first half.
  local function replay()
    local c=H.new_clock(lx,lz,head,start.counter)
    local got={}
    local function record(tile,t,slot)
      got[#got+1]=tile..":"..t..":"..slot
    end
    I.advance_active(c,2,compiled,record)
    I.advance_active(c,2,compiled,record)
    same(c,stock)
    eq(#got,#trace)
    for n,r in ipairs(trace) do eq(got[n],r[1]..":"..r[2]..":"..r[3]) end
  end
  replay()
  assert(I.stats().baby_steps<=4096 and I.stats().jump_columns<=1152)
  pairs_checked=pairs_checked+1
end end

-- Exact absolute rank against full canonical stock traversal and reverse
-- steps. Verify dense brief rank coverage at 128² without a production rank table.
local A=J.new(7,7)
local head1=H.new_clock(7,7,1,0)
local covered,zero=0,0
H.advance(head1,256,function(tile)
  if tile==0 then zero=zero+1;return end
  if covered%53==0 or covered==A.period-1 then
    eq(A.index(tile),covered);eq(A.at(covered),tile)
  end
  covered=covered+1
end)
eq(covered,A.period);eq(zero,1);eq(head1.head,1)

-- Resume both full and active modes from a wide carried river-like head.
-- Live coastal/industrial side effects may use the same stream; skipped
-- cells here are proven no-ops. Stock housing production, lift decisions,
-- cargo, and per-tick callbacks retain relative order across resumes.
local function economic_replay(mode,sparse)
  local idx=J.new(7,6)
  local c=H.new_clock(7,6,6090,253)
  local ids={0,1,6090,8191,45,456,2341,6488,7011}
  local compiled=idx.compile(ids)
  local houses={}
  for i,t in ipairs(ids) do
    houses[t]={id=i%2==0 and 0x1e or 0x19,completed=true,town=i}
  end
  local prng={1751,1751}
  local logs,draws,effects={},0,0
  local function push(...) logs[#logs+1]=table.concat({...},":") end
  local function random()
    draws=draws+1
    return Random.next_random(prng)
  end
  local settings={mode=mode,percentage=75,start_lift=function(h)
    h.lift_has_destination=true
    push("lift",h.town)
  end}
  local function emit(cargo,amount,x,z,house,tick)
    push(cargo,amount,x,z,house.town,tick)
  end
  local function day_tick(tick)
    if tick%13==0 then push("tick",tick,random()) end
  end
  local function effect(x,z,tick)
    local tile=x+z*128
    if houses[tile] then effects=effects+1;push("land",tile,tick,random()) end
  end
  for _,n in ipairs{2,0,1,255,511,7,2} do
    if sparse then
      idx.advance_active(c,n,compiled,function(tile,tick,slot,x,z)
        effect(x,z,tick)
        H.produce_tile(tile,tick,houses[tile],settings,random,function(cargo,amount)
          emit(cargo,amount,x,z,houses[tile],tick)
        end)
      end,day_tick)
    else
      H.advance_houses(c,n,function(x,z)return houses[x+z*128] end,
        settings,random,emit,day_tick,effect)
    end
  end
  return logs,c,prng,draws,effects
end
for _,mode in ipairs{"bitcount","original"} do
  local a,b,c,d,e=economic_replay(mode,false)
  local j,k,l,m,n=economic_replay(mode,true)
  eq(#a,#j);for i=1,#a do eq(a[i],j[i]) end
  same(b,k);eq(c[1],l[1]);eq(c[2],l[2]);eq(d,m);eq(e,n)
  assert(d>40 and e>20 and #a>e)
end

-- Zero-only windows, multiple periods, tests near the safe-integer edge.
local limit=9007199254740991
local A=J.new(12,12)
local empty=A.compile({})
local zeros=A.compile({0})
local last=H.new_clock(12,12,67890,limit-J.MAX_TICKS)
local whole,count=A.skip(last,J.MAX_TICKS)
local q=A.skip(last,J.MAX_TICKS-98765)
same(whole,A.skip(q,98765));eq(whole.counter,limit)
eq(count,J.MAX_TICKS*65536-(math.floor(limit/256)-math.floor(last.counter/256)))
local it,next_c=A.window(last,J.MAX_TICKS,empty)
assert(it()==nil);same(whole,next_c)
it,next_c=A.window(last,J.MAX_TICKS,zeros)
for j=1,5 do
  local tile,tick,slot=it()
  eq(tile,0);eq(slot,0);eq(tick,(math.floor(last.counter/256)+j)*256)
end
same(whole,next_c)
eq(A.jump(A.jump(67890,limit),-limit),67890)
local first=H.new_clock(12,12,67999,255)
local out=A.window(first,1,A.compile({0,67999}))
local t,v,slot=out();eq(t,0);eq(v,256);eq(slot,0)
t,v,slot=out();eq(t,67999);eq(v,256);eq(slot,1)
eq(out(),nil)
assert(not pcall(A.jump,0,10) and not pcall(A.index,0))
assert(not pcall(A.compile,{1,1}) and not pcall(A.compile,{[2]=100}))
assert(not pcall(A.skip,last,J.MAX_TICKS+1))
assert(not pcall(A.window,last,1,J.new(12,12).compile({1})))
assert(not pcall(A.skip,H.new_clock(11,12),1))
-- Reconcile at an owner boundary. Previous compiled membership and
-- detached iterators remain unchanged; only genuinely new IDs are ranked.
local queued=A.compile({0,67999})
local published=A.window(first,1,queued)
local next_set=A.compile({A.step(67999),67999},queued)
local revised=A.window(first,1,next_set)
local tile_id,tick,ord=revised()
eq(tile_id,67999);eq(tick,256);eq(ord,1)
tile_id,tick,ord=revised()
eq(tile_id,A.step(67999));eq(tick,256);eq(ord,2)
eq(revised(),nil)
eq(published(),0);eq(published(),67999);eq(published(),nil)
assert(not pcall(A.compile,{1},J.new(12,12).compile({1})))
print(("LANDSCAPE INDEX PASS: %d square/rectangular stock strides, %d direct stock visits, full rank sampling, zero slot, cargo/RNG exact after resume")
  :format(pairs_checked,stock_records))
