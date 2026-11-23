-- Tool supplies the signal type; the pointed rail chooses its axis.
-- Direction describes train travel, not the side of the mast.
return function(api,status)
  local Sim,S=api.Sim,api.s
  local W={form="luanttd_core:rail_signal"}
  local pending,serial={},0
  local options={rail_signal_pbs=4,rail_signal_oneway=5,rail_signal_block=0}
  local names={[4]="Path signal",[5]="One-way path signal",[0]="Block signal"}
  local explanation={
    [4]="Recommended for most layouts. A train approaching the head waits for a safe path ahead. A train coming from the other side can pass.",
    [5]="Reserves a path like a normal path signal, but trains cannot pass from the other side. Do not use one for a single-track shuttle that returns the same way.",
    [0]="Controls a whole section of track. A train waits for the next block to clear. Use both directions for track that trains travel in both directions.",
  }
  local direction={[0]="West",[1]="South",[2]="East",[3]="North"}
  local function opposite(dir) return (dir+2)%4 end
  local Track=dofile((core.get_modpath and core.get_modpath("luanttd_core") or "mods/luanttd_core").."/openttd/rail_track.lua")
  local function rail_at(id,hit)
    return api.rail_build.signal_track(id,hit)
  end
  function W.tool(tool) return options[tool]~=nil end
  local function preferred(p,id,track)
    if not p.get_pos then return track+8 end
    local x,z=Sim.xy(id)
    local here=p:get_pos()
    local function approach(td)
      local side=Track.entry_side(td)
      local dx=side==0 and -1 or side==2 and 1 or 0
      local dz=side==1 and 1 or side==3 and -1 or 0
      return (here.x-2*x-.5-dx)^2+(here.z-2*z-.5-dz)^2
    end
    return approach(track)<=approach(track+8) and track or track+8
  end
  local function quote(n,id,td,kind,both)
    return api.rail_build.quote_signal_track(n,id,td,kind,both)
  end
  function W.preview(p,tool,id,hit)
    local track=rail_at(id,hit)
    if track==nil then return nil,"Aim at an owned rail piece. Avoid platforms and junctions." end
    local td=preferred(p,id,track)
    local dir=Track.exit_side(td)
    local q,why=quote(p:get_player_name(),id,td,options[tool])
    local arrow=track<=1 and dir or {td=td,dir=dir}
    return q,q and ("Train travels "..direction[dir].."  ·  Click to pick direction") or why,arrow
  end
  local function panel(p,id,kind,inspecting,hit)
    local n=p:get_player_name()
    local B=api.rail_build
    local track=rail_at(id,hit)
    local details=inspecting and (not hit or track~=nil) and B.signal_details(id,track)
    if inspecting and not details then return false end
    if track==nil then status(p,"Aim at an owned rail piece. Avoid platforms and junctions.");return false end
    if details then kind,track=details.kind,details.track end
    local x,z=Sim.xy(id)
    serial=serial+1
    local token=serial
    local esc=core.formspec_escape
    local b={"formspec_version[7]size[12.3,7.1]bgcolor[#152334;false]",
      "style_type[label;textcolor=#E5ECEA]style_type[button;bgimg=bl_button.png;bgimg_middle=6;textcolor=#E5ECEA]"}
    local function label(x_,y,text) b[#b+1]=("label[%g,%g;%s]"):format(x_,y,esc(text)) end
    local function button(x_,y,w,key,text)
      b[#b+1]=("button[%g,%g;%g,.61;signal_%d_%s;%s]"):format(x_,y,w,token,key,esc(text))
    end
    label(.4,.43,("%s %s   /   tile %d, %d"):format(inspecting and "Inspect" or "Place",names[kind] or "rail signal",x,z))
    b[#b+1]="textarea[.4,.84;11.5,1.47;;;"..esc(explanation[kind] or "Controls train entry into the track ahead.").."]"
    if inspecting then
      local shown={}
      for _,dir in ipairs(details.dirs) do shown[#shown+1]=direction[dir] end
      label(.4,2.51,"Protects trains travelling "..table.concat(shown," and ")..".")
      local turn,reason=B.quote_flip_signal(n,id,track)
      if turn then button(.4,3.03,5.56,"flip","Flip 180° (free)") else label(.4,3.28,reason or "This signal cannot be flipped.") end
      button(6.24,3.03,5.63,"remove","Review signal removal")
      label(.4,4.16,"Normal path signals can be red until a train reserves a path.")
    else
      label(.4,2.50,"Which way will the arriving train travel?")
      local from=preferred(p,id,track)
      for i,td in ipairs({from,Track.reverse_trackdir(from)}) do
        local q,why=quote(n,id,td,kind)
        local x_=i==1 and .4 or 6.24
        local travel=direction[Track.entry_side(td)].."  →  "..direction[Track.exit_side(td)]
        local key=track<=1 and ("dir"..Track.exit_side(td)) or ("td"..td)
        if q then button(x_,3.04,5.62,key,travel.."    $"..q.price)
        else label(x_,3.31,travel);b[#b+1]=("textarea[%g,3.64;5.58,1.03;;;%s]"):format(x_,esc(why or "Not available.")) end
      end
      if kind==0 then
        local q=quote(n,id,track,kind,true)
        if q then button(.4,4.05,11.47,"both","Both directions    $"..q.price) end
      end
      label(.4,5.01,"Start with one train on a connected route: signals are optional there.")
      label(.4,5.49,"Add signals when trains need to share track. Place them on plain rail, not a station.")
    end
    b[#b+1]="button_exit[.4,6.15;11.5,.62;signal_exit;Back to railway]"
    pending[n]={id=id,kind=kind,track=track,inspect=inspecting,token=token,topology=S.topology}
    core.show_formspec(n,W.form,table.concat(b))
    return true
  end
  function W.open(p,id,tool,hit)
    local track=rail_at(id,hit)
    local detail=track~=nil and api.rail_build.signal_details(id,track)
    if detail then return panel(p,id,nil,true,hit) end
    return panel(p,id,options[tool],false,hit)
  end
  function W.inspect(p,id,hit) return panel(p,id,nil,true,hit) end
  function W.fields(p,f,remove)
    local n=p:get_player_name()
    local q=pending[n]
    if not q then return true end
    if f.signal_exit or f.quit then pending[n]=nil;return true end
    local action
    for key in pairs(f) do
      local a,b=key:match("^signal_(%d+)_(%w+)$")
      if tonumber(a)==q.token then if action then return true end;action=b end
    end
    if not action then return true end
    pending[n]=nil
    core.close_formspec(n,W.form)
    if q.topology~=S.topology then status(p,"The railway changed. Select the tile again.");return true end
    if q.inspect and action=="remove" then return remove(p,q.id) end
    local plan,why
    if q.inspect and action=="flip" then plan,why=api.rail_build.quote_flip_signal(n,q.id,q.track)
    elseif not q.inspect then
      local both=action=="both" and q.kind==0
      local dir=tonumber(action:match("^dir([0-3])$"))
      local td=both and q.track or dir and Track.diagonal_trackdir(dir) or tonumber(action:match("^td(%d+)$"))
      if not Track.valid_trackdir(td) or Track.track(td)~=q.track then return true end
      plan,why=quote(n,q.id,td,q.kind,both)
    end
    if not plan then status(p,why or "No change made.");return true end
    local ok,note=api.rail_build.build(n,plan)
    status(p,note)
    if ok and action=="flip" then W.inspect(p,q.id) end
    return true
  end
  function W.leave(n) pending[n]=nil end
  return W
end
