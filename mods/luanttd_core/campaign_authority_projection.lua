-- Cached read-only view, deliberately not shaped like writable Sim state.
-- Each region needs a fresh request token when it is added again.
return function()
  local P={}
  local regions={}
  local epoch=0
  local companies,company_seq={},-1
  local function newer_than(a,b)
    return a.tick>b.tick or a.tick==b.tick and a.seq>b.seq
  end
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
  function P.scene(key)
    local region=regions[key]
    return region and region.result and region.result.value.scene
  end
  function P.accept_batch(subscriptions,reply)
    if not reply or not reply.ok or type(reply.seq)~="number" or not reply.value or #subscriptions~=#reply.value then return false end
    for i,request in ipairs(subscriptions) do
      local r=regions[request.key]
      if not r or r.token~=request.token or r.result and r.result.seq>=reply.seq then return false end
      local w=reply.value[i]
      if w.scene and not w.tiles then
        local old=r.result and r.result.value
        if not old or old.scene~=w.scene or old.x~=w.x or old.z~=w.z
          or old.width~=w.width or old.height~=w.height then return false end
      end
    end
    if reply.companies and reply.seq>company_seq then
      companies,company_seq=reply.companies,reply.seq
    end
    for i,request in ipairs(subscriptions) do
      local w=reply.value[i]
      if w.scene and not w.tiles then
        local materialized={}
        for k,v in pairs(w) do materialized[k]=v end
        local old=regions[request.key].result.value
        materialized.tiles,materialized.corners,materialized.registries=old.tiles,old.corners,old.registries
        w=materialized
      end
      P.accept(request.key,request.token,{ok=true,seq=reply.seq,tick=reply.tick,revision=reply.revision,value=w})
    end
    return true
  end
  function P.company(name) return companies[name] end
  function P.windows()
    local list={}
    for _,r in pairs(regions) do if r.result then list[#list+1]=r.result end end
    table.sort(list,function(a,b)
      return a.tick<b.tick or a.tick==b.tick and a.seq<b.seq
    end)
    return list
  end
  function P.terrain(x,z)
    local newest,cell,corner
    for _,r in pairs(regions) do
      local receipt=r.result
      local window=receipt and receipt.value
      if window and window.x then
        local dx,dz=x-window.x,z-window.z
        if dx>=0 and dz>=0 and dx<=window.width and dz<=window.height then
          if (not newest or newer_than(receipt,newest)) and dx<window.width and dz<window.height then
            cell=window.tiles and window.tiles[1+dz*window.width+dx]
            newest=receipt
          end
          if window.corners and (not corner or newer_than(receipt,corner.receipt)) then
            corner={receipt=receipt,height=window.corners:byte(1+dz*(window.width+1)+dx)}
          end
        end
      end
    end
    return cell,corner and corner.height
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
