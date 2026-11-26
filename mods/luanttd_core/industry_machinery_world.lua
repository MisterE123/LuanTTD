-- World-owned RC1 machinery clock. Static footprint roles on native
-- scene tiles never change when their industry sprite state changes.
return function(Sim,Rules)
  local M={}
  local function index(s,include_wells)
    local records,animated={},{}
    local function add(all,well)
      for _,industry in pairs(all or {}) do
        if not industry.removed and (not well or industry.kind=="oil_well") then
          for _,part in ipairs(industry.tiles) do
            local g=part.gfx
            if include_wells or not well and (g==Rules.MINE_REST or g==Rules.MINE_RUN or g==Rules.POWER_SPARKS)
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
    if include_wells then add(s.stock_oil_industries,true) end
    return records,animated
  end
  function M.bind(s,include_wells)
    local records,animated=index(s,include_wells)
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
            part.construction_counter,part.stage=0,(part.stage or 0)+1
            if part.stage==3 then part.completed=true end
          else part.construction_counter=counter end
        end
        return
      end
      local prev_gfx,prev_frame,was=part.gfx,part.animation_frame,part.animated
      Rules.visit(part,tick,random)
      animated[id]=part.animated and part or nil
      if include_wells and part.gfx>=Rules.OIL_FIRST and part.gfx<=Rules.OIL_LAST then
        s.stock_oil_animated=s.stock_oil_animated or {}
        s.stock_oil_animated[id]=part.animated or nil
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
  function M.visible(s,x,z,w,h)
    if not (s.stock_generated_profile and s.stock_coal_industries) then return end
    local poses={}
    local tick=s.passenger_house_clock and s.passenger_house_clock.counter or 0
    local phase=tick%2048-1024
    for _,industry in pairs(s.stock_coal_industries) do
      if not industry.removed then
        for _,part in ipairs(industry.tiles) do
          local u,v=part.x+1,part.z+1
          if u>=x and u<x+w and v>=z and v<z+h then
            local g=part.gfx
            if g==Rules.MINE_REST or g==Rules.MINE_RUN or g==Rules.POWER_SPARKS then
              local id=Sim.id(u,v)
              local tile=s.tiles[id]
              if tile and tile.stock_industry and tile.stock_industry.id==industry.id then
                local dir=0
                if g==Rules.MINE_RUN then
                  if phase>=0 and phase<0x1A0 then dir=1
                  elseif phase>=0x200 and phase<0x3A0 then dir=-1 end
                end
                poses[id]={gfx=g,frame=part.animation_frame or 0,dir=dir,tick=tick,active=part.animated or false}
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
