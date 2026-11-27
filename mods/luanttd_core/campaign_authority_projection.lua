-- Cached read-only view, deliberately not shaped like writable Sim state.
-- Each region needs a fresh request token when it is added again.
return function()
  local P={}
  local regions={}
  local epoch=0
  local actor_us
  local companies,company_seq={},-1
  local pulses,fares,seen,max_boarding={},{},{},0
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
    if not r.motion or result.seq>r.motion.seq then r.motion=result end
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
      if type(w)~="table" or w.scene_base and (not w.scene or w.tiles or w.corners) then return false end
      if w.scene and not w.tiles then
        local old=r.result and r.result.value
        if not old or old.scene~=(w.scene_base or w.scene) or old.x~=w.x or old.z~=w.z
          or old.width~=w.width or old.height~=w.height then return false end
        if w.scene_base then
          if w.scene==w.scene_base or type(old.tiles)~="table" or type(w.tile_patch)~="table" or #w.tile_patch>64 then return false end
          local index=0
          for _,replacement in ipairs(w.tile_patch) do
            if type(replacement)~="table" then return false end
            local i,row=replacement[1],replacement[2]
            if type(i)~="number" or i%1~=0 or i<=index or i>#old.tiles or type(row)~="table" then return false end
            local previous=old.tiles[i]
            if type(previous)~="table" or row.id~=previous.id then return false end
            index=i
          end
        end
      end
    end
    if reply.actor_us then actor_us=math.max(actor_us or 0,reply.actor_us) end
    if reply.companies and reply.seq>company_seq then
      companies,company_seq=reply.companies,reply.seq
    end
    for i,request in ipairs(subscriptions) do
      local w=reply.value[i]
      if w.scene and not w.tiles then
        local materialized={}
        for k,v in pairs(w) do materialized[k]=v end
        local old=regions[request.key].result.value
        materialized.tiles,materialized.corners=old.tiles,old.corners
        materialized.registries=materialized.registries or old.registries
        if w.scene_base then
          if #w.tile_patch>0 then
            local rows={}
            for j,row in ipairs(old.tiles) do rows[j]=row end
            for _,p in ipairs(w.tile_patch) do rows[p[1]]=p[2] end
            materialized.tiles=rows
          end
          materialized.scene_base,materialized.tile_patch=nil,nil
        end
        w=materialized
      end
      local function receive(events,out)
        for _,event in ipairs(events or {}) do
          local n=event.seq
          if n>max_boarding-256 and not seen[n] then
            seen[n]=true;out[#out+1]=event
            max_boarding=math.max(max_boarding,n)
          end
        end
      end
      receive(w.boardings,pulses)
      receive(w.fares,fares)
      for n in pairs(seen) do if n<=max_boarding-256 then seen[n]=nil end end
      P.accept(request.key,request.token,{ok=true,seq=reply.seq,tick=reply.tick,revision=reply.revision,value=w})
    end
    return true
  end
  function P.accept_motion(subscriptions,reply)
    if not reply or not reply.ok or type(reply.seq)~="number" or not reply.value or #subscriptions~=#reply.value then return false end
    for i,request in ipairs(subscriptions) do
      local r=regions[request.key]
      local old=r and r.result and r.result.value
      local w=reply.value[i]
      if not old or r.token~=request.token or r.motion and r.motion.seq>=reply.seq
        or old.x~=w.x or old.z~=w.z or old.width~=w.width or old.height~=w.height then return false end
    end
    if reply.actor_us then actor_us=math.max(actor_us or 0,reply.actor_us) end
    for i,request in ipairs(subscriptions) do
      regions[request.key].motion={seq=reply.seq,tick=reply.tick,value=reply.value[i]}
    end
    return true
  end
  function P.actor_clock() return actor_us end
  function P.boarding_cursor(key)
    local r=regions[key]
    return r and r.result and r.result.value.boarding_cursor
  end
  function P.take_boardings()
    local list=pulses;pulses={};return list
  end
  function P.take_cash_sounds()
    local list=fares;fares={};return list
  end
  function P.waiting(mode,id)
    local result,seq=0,-1
    for _,r in pairs(regions) do
      local q=r.result
      local n=q and q.value.passengers and q.value.passengers[mode..":"..id]
      if n~=nil and q.seq>seq then result,seq=n,q.seq end
    end
    return result
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
  function P.signals()
    local result={}
    for _,r in pairs(regions) do
      if r.result then
        for _,row in ipairs(r.result.value.signals or {}) do result[row.key]=row end
      end
    end
    return result
  end
  local function motion_slots(field)
    local values,receipts={},{}
    for _,region in pairs(regions) do
      local r=region.motion
      if r then
        for id,pos in pairs(r.value[field] or {}) do
          if not receipts[id] or newer_than(r,receipts[id]) then values[id],receipts[id]=pos,r end
        end
      end
    end
    return values
  end
  function P.town_lifts() return motion_slots("town_lifts") end
  function P.industry_machinery() return motion_slots("industry_machinery") end
  function P.actors()
    local merged={}
    for _,region in pairs(regions) do
      if region.motion then
        local receipt=region.motion
        for _,row in ipairs(receipt.value.actors or {}) do
          local current=merged[row.key]
          if not current or current.tick<receipt.tick or
            current.tick==receipt.tick and (not row.parts or row.complete_parts or current.complete) and current.seq<receipt.seq then
            local desc={}
            for k,v in pairs(row) do if k~="parts" then desc[k]=v end end
            current={tick=receipt.tick,seq=receipt.seq,value=desc,complete=row.complete_parts}
            if row.parts then current.parts={} end
            merged[row.key]=current
          end
          -- A consist can cross a sector boundary. Combine bodies only
          -- for the same committed simulation tick, never older motion.
          if current.tick==receipt.tick and row.parts and current.parts and
            (current.seq==receipt.seq or not current.complete and not row.complete_parts) then
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
