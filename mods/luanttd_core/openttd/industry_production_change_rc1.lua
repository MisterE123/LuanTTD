-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 16.0-RC1 industry_cmd.cpp, UpdateIndustryStatistics,
-- CheckIndustryCloseDownProtection and vanilla ChangeIndustryProduction.
-- The host supplies current rates, live counts, vehicle ledgers and the
-- shared RNG. No NewGRF callbacks are present in the vanilla model.
local M={}
local floor,ceil,min,max=math.floor,math.ceil,math.min,math.max
local Q=65536
local function chance(n,d,r) return floor(((r%Q)*d+floor(d/2))/Q)<n end
local function pct(p)
  local prod=p and p.last_production or 0
  if prod==0 then return 0 end
  return min(255,floor((p.last_transported or 0)*256/prod))
end
function M.roll(firm,year)
  for _,p in ipairs(firm.produced) do
    if (p.current_production or 0)~=0 then firm.last_prod_year=year end
    p.last_production,p.current_production=p.current_production or 0,0
    p.last_transported,p.current_transported=p.current_transported or 0,0
  end
end
function M.change(firm,spec,climate,economy,monthly,year,random,same_type,flags)
  local original=economy=="original"
  if monthly==original or economy=="frozen" or spec.life=="INDUSTRYLIFE_BLACK_HOLE" then return end
  flags=flags or {}
  local close,level=false,firm.prod_level
  local only_decrease=climate=="temperate" and spec.behavior.DontIncrProd
  if spec.life=="Organic" or spec.life=="Extractive" then
    if original then
      if only_decrease or chance(1,3,random()) then
        local increase=not only_decrease and ((pct(firm.produced[1])>153)~=chance(1,3,random()))
        if (increase and flags.no_increase) or (not increase and flags.no_decrease) then return end
        if not flags.external_level then
          if increase then level=min(128,level*2)
          elseif level==4 then close=true
          else level=max(4,floor(level/2)) end
        end
      end
    else
      close=not (flags.no_closure or flags.no_decrease)
      for _,p in ipairs(firm.produced) do
        local r=random()
        local old,rate=p.rate,p.rate
        if chance(1,22,floor(r/Q)) then
          local rating=pct(p)
          local up=not only_decrease and (rating<=153 and chance(1,3,r)
            or rating>153 and rating<=204 and chance(2,3,r)
            or rating>204 and chance(5,6,r))
          local factor=floor(random()*50/4294967296)+10
          rate=rate+(up and 1 or -1)*max(floor(factor*old/256),1)
        end
        rate=max(1,min(255,rate))
        if p.id==0 and not spec.behavior.NoPaxProdClamp then rate=min(16,rate) end
        if not ((rate<old and flags.no_decrease) or (rate>old and flags.no_increase)) then
          if (rate==old and old>1) or rate>1 then close=false end
          p.rate=rate
        end
      end
    end
  elseif spec.life=="Processing" and year-(firm.last_prod_year or firm.created_year or year)>=5 then
    close=chance(1,original and 2 or 180,random())
  end
  if level~=firm.prod_level then
    firm.prod_level=level
    local slots={}
    for _,def in ipairs(spec.produce) do if def.cargo then slots[def.cargo.id]=def.value end end
    for _,p in ipairs(firm.produced) do p.rate=min(255,ceil(assert(slots[p.id])*level/16)) end
  end
  if close and not flags.no_closure and (only_decrease or spec.behavior.CanCloseLastInstance or same_type>1) then
    firm.prod_level=0
    return "closing"
  end
end
return M
