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
    [0]="Controls a whole section of track. A train waits for the next block to clear. Use a separate block-signalled line, not mixed with path signals.",
  }
  local direction={[0]="West",[1]="South",[2]="East",[3]="North"}
  local function opposite(dir) return (dir+2)%4 end
  local function axis(id)
    local t=id and S.tiles[id]
    return t and (t.rail_tracks==1 and 0 or t.rail_tracks==2 and 1 or nil)
  end
  function W.tool(tool) return options[tool]~=nil end
  local function preferred(p,id,ax)
    if not p.get_pos then return ax+2 end
    local x,z=Sim.xy(id)
    local here=p:get_pos()
    return ax==0 and (here.x<2*x+.5 and 2 or 0)
      or (here.z<2*z+.5 and 1 or 3)
  end
  local function quote(n,id,dir,kind)
    return api.rail_build.quote_signal(n,id,dir,kind==5,kind==0)
  end
  function W.preview(p,tool,id)
    local ax=axis(id)
    if ax==nil then return nil,"Aim at owned, straight track. Avoid platforms and junctions." end
    local dir=preferred(p,id,ax)
    local q,why=quote(p:get_player_name(),id,dir,options[tool])
    return q,q and ("Train travels "..direction[dir].."  ·  Click to pick direction") or why,dir
  end
  local function panel(p,id,kind,inspecting)
    local n=p:get_player_name()
    local B=api.rail_build
    local ax=axis(id)
    local details=inspecting and B.signal_details(id)
    if inspecting and not details then return false end
    if ax==nil then status(p,"Aim at owned, straight track. Avoid platforms and junctions.");return false end
    if details then kind=details.kind end
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
      local turn,reason=B.quote_flip_signal(n,id)
      if turn then button(.4,3.03,5.56,"flip","Flip 180° (free)") else label(.4,3.28,reason or "This signal cannot be flipped.") end
      button(6.24,3.03,5.63,"remove","Review signal removal")
      label(.4,4.16,"Normal path signals can be red until a train reserves a path.")
    else
      label(.4,2.50,"Which way will the arriving train travel?")
      local from=preferred(p,id,ax)
      for i,dir in ipairs({from,opposite(from)}) do
        local q,why=quote(n,id,dir,kind)
        local x_=i==1 and .4 or 6.24
        local travel=direction[opposite(dir)].."  →  "..direction[dir]
        if q then button(x_,3.04,5.62,"dir"..dir,travel.."    $"..q.price)
        else label(x_,3.31,travel);b[#b+1]=("textarea[%g,3.64;5.58,1.03;;;%s]"):format(x_,esc(why or "Not available.")) end
      end
      label(.4,5.01,"Start with one train on a connected route: signals are optional there.")
      label(.4,5.49,"Add signals when trains need to share track. Place them on plain rail, not a station.")
    end
    b[#b+1]="button_exit[.4,6.15;11.5,.62;signal_exit;Back to railway]"
    pending[n]={id=id,kind=kind,inspect=inspecting,token=token,topology=S.topology}
    core.show_formspec(n,W.form,table.concat(b))
    return true
  end
  function W.open(p,id,tool)
    local detail=api.rail_build.signal_details(id)
    if detail then return panel(p,id,nil,true) end
    return panel(p,id,options[tool],false)
  end
  function W.inspect(p,id) return panel(p,id,nil,true) end
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
    if q.inspect and action=="flip" then plan,why=api.rail_build.quote_flip_signal(n,q.id)
    elseif not q.inspect then
      local dir=tonumber(action:match("^dir([0-3])$"))
      if not dir or dir%2~=axis(q.id) then return true end
      plan,why=quote(n,q.id,dir,q.kind)
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
