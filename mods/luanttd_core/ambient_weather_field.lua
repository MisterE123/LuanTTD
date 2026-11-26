-- Continuous, unsaved sky in world coordinates. No player or camera state
-- enters this module; clients looking at a shared cell get the same weather.
local F={spacing=91,period=184,radius=134}
local floor,sqrt=math.floor,math.sqrt
local function unit(x) return math.min(1,math.max(0,x)) end
function F.smooth(t) t=unit(t);return t*t*(3-2*t) end
local function ramp(t,a,b) return F.smooth((t-a)/(b-a)) end
local function envelope(t,a,b,c,d) return ramp(t,a,b)*(1-ramp(t,c,d)) end
local function hash(x,z,salt)
  local n=((x%8191)*2837+(z%8191)*6197+salt*2017)%65521
  return ((n*n*17+n*193+salt*337)%65521)/65521
end
function F.wind(t,prevailing)
  local w=prevailing or {x=1.1,z=.4}
  -- A gentle shared veer has a continuous integral. Flight across an
  -- observer or a cell-period boundary cannot change an anchor.
  return w.x*.72*t+4*math.sin(t/32),w.z*.72*t+5*math.sin(t/53)
end
function F.lifecycle(seconds,kind)
  local density=envelope(seconds,1,27,151,183)
  local uplift=kind=="storm" and envelope(seconds,31,67,105,141) or 0
  local rain=kind=="storm" and envelope(seconds,46,74,106,141) or
    kind=="shower" and .54*envelope(seconds,39,61,105,134) or 0
  local mist=kind=="mist" and .55*envelope(seconds,15,43,110,167) or .19*rain
  -- Thunder declines before the parent cloud thins; the cell has a
  -- distinct dry, growing, raining and dry dispersal period.
  return density,uplift,rain,mist
end
function F.cells(x,z,age,prevailing,seed)
  seed=seed or 0
  local windx,windz=F.wind(age,prevailing)
  local i,j=floor((x-windx)/F.spacing),floor((z-windz)/F.spacing)
  local result={}
  for v=j-2,j+2 do for u=i-2,i+2 do
    local a=hash(u,v,11+seed)
    local b=hash(u,v,23+seed)
    local px,pz=(u+.18+.64*a)*F.spacing+windx,(v+.18+.64*b)*F.spacing+windz
    local dx,dz=px-x,pz-z
    local d=sqrt(dx*dx+dz*dz)
    if d<F.radius then
      local t=age+F.period*hash(u,v,41+seed)
      local generation=floor(t/F.period)
      t=t-generation*F.period
      local mode=hash(u,v,53+(generation%173)+seed)
      local kind=mode<.31 and "storm" or mode<.53 and "shower" or mode<.70 and "mist" or "cloud"
      local density,uplift,rain,mist=F.lifecycle(t,kind)
      local fade=1-ramp(d,91,F.radius)
      if density>.008 and fade>.005 then
        result[#result+1]={key=u..":"..v..":"..generation,x=px,z=pz,dist=d,
          time=t,alpha=density*fade,growth=uplift,rain=rain,mist=mist,kind=kind,size=.78+.48*a,
          skew=(b-.5)*.3,rank=d+16*(1-density)}
      end
    end
  end end
  table.sort(result,function(a,b) return a.rank==b.rank and a.key<b.key or a.rank<b.rank end)
  return result
end
function F.builder_avoid(x,z,c,builder,wx,wz)
  if not builder then return 0,0,1 end
  local dx,dz=c.x-x,c.z-z
  local d=sqrt(dx*dx+dz*dz)
  local n=28*(1-ramp(d,7,39))
  local blend=ramp(d,0,10)
  local wd=sqrt(wx*wx+wz*wz)
  if wd==0 then wx,wz,wd=1,0,1 end
  if d<.001 then dx,dz,d=wx,wz,wd end
  return n*((dx/d)*blend+wx/wd*(1-blend)),n*((dz/d)*blend+wz/wd*(1-blend)),
    .08+.92*ramp(d,8,35)
end
return F
