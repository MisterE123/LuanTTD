-- SPDX-License-Identifier: GPL-2.0-only
-- A narrow, detached native command bridge to the landscape authority.
-- The planner and writer are the *existing* Sim methods, not new rules.
return function(Sim,Authority)
  local M={MAX_NATIVE_TILES=256}
  local floor,min,max=math.floor,math.min,math.max
  local function integer(n,a,b) return type(n)=="number" and n>=a and n<=b and floor(n)==n end
  local function plain(t) return type(t)=="table" and getmetatable(t)==nil end
  local function keyset(t,set)
    for k in pairs(t) do if not set[k] then return false end end
    return true
  end
  local command_tile={tool=true,ids=true}
  local command_corner={tool=true,x=true,z=true}
  local physical={terrain=true,h=true,variant=true,wood=true,stock_clear_ground=true,coastal_water=true,
    water_class=true,stock_river_bits=true,parcel=true,house=true,source_house=true,build=true,owner=true,road_bits=true,
    road_town=true} -- town road allowed only as a road-planner read
  local overlays={level_crossing_tiles=true,bridge_above=true,aqueduct_above=true,tunnel_below=true,
    rail_bridge_above=true,rail_tunnel_below=true,road_oneway_removed=true,stock_farm_fields=true}
  local routed={"fleet","stock_owned_air_fleet","stock_rail_fleet","stock_rail_run","stock_coal_ship_run",
    "ship_pilot","tram_pilot"}
  local function active(v) return type(v)=="table" and next(v)~=nil or v~=nil and v~=false and type(v)~="table" end
  local function unreviewed(k)
    return type(k)=="string" and (k:match("^tile_") or k:match("_tile$") or k:match("_tiles$") or
      k:match("_overlays?$") or k:match("_layers?$") or k:match("_above$") or k:match("_below$") or k:match("_by_tile$"))
  end

  -- Company registration takes place outside this proof. Sim.plan and
  -- legacy Sim.landscape quotes open missing companies otherwise.
  function M.bind(s,world_name,company,owner,opts)
    assert(plain(s) and type(world_name)=="string" and type(company)=="string" and #company>0)
    assert(type(owner)=="table" and type(owner.preflight)=="function" and type(owner.run)=="function")
    opts=opts or {}
    -- A real mount must enumerate *all* additional side-layer providers.
    -- This proof accepts none of them. A guard can also veto ephemeral
    -- runs not captured by known saved fields.
    assert(plain(opts) and (opts.untracked==nil or type(opts.untracked)=="function") and
      (opts.additional_layers==nil or plain(opts.additional_layers)))
    local width,depth=Sim.W,Sim.H
    local C={}
    local function host(x,z) return (z-1)*width+x end
    local function xy(id) return (id-1)%width+1,floor((id-1)/width)+1 end
    local function guard_world()
      if not plain(s.corner_grid) or s.corner_grid.width~=width or s.corner_grid.depth~=depth or
        Sim.W~=width or Sim.H~=depth or not plain(s.tiles) then return "HOST_DIMENSIONS_CHANGED" end
      if not integer(s.topology,0,9007199254740990) or
        not integer(s.corner_grid.revision,0,9007199254740990) then return "UNKNOWN_HOST_REVISION" end
      if not plain(s.companies) or not plain(s.companies[company]) then return "COMPANY_REQUIRED" end
      if opts.additional_layers and next(opts.additional_layers) then return "UNREVIEWED_LAYER" end
      for _,k in ipairs(routed) do if active(s[k]) then return "ROUTED_WORLD" end end
      if active(s.stock_rail_dispatch and s.stock_rail_dispatch.runs) or (opts.untracked and opts.untracked()) then
        return "ROUTED_WORLD"
      end
      for k,v in pairs(s) do
        if unreviewed(k) and not overlays[k] and active(v) then return "UNREVIEWED_LAYER" end
      end
    end
    local function guard_tile(id,tool,read)
      local t=s.tiles[id]
      if not plain(t) then return "MISSING_TILE" end
      if not keyset(t,physical) then return "UNREVIEWED_TILE" end
      for k in pairs(overlays) do
        local layer=s[k]
        if layer~=nil and not plain(layer) then return "UNREVIEWED_LAYER" end
        if layer and layer[id]~=nil then return "PROTECTED_LAYER" end
      end
      if t.terrain~="grass" and t.terrain~="hill" and t.terrain~="water" then return "UNREVIEWED_GROUND" end
      if t.terrain=="water" then
        if not read and (tool=="road" or tool=="clear") then return "WATER_TOOL_REQUIRED" end
        if not read and (t.water_class~=nil and t.water_class~="sea" or t.stock_river_bits~=nil
            or not s.stock_coastal_flood) then return "WATER_TOOL_REQUIRED" end
      end
      -- The planner's pure connection read can see a normal public or
      -- private carriageway. The certified write scope is private road.
      if t.build~=nil and t.build~="road" then return "UNSUPPORTED_FACILITY" end
      if t.build=="road" and not integer(t.road_bits,1,15) then return "UNREVIEWED_ROAD" end
      if t.road_town and not read then return "PUBLIC_ROAD" end
      if t.house and not read and tool~="clear" then return "HOUSE_CLEAR_REQUIRED" end
      if t.source_house~=nil and not t.house then return "UNREVIEWED_HOUSE" end
      return nil
    end
    local function parse(spec)
      if not plain(spec) then return end
      local k=spec.tool
      if k=="road" or k=="clear" then
        if not keyset(spec,command_tile) or not plain(spec.ids) then return end
        local n=0
        for i in pairs(spec.ids) do
          if not integer(i,1,M.MAX_NATIVE_TILES) then return end
          n=n+1
        end
        if n==0 then return end
        local ids={}
        for i=1,n do
          if not integer(spec.ids[i],1,width*depth) then return end
          ids[i]=spec.ids[i]
        end
        return k,ids
      elseif k=="raise" or k=="lower" then
        if not keyset(spec,command_corner) or not integer(spec.x,1,width+1) or not integer(spec.z,1,depth+1) then
          return
        end
        return k,nil,spec.x,spec.z
      end
    end
    local function entries(ids)
      local out={}
      for i,id in ipairs(ids) do out[i]={kind="tile",host=id} end
      return out
    end
    function C.quote(spec)
      local illegal=guard_world()
      if illegal then return nil,illegal,"unsupported" end
      local k,ids,x,z=parse(spec)
      if not k then return nil,"UNSUPPORTED_COMMAND","unsupported" end
      local info={tool=k,ids=ids,x=x,z=z,dirty={},changes={},topology=s.topology,
        revision=owner.revision(),terrain_revision=s.corner_grid.revision}
      if ids then
        local checked,selected={},{}
        for _,id in ipairs(ids) do
          illegal=guard_tile(id,k,false)
          if illegal then return nil,illegal,"unsupported" end
          checked[id],selected[id]=true,true
        end
        -- Plain road plan reads reciprocal surfaces from cardinal
        -- neighbors. Don't grant access to special side-layer geometry.
        if k=="road" then
          for _,id in ipairs(ids) do
            local u,v=xy(id)
            for _,d in ipairs(Sim.dir) do
              local a,b=u+d[1],v+d[2]
              if a>=1 and a<=width and b>=1 and b<=depth then
                local id2=host(a,b)
                if not checked[id2] then
                  illegal=guard_tile(id2,k,true)
                  if illegal then return nil,illegal,"unsupported" end
                  checked[id2]=true
                end
              end
            end
          end
        end
        local plan,cost=Sim.plan(s,company,k,ids)
        if not plan then return nil,cost,"denied" end
        info.cost=cost
        for i,item in ipairs(plan) do
          if not selected[item.id] or (item.tool~=k) or (#plan>M.MAX_NATIVE_TILES) or
            (k=="road" and not integer(item.road_bits,1,15)) then
            return nil,"UNPROVED_NATIVE_PLAN","unsupported"
          end
          info.dirty[i]=item.id
        end
        info.changes=entries(info.dirty)
      else
        local ok,cost,plan=Sim.landscape(s,company,k,x,z,nil,nil,nil,"footprint")
        if not ok then return nil,cost,"denied" end
        if not plan or #plan.corners<1 or #plan.corners>M.MAX_NATIVE_TILES or #plan.tiles>M.MAX_NATIVE_TILES or
          plan.terrain_revision~=s.corner_grid.revision or plan.topology~=s.topology then
          return nil,"UNPROVED_NATIVE_PLAN","unsupported"
        end
        info.cost,info.peak=cost,0
        local original={}
        for i,c in ipairs(plan.corners) do
          info.changes[i]={kind="corner",x=c.x,z=c.z}
          info.peak=max(info.peak,c.height)
          for v=max(c.z-1,1),min(c.z,depth) do
            for u=max(c.x-1,1),min(c.x,width) do original[host(u,v)]=true end
          end
        end
        -- Check the real propagated dirty set, not simply clicked
        -- tiles. Bounds and completeness are independent of quote price.
        for i,cell in ipairs(plan.tiles) do
          local id=host(cell.x,cell.z)
          if not original[id] then return nil,"UNPROVED_NATIVE_PLAN","unsupported" end
          original[id]=nil
          illegal=guard_tile(id,k,false)
          if illegal then return nil,illegal,"unsupported" end
          info.dirty[i]=id
        end
        if next(original) then return nil,"UNPROVED_NATIVE_PLAN","unsupported" end
      end
      return info
    end
    function C.run(spec)
      -- Re-quote at execution. Nothing from an advisory quote serves as
      -- a held authorization or a deferred write plan.
      local q,reason,mode=C.quote(spec)
      if not q then return nil,reason,mode end
      if #q.changes==0 then return true,{message="Nothing to change.",dirty={},cost=0},"unchanged" end
      local plan,err,disposition=owner.preflight({schema=Authority.SCHEMA,world=world_name,
        revision=q.revision,changes=q.changes},"boundary")
      if not plan then return nil,err,disposition end
      local result
      local ok,answer,status=owner.run(plan,"boundary",function()
        -- Serialized owner and read-only classification: the exact Sim
        -- planner is called again by its real commit, no speculative rules.
        assert(q.topology==s.topology and q.terrain_revision==s.corner_grid.revision and not guard_world(),
          "Detached command proof became stale before the native writer")
        local cash=s.companies[company].cash
        local wrote,text,dirty,peak
        if q.ids then wrote,text,dirty=Sim.build(s,company,q.tool,q.ids)
        else wrote,text,dirty,peak=Sim.landscape(s,company,q.tool,q.x,q.z) end
        assert(wrote and plain(dirty) and cash-s.companies[company].cash==q.cost and q.peak==peak,
          "Detached command receipt failed")
        result={message=text,dirty=dirty,cost=q.cost,peak=peak}
        return entries(dirty)
      end)
      if not ok then return nil,answer,status end
      result.membership_updates=answer
      return true,result,status
    end
    return C
  end
  return M
end
