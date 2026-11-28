-- World-owned RC1 machinery clock. Static footprint roles on native
-- scene tiles never change when their industry sprite state changes.
return function(Sim,Rules,OilRegistry)
  local M={}
  local function index(s,include_wells,stock_all)
    local records,animated={},{}
    local function add(all,well)
      for _,industry in pairs(all or {}) do
        if not industry.removed and (not well or industry.kind=="oil_well") then
          for _,part in ipairs(industry.tiles) do
            local g=part.gfx
            if stock_all or include_wells or not well and (g==Rules.MINE_REST or g==Rules.MINE_RUN or g==Rules.POWER_SPARKS)
                or well and g>=Rules.OIL_REST and g<=Rules.OIL_LAST then
              local id=Sim.id(part.x+1,part.z+1)
              local tile=id and s.tiles[id]
              if tile and tile.stock_industry and tile.stock_industry.id==industry.id then
                records[id]=part
                if part.animated then animated[id]=part end
              end
            end
          end
        end
      end
    end
    add(s.stock_coal_industries,false)
    if stock_all then
      add(s.stock_oil_industries,false)
      add(s.stock_timber_industries,false)
      add(s.stock_farm_industries,false)
      add(s.stock_heavy_industries,false)
      add(s.stock_bank_industries,false)
    elseif include_wells then add(s.stock_oil_industries,true) end
    return records,animated
  end
  function M.bind(s,include_wells)
    local stock_all=s.stock_generated_profile and s.stock_generated_profile.rc1_industry_phase
    local records,animated=index(s,include_wells,stock_all)
    local W={}
    local random=function() return Sim.stock_random_u32(s) end
    function W.completed(id)
      local part=records[id]
      return part and part.completed
    end
    function W.visit(id,tick)
      local part=records[id]
      if not part then return end
      if not part.completed then
        if include_wells then
          -- RC1 MakeIndustryTileBigger: the first generated visit
          -- usually completes stage 2/counter 3. The animation lottery
          -- can only begin on a later physical visit.
          local counter=(part.construction_counter or 0)+1
          if counter>=4 then
            if stock_all then random() end -- ConstructionStageChanged dispatch
            part.construction_counter,part.stage=0,(part.stage or 0)+1
            if part.stage==3 then
              part.completed=true
              if stock_all and part.gfx==8 then
                -- MakeIndustryTileBigger -> CreateChimneySmoke ->
                -- ChimneySmokeInit consumes one shared sprite-phase word.
                part.stock_chimney_start=random()
              end
            end
          else part.construction_counter=counter end
        end
        return
      end
      if stock_all then random() end -- unconditional base TileLoop animation callback word
      if not include_wells and not (part.gfx==Rules.MINE_REST or part.gfx==Rules.MINE_RUN
            or part.gfx==Rules.POWER_SPARKS) then return end
      local prev_gfx,prev_frame,was=part.gfx,part.animation_frame,part.animated
      Rules.visit(part,tick,random)
      animated[id]=part.animated and part or nil
      if include_wells and part.gfx>=Rules.OIL_FIRST and part.gfx<=Rules.OIL_LAST then
        -- Registration survives later pregame visits and preserves
        -- physical activation order. The live animation starts later.
        OilRegistry.add(s,id)
        -- The established live oil animation list is authoritative for
        -- pumps after generation; never tick that same actor twice.
        part.animated=nil
        animated[id]=nil
      end
      return part.gfx~=prev_gfx or part.animation_frame~=prev_frame or part.animated~=was
    end
    function W.animate(tick)
      -- Native GameLoop invokes AnimateAnimatedTiles before updating
      -- TimerGameTick. Neither coal sheaves nor power flashes draw RNG,
      -- so Lua iteration order is immaterial for this live subset.
      for id,part in pairs(animated) do
        Rules.animate(part,tick,random)
        if not part.animated then animated[id]=nil end
      end
    end
    return W
  end
  local sector_size=32
  local visibility=setmetatable({},{__mode="k"})
  local function visibility_index(s)
    local coal,oil=s.stock_coal_industries,s.stock_oil_industries
    local nc,no=s.next_stock_coal_industry,s.next_stock_oil_industry
    local c=visibility[s]
    if c and c.coal==coal and c.oil==oil and c.nc==nc and c.no==no and c.w==Sim.W and c.h==Sim.H then
      return c.sectors
    end
    local sectors={}
    local function add(list,well)
      for _,industry in pairs(list or {}) do
        if not industry.removed and (not well or industry.kind=="oil_well") then
          for _,part in ipairs(industry.tiles) do
            local u,v=part.x+1,part.z+1
            local id=Sim.id(u,v)
            if id then
              local bx,bz=math.floor((u-1)/sector_size),math.floor((v-1)/sector_size)
              local row=sectors[bz]
              if not row then row={};sectors[bz]=row end
              local bucket=row[bx]
              if not bucket then bucket={};row[bx]=bucket end
              -- Keep all parts: the live RC1 animation can change gfx.
              -- Only static coordinates are cached, never pose or activity.
              bucket[#bucket+1]={id=id,x=u,z=v,well=well,industry=industry,part=part}
            end
          end
        end
      end
    end
    add(coal,false)
    add(oil,true)
    -- Funding appends a new ID; mounting stock footprints can replace
    -- the registry. Either rebuilds the index. Closures retain a tombstone
    -- and are respected immediately without reacting to ordinary road edits.
    visibility[s]={coal=coal,oil=oil,nc=nc,no=no,w=Sim.W,h=Sim.H,sectors=sectors}
    return sectors
  end
  function M.visible(s,x,z,w,h)
    if not (s.stock_generated_profile and (s.stock_coal_industries or s.stock_oil_industries)) then return end
    local poses={}
    local sectors=visibility_index(s)
    local tick=s.passenger_house_clock and s.passenger_house_clock.counter or 0
    local phase=tick%2048-1024
    local mine_dir=phase>=0 and phase<0x1A0 and 1 or (phase>=0x200 and phase<0x3A0 and -1 or 0)
    for bz=math.floor((z-1)/sector_size),math.floor((z+h-2)/sector_size) do
      local row=sectors[bz]
      if row then
        for bx=math.floor((x-1)/sector_size),math.floor((x+w-2)/sector_size) do
          local bucket=row[bx]
          if bucket then
            for _,r in ipairs(bucket) do
              local t=s.tiles[r.id]
              local i,p=r.industry,r.part
              local g=p.gfx
              if r.x>=x and r.x<x+w and r.z>=z and r.z<z+h and not i.removed
                and t and t.stock_industry and t.stock_industry.id==i.id then
                if r.well then
                  if i.kind=="oil_well" and t.stock_industry.chain=="oil" and
                    g>=Rules.OIL_REST and g<=Rules.OIL_LAST then
                    local frame=g==Rules.OIL_REST and 0 or (g-Rules.OIL_FIRST)*4+(p.animation_frame or 0)
                    poses[r.id]={oil=frame,base=t.h,site=i.id,tick=tick}
                  end
                elseif g==Rules.MINE_REST or g==Rules.MINE_RUN or g==Rules.POWER_SPARKS then
                  poses[r.id]={gfx=g,frame=p.animation_frame or 0,dir=g==Rules.MINE_RUN and mine_dir or 0,
                    tick=tick,active=p.animated or false}
                end
              end
            end
          end
        end
      end
    end
    return poses
  end
  return M
end
