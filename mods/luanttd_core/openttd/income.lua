-- SPDX-License-Identifier: GPL-2.0-only
-- Originally part of OpenTTD, copyright the OpenTTD contributors.
-- No warranty. See COPYING.OpenTTD.md and PORTING.md.
-- Ported 2026-11-22 from OpenTTD 14.1 src/economy.cpp
-- GetTransportedGoodsIncome (ordinary payment, not the NewGRF callback).
-- Default temperate CargoSpecs from src/table/cargo_const.h.
local I={}
I.temperate={
  passenger={3185, 0, 24}, coal={5916, 7, 255}, mail={4550, 20, 90},
  goods={6144, 5, 28}, grain={4778, 4, 40}, steel={5688, 7, 255},
}
local floor,max=math.floor,math.max
function I.regular(pieces,distance,periods,payment,first,second)
  local min_factor,max_factor,fraction=31,255,16
  local over_first=max(periods-first,0)
  local over_second=max(over_first-second,0)
  local over_max=min_factor-max_factor
  if second>-over_max then
    over_max=over_max+periods-first
  else
    over_max=over_max+2*(periods-first)-second
  end
  if over_max>0 then
    local factor=max(floor(2*min_factor*fraction*fraction/(over_max+2*fraction)),1)
    return floor(distance*factor*pieces*payment/(2^21*fraction))
  end
  local factor=max(max_factor-over_first-over_second,min_factor)
  return floor(distance*factor*pieces*payment/2^21)
end
return I
