-- Server-side visual playout only. The worker's timestamps and poses are
-- authoritative; the host never extrapolates a unit through a stop.
return function()
  local A={}
  local frames={}
  local last_target
  local lag=160000
  local tau=math.pi*2
  local function mixed(a,b,t) return a+(b-a)*t end
  local function angle(a,b,t) return a+((b-a+math.pi)%tau-math.pi)*t end
  local function v3(a,b,t)
    return {x=mixed(a.x,b.x,t),y=mixed(a.y,b.y,t),z=mixed(a.z,b.z,t)}
  end
  local function rot(a,b,t)
    return {x=angle(a.x,b.x,t),y=angle(a.y,b.y,t),z=angle(a.z,b.z,t)}
  end
  local function copy(row)
    local out={}
    for k,v in pairs(row) do out[k]=v end
    return out
  end
  local function blend(a,b,t)
    if not a or not b then return b or a end
    if a.mode~=b.mode or a.engine~=b.engine or t>=1 then return b end
    if a.parts or b.parts then
      if not a.parts or not b.parts or #a.parts~=#b.parts then return a end
      for i,p in ipairs(a.parts) do
        local q=b.parts[i]
        if p.body_index~=q.body_index or p.kind~=q.kind or p.flip~=q.flip or
            (p.bogies and #p.bogies)~=(q.bogies and #q.bogies) then return a end
      end
      local row=copy(a)
      row.parts={}
      for i,p in ipairs(a.parts) do
        local q=b.parts[i]
        local body=copy(p)
        body.pos=v3(p.pos,q.pos,t)
        body.rotation=rot(p.rotation,q.rotation,t)
        if p.bogies then
          body.bogies={}
          for j,g in ipairs(p.bogies) do
            local h=q.bogies[j]
            body.bogies[j]={pos=v3(g.pos,h.pos,t),rotation=rot(g.rotation,h.rotation,t)}
          end
        end
        local l,r=p.drawbar,q.drawbar
        if l and r then
          body.drawbar={pos=v3(l.pos,r.pos,t),rotation=rot(l.rotation,r.rotation,t),length=mixed(l.length,r.length,t)}
        end
        row.parts[i]=body
      end
      return row
    end
    if not a.pos or not b.pos then return b end
    local row=copy(a)
    row.pos=v3(a.pos,b.pos,t)
    for _,k in ipairs({"yaw","dir","pitch"}) do
      if type(a[k])=="number" and type(b[k])=="number" then row[k]=angle(a[k],b[k],t) end
    end
    return row
  end
  function A.observe(rows,at)
    if not at then return end
    local last=frames[#frames]
    if last then
      if at<last.at then return end
      if at==last.at then
        -- Leaving a viewport removes membership without a new worker
        -- clock sample, including any simultaneously queued packets.
        last.rows=rows
        return
      end
      local gap=at-last.at
      if gap>520000 then
        frames={};last_target=nil
      else
        lag=lag*.85+math.min(240000,math.max(145000,gap*1.4+45000))*.15
      end
    end
    frames[#frames+1]={at=at,rows=rows}
    while #frames>8 do table.remove(frames,1) end
  end
  function A.sample(now)
    local last=frames[#frames]
    if not last then return {} end
    local target=math.max(last_target or 0,now-lag)
    last_target=target
    if #frames==1 or target>=last.at then return last.rows end
    local j=2
    while frames[j].at<target do j=j+1 end
    local a,b=frames[j-1],frames[j]
    local fraction=math.max(0,(target-a.at)/(b.at-a.at))
    local out={}
    -- Membership always comes from the live viewport. History provides
    -- only geometry and never respawns a unit that has gone out of sight.
    for k,row in pairs(last.rows) do
      if not row.pos and not row.parts then out[k]=row
      else
        out[k]=blend(a.rows[k],b.rows[k],fraction) or row
        if not out[k].pos and not out[k].parts then out[k]=row end
      end
    end
    return out
  end
  return A
end
