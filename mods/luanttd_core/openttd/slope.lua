-- SPDX-License-Identifier: GPL-2.0-only
-- Originally part of OpenTTD, copyright the OpenTTD contributors.
-- No warranty. See COPYING.OpenTTD.md and PORTING.md at the game root.
-- Ported to Lua, 2026-11-22, from OpenTTD 14.1:
-- src/tile_map.cpp (GetTileSlopeGivenHeight), src/slope_type.h,
-- src/landscape.cpp (ApplyFoundationToSlope and GetPartialPixelZ).
-- No original artwork is used. Input validation and continuous sampling
-- are Bayline adapter functions; integer sample is the upstream algorithm.
local T={}
local f=math.floor
local W,S,E,N=1,2,4,8
local STEEP,HALF=16,32
local SW,SE,NE,NW=W+S,S+E,E+N,N+W
local NS,EW=N+S,E+W
local NWS,WSE,SEN,ENW=N+W+S,W+S+E,S+E+N,E+N+W
local STEEP_W,STEEP_S,STEEP_E,STEEP_N=STEEP+NWS,STEEP+WSE,STEEP+SEN,STEEP+ENW
-- X is the N->W edge, Y is N->E. Heights are in OpenTTD tile levels.
function T.classify(hn,hw,he,hs)
  local base=math.min(hn,hw,he,hs)
  local high=math.max(hn,hw,he,hs)
  local s=(hn~=base and N or 0)+(hw~=base and W or 0)+(he~=base and E or 0)+(hs~=base and S or 0)
  if high-base==2 then s=s+STEEP end
  return s,base
end
function T.valid(hn,hw,he,hs)
  return math.abs(hn-hw)<=1 and math.abs(hn-he)<=1 and math.abs(hs-hw)<=1 and math.abs(hs-he)<=1
end
local high_corner={[N]=3,[E]=2,[S]=1,[W]=0,[STEEP_N]=3,[STEEP_E]=2,[STEEP_S]=1,[STEEP_W]=0}
function T.foundation(s,kind,corner)
  if kind=="none" then return s,0 end
  local steep=s>=STEEP
  if kind=="leveled" then return 0,steep and 2 or 1 end
  if kind=="half" then return s+HALF+64*assert(corner),0 end
  if kind=="rail" then return 15-2^((assert(corner)+2)%4),0 end
  local highest=assert(high_corner[s],"Foundation requires a highest corner")
  local r
  if kind=="x" then r=(highest==0 or highest==1) and SW or NE
  elseif kind=="y" then r=(highest==1 or highest==2) and SE or NW
  elseif kind=="steep_lower" then r=2^highest
  elseif kind=="steep_both" then r=2^highest+HALF+64*highest
  else error("Unknown foundation: "..tostring(kind)) end
  return r,steep and 1 or 0
end
local function sample(x,y,s,quantize)
  local a=s%32
  if f(s/32)%2==1 then
    local c=f(s/64)
    if (c==0 and x>y) or (c==1 and x+y>=16) or (c==2 and x<=y) or (c==3 and x+y<16) then
      return a>=STEEP and 16 or 8
    end
  end
  -- Integer upstream sampling has asymmetric +1 terms where a pixel just
  -- inside an edge belongs to the higher side. Continuous sampling removes
  -- that quantization to stitch the adjacent real 3D tile edges exactly.
  local function half(v,offset)
    return quantize and f((v+(offset or 0))/2) or v/2
  end
  if a==0 then return 0
  elseif a==N then return math.max(0,half(16-x-y))
  elseif a==E then return y>=x and half(y-x,1) or 0
  elseif a==S then return x+y>=16 and half(x+y-16,1) or 0
  elseif a==W then return math.max(0,half(x-y))
  elseif a==NE then return half(16-x)
  elseif a==SE then return half(y,1)
  elseif a==SW then return half(x,1)
  elseif a==NW then return half(16-y)
  elseif a==ENW then return x+y>=16 and 8-half(x+y-16,1) or 8
  elseif a==SEN then return y<x and 8-half(x-y) or 8
  elseif a==WSE then return x+y<=16 and 8-half(16-x-y) or 8
  elseif a==NWS then return x<y and 8-half(y-x,1) or 8
  elseif a==NS then return x+y<16 and half(16-x-y) or half(x+y-16,1)
  elseif a==EW then return x>=y and half(x-y) or half(y-x,1)
  elseif a==15 then return 8
  elseif a==STEEP_N then return half(32-x-y)
  elseif a==STEEP_E then return half(16+y-x,1)
  elseif a==STEEP_S then return half(x+y,1)
  elseif a==STEEP_W then return half(16+x-y)
  else error("Invalid slope mask: "..tostring(s)) end
end
function T.pixel(x,y,s) return sample(x,y,s,true) end
function T.surface(u,v,s) return sample(u*16,v*16,s,false)/8 end
return T
