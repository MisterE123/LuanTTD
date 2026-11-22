-- Read-only OpenTTD snapshot baseline; no campaign/world startup.
-- Factory arguments: world_storage.lua API, openttd_map.lua factory, SHA-256
-- function returning 64 lowercase hex digits (normally Luanti core.sha256).
return function(W,Map,sha256)
  local M={}
  local floor,min,abs=math.floor,math.min,math.abs
  local byte,char=string.byte,string.char
  local function int(n,lo,hi)
    return type(n)=="number" and n>=lo and n<=hi and n==floor(n)
  end
  local function plain(t) return type(t)=="table" and getmetatable(t)==nil end
  local function u16(n) return char(n%256,floor(n/256)) end
  local function u32(n) return u16(n%65536)..u16(floor(n/65536)) end
  local function at32(s,k)
    local a,b,c,d=byte(s,k,k+3)
    return a+256*b+65536*c+16777216*d
  end
  local function digest(s)
    local out=sha256(s)
    assert(type(out)=="string" and #out==64 and out:match("^[0-9a-f]+$"),"invalid SHA-256 provider")
    return out
  end

  local terrain={}
  -- Reuse the existing hex/schema/void/record-coordinate validator and substitute
  -- a compact corner plane for Terrain.new's one-Lua-number-per-corner grid.
  function terrain.new(w,h,sample)
    local rows={}
    for z=1,h+1 do
      local row={}
      for x=1,w+1 do
        local v=sample(x,z)
        assert(x==1 or abs(v-byte(row[x-1]))<=1,"source X edge exceeds one level")
        assert(z==1 or abs(v-byte(rows[z-1],x))<=1,"source Z edge exceeds one level")
        row[x]=char(v)
      end
      rows[z]=table.concat(row)
    end
    return rows
  end

  local kinds={road=1,crossing=2,depot=3,drive_stop=4,bay_stop=5}
  local common={{"kind","kind"},{"unsupported_for_initial_bus_world","flags"}}
  local groups={
    road={{"disallowed",3},{"town_or_meta_id",65535}},
    crossing={{"axis",1},{"rail_axis",1},{"rail_owner",31},{"reserved","boolean"},{"barred","boolean"},{"town_or_meta_id",65535}},
    depot={{"direction",3},{"depot_id",65535},{"depot_owner",31}},
    drive_stop={{"axis",1},{"station_id",65535},{"station_owner",31},{"stop_type","stop"},{"custom_stop_spec",63}},
    bay_stop={{"direction",3},{"station_id",65535},{"station_owner",31},{"stop_type","stop"},{"custom_stop_spec",63}},
  }
  local order={"one_way_road","rail_crossing","custom_stop","nonstandard_roadtype","tram"}
  local tilegroups={road={{"road_bits",15},{"road_type",62},{"road_owner",31}},
    tram={{"tram_bits",15},{"tram_type",62},{"tram_owner",31}}}
  local function clone_record(incoming,class)
    assert(plain(incoming) and groups[incoming.kind],"invalid snapshot road record")
    local kind=incoming.kind
    assert((class==2 and kinds[kind]<=3) or (class==5 and kinds[kind]>=4),"source road record/class mismatch")
    local checked,bytes={},{}
    local function fields(group)
      for _,spec in ipairs(group) do
        local key,rule=spec[1],spec[2]
        local v=incoming[key]
        if type(rule)=="number" then
          assert(int(v,0,rule),"invalid source road field: "..key)
          bytes[#bytes+1]=u16(v)
        elseif rule=="kind" then bytes[#bytes+1]=char(kinds[v])
        elseif rule=="boolean" then
          assert(type(v)=="boolean","invalid source road field: "..key)
          bytes[#bytes+1]=char(v and 1 or 0)
        elseif rule=="stop" then
          assert(v=="truck" or v=="bus","invalid stock road stop type")
          bytes[#bytes+1]=char(v=="truck" and 1 or 2)
        else
          assert(plain(v),"invalid unsupported source road flags")
          local lookup={}
          for k,flag in pairs(v) do
            assert(int(k,1,#order) and type(flag)=="string" and not lookup[flag],"invalid unsupported source road flag list")
            lookup[flag]=true
          end
          v={}
          local wanted={one_way_road=incoming.disallowed~=nil and incoming.disallowed~=0,
            rail_crossing=kind=="crossing",custom_stop=incoming.custom_stop_spec~=nil and incoming.custom_stop_spec~=0,
            nonstandard_roadtype=incoming.road_type~=nil and incoming.road_type~=0,tram=incoming.tram_type~=nil}
          local mask=0
          for i,flag in ipairs(order) do
            assert((not not wanted[flag])==(not not lookup[flag]),"incorrect or missing unsupported source road flag")
            if lookup[flag] then
              mask=mask+2^(i-1)
              v[#v+1]=flag
              lookup[flag]=nil
            end
          end
          for i=1,#v do assert(incoming[key][i]~=nil,"fragmented unsupported source road flag list") end
          assert(not next(lookup),"unknown unsupported source road flag")
          bytes[#bytes+1]=char(mask)
        end
        checked[key]=v
      end
    end
    fields(common)
    fields(groups[kind])
    local fixed
    if kind=="crossing" or kind=="drive_stop" then
      fixed=checked.axis==0 and 10 or 5
      assert(kind~="crossing" or checked.rail_axis==1-checked.axis,"invalid crossing rail axis")
    elseif kind~="road" then
      fixed=2^(3-checked.direction)
    end
    for _,layer in ipairs({"road","tram"}) do
      local enabled=incoming[layer.."_type"]~=nil
      bytes[#bytes+1]=char(enabled and 1 or 0)
      if enabled then
        fields(tilegroups[layer])
        assert(not fixed or checked[layer.."_bits"]==fixed,"wrong stock road orientation")
      end
    end
    for k in pairs(incoming) do assert(checked[k]~=nil,"unknown source road field") end
    return checked,table.concat(bytes)
  end

  -- Tile classes retain OpenTTD's low four bits; a zero connection mask
  -- differs from an absent transport layer (presence flags are above masks).
  local function pack_tile(class,road_bits,tram_bits)
    if not int(class,0,10) or (road_bits~=nil and not int(road_bits,0,15))
      or (tram_bits~=nil and not int(tram_bits,0,15))
      or ((road_bits~=nil or tram_bits~=nil) and class~=2 and class~=5) then return nil end
    return class+(road_bits and (16+road_bits*32) or 0)+(tram_bits and (512+tram_bits*1024) or 0)
  end

  local function unpack_tile(word)
    if not int(word,0,16383) then return nil end
    local class=word%16
    local road=word%32>=16 and floor(word/32)%16 or nil
    local tram=word%1024>=512 and floor(word/1024)%16 or nil
    if pack_tile(class,road,tram)==word then return class,road,tram end
  end

  M.pack_tile,M.unpack_tile=pack_tile,unpack_tile

  function M.prepare(data)
    assert(type(sha256)=="function","SHA-256 provider required")
    assert(plain(data) and plain(data.source) and (data.source.save_version==333 or data.source.save_version==334),
      "stock 14.1 snapshot source required")
    local source_sha=data.source.sha256
    assert(type(source_sha)=="string" and #source_sha==64 and source_sha:match("^[0-9a-f]+$"),
      "missing source provenance SHA-256")
    assert(plain(data.road_tiles),"plain source road plane required")
    local stage=Map(terrain).prepare(data)
    local w,h=data.width,data.height
    local tw,th=w-1,h-1
    local sw,sh=math.max(64,tw),math.max(64,th)
    local freeform=data.freeform_edges
    local heights,types,roads=stage.corner_grid,{},{}
    -- Retain two rows of single bytes per source cell, not a uint32 array.
    -- Road words are a sparse secondary plane indexed by actual source TileID.
    for z=1,h do
      local row={}
      for x=1,w do row[x]=char(stage.tile_type(x,z) or 7) end
      types[z]=table.concat(row)
    end
    local ids,words,serial={},{},{}
    for key,record in pairs(data.road_tiles) do
      local id=tonumber(key)
      local x,z=id%w+1,floor(id/w)+1
      local info,packed=clone_record(record,byte(types[z],x))
      roads[id]={fields=info,bytes=packed}
      words[id]=pack_tile(byte(types[z],x),info.road_bits,info.tram_bits)
      ids[#ids+1]=id
    end
    table.sort(ids)
    for i,id in ipairs(ids) do
      local packed=roads[id].bytes
      serial[i]=u32(id)..char(#packed)..packed
      roads[id]=roads[id].fields
    end
    local identity=digest("luanttd/openttd-map-base/1\0"..u16(w)..u16(h)..char(freeform and 1 or 0)
      ..digest(table.concat(heights))..digest(table.concat(types))..digest(table.concat(serial)))
    local opts={base_id="openttd-map/1:"..identity,seed=0,
      corner=function(_,x,z) return byte(heights[min(z,h)],min(x,w)) end,
      tile=function(_,x,z)
        if x>tw or z>th then return 7 end
        return words[(z-1)*w+x-1] or byte(types[z],x)
      end}
    -- Never keep the input JSON or stage: closures own compact immutable
    -- strings and copies of the small road records only.
    local base={base_id=opts.base_id,width=tw,depth=th,source_width=w,source_depth=h,
      source_sha256=source_sha,freeform_edges=freeform,can_resume_in_luanti=false}
    local function has_tile(x,z) return int(x,1,tw) and int(z,1,th) end
    local function source_tile_id(x,z)
      if has_tile(x,z) then return (z-1)*w+x-1 end
    end
    base.source_tile_id=source_tile_id
    function base.source_tile_xy(id)
      if int(id,0,w*h-1) then
        local x,z=id%w+1,floor(id/w)+1
        if has_tile(x,z) then return x,z end
      end
    end
    function base.logical_tile_id(x,z)
      if has_tile(x,z) then return (z-1)*tw+x-1 end
    end
    function base.logical_tile_xy(id)
      if int(id,0,tw*th-1) then return id%tw+1,floor(id/tw)+1 end
    end
    function base.source_road_tile(x,z)
      local id=source_tile_id(x,z)
      local rec=id and roads[id]
      if not rec then return nil end
      local out={}
      for k,v in pairs(rec) do
        if type(v)=="table" then
          local copy={}
          for i,flag in ipairs(v) do copy[i]=flag end
          out[k]=copy
        else out[k]=v end
      end
      return out
    end

    local function editable_word(x,z,v)
      local class=unpack_tile(v)
      return has_tile(x,z) and class~=nil and class~=7 and byte(types[z],x)~=7
    end

    local function valid_patch(patch)
      if not plain(patch) then return nil,"invalid stock overlay patch" end
      local n=0
      for k,edit in pairs(patch) do
        n=n+1
        if not int(k,1,8448) or n>8448 or not plain(edit) then return nil,"invalid stock overlay patch" end
        if edit.kind=="tile" then
          if not editable_word(edit.x,edit.z,edit.value) then return nil,"invalid or void stock tile edit" end
        elseif edit.kind=="corner" then
          if not int(edit.x,1,tw) or not int(edit.z,1,th) then return nil,"corner outside editable source lattice" end
        else return nil,"invalid stock overlay edit kind" end
      end
      return true
    end

    local function bind(world)
      local V={}
      function V.stats()
        local info=W.stats(world)
        info.width,info.depth=tw,th
        return info
      end
      function V.encode() return W.encode(world) end
      function V.corner(x,z)
        if int(x,1,w) and int(z,1,h) then return W.get_corner(world,x,z) end
      end
      function V.tile_corners(x,z)
        if has_tile(x,z) then return W.tile_corners(world,x,z) end
      end
      function V.tile(x,z)
        if has_tile(x,z) then return unpack_tile(W.get_tile(world,x,z)) end
      end
      function V.commit(revision,patch)
        local ok,why=valid_patch(patch)
        if not ok then return nil,why end
        return W.commit(world,revision,patch)
      end
      function V.snapshot(x1,z1,x2,z2)
        if not has_tile(x1,z1) or not has_tile(x2,z2) then return nil,"outside stock snapshot bounds" end
        local snap,ticket=W.snapshot(world,x1,z1,x2,z2)
        if snap then snap.map_width,snap.map_depth=tw,th end
        return snap,ticket
      end
      function V.apply_job(ticket,patch)
        local ok,why=valid_patch(patch)
        if not ok then return nil,why end
        return W.apply_job(world,ticket,patch)
      end
      return V
    end

    function base.new_world() return bind(W.new(sw,sh,opts)) end
    function base.load_world(bytes)
      local loaded,err=W.decode(bytes,opts)
      if not loaded then return nil,err end
      local stats=W.stats(loaded)
      if stats.width~=sw or stats.depth~=sh or stats.seed~=0 then return nil,"wrong stock overlay dimensions or seed" end
      -- W.decode verified BLS/1 lengths, ordering, values, callback identity
      -- and edges. Check adapter-level typed words and locked padding too.
      local k=22+#opts.base_id
      for _=1,stats.corners do
        local id=at32(bytes,k)
        if id%(sw+1)+1>tw or floor(id/(sw+1))+1>th then return nil,"corner outside editable source lattice" end
        k=k+5
      end
      for _=1,stats.tiles do
        local id=at32(bytes,k)
        local x,z=id%sw+1,floor(id/sw)+1
        if not editable_word(x,z,at32(bytes,k+4)) then return nil,"invalid or void stock overlay tile" end
        k=k+8
      end
      return bind(loaded)
    end
    return base
  end
  return M
end
