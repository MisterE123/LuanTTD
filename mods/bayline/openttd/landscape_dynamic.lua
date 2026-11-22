-- SPDX-License-Identifier: GPL-2.0-only
-- Detached sparse owner-side scheduler for OpenTTD 14.1 RunTileLoop.
-- Uses the stock landscape_index for cycle ranks and jumps. This is not
-- mounted by the game; the owner must report every membership mutation.
return function(Index)
  local M={}
  local floor,max,min=math.floor,math.max,math.min
  local function uint(x) return type(x)=="number" and x>=0 and x==floor(x) end
  local function less(a,b)
    return a.tick<b.tick or a.tick==b.tick and a.slot<b.slot
  end
  function M.new(log_x,log_z)
    local X=Index.new(log_x,log_z)
    local width,period,stride=2^log_x,X.period,X.tiles_per_tick
    local active,count={},0
    local limit=min(period+1,Index.MAX_ACTIVE)
    local work,head_hint,rank_hint
    local D={index=X}
    local function place(heap,i,q)
      heap[i],q.heap_index=q,i
    end
    local function balance(heap,i,q)
      local p=floor(i/2)
      if i>1 and less(q,heap[p]) then
        repeat
          place(heap,i,heap[p]);i,p=p,floor(p/2)
        until i==1 or not less(q,heap[p])
      else
        local c=2*i
        while c<=#heap do
          if c<#heap and less(heap[c+1],heap[c]) then c=c+1 end
          if not less(heap[c],q) then break end
          place(heap,i,heap[c]);i,c=c,2*c
        end
      end
      place(heap,i,q)
    end
    local function take(heap,i)
      local q,tail=heap[i],heap[#heap]
      heap[#heap]=nil
      if q~=tail then balance(heap,i,tail) end
      q.heap_index=nil
      return q
    end
    local function enqueue(q)
      if q.tick<=work.stop then
        local heap=work.heap
        balance(heap,#heap+1,q)
        work.high=max(work.high,#heap)
      end
    end
    local function schedule(q)
      -- With a full stock cycle every 256 ticks, each tile keeps the
      -- same tick phase and intra-tick slot relative to this start.
      local start=work.start
      local phase,slot
      if q.tile==0 then
        phase,slot=256-start%256,0
      else
        local offset=(q.rank-work.head_rank)%period
        local lo=floor(offset/stride)+1
        local tick_mod=(start%256+lo)%256
        local prefix=lo*stride-floor((start%256+lo)/256)
        if prefix<=offset then
          lo,tick_mod=lo+1,(tick_mod+1)%256
          prefix=prefix+stride-(tick_mod==0 and 1 or 0)
        end
        phase,slot=lo,offset-prefix+stride
      end
      -- No overflow near the exact-number limit; count the only
      -- possible past cycles relative to the *delta*, not absolute time.
      local current=work.elapsed
      if phase<current then phase=phase+256*floor((current-phase+255)/256) end
      if phase==current and slot<=work.slot then phase=phase+256 end
      if phase<=work.ticks then
        q.tick,q.slot=start+phase,slot
        enqueue(q)
      end
    end
    function D.set(tile,on)
      assert(uint(tile) and tile<=period and type(on)=="boolean","Invalid landscape membership")
      local old=active[tile]
      if on then
        if old then return false end
        assert(count<limit,"Dynamic active landscape ceiling exceeded")
        local q={tile=tile,rank=tile~=0 and X.index(tile) or nil}
        active[tile],count=q,count+1
        if work then schedule(q) end
      elseif old then
        if work and old.heap_index then take(work.heap,old.heap_index) end
        active[tile],count=nil,count-1
      else return false end
      return true
    end
    function D.contains(tile) return active[tile]~=nil end
    function D.count() return count end
    -- With after, use interactive H.advance_houses(clock,1,...) clock
    -- visibility; the post hook sees the completed tick. Without after,
    -- expose the initial clock throughout like a single batch.
    -- All mutation (including callbacks) runs serially on the owner.
    function D.advance(clock,ticks,visit,before,after)
      assert(not work,"Landscape scheduling cannot be reentered")
      assert(type(visit)=="function" and (not before or type(before)=="function") and (not after or type(after)=="function"))
      local final,steps=X.skip(clock,ticks) -- public validation
      if ticks==0 then return 0,0 end
      local start,head=clock.counter,clock.head
      local rank=head==head_hint and rank_hint or X.index(head)
      work={start=start,stop=final.counter,ticks=ticks,head_rank=rank,elapsed=0,slot=-1,heap={},high=0}
      for _,q in pairs(active) do schedule(q) end
      local calls=0
      for elapsed=1,ticks do
        local tick=start+elapsed
        work.elapsed,work.slot=elapsed,-1
        if before then before(tick) end
        local heap=work.heap
        while heap[1] and heap[1].tick==tick do
          local q=take(heap,1)
          work.slot=q.slot
          -- Recurrence is scheduled before dispatch so a deletion
          -- mid-callback can cancel it, even on this very tile.
          if work.stop-tick>=256 then q.tick=tick+256;enqueue(q) end
          local tile=q.tile
          visit(tile,tick,q.slot,tile%width,floor(tile/width))
          calls=calls+1
        end
        work.slot=stride-1 -- new additions after tick cannot run during it
        if after then
          local jump=X.skip(clock,1)
          clock.head,clock.counter=jump.head,jump.counter
          after(tick)
        end
      end
      clock.head,clock.counter=final.head,final.counter
      head_hint,rank_hint=final.head,(rank+steps%period)%period
      local high=work.high
      work=nil
      return calls,high
    end
    return D
  end
  return M
end
