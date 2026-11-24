-- Audio presentation for the stock simulation. The soundtrack is personal;
-- neither playlists nor playback side effects can advance the world or RNG.
return function(core,mod,catalog)
  local S=dofile(mod.."/openttd/sound_rc1.lua")
  local A={samples=S.sample}
  local function available(path)
    local file=io.open(path,"rb")
    if not file then return false end
    file:close()
    return true
  end
  local sounds={}
  for _,index in pairs(S.sample) do
    local name=("stock_sfx_%02x"):format(index)
    if catalog or available(mod.."/sounds/"..name..".ogg") then sounds[index]=name end
  end
  local includes_music=catalog or available(mod.."/stock_audio_music.lua")
  local tracks=catalog or (includes_music and dofile(mod.."/stock_audio_music.lua")) or {}
  local listening,actors={},{}
  local prefix="luanttd_stock_audio:"
  local function clamp(n) return math.max(0,math.min(100,math.floor(n))) end
  local function volume(meta,name,default)
    return clamp(tonumber(meta:get_string(prefix..name)) or default)/100
  end
  local lists={"All tracks","Old style","Modern","Ezy street"}
  local function matches(track,list)
    local group=track.slot:match("^([^_]+)")
    return group~="theme" and (list==1 or group==({"all","old","new","ezy"})[list])
  end
  local function order(s,preserve)
    local old=preserve and s.order[s.index]
    s.order={}
    for i,t in ipairs(tracks) do if matches(t,s.list) then s.order[#s.order+1]=i end end
    -- Forward Fisher-Yates as in RC1 MusicSystem::Shuffle; private
    -- presentation PRNG, deliberately not Sim.Random nor math.random.
    if s.shuffle then
      for i=1,#s.order do
        s.random=(s.random*48271)%2147483647
        local j=i+s.random%(#s.order-i+1)
        s.order[i],s.order[j]=s.order[j],s.order[i]
      end
    end
    s.index=1
    if old then for i,k in ipairs(s.order) do if k==old then s.index=i;break end end end
  end
  local function stop(s)
    if s.handle then core.sound_stop(s.handle);s.handle=nil end
    s.ending=nil
  end
  local function start(s)
    stop(s)
    local t=tracks[s.order[s.index]]
    if not s.playing or s.music==0 or not t then return end
    s.handle=core.sound_play(t.name,{to_player=s.name,gain=s.music},false)
    s.ending=core.get_us_time()+t.duration*1000000
  end
  function A.advance(s,delta)
    if #s.order==0 then return end
    s.index=(s.index+delta-1)%#s.order+1
    start(s)
  end
  function A.join(p)
    local name=p:get_player_name()
    local meta=p:get_meta()
    local list=tonumber(meta:get_string(prefix.."list")) or 1
    local s={name=name,meta=meta,order={},index=1,list=lists[list] and list or 1,
      random=math.floor(core.get_us_time()%2147483646)+1,shuffle=meta:get_string(prefix.."shuffle")=="1",
      sfx=volume(meta,"sfx",100),music=volume(meta,"music",40),
      playing=meta:get_string(prefix.."playing")~="0"}
    if listening[name] then stop(listening[name]) end
    listening[name]=s
    order(s,false)
    start(s)
  end
  function A.leave(name)
    local s=listening[name]
    if s then stop(s);listening[name]=nil end
  end
  function A.step()
    local now=core.get_us_time()
    for _,s in pairs(listening) do
      if s.ending and now>=s.ending then A.advance(s,1) end
    end
  end
  function A.effect(id,options)
    local n=type(id)=="number" and id or S.sample[id]
    local asset=sounds[n]
    if not asset then return end
    options=options or {}
    local base=(S.gain[n] or 1)*(options.gain or .75)
    local function play(name,s)
      local gain=(s and s.sfx or 1)*base
      if gain<=0 then return end
      core.sound_play(asset,{to_player=name,pos=options.pos,max_hear_distance=options.range or 27,gain=gain},true)
    end
    if options.player then play(options.player,listening[options.player]);return end
    if not options.pos then return end
    local limit=(options.range or 27)^2
    for _,p in ipairs(core.get_connected_players()) do
      local pp=p:get_pos()
      if pp then
        local a,b,c=pp.x-options.pos.x,pp.y-options.pos.y,pp.z-options.pos.z
        local name=p:get_player_name()
        if a*a+b*b+c*c<=limit then play(name,listening[name]) end
      end
    end
  end

  function A.construction(kind,request,player,pos)
    local fx="CONSTRUCTION_OTHER"
    if request.tool=="bridge" or request.operation=="bridge" then fx="CONSTRUCTION_BRIDGE"
    elseif request.mode=="ship" then fx="CONSTRUCTION_WATER"
    elseif kind=="rail" or request.mode=="rail" then fx="CONSTRUCTION_RAIL" end
    A.effect(fx,{player=player,pos=pos})
  end

  -- LuanTTD worker projection is sampled independently of the simulation.
  -- Remember each visible actor's state and never fire a transition just
  -- because a player moved far enough away for an entity to spawn again.
  function A.observe_vehicles(rows)
    local seen={}
    for key,r in pairs(rows) do
      local lead=r.parts and r.parts[1]
      local pos=r.pos or lead and lead.pos
      if pos and (r.mode=="road" or r.mode=="rail" or r.mode=="ship" or r.mode=="air") then
        seen[key]=true
        local now={idle=r.sound_idle,airborne=r.airborne,breakdown=r.sound_breakdown or r.breakdown_smoke,
          crashed=r.sound_crashed,crossing=r.sound_crossing}
        local old=actors[key]
        if old and not r.sound_paused then
          if now.crashed and not old.crashed then
            A.effect(r.mode=="rail" and "TRAIN_COLLISION" or "EXPLOSION",{pos=pos})
          elseif now.breakdown and not old.breakdown then
            A.effect(r.mode=="road" and "BREAKDOWN_ROADVEHICLE" or "BREAKDOWN_TRAIN_SHIP",{pos=pos})
          elseif r.mode=="air" and old.airborne~=now.airborne then
            local id
            local helicopter=r.sound_helicopter or r.rotor_period~=nil
            if now.airborne then id=S.departure("air",r.engine,nil,helicopter)
            elseif not helicopter then id=S.sample.SKID_PLANE end
            if id then A.effect(id,{pos=pos}) end
          elseif old.idle and not now.idle then
            local id=S.departure(r.mode,r.sound_engine or r.engine,r.sound_tick)
            if id then A.effect(id,{pos=pos}) end
          end
          if now.crossing and now.crossing~=old.crossing then A.effect("LEVEL_CROSSING",{pos=pos,range=23}) end
        end
        actors[key]=now
      end
    end
    for k in pairs(actors) do if not seen[k] then actors[k]=nil end end
  end
  local form="luanttd_core:stock_audio"
  function A.open(p)
    local s=listening[p:get_player_name()]
    if not s then A.join(p);s=listening[p:get_player_name()] end
    local current=tracks[s.order[s.index]]
    local esc=core.formspec_escape
    core.show_formspec(s.name,form,
      "formspec_version[7]size[10.6,6.2]bgcolor[#152334;false]label[.45,.49;Music & sound]"..
      ("label[.45,1.03;%s]"):format(esc(current and ((s.playing and "Now playing: " or "Selected: ")..
        current.title.."  ·  "..current.author) or "No soundtrack installed"))..
      ("dropdown[.45,1.45;8.1,.6;audio_list;%s;%d;true]"):format(table.concat(lists,","),s.list)..
      ("checkbox[8.76,1.74;audio_shuffle;Shuffle;%s]"):format(s.shuffle and "true" or "false")..
      "button[.45,2.35;2.9,.65;audio_prev;Previous]"..
      "button[3.59,2.35;3.43,.65;audio_play;"..(s.playing and "Stop" or "Play").."]"..
      "button[7.26,2.35;2.9,.65;audio_next;Next]"..
      ("label[.45,3.27;Music volume]scrollbaroptions[min=0;max=100;smallstep=5;largestep=10]"..
       "scrollbar[.45,3.63;9.7,.3;horizontal;audio_music;%d]"):format(math.floor(s.music*100+.5))..
      ("label[.45,4.18;Sound effects volume]scrollbar[.45,4.55;9.7,.3;horizontal;audio_sfx;%d]"):format(math.floor(s.sfx*100+.5))..
      "button_exit[.45,5.30;9.7,.57;close;Back to world]")
    return true
  end
  function A.fields(p,which,f)
    if which~=form then return false end
    local s=listening[p:get_player_name()]
    if not s or f.quit then return true end
    local function save(key,val) s.meta:set_string(prefix..key,tostring(val)) end
    local function adjust(kind,val)
      if not val then return false end
      local v=val:match("^CHG:(%d+)$")
      if not v then return false end
      v=clamp(tonumber(v))
      s[kind]=v/100
      save(kind,v)
      if kind=="music" then
        if v==0 then stop(s)
        elseif s.handle then core.sound_fade(s.handle,2,s.music)
        else start(s) end
      end
      return true
    end
    if adjust("music",f.audio_music) or adjust("sfx",f.audio_sfx) then return true end
    local list=tonumber(f.audio_list)
    if list and lists[list] and s.list~=list then s.list=list;save("list",list);order(s,false);start(s)
    elseif f.audio_shuffle then s.shuffle=f.audio_shuffle=="true";save("shuffle",s.shuffle and 1 or 0);order(s,true)
    elseif f.audio_play then s.playing=not s.playing;save("playing",s.playing and 1 or 0);start(s)
    elseif f.audio_next then A.advance(s,1)
    elseif f.audio_prev then A.advance(s,-1)
    else return true end
    A.open(p)
    return true
  end
  if core.register_on_joinplayer then
    core.register_on_joinplayer(A.join)
    core.register_on_leaveplayer(function(p) A.leave(p:get_player_name()) end)
    core.register_globalstep(A.step)
    core.register_on_player_receive_fields(function(p,name,f) return A.fields(p,name,f) end)
  end
  return A
end
