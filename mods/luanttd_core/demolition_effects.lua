-- Victory/cancel/reject state remains with the command owner. This module
-- only reacts to the nonempty changed-tile list on a successful receipt.
return function(core,api)
  local E={}
  local Sim=api.Sim
  local radius,max_sites=34,3
  local budget,last=12,core.get_us_time()
  local function dist(a,b)
    return (a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2
  end
  local function xyz(x,y,z) return {x=x,y=y,z=z} end
  local function span(x,y,z,u,v,w) return {min=xyz(x,y,z),max=xyz(u,v,w)} end
  local function particles(player,at,kind,amount,seconds,velocity,acc,min_time,max_time,min_size,max_size,start,finish,glow)
    core.add_particlespawner({
      playername=player,time=seconds,amount=amount,glow=glow or 0,
      pos=span(at.x-.12,at.y-.04,at.z-.12,at.x+.12,at.y+.11,at.z+.12),
      vel=velocity,acc=acc,exptime={min=min_time,max=max_time},size={min=min_size,max=max_size},
      collisiondetection=false,
      texture={name="bl_demolition_"..kind..".png",alpha_tween={1,0},scale_tween={start,finish}},
    })
  end
  function E.origin(id,layer)
    if type(id)~="number" or id<1 or id>Sim.W*Sim.H or id~=math.floor(id) then return end
    local R=api.render
    if not R then return end
    local t=R.host_tile(id)
    if not t or t.stock_void then return end
    local a,b=Sim.xy(id)
    local x,z=2*a+.5,2*b+.5
    local y=R.surface(id,x,z)
    if not y then return end
    if layer and (layer:find("bridge",1,true) or layer:find("aqueduct",1,true)) then
      local deck=R.host_deck and R.host_deck(id)
      if deck then y=math.max(y,deck+.5) end
    end
    return xyz(x,y+.32,z)
  end
  local function burst(player,at)
    -- Very short initial flare (the stock effect only changes frames
    -- every four ticks), quick ballistic chips, then a warm drifting plume.
    particles(player,at,"flare",1,.055,span(-.10,.12,-.10,.10,.25,.10),xyz(0,0,0),
      .21,.26,6.5,8.5,.62,1.15,8)
    particles(player,at,"chips",10,.11,span(-2.0,1.2,-2.1,2.1,2.85,2.0),xyz(.13,-6.5,-.08),
      .27,.64,1.0,2.4,1,.72)
    particles(player,at,"dust",11,.36,span(.25,.23,-.89,1.09,.86,-.12),xyz(.10,.07,-.04),
      .67,1.42,7.5,11,.53,1.37)
  end
  function E.receipt(ok,changed,focus,original)
    if ok~=true or type(changed)~="table" or #changed==0 then return 0 end
    local watchers={}
    for _,p in ipairs(core.get_connected_players()) do
      local pos=p:get_pos()
      if pos then watchers[#watchers+1]={name=p:get_player_name(),pos=pos} end
    end
    if #watchers==0 then return 0 end
    local candidates,seen={},{}
    for _,id in ipairs(changed) do
      if not seen[id] then
        seen[id]=true
        local at=id==focus and original or E.origin(id)
        if at then
          local near,nearest={},radius^2
          for _,w in ipairs(watchers) do
            local d=dist(w.pos,at)
            if d<=radius^2 then near[#near+1]=w.name;nearest=math.min(nearest,d) end
          end
          if #near>0 then candidates[#candidates+1]={id=id,at=at,near=near,dist=nearest} end
        end
      end
    end
    table.sort(candidates,function(a,b)
      if a.id==focus or b.id==focus then return a.id==focus end
      if a.dist==b.dist then return a.id<b.id end
      return a.dist<b.dist
    end)
    local now=core.get_us_time()
    budget=math.min(12,budget+math.max(0,now-last)*12/1000000)
    last=now
    local n=math.min(#candidates,max_sites,math.floor(budget))
    budget=budget-n
    if n>0 then
      if api.stock_audio then api.stock_audio.effect("EXPLOSION",{pos=candidates[1].at,range=radius,gain=.72}) end
      for i=1,n do
        local e=candidates[i]
        for _,player in ipairs(e.near) do burst(player,e.at) end
      end
    end
    return n
  end
  return E
end
