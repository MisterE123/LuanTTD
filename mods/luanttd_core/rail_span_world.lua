-- Opt-in native board adapter and write transaction for the stock rail
-- span planner. Initial visual envelope: wooden bridges, and existing,
-- complementary tunnel portals which do not require excavation.
return function(Sim,Terrain,Height,Bridge,Tunnel,Track,mounted_bridge_styles)
  local W={}
  mounted_bridge_styles=mounted_bridge_styles or {[0]=true}
  local function has_style(style,gauge)
    if type(mounted_bridge_styles)=="function" then return mounted_bridge_styles(style,gauge) end
    return mounted_bridge_styles[style]~=nil
  end
  local function copy(t)
    local q={}
    for k,v in pairs(t) do q[k]=v end
    return q
  end
  function W.by_portal(s,id)
    local t=id and s.tiles[id]
    return t and t.rail_span_id and (s.stock_rail_spans or {})[t.rail_span_id]
  end
  local function span_head(s,id)
    local p=W.by_portal(s,id)
    if p then return p.start==id and p.head or p.tail,p end
  end
  function W.by_bridge_middle(s,id)
    local k=s.rail_bridge_above and s.rail_bridge_above[id]
    return k and s.stock_rail_spans[k]
  end
  local function by_tunnel_middle(s,id)
    local k=s.rail_tunnel_below and s.rail_tunnel_below[id]
    return k and s.stock_rail_spans[k]
  end
  function W.protected(s,id)
    if id~=nil and Sim.crossing_protected and Sim.crossing_protected(s,id) then return true end
    return W.by_portal(s,id)~=nil or W.by_bridge_middle(s,id)~=nil or by_tunnel_middle(s,id)~=nil
  end
  -- Read-only adapter for the source railtype converter. A portal is
  -- the selection unit; its middle is a separate protected layer,
  -- never a request to edit the ground record beneath the structure.
  -- Keep this detached until the native wire/traction mount qualifies.
  function W.electric_record(s,id)
    local function index(n,limit)
      return type(n)=="number" and n%1==0 and n>=1 and n<=limit
    end
    local size=Sim.W*Sim.H
    if not index(id,size) then return nil,"INVALID_RAIL_SPAN" end
    local chosen=s.tiles[id]
    local key=chosen and chosen.rail_span_id
    if not index(key,2^31-1) then return nil,"INVALID_RAIL_SPAN" end
    local p=(s.stock_rail_spans or {})[key]
    if type(p)~="table" or p.transport~="rail" or p.kind~="bridge" and p.kind~="tunnel" or
        p.railtype~=0 and p.railtype~=1 or type(p.owner)~="string" or p.owner=="" or
        not index(p.start,size) or not index(p["end"],size) or p.start==p["end"] or
        id~=p.start and id~=p["end"] or type(p.middle)~="table" or type(p.middle_by_tile)~="table" then
      return nil,"INVALID_RAIL_SPAN"
    end
    local x,z=Sim.xy(p.start)
    local xx,zz=Sim.xy(p["end"])
    local dx,dz=xx-x,zz-z
    if dx~=0 and dz~=0 then return nil,"INVALID_RAIL_SPAN" end
    local sx=dx==0 and 0 or dx>0 and 1 or -1
    local sz=dz==0 and 0 or dz>0 and 1 or -1
    local dir=sx==1 and Track.SW or sx==-1 and Track.NE or sz==1 and Track.SE or Track.NW
    local axis=dir%2
    local n=math.abs(dx)+math.abs(dz)-1
    if p.axis~=axis or n~=p.middle_length or p.total_length~=n+2 or #p.middle~=n or
        p.kind=="bridge" and p.bridge_type~=0 then return nil,"INVALID_RAIL_SPAN" end
    local function portal(h,at,other,sd)
      local t=s.tiles[at]
      return t and t.build=="stock_rail_"..p.kind and t.owner==p.owner and
        t.rail_span_id==key and t.rail_tracks==nil and type(h)=="table" and
        h.id==at and h.other==other and h.inside_direction==sd and h.dir==sd and
        h.axis==axis and h.trackbits==2^axis and h.skip==n and
        h.kind==p.kind and h.transport=="rail" and h.owner==p.owner and h.railtype==p.railtype
    end
    if not portal(p.head,p.start,p["end"],dir) or not portal(p.tail,p["end"],p.start,Track.reverse_side(dir)) then
      return nil,"INVALID_RAIL_SPAN"
    end
    local layer=s[p.kind=="bridge" and "rail_bridge_above" or "rail_tunnel_below"]
    local middle={}
    for k in pairs(p.middle) do if not index(k,n) then return nil,"INVALID_RAIL_SPAN" end end
    for i=1,n do
      local expected=Sim.id(x+i*sx,z+i*sz)
      if p.middle[i]~=expected or p.middle_by_tile[expected]~=true or not layer or layer[expected]~=key then
        return nil,"INVALID_RAIL_SPAN"
      end
      middle[i]=expected
    end
    local marked=0
    for _,yes in pairs(p.middle_by_tile) do
      if yes~=true then return nil,"INVALID_RAIL_SPAN" end
      marked=marked+1
    end
    if marked~=n then return nil,"INVALID_RAIL_SPAN" end
    local from_head=id==p.start
    return {
      kind=p.kind,transport=p.transport,owner=p.owner,railtype=p.railtype,
      other=from_head and p["end"] or p.start,length=n,axis=axis,
      trackbits=2^axis,dir=from_head and dir or Track.reverse_side(dir),
      span_id=key,start=p.start,finish=p["end"],middle=middle,
    }
  end
  local function reserved_supplier(s)
    local state=s.stock_rail_dispatch
    return state and #state.runs>0
  end
  local function busy(s)
    return s.stock_rail_run or reserved_supplier(s)
  end
  local function authority(s,owner)
    local c=s.companies and s.companies[owner]
    return c and c.cash or 100000
  end
  local function terrain(s,id)
    local x,z=Sim.xy(id)
    return Terrain.tile(s.corner_grid,x,z)
  end
  local function raw_board(s)
    local q={xy=Sim.xy,id=Sim.id,max_x=Sim.W-1}
    function q.tile(id)
      local t=s.tiles[id]
      if not t then return end
      local shape,base,top=terrain(s,id)
      if shape==nil then return end
      local h=span_head(s,id)
      local dirt={slope=shape,base=base,max_z=top,owner=t.owner,kind="clear"}
      if h then
        for k,v in pairs(h) do dirt[k]=v end
        dirt.base,dirt.slope,dirt.max_z=base,shape,top
      elseif t.rail_tracks then
        dirt.kind=t.rail_depot_dir and "depot" or t.rail_station_id and "station" or "rail"
        dirt.railtype=t.rail_type or 0
      elseif t.tunnel_id or t.road_tunnel_id then dirt.kind="tunnel";dirt.transport="road"
      elseif t.road_bridge_id then
        local st=s.stock_road_bridges and s.stock_road_bridges[t.road_bridge_id]
        dirt.kind="bridge";dirt.transport="road";dirt.axis=st and st.axis;dirt.deck=st and st.deck
        if not dirt.deck then dirt.kind="obstructed" end
      elseif t.build=="road" then dirt.kind="road"
      elseif t.terrain=="water" and not (t.ship or t.build) then dirt.kind="water"
      elseif Sim.is_owned_land and Sim.is_owned_land(t) then dirt.kind="owned_land"
      elseif t.wood or t.site or t.house or t.build or t.tram or t.ship or t.airfield or t.stock_industry or t.stock_landmark or t.owner then
        dirt.kind="obstructed"
      end
      dirt.underground=by_tunnel_middle(s,id) or s.tunnel_below and s.tunnel_below[id]
      local k=s.bridge_above and s.bridge_above[id]
      local a=s.aqueduct_above and s.aqueduct_above[id]
      local o=W.by_bridge_middle(s,id) or k and s.stock_road_bridges and s.stock_road_bridges[k]
        or a and s.stock_aqueducts and s.stock_aqueducts[a]
      if o then dirt.overhead={deck=o.deck,axis=o.axis} end
      return dirt
    end
    function q.clear_quote(_,t,role,owner)
      if t.kind=="owned_land" and not t.overhead and not t.underground then
        if t.owner==owner then return -Sim.owned_land_resale() end
        return nil,"OWNED_BY_ANOTHER"
      end
      if t.kind~="clear" or t.owner or t.overhead or t.underground then
        return nil,"Choose a clear rail portal tile; the existing layer is protected."
      end
      return 20 -- Ordinary grass, stock density > 0, before construction.
    end
    function q.tunnel_in_way(id,level)
      local below=by_tunnel_middle(s,id)
      local key=s.tunnel_below and s.tunnel_below[id]
      local older=key and s.stock_road_tunnels and s.stock_road_tunnels[key]
      return below and below.base==level or older and older.base==level or false
    end
    return q
  end
  local function precheck(s,allow_running)
    if not s.rail_span_enabled then return nil,"Enable the rail spans preview first." end
    if not allow_running and busy(s) then return nil,"Clear the running train before editing spans." end
    if not s.corner_grid then return nil,"Rail spans need shared-corner terrain." end
    return true
  end
  local function quote(s,owner,plan,why,where)
    if not plan then return nil,why,where end
    plan.topology=s.topology
    plan.owner=owner
    return plan
  end
  local function spec(s,owner,gauge,available)
    gauge=gauge or 0
    if gauge~=0 and not ((gauge==2 or gauge==3) and available and available(owner,gauge)) then
      return nil,"Rail type is not available for this structure."
    end
    return {owner=owner,budget=authority(s,owner),railtype=gauge,
      can_build_railtype=function(r) return r==gauge end}
  end
  function W.quote_bridge(s,owner,a,b,gauge,available,style)
    style=style or 0
    if not has_style(style,gauge) or not Bridge.catalog[style] then
      return nil,"This bridge style is not available for this railway."
    end
    local old=a and W.by_portal(s,a)
    local replacing=old and old.kind=="bridge" and b and W.by_portal(s,b)==old and a~=b
      and (old.start==a and old["end"]==b or old.start==b and old["end"]==a)
    local ok,err=precheck(s,replacing)
    if not ok then return nil,err end
    local options,e=spec(s,owner,gauge,available)
    if not options then return nil,e end
    local terrain_board=raw_board(s)
    if Sim.date then options.year=Sim.date(s) end
    if replacing then
      -- All ground classes this adapter could legally mount on a
      -- native rail span. Other stock tile handlers are still unmounted.
      function terrain_board.check_build_above(_,t)
        if t.kind=="clear" or t.kind=="water" or t.kind=="road" or t.kind=="rail"
          or t.kind=="signals" or t.kind=="tunnel" then return 0 end
        return nil,"BRIDGE_MIDDLE_OBSTRUCTED"
      end
    end
    local p,why,id=Bridge.plan(terrain_board,a,b,style,options)
    if p and p.replacement then
      if not replacing or p.axis~=old.axis or p.deck~=old.deck or #p.middle~=#old.middle then
        return nil,"The existing bridge geometry changed."
      end
      local key=s.tiles[a].rail_span_id
      for i,id in ipairs(p.middle) do
        if id~=old.middle[i] or not s.rail_bridge_above or s.rail_bridge_above[id]~=key then
          return nil,"The existing bridge layer changed.",id
        end
      end
    elseif p then
      -- First renderer doesn't stack rail infrastructure over other
      -- portals, roads with worn metadata, or another span layer.
      for _,tile in ipairs({p.start,p["end"]}) do
        if W.protected(s,tile) or terrain_board.tile(tile).overhead then return nil,"That rail portal layer is occupied.",tile end
      end
      for _,tile in ipairs(p.middle) do
        local record=terrain_board.tile(tile)
        if record.kind=="bridge" or W.by_portal(s,tile) or
            (Sim.crossing_protected and Sim.crossing_protected(s,tile)) then
          return nil,"This preview does not layer railway portals or level crossings.",tile
        end
      end
    end
    return quote(s,owner,p,why,id)
  end
  function W.quote_tunnel(s,owner,start,gauge,available)
    local ok,err=precheck(s)
    if not ok then return nil,err end
    local options,e=spec(s,owner,gauge,available)
    if not options then return nil,e end
    local board=raw_board(s)
    local p,why,id=Tunnel.plan(board,start,options)
    if p then
      if p.excavation or p.tail.slope~=15-p.head.slope then
        return nil,"The native portal needs an unmodified opposite slope.",p["end"]
      end
      for _,tile in ipairs(p.middle) do
        if by_tunnel_middle(s,tile) or s.tunnel_below and s.tunnel_below[tile] or
            W.by_portal(s,tile) or s.tiles[tile].road_tunnel_id or
            (Sim.crossing_protected and Sim.crossing_protected(s,tile)) then
          return nil,"This preview does not stack tunnels.",tile
        end
      end
    end
    return quote(s,owner,p,why,id)
  end
  function W.commit(s,owner,p,available)
    if not p or p.topology~=s.topology or p.owner~=owner then return false,"The railway changed. Quote it again." end
    local checked,why,at
    if p.kind=="bridge" then checked,why,at=W.quote_bridge(s,owner,p.start,p["end"],p.railtype,available,p.bridge_type)
    elseif p.kind=="tunnel" then checked,why,at=W.quote_tunnel(s,owner,p.start,p.railtype,available)
    else return false,"No rail span selected." end
    if not checked then return false,why,at end
    if checked.price~=p.price or checked["end"]~=p["end"] then return false,"The span price or geometry changed. Quote it again." end
    p=checked
    if p.replacement then
      -- CmdBuildBridge keeps both physical ramp tiles and the PBS path.
      -- Claim ownership is held separately by the dispatch ledger, so
      -- leave it, the active consist and the indices entirely untouched.
      local old=assert(W.by_portal(s,p.start))
      old.bridge_type,old.spec=p.bridge_type,p.spec
      for _,head in ipairs({old.head,old.tail}) do
        head.bridge_type,head.bridge_speed=p.bridge_type,p.spec.speed
      end
      local c=Sim.company(s,owner)
      c.cash,c.expense,c.month_exp=c.cash-p.price,c.expense+p.price,c.month_exp+p.price
      s.topology=s.topology+1
      local dirty={p.start,p["end"]}
      for _,id in ipairs(p.middle) do dirty[#dirty+1]=id end
      return true,("Rail bridge upgraded for $%d. Its track and reservations are unchanged."):format(p.price),
        dirty,p.deck,old
    end
    local key=s.next_stock_rail_span or 1
    s.next_stock_rail_span=key+1
    s.stock_rail_spans=s.stock_rail_spans or {}
    s.stock_rail_spans[key]=p
    local dirty={p.start,p["end"]}
    for _,id in ipairs(p.clears or {}) do
      local t=s.tiles[id]
      if Sim.is_owned_land and Sim.is_owned_land(t) then t.owner,t.stock_object=nil,nil end
    end
    for _,id in ipairs(dirty) do
      local t=s.tiles[id]
      t.build,t.owner,t.rail_span_id=p.kind=="bridge" and "stock_rail_bridge" or "stock_rail_tunnel",owner,key
    end
    local index=p.kind=="bridge" and "rail_bridge_above" or "rail_tunnel_below"
    s[index]=s[index] or {}
    for _,id in ipairs(p.middle) do s[index][id]=key;dirty[#dirty+1]=id end
    local c=Sim.company(s,owner)
    c.cash,c.expense,c.month_exp=c.cash-p.price,c.expense+p.price,c.month_exp+p.price
    s.topology=s.topology+1
    return true,("Rail %s built for $%d."):format(p.kind,p.price),dirty,p.deck,p
  end
  function W.clear(s,owner,id)
    local permitted,err=precheck(s)
    if not permitted then return false,err end
    local p=W.by_portal(s,id)
    if not p or p.owner~=owner then return false,"Choose your rail span portal." end
    local key=s.tiles[id].rail_span_id
    local dirty={p.start,p["end"]}
    for _,portal in ipairs(dirty) do
      local tile=s.tiles[portal]
      tile.build,tile.owner,tile.rail_span_id=nil,nil,nil
    end
    local index=p.kind=="bridge" and "rail_bridge_above" or "rail_tunnel_below"
    for _,middle in ipairs(p.middle) do s[index][middle]=nil;dirty[#dirty+1]=middle end
    s.stock_rail_spans[key]=nil
    local price=p.total_length*((p.kind=="bridge" and 50 or 30)-70)
    local c=Sim.company(s,owner)
    c.cash,c.expense,c.month_exp=c.cash-price,c.expense+price,c.month_exp+price
    s.topology=s.topology+1
    return true,"Rail span cleared; the terrain was retained.",dirty,p.deck
  end

  function W.board(s,base,enabled)
    if not enabled or not s.rail_span_enabled then return base end
    local b=copy(base)
    b.span_enabled=true
    function b.tile(id)
      local h=span_head(s,id)
      return h or (id~=nil and base.tile(id))
    end
    local pixel,profile=Height.bind(base,function(id) return terrain(s,id) end)
    function b.stock_height(id,x,y)
      local _,p=span_head(s,id)
      if p then
        return p.kind=="bridge" and Bridge.pixel(p,id,x,y) or Tunnel.pixel(p,id)
      end
      return pixel(id,x,y)
    end
    function b.span_seam(from,td,to,next_td)
      if not (W.by_portal(s,from) or W.by_portal(s,to)) then return true end
      local function level(id,direction,f)
        local z=W.presentation(s,id,direction,f)
        if z~=nil then return z end
        local record=profile(id)
        return record and Height.render(record,direction,f)
      end
      local a,c=level(from,td,1),level(to,next_td,0)
      return a~=nil and c~=nil and a==c
    end
    function b.span_middle(portal,id)
      local p=W.by_portal(s,portal)
      return p and p.middle_by_tile[id]
    end
    return b
  end
  function W.presentation(s,id,td,f,part)
    local head,plan=span_head(s,id)
    if head and plan.kind=="tunnel" then return plan.base,0 end
    if head and plan.kind=="bridge" then
      if head.flat_ramp or part and part.wormhole then return plan.deck,0 end
      local enters=Track.exit_side(td)==head.dir
      local a=enters and f or 1-f
      return head.base+a,math.atan(enters and .5 or -.5)
    end
    local middle=W.by_bridge_middle(s,id)
    if middle and part and part.wormhole then return middle.deck,0 end
    local bore=part and part.wormhole and by_tunnel_middle(s,id)
    if bore and bore.kind=="tunnel" and bore.middle_by_tile[id] then return bore.base,0 end
  end
  return W
end
