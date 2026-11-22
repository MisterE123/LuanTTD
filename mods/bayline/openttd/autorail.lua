-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD 14.1: viewport.cpp (GetAutorailHT, Check2x1AutoRail,
-- CalcRaildirsDrawstyle's automatic branch), table/autorail.h,
-- and rail_cmd.cpp (ValidateAutoDrag and physical track stepping).
return function(Track)
  local A={}
  local floor,abs=math.floor,math.abs
  local X,Y,HU,HL,VL,VR=Track.X,Track.Y,Track.UPPER,Track.LOWER,Track.LEFT,Track.RIGHT
  local pick={
    "2222220000555555",
    "2222220000555555",
    "2222220000555555",
    "2222220000555555",
    "2222220000555555",
    "2222220000555555",
    "1111110001111111",
    "1111111011111111",
    "1111111101111111",
    "1111111000111111",
    "4444440000333333",
    "4444440000333333",
    "4444440000333333",
    "4444440000333333",
    "4444440000333333",
    "4444440000333333",
  }
  local function aligned(a) return floor(a/16)*16 end
  local function single(x,y) return tonumber(pick[x%16+1]:sub(y%16+1,y%16+1)) end
  local function two(mode,fx,fy,sx,sy)
    local fs,ss,fd,sd=fx+fy,sx+sy,fx-fy,sx-sy
    if mode==0 then
      if fs>=20 and ss<=12 then return HL end
      if fd< -3 and sd>3 then return VR end
      return Y
    elseif mode==1 then
      if fd>3 and sd< -3 then return VL end
      if fs<=12 and ss>=20 then return HU end
      return Y
    elseif mode==2 then
      if fd>3 and sd< -3 then return VL end
      if fs>=20 and ss<=12 then return HL end
      return X
    else
      if fd< -3 and sd>3 then return VR end
      if fs<=12 and ss>=20 then return HU end
      return X
    end
  end
  function A.snap(fx,fy,x,y)
    local ax,ay=aligned(fx),aligned(fy)
    local dx,dy=ax-aligned(x),ay-aligned(y)
    local w,h=abs(dx)+16,abs(dy)+16
    local b
    if dx==0 and dy==0 then b=single(x,y)
    elseif h==16 then
      b=abs(dx)==16 and two(dx>0 and 3 or 2,fx%16,fy%16,x%16,y%16) or X;y=ay
    elseif w==16 then
      b=abs(dy)==16 and two(dy>0 and 1 or 0,fx%16,fy%16,x%16,y%16) or Y;x=ax
    elseif w>h*2 then b=X;y=ay
    elseif h>w*2 then b=Y;x=ax
    else
      local d=w-h
      local px,py=x%16,y%16
      if x>ax and y>ay then
        if d==0 then b=px>py and VL or VR
        elseif d>=0 then x=ax+h;b=VL else y=ay+w;b=VR end
      elseif x>ax then
        if d==0 then b=px+py>=16 and HL or HU
        elseif d>=0 then x=ax+h;b=HL else y=ay-w;b=HU end
      elseif y>ay then
        if d==0 then b=px+py>=16 and HL or HU
        elseif d>=0 then x=ax-h;b=HU else y=ay+w;b=HL end
      else
        if d==0 then b=px>py and VL or VR
        elseif d>=0 then x=ax-h;b=VR else y=ay-w;b=VL end
      end
    end
    return b,floor(x/16),floor(y/16),x,y
  end
  local sx,sy={[0]=-1,0,-1,0,1,0,0,0,1,0,0,1,0,-1},
    {[0]=0,1,0,1,0,1,0,0,0,-1,-1,0,-1,0}
  local function toggle(td) return td%2==0 and td+1 or td-1 end
  function A.trace(x,y,u,v,b)
    if not b or b<0 or b>5 or b%1~=0 then return end
    local dx,dy=u-x,v-y
    local tx,ty=sx[b],sy[b]
    if b>=2 then tx,ty=tx+sx[toggle(b)],ty+sy[toggle(b)] end
    local function wrong()
      return tx<=0 and dx>0 or tx>=0 and dx<0 or ty<=0 and dy>0 or ty>=0 and dy<0
    end
    local td=b
    if wrong() then
      td,tx,ty=b+8,-tx,-ty
      if wrong() then return end
    end
    if b>=2 and abs(dx)~=abs(dy) and abs(dx)+abs(sy[td])~=abs(dy)+abs(sx[td]) then return end
    local out={}
    for step=1,abs(dx)+abs(dy)+1 do
      out[step]={x=x,z=y,track=Track.track(td)}
      if x==u and y==v then return out end
      x,y=x+sx[td],y+sy[td]
      if b>=2 then td=toggle(td) end
    end
  end
  return A
end
