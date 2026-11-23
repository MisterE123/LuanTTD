-- Worker-facing transactions call the regular railway, water and airfield
-- models. Their quotes are retained on the owner, not trusted from forms.
return function(Sim,R)
  local s=R.world
  local T={}
  local function integer(x,min,max)
    return type(x)=="number" and x>=min and x<=max and x%1==0
  end
  local function tile(x) return integer(x,1,Sim.W*Sim.H) end
  local function id(x) return integer(x,1,2147483647) end
  local function collect_tiles(q)
    local out={}
    for _,x in ipairs(q.tiles or {}) do out[#out+1]=type(x)=="table" and x.id or x end
    if #out==0 then
      if q.land then out[#out+1]=q.land end
      if q.water then out[#out+1]=q.water end
      if q.origin then out[#out+1]=q.origin end
    end
    return out
  end
  local function span_tiles(plan)
    local cells={plan.start,plan["end"]}
    for _,v in ipairs(plan.middle or {}) do cells[#cells+1]=v end
    return cells
  end
  local function spans(owner,cmd,quote)
    local op,mode=cmd.operation,cmd.mode
    if not tile(cmd.tile) or op=="bridge" and not tile(cmd.last) then return false,"INVALID_SPAN" end
    if mode=="road" then
      if op=="bridge" and not integer(cmd.style,0,2) then return false,"INVALID_BRIDGE_STYLE" end
      if op=="bridge" then return Sim.road_bridge(s,owner,cmd.tile,cmd.last,cmd.style,quote) end
      return Sim.road_tunnel(s,owner,cmd.tile,quote)
    elseif mode=="rail" and R.rail then
      local n=R.network.spans
      local p,e
      if op=="bridge" then p,e=n.quote_bridge(s,owner,cmd.tile,cmd.last)
      else p,e=n.quote_tunnel(s,owner,cmd.tile) end
      if not p then return false,e end
      if quote then return true,p.price,p end
      return n.commit(s,owner,p)
    end
    return false,"UNSUPPORTED_SPAN_MODE"
  end
  function T.quote(owner,cmd)
    if type(cmd)~="table" then return nil,"INVALID_TRANSPORT_COMMAND" end
    local mode,op=cmd.mode,cmd.operation
    if op=="bridge" or op=="tunnel" then
      local ok,price,p=spans(owner,cmd,true)
      if not ok then return nil,price end
      return {request={mode=mode,operation=op,tile=cmd.tile,last=cmd.last,style=cmd.style},
        price=price,tiles=span_tiles(p)}
    elseif op=="build" and mode=="air" and R.air and tile(cmd.tile) then
      local q,why=R.air.network.quote(s,owner,cmd.tile)
      if not q then return nil,why end
      return {request={mode=mode,operation=op,tile=cmd.tile},price=q.price,tiles=collect_tiles(q)}
    elseif op=="build" and mode=="ship" and R.water and tile(cmd.tile) and
      (cmd.kind=="dock" or cmd.kind=="buoy" or cmd.kind=="depot" and integer(cmd.axis,0,1)) then
      local q,why=R.water.network.quote(s,owner,cmd.kind,cmd.tile,cmd.axis)
      if not q then return nil,why end
      local tiles=collect_tiles(q)
      if #tiles==0 then tiles[1]=cmd.tile end
      return {request={mode=mode,operation=op,tile=cmd.tile,kind=cmd.kind,axis=cmd.axis},price=q.cost,tiles=tiles}
    elseif op=="buy" and mode=="rail" and R.rail and R.rail.owned and tile(cmd.depot)
      and type(cmd.parts)=="table" and #cmd.parts>=1 and #cmd.parts<=16 then
      local parts={}
      for i=1,#cmd.parts do
        if not integer(cmd.parts[i],0,255) then return nil,"INVALID_CONSIST" end
        parts[i]=cmd.parts[i]
      end
      local q,why=R.rail.owned.quote(s,owner,cmd.depot,parts)
      if not q then return nil,why end
      return {request={mode=mode,operation=op,depot=cmd.depot,parts=parts},price=q.price,tiles={cmd.depot}}
    elseif op=="buy" and mode=="ship" and R.water and id(cmd.depot) and (cmd.engine==206 or cmd.engine==207) then
      local q,why=R.water.depot.quote(s,owner,cmd.depot,cmd.engine)
      if not q then return nil,why end
      return {request={mode=mode,operation=op,depot=cmd.depot,engine=cmd.engine},price=q.price,tiles={}}
    elseif op=="buy" and mode=="air" and R.air and id(cmd.depot) and integer(cmd.engine,215,255) then
      local q,why=R.air.owned.quote(s,owner,cmd.depot,cmd.engine)
      if not q then return nil,why end
      return {request={mode=mode,operation=op,depot=cmd.depot,engine=cmd.engine},price=q.price,tiles={}}
    end
    return nil,"UNSUPPORTED_TRANSPORT_COMMAND"
  end
  function T.commit(owner,quote)
    local req=quote.request
    local current,why=T.quote(owner,req)
    if not current then return false,why end
    if current.price~=quote.price or #current.tiles~=#quote.tiles then return false,"TRANSPORT_QUOTE_CHANGED" end
    for i,t in ipairs(current.tiles) do if t~=quote.tiles[i] then return false,"TRANSPORT_QUOTE_CHANGED" end end
    if req.operation=="bridge" or req.operation=="tunnel" then
      local ok,msg,tiles,deck=spans(owner,req,false)
      return ok,msg,ok and {tiles=tiles,deck=deck} or nil
    end
    local unit,msg
    if req.operation=="build" and req.mode=="air" then
      unit,msg=R.air.network.build(s,owner,req.tile)
    elseif req.operation=="build" and req.mode=="ship" then
      unit,msg=R.water.network.build(s,owner,req.kind,req.tile,req.axis)
    elseif req.mode=="rail" then
      local q,e=R.rail.owned.quote(s,owner,req.depot,req.parts)
      if not q then return false,e end
      unit,msg=R.rail.owned.commit(s,owner,q)
    elseif req.mode=="ship" then
      unit,msg=R.water.depot.buy(s,owner,req.depot,req.engine)
    else
      local q,e=R.air.owned.quote(s,owner,req.depot,req.engine)
      if not q then return false,e end
      unit,msg=R.air.owned.commit(s,owner,q)
    end
    if not unit then return false,msg end
    return true,type(msg)=="string" and msg or nil,{id=unit.id or req.mode=="ship" and "ferry",tiles=current.tiles}
  end
  function T.start(owner,req)
    if not (id(req.first) and id(req.second)) or req.first==req.second then return false,"INVALID_DESTINATIONS" end
    if req.mode=="rail" and R.rail and R.rail.owned and id(req.vehicle) then
      return R.rail.owned.start(s,owner,req.vehicle,req.first,req.second)
    elseif req.mode=="ship" and R.water and id(req.depot) and (req.via==nil or tile(req.via)) then
      local run,why=R.water.depot.start(s,owner,req.depot,req.first,req.second,req.via)
      return run~=nil,why
    elseif req.mode=="air" and R.air then
      local run,why=R.air.owned.start(s,owner,req.first,req.second)
      return run~=nil,why
    end
    return false,"UNSUPPORTED_ROUTE"
  end
  return T
end
