-- Cached read-only view, deliberately not shaped like writable Sim state.
-- Each region needs a fresh request token when it is added again.
return function()
  local P={}
  local regions={}
  local epoch=0
  function P.subscribe(key)
    if regions[key] then return regions[key].token end
    epoch=epoch+1
    regions[key]={token=epoch}
    return epoch
  end
  function P.unsubscribe(key)
    regions[key]=nil
  end
  function P.accept(key,token,result)
    local r=regions[key]
    if not r or r.token~=token or not result or not result.ok or type(result.seq)~="number" then return false end
    if r.result and r.result.seq>=result.seq then return false end
    r.result=result
    return true
  end
  function P.accept_batch(subscriptions,reply)
    if not reply or not reply.ok or type(reply.seq)~="number" or not reply.value or #subscriptions~=#reply.value then return false end
    for _,request in ipairs(subscriptions) do
      local r=regions[request.key]
      if not r or r.token~=request.token or r.result and r.result.seq>=reply.seq then return false end
    end
    for i,request in ipairs(subscriptions) do
      P.accept(request.key,request.token,{ok=true,seq=reply.seq,tick=reply.tick,value=reply.value[i]})
    end
    return true
  end
  function P.actors()
    local merged={}
    for _,region in pairs(regions) do
      if region.result then
        local receipt=region.result
        for _,row in ipairs(receipt.value.actors or {}) do
          local current=merged[row.key]
          if not current or current.tick<receipt.tick or
            current.tick==receipt.tick and not row.parts and current.seq<receipt.seq then
            local desc={}
            for k,v in pairs(row) do if k~="parts" then desc[k]=v end end
            current={tick=receipt.tick,seq=receipt.seq,value=desc}
            if row.parts then current.parts={} end
            merged[row.key]=current
          end
          -- A consist can cross a sector boundary. Combine bodies only
          -- for the same committed simulation tick, never older motion.
          if current.tick==receipt.tick and row.parts and current.parts then
            for _,p in ipairs(row.parts) do
              local previous=current.parts[p.index]
              if not previous or previous.seq<receipt.seq then current.parts[p.index]={seq=receipt.seq,part=p} end
            end
          end
        end
      end
    end
    local values={}
    for key,row in pairs(merged) do
      if row.parts then
        local list={}
        for _,value in pairs(row.parts) do list[#list+1]=value.part end
        table.sort(list,function(a,b) return a.index<b.index end)
        row.value.parts=list
      end
      values[key]=row.value
    end
    return values
  end
  return P
end
