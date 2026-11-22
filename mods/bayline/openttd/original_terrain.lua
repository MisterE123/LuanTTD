-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors: 14.1 src/landscape.cpp Original temperate branch,
-- src/heightmap.cpp FixSlopes, src/water_cmd.cpp water/shore conversion,
-- src/map_func.h ScaleBySize, and src/core/random_func.cpp Randomizer.
-- OpenGFX/TTD MAPGEN sample grids supplied externally, never bundled.
return function(Slope)
  local G={}
  local floor,min,max=math.floor,math.min,math.max
  local byte,char=string.byte,string.char
  local U32=4294967296
  local function int(n,lo,hi)
    return type(n)=="number" and n>=lo and n<=hi and floor(n)==n
  end
  local function rotr(n,k) return floor(n/2^k)+n%2^k*2^(32-k) end
  local function xor(a,b)
    local v,m=0,1
    for _=1,32 do
      if a%2~=b%2 then v=v+m end
      a,b,m=floor(a/2),floor(b/2),m*2
    end
    return v
  end
  function G.next_random(state)
    local a,b=state[1],state[2]
    state[1]=(a+rotr(xor(b,0x1234567f),7)+1)%U32
    state[2]=(rotr(a,3)-1)%U32
    return state[2]
  end

  local N={10,22,33,37}
  local sizes={}
  for k=6,12 do sizes[2^k]=k end
  local BAND=16
  local expected_count=37
  -- Versioned local interchange (not an OpenTTD GRF reader): magic, then
  -- 37 zero-offset rows of width(u8), depth(u8), width*depth palette bytes.
  function G.read_masks(data)
    if type(data)~="string" or data:sub(1,8)~="OTMAPGEN" then return nil,"bad terrain mask header" end
    local templates,p={},9
    for i=1,expected_count do
      local w,h=byte(data,p,p+1)
      if not w or not h or w==0 or h==0 or p+1+w*h>#data then return nil,"bad terrain mask dimensions at "..i end
      templates[i]={width=w,depth=h,data=data:sub(p+2,p+1+w*h)}
      p=p+2+w*h
    end
    if p~=#data+1 then return nil,"trailing terrain mask bytes" end
    return templates
  end
  local function template_valid(t)
    return t and int(t.width,1,255) and int(t.depth,1,255) and
      type(t.data)=="string" and #t.data==t.width*t.depth
  end

  -- Orient the small template bank once; each raw byte's low nibble
  -- goes to exactly the same x,z as the four source orientation loops.
  local function prepare(bank,count)
    local all,max_depth={},1
    for index=1,count do
      local t=bank[index]
      for dir=0,3 do
        local w,h=t.width,t.depth
        if dir%2==1 then w,h=h,w end
        local rows={}
        for z=1,h do
          local row={}
          for x=1,w do
            local u,v
            if dir==0 then u,v=x,z
            elseif dir==1 then u,v=z,x
            elseif dir==2 then u,v=w+1-x,z
            else u,v=h+1-z,x end
            row[x]=byte(t.data,(v-1)*t.width+u)%16
          end
          rows[z]=char(unpack(row,1,w))
        end
        all[(index-1)*4+dir+1]={width=w,depth=h,rows=rows}
        max_depth=max(max_depth,h)
      end
    end
    return all,max_depth
  end

  local function stamp_recipes(w,h,log_x,freeform,count,templates,attempts,state)
    -- A recipe is x(low byte,high byte), oriented template(u8). Its
    -- source row is the bucket index. This is bounded by actual attempts,
    -- not number of covered cells, and never contains a dense Lua heightmap.
    local recipes={}
    local edge=freeform and 2 or 1
    for _=1,attempts do
      local r=G.next_random(state)
      local x,z=r%w,floor(r/2^log_x)%h
      if x>edge and z>edge then
        -- On a 4096² map two direction bits overlap the Z coordinate.
        -- Deliberately derive everything from the original single draw.
        local dir=floor(r/2^22)%4
        local index=floor(floor(r/2^24)*count/256)*4+dir+1
        local template=templates[index]
        if x+template.width<w-1 and z+template.depth<h-1 then
          local row=z+1
          recipes[row]=(recipes[row] or "")..char(x%256,floor(x/256),index)
        end
      end
    end
    return recipes
  end

  local function raster_stamps(w,h,templates,max_depth,recipes)
    local rows,bands={},{}
    -- Replay max-height overlays by band. Max is associative and
    -- commutative, so separating the RNG pass and sampling by source
    -- start row preserves every output byte even through overlaps.
    for first=1,h,BAND do
      local last=min(h,first+BAND-1)
      for z=first,last do
        local i=z-first+1
        local row=bands[i] or {}
        bands[i]=row
        for x=1,w do row[x]=0 end
      end
      for z=max(1,first-max_depth+1),last do
        local packed=recipes[z]
        if packed then
          for i=1,#packed,3 do
            local lo,hi,index=byte(packed,i,i+2)
            local t=templates[index]
            local x=lo+256*hi -- absolute zero-based source X
            for y=max(first,z),min(last,z+t.depth-1) do
              local src=t.rows[y-z+1]
              local row=bands[y-first+1]
              for dx=1,t.width do
                local sample=byte(src,dx)
                local u=x+dx
                if sample>row[u] then row[u]=sample end
              end
            end
          end
        end
      end
      for z=first,last do rows[z]=char(unpack(bands[z-first+1],1,w)) end
    end
    return rows
  end

  -- Literal decreasing-only FixSlopes. Repack one row at a time, so
  -- the forward/backward pass sees the already fixed neighboring row
  -- in precisely the original order, with no second full map plane.
  local function fix_slopes(rows,w,h)
    local scratch={}
    local sentinel=string.rep(char(255),w)
    local function sweep(a,b,step)
      local neighbor=sentinel
      local x1,x2=step==1 and 1 or w,step==1 and w or 1
      for z=a,b,step do
        local row=rows[z]
        local previous,changed=255,false
        for x=x1,x2,step do
          local ceiling=min(previous,byte(neighbor,x))+1
          local value=byte(row,x)
          if value>ceiling then value,changed=ceiling,true end
          scratch[x],previous=value,value
        end
        if changed then row=char(unpack(scratch,1,w));rows[z]=row end
        neighbor=row
      end
    end
    sweep(1,h,1)
    sweep(h,1,-1)
  end

  local CLEAR,WATER,VOID=0,6,7
  -- Bitfields from source water_cmd.cpp (OpenTTD Direction, not DiagDirection).
  local flood={[0]=170,10,130,2,160,0,128,131,40,8,0,14,32,56,224}
  local dx,dz={[0]=-1,-1,-1,0,1,1,1,0},{[0]=-1,0,1,1,1,0,-1,-1}
  local raised={[1]=true,[2]=true,[4]=true,[8]=true}
  local function void(freeform,x,z,width,depth)
    return x==width or z==depth or freeform and (x==1 or z==1)
  end
  local function slope(rows,w,h,x,z)
    local v=rows[min(z+1,h)]
    local r=rows[z]
    local u=min(x+1,w)
    return Slope.classify(byte(r,x),byte(r,u),byte(v,x),byte(v,u))
  end

  function G.describe(word)
    -- Class in low nibble, detached TerrainStream ground enum in next.
    -- Dynamic world adapters may add independent properties above byte 1.
    return word%16,floor(word/16)%16
  end

  function G.generate(opts,bank)
    opts=opts or {}
    local w,h,seed=opts.width,opts.depth,opts.seed
    local log_x,log_z=sizes[w],sizes[h]
    local freeform=opts.freeform_edges~=false
    local terrain,sea=opts.terrain_type or 1,opts.quantity_sea_lakes or 1
    assert(log_x and log_z,"Original terrain requires power-of-two stock axes, 64–4096")
    assert(int(seed,0,U32-1),"Original terrain requires a uint32 seed")
    assert(int(terrain,0,3) and int(sea,0,3),"Original temperate terrain/sea settings out of range")
    assert(type(bank)=="table" and #bank==expected_count,"Original terrain needs 37 externally supplied templates")
    local digest=opts.masks_sha256
    if digest then
      assert(type(digest)=="string" and #digest==64 and digest:match("^[a-f0-9]+$"),
        "Invalid caller-verified template SHA-256")
    end
    for i=1,expected_count do assert(template_valid(bank[i]),"Invalid Original terrain template #"..i) end

    local state={seed,seed}
    local r=G.next_random(state)
    local stamps=floor(((r%128+(3-sea)*256+100)*2^(log_x+log_z-12)+15)/16)
    local function stamped()
      local count=N[terrain+1]
      local templates,max_depth=prepare(bank,count)
      local recipes=stamp_recipes(w,h,log_x,freeform,count,templates,stamps,state)
      return raster_stamps(w,h,templates,max_depth,recipes)
    end
    local rows=stamped()
    fix_slopes(rows,w,h)
    local V={width=w,depth=h,seed=seed,freeform=freeform,stamp_count=stamps,rng_after=state}
    local base_id=digest and ("ott14.1-original-v1/"..w.."x"..h.."/"..seed.."/"..terrain.."/"..sea.."/"..(freeform and 1 or 0).."/"..digest)
    function V.generation_footprint()
      return {height_bytes=w*h,stamp_band_rows=BAND,stamp_mutable_cells=w*BAND,sweep_mutable_cells=w}
    end
    function V.corner(x,z)
      if int(x,1,w+1) and int(z,1,h+1) then
        -- WorldStorage stores a fringe beyond its last tile. Stock reads
        -- the final corner again (clamped) for its void boundary tiles.
        return byte(rows[min(z,h)],min(x,w))
      end
    end
    function V.tile(x,z)
      if not int(x,1,w) or not int(z,1,h) then return nil end
      if void(freeform,x,z,w,h) then return VOID end
      local s,b=slope(rows,w,h,x,z)
      if b~=0 then return CLEAR end
      if s==0 then return WATER+16 end -- sea: ground 1
      if raised[s] then return WATER+32 end -- coast: ground 2
      local directions=flood[s%16]
      for d=0,7 do
        if directions%2~=0 then
          local u,v=x+dx[d],z+dz[d]
          local ds=slope(rows,w,h,u,v)%16
          if ds==0 or raised[ds] or void(freeform,u,v,w,h) then return WATER+32 end
        end
        directions=floor(directions/2)
      end
      return CLEAR
    end
    function V.storage_options()
      assert(base_id,"WorldStorage requires caller-verified mask SHA-256")
      return {seed=seed,base_id=base_id,corner=function(_,x,z)return V.corner(x,z) end,
        tile=function(_,x,z)return V.tile(x,z) end}
    end
    return V
  end
  return G
end
