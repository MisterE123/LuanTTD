-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, RC1 landscape.cpp GenerateLandscape,
-- CreateDesertOrRainForest, RunTileLoop and CalculateSnowLine.
-- The port is separate from the game selector until its downstream
-- consumers (rivers, town content, assets, and supply chains) are ready.
return function(Climate,River,Slope)
  local M={}
  local floor,min,max=math.floor,math.min,math.max
  local ground_name={[0]="grass","rough","rocks","fields",[5]="desert"}
  local ground_code={grass=0,rough=1,rocks=2,fields=3,desert=5}
  -- Twenty-four zone states or eight clear-ground overrides per exact
  -- Lua number, not a table or Lua object for every physical tile.
  local function bits(width,count)
    local span=2^width
    local power={}
    for i=0,count-1 do power[i]=span^i end
    local words={}
    local function at(i)
      local j=floor(i/count)+1
      return j,power[i%count],words[j] or 0
    end
    return function(i)
      local _,shift,w=at(i)
      return floor(w/shift)%span
    end,function(i,v)
      local j,shift,w=at(i)
      words[j]=w+(v-floor(w/shift)%span)*shift
    end
  end

  function M.prepare(base,opts)
    opts=opts or {}
    local climate=base.landscape or "temperate"
    if climate~="arctic" and climate~="tropic" then return base end
    local w,d=base.width,base.depth
    local total=w*d
    local zone,set_zone=bits(2,24)
    -- An override is 1 + (raw cover, arranged as 0..5 ground
    -- or 6..7 for water) * 4 + density. Zero means read base.
    local cover,set_cover=bits(6,8)
    local function i_of(x,z) return z*w+x end
    local function xy(i) return i%w,floor(i/w) end
    local function height(x,z) return base.corner(x+1,z+1) end
    local function word(i)
      local ov=cover(i)
      local x,z=xy(i)
      if ov==0 then return base.tile(x+1,z+1) end
      local k=floor((ov-1)/4)
      if k==6 then return 22 end
      if k==7 then return 38 end
      return k*256
    end
    local function density(i)
      local ov=cover(i)
      return ov==0 and 3 or (ov-1)%4
    end
    local function valid(tile) return tile>=0 and tile<total and word(tile)%16~=7 end
    local function seed_water(i,v)
      set_cover(i,1+(v==22 and 6 or v==38 and 7 or 0)*4+3)
    end
    local function full_tile(i)
      local x,z=xy(i)
      local u,dz=min(x+1,w-1),min(z+1,d-1)
      local n,a,b,c=height(x,z),height(u,z),height(x,dz),height(u,dz)
      local s,h=Slope.classify(n,a,b,c)
      local v=word(i)
      local kind,water=v%16,floor(v/16)%16
      return {kind=kind==7 and "void" or kind==6 and "water" or "clear",
        class=water==1 and "sea" or water==2 and "coast" or nil,
        slope=s,base=h,top=max(n,a,b,c)}
    end
    local board={
      width=w,depth=d,valid=function(x,z) return valid(i_of(x,z)) end,height=height,
      is_water=function(x,z) return word(i_of(x,z))%16==6 end,
      is_clear_desert=function(x,z) local v=word(i_of(x,z));return v%16==0 and floor(v/256)%16==5 end,
      zone=function(x,z) return zone(i_of(x,z)) end,
      set_zone=function(x,z,value) set_zone(i_of(x,z),value) end,
    }
    local V={}
    for k,v in pairs(base) do V[k]=v end
    local cursor=opts.cursor or 1
    if climate=="arctic" then
      V.snowline=Climate.snow_line(board,opts.snow_coverage)
      V.base_id=base.base_id.."/snow"..(opts.snow_coverage or Climate.DEFAULT_SNOW_COVERAGE)
    else
      V.desert_line=Climate.desert_line(board,opts.desert_coverage)
      V.base_id=base.base_id.."/desert"..(opts.desert_coverage or Climate.DEFAULT_DESERT_COVERAGE)
      local fb={width=w,height=d,freeform=base.freeform,tile=full_tile}
      local step=River.loop_scheduler(fb,function(i)
        local v=word(i)
        if v%16==0 then
          local ground=ground_name[floor(v/256)%16]
          local cover_type,den=Climate.clear_desert(ground,density(i),zone(i),function()
            return Climate.normal_neighbor(w,i,valid,
              function(j) return zone(j)==Climate.DESERT end,
              function(j) return word(j)%16==6 end)
          end)
          if cover_type then set_cover(i,1+ground_code[cover_type]*4+den) end
        else
          River.loop_water(fb,seed_water,i)
        end
      end,{cursor=cursor,counter=0})
      -- GenerateLandscape calls RunTileLoop directly with counter 0 all
      -- 256 times. It does not visit all tiles exactly once.
      Climate.classify_tropic(board,V.desert_line,function() cursor=step() end)
    end
    V.climate_tileloop_cursor=cursor
    function V.town_climate(x,z)
      if not base.tile(x,z) then return end
      local i=i_of(x-1,z-1)
      return {tile_height=height(x-1,z-1),snowline=V.snowline,is_desert=zone(i)==Climate.DESERT}
    end
    function V.tile(x,z)
      if x>=1 and x<=w and z>=1 and z<=d then return word(i_of(x-1,z-1)) end
    end
    function V.tropic_zone(x,z)
      if x>=1 and x<=w and z>=1 and z<=d then return zone(i_of(x-1,z-1)) end
    end
    function V.clear_density(x,z)
      local v=V.tile(x,z)
      if v and v%16==0 then return density(i_of(x-1,z-1)) end
    end
    function V.storage_options()
      return {seed=base.seed,base_id=V.base_id,
        corner=function(_,x,z)return base.corner(x,z) end,
        tile=function(_,x,z)return V.tile(x,z) end}
    end
    return V
  end

  return M
end
