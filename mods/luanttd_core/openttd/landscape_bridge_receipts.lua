-- SPDX-License-Identifier: GPL-2.0-only
-- Detached receipts for the actual native timber road bridge command.
-- Planning, ownership, geometry, occupancy and pricing stay in Sim.
return function(Sim,Authority)
  local M={}
  local max_changes=66 -- stock 64 middle tiles plus two ramps
  local fields={terrain=true,h=true,variant=true,stock_clear_ground=true,stock_clear_density=true,coastal_water=true,
    water_class=true,stock_river_bits=true,stock_water_rocks=true,build=true,owner=true,road_bits=true,
    road_bridge_id=true}
  local untracked_maps={"level_crossing_tiles","aqueduct_above","tunnel_below","rail_bridge_above",
    "rail_tunnel_below","stock_farm_fields","road_oneway_removed"}
  local function plain(v) return type(v)=="table" and getmetatable(v)==nil end
  local function int(v,lo,hi) return type(v)=="number" and v>=lo and v<=hi and v==math.floor(v) end
  local function copy(v)
    local out={}
    for k,x in pairs(v) do out[k]=x end
    return out
  end
  local function different(a,b)
    for k,v in pairs(a) do if b[k]~=v then return true end end
    for k,v in pairs(b) do if a[k]~=v then return true end end
    return false
  end

  function M.bind(s,world,company,owner,side_guard)
    assert(plain(s) and type(world)=="string" and type(company)=="string" and plain(owner))
    assert(side_guard==nil or type(side_guard)=="function")
    local width,depth=Sim.W,Sim.H
    local R={}
    local function physical(id)
      return int(id,1,width*depth) and plain(s.tiles[id]) and s.tiles[id]
    end
    local function world_ready()
      if not plain(s.corner_grid) or s.corner_grid.width~=width or s.corner_grid.depth~=depth or
         Sim.W~=width or Sim.H~=depth or not plain(s.tiles) then return nil,"WORLD_DIMENSIONS_CHANGED" end
      if not int(s.topology,0,9007199254740990) or not int(s.corner_grid.revision,0,9007199254740990) then
        return nil,"UNKNOWN_WORLD_REVISION"
      end
      if not plain(s.companies) or not plain(s.companies[company]) then return nil,"COMPANY_REQUIRED" end
      if not plain(s.fleet) then return nil,"MISSING_NATIVE_FLEET" end
      for _,key in ipairs(untracked_maps) do
        if s[key]~=nil and not plain(s[key]) then return nil,"UNREVIEWED_LAYER" end
      end
      if s.bridge_above~=nil and not plain(s.bridge_above) or
          s.stock_road_bridges~=nil and not plain(s.stock_road_bridges) then return nil,"UNREVIEWED_LAYER" end
      if side_guard and side_guard() then return nil,"UNREVIEWED_LAYER_OR_ACTOR" end
      return true
    end

    local function path(a,b)
      if not physical(a) or not physical(b) then return nil,"INVALID_HEAD" end
      local x,z=Sim.xy(a)
      local u,v=Sim.xy(b)
      if a==b or x~=u and z~=v then return nil,"HEADS_MUST_ALIGN" end
      if u<x or v<z then x,z,u,v=u,v,x,z end
      local dx,dz=x==u and 0 or 1,z==v and 0 or 1
      local length=(u-x)+(v-z)+1
      if length>max_changes then return nil,"PROTECTED_SPAN_TOO_LONG" end
      local row={}
      for i=0,length-1 do row[i+1]=assert(Sim.id(x+i*dx,z+i*dz)) end
      return row
    end
    local function exact_path(row,p)
      if not p or p.start~=row[1] or p["end"]~=row[#row] or #p.middle~=#row-2 then return false end
      for j=2,#row-1 do if p.middle[j-1]~=row[j] then return false end end
      return true
    end
    local function allowed(row,key)
      for i,id in ipairs(row) do
        local t=physical(id)
        if not t then return nil,"MISSING_TILE" end
        for k in pairs(t) do if not fields[k] then return nil,"UNREVIEWED_TILE",id end end
        if t.stock_clear_density~=nil and t.stock_clear_density~=0 then return nil,"UNREVIEWED_GROUND",id end
        if t.terrain~="grass" and t.terrain~="hill" and t.terrain~="water" then return nil,"UNREVIEWED_GROUND",id end
        for _,map in ipairs(untracked_maps) do
          if s[map] and s[map][id]~=nil then return nil,"PROTECTED_LAYER",id end
        end
        if s.stock_generated_profile and t.build==nil and t.terrain~="water" and
            (t.stock_clear_ground~=nil or t.stock_clear_density~=0) then
          return nil,"UNREVIEWED_GROUND",id
        end
        local high=s.bridge_above and s.bridge_above[id]
        local head=(i==1 or i==#row)
        if head then
          if high~=nil then return nil,"PROTECTED_OVERHEAD",id end
          if key then
            if t.build~="stock_road_bridge" or t.road_bridge_id~=key or t.owner~=company then
              return nil,"MISMATCHED_BRIDGE_HEAD",id
            end
          elseif t.build~=nil or t.road_bridge_id~=nil or t.owner~=nil or t.terrain=="water" or t.road_bits~=nil then
            return nil,"UNREVIEWED_HEAD",id
          end
        else
          if high~=key then return nil,key and "MISMATCHED_BRIDGE_LAYER" or "PROTECTED_OVERHEAD",id end
          if t.road_bridge_id or t.build~=nil and t.build~="road" then return nil,"UNREVIEWED_UNDERLAY",id end
          if (t.build=="road" and not int(t.road_bits,1,15)) or (t.build==nil and t.road_bits~=nil) then
            return nil,"UNREVIEWED_UNDERLAY",id
          end
        end
      end
      return true
    end

    local function quote(action,a,b)
      local ready,why=world_ready()
      if not ready then return nil,why,"unsupported" end
      local row,key,price,p
      if action=="remove" then
        local t=physical(a)
        key=t and t.road_bridge_id
        local stored=key and s.stock_road_bridges and s.stock_road_bridges[key]
        if not stored or stored.owner~=company then return nil,"SELECT_OWN_BRIDGE","denied" end
        if stored.bridge_type~=0 or stored.replacement then return nil,"ONLY_NATIVE_TIMBER","unsupported" end
        row,why=path(stored.start,stored["end"])
        if not row or not exact_path(row,stored) or (a~=row[1] and a~=row[#row]) then
          return nil,why or "MISMATCHED_BRIDGE_FOOTPRINT","unsupported"
        end
      elseif action=="build" then
        row,why=path(a,b)
        if not row then return nil,why,"unsupported" end
      else return nil,"UNSUPPORTED_COMMAND","unsupported" end
      local approved,problem,at=allowed(row,key)
      if not approved then return nil,problem,"unsupported",at end

      -- These are the same pure-read branches used by the live commands.
      -- Removal goes through the unchanged owner and v.route guards.
      local ok
      if key then ok,price,p=Sim.remove_wood_bridge(s,company,a,true)
      else ok,price,p=Sim.road_bridge(s,company,a,b,0,true) end
      if not ok then return nil,price,"denied" end
      if not exact_path(row,p) or p.bridge_type~=0 or p.owner~=company or p.replacement then
        return nil,"UNPROVED_NATIVE_BRIDGE_PLAN","unsupported"
      end
      local changes={}
      for i,id in ipairs(row) do
        changes[i]=(i==1 or i==#row) and {kind="tile",host=id} or
          {kind="layer",layer="bridge_above",host=id}
      end
      return {action=action,start=a,last=b,bridge=key,deck=p.deck,price=price,tiles=row,changes=changes,
        revision=owner.revision(),topology=s.topology,terrain_revision=s.corner_grid.revision}
    end
    R.quote=quote

    function R.run(action,a,b)
      local q,reason,mode,at=quote(action,a,b)
      if not q then return nil,reason,mode,at end
      local token,err,state=owner.preflight({schema=Authority.SCHEMA,world=world,revision=q.revision,
        changes=q.changes},"boundary")
      if not token then return nil,err,state end
      local out
      local result,answer,disposition=owner.run(token,"boundary",function()
        assert(s.topology==q.topology and s.corner_grid.revision==q.terrain_revision)
        assert(world_ready() and allowed(q.tiles,q.bridge),"Native bridge proof became stale")
        local cells={}
        for _,id in ipairs(q.tiles) do
          cells[id]={tile=copy(s.tiles[id]),high=s.bridge_above and s.bridge_above[id]}
        end
        local balance=s.companies[company].cash
        local wrote,text,dirty,deck
        if action=="build" then wrote,text,dirty,deck=Sim.road_bridge(s,company,a,b,0)
        else wrote,text,dirty,deck=Sim.remove_wood_bridge(s,company,a) end
        assert(wrote and plain(dirty) and deck==q.deck and balance-s.companies[company].cash==q.price)
        assert(s.topology==q.topology+1 and s.corner_grid.revision==q.terrain_revision)
        local key=action=="build" and s.tiles[q.tiles[1]].road_bridge_id or q.bridge
        local stored=s.stock_road_bridges[key]
        if action=="build" then
          assert(exact_path(q.tiles,stored) and stored.owner==company and stored.deck==deck)
        else assert(stored==nil) end
        local changes,seen={},{}

        -- Receipt deliberately derives layer-vs-tile from the actual
        -- native return AND before/after owner records, not q.changes.
        assert(#dirty==#q.tiles)
        for i,id in ipairs(dirty) do
          local before=cells[id]
          assert(before and not seen[id],"Unexpected/duplicate physical dirty tile")
          seen[id]=true
          for _,map in ipairs(untracked_maps) do
            assert(not s[map] or s[map][id]==nil,"Native bridge touched an unattested protection map")
          end
          local tile,high=s.tiles[id],s.bridge_above and s.bridge_above[id]
          local tile_changed,layer_changed=different(tile,before.tile),high~=before.high
          assert(tile_changed~=layer_changed,"Expected exactly one physical write class per registered bridge tile")
          if tile_changed then
            local expected=copy(before.tile)
            if action=="build" then
              expected.build,expected.owner,expected.road_bridge_id="stock_road_bridge",company,key
            else expected.build,expected.owner,expected.road_bridge_id=nil,nil,nil end
            assert(not different(tile,expected),"Bridgehead touched unexpected native fields")
            changes[i]={kind="tile",host=id}
          else
            if action=="build" then assert(high==key) else assert(before.high==key and high==nil) end
            changes[i]={kind="layer",layer="bridge_above",host=id}
          end
        end
        out={message=text,dirty=dirty,changes=changes,price=q.price,deck=deck,bridge=key}
        return changes
      end)
      if not result then return nil,answer,disposition end
      out.membership_updates=answer
      return true,out,disposition
    end
    return R
  end
  return M
end
