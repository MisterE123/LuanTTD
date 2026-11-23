-- Schedule bounded terrain/actor observations. The viewport controls only
-- what the host receives; it never pauses or steers the campaign owner.
return function(client,projection,width,depth,changed)
  local I={}
  local sectors,by_key={},{}
  local frame=0
  local pending
  local cursor=1
  local players={}
  local elapsed=.2
  local size=32
  local limit=9
  local function collect(positions)
    local next_,list={},{}
    for _,pos in ipairs(positions) do
      local x=math.max(1,math.min(width,math.floor((pos.x+.5)/2)))
      local z=math.max(1,math.min(depth,math.floor((pos.z+.5)/2)))
      local sx,sz=math.floor((x-1)/size),math.floor((z-1)/size)
      for dz=-1,1 do for dx=-1,1 do
        local u,v=(sx+dx)*size+1,(sz+dz)*size+1
        local key=u..":"..v
        if u>=1 and v>=1 and u<=width and v<=depth and not next_[key] then
          local r={key=key,x=u,z=v,w=math.min(size,width-u+1),h=math.min(size,depth-v+1)}
          next_[key]=r;list[#list+1]=r
        end
      end end
    end
    table.sort(list,function(a,b) return a.z==b.z and a.x<b.x or a.z<b.z end)
    return list,next_
  end
  function I.update(positions)
    players={}
    local names={}
    for _,p in ipairs(positions) do
      if type(p.name)=="string" and not names[p.name] and #players<32 then
        names[p.name]=true;players[#players+1]=p.name
      end
    end
    local list,next_=collect(positions)
    local moved=#list~=#sectors
    if not moved then for k in pairs(next_) do if not by_key[k] then moved=true;break end end end
    if not moved then return end
    for key in pairs(by_key) do if not next_[key] then projection.unsubscribe(key) end end
    for _,r in ipairs(list) do r.token=projection.subscribe(r.key) end
    sectors,by_key=list,next_
    frame=frame+1
    cursor=1
    elapsed=.2
    changed(projection)
  end
  function I.step(dt,fraction)
    elapsed=math.min(.2,elapsed+dt)
    if pending or elapsed<.2 or #sectors==0 then return false end
    local windows,subscriptions={},{}
    local last=math.min(#sectors,cursor+limit-1)
    for i=cursor,last do
      local r=sectors[i]
      windows[#windows+1]={x=r.x,z=r.z,w=r.w,h=r.h}
      subscriptions[#subscriptions+1]={key=r.key,token=r.token}
    end
    local request={frame=frame,last=last}
    pending=request
    local function applied(reply)
      if pending~=request then return end
      pending=nil
      if request.frame==frame and projection.accept_batch(subscriptions,reply) then
        cursor=last==#sectors and 1 or last+1
        changed(projection)
      end
    end
    local queued=client.query({kind="snapshots",windows=windows,fraction=fraction,players=players},applied)
    if not queued then pending=nil;return false end
    elapsed=0
    return true
  end
  return I
end
