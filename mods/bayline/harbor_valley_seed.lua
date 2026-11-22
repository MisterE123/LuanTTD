-- Original Harbor Valley starter region. Geography only: stock tiles,
-- slopes, roads, industry permissions, and clocks retain their own rules.
-- Mount once during a fresh seed-1751 campaign, after municipal seed roads.
return function(Sim,Terrain,s,grid)
  assert(s.seed==1751 and grid.revision==0)
  assert(Sim.W==48 and Sim.H==36 and grid.width==Sim.W and grid.depth==Sim.H)
  local stats={name="Harbor Valley",seed=1751,land=0,water=0,shore=0,flat=0,peak=0,
    bridge={x1=21,x2=27,z=13,channel_first=23,channel_last=25},
    rail={z=14,x1=28,x2=37,depot={28,14},western_platform={{31,14},{32,14}},
      eastern_platform={{36,14},{37,14}},bridge={x1=21,x2=27,z=15}},
    harbor={west_dock={5,32},east_dock={8,32},water_depot={12,34}},
    airfields={{7,12},{18,20},{30,16}},
    launch={x=42,y=20,z=15,look_x=43.5,look_y=2,look_z=22}}
  local W,H=Sim.W,Sim.H
  local function rect(x,z,a,b,c,d)return x>=a and x<=c and z>=b and z<=d end
  -- These plateaus reserve actual machine footprints *and* buildable
  -- approaches. Mutually exclusive preplaced land freight profiles still
  -- retain their own rules; this terrain does not enable or merge them.
  local terraces={
    {6,5,21,14},                  -- Port Alder–Mason Quay / charter rail right of way
    {7,12,10,18},{18,20,21,22},  -- dry Country Airfield choices
    {10,1,16,7},{11,12,20,20},   -- all three alternative west freight profiles
    {12,25,16,30},{4,26,10,31},  -- optional legacy South Coast coal pads and road walks
    {29,6,33,18},{33,16,34,18},  -- eastern towns, coal and flight approach
    {38,11,45,15},{38,11,40,22}, -- Riverbend Power, road-to-rail staging and approach
    {19,12,21,15},{27,12,30,15}, -- exact flat bridge heads; clear opposite-bank approaches
    {34,23,40,28},              -- Tern Island headland town and leveled yard
  }
  local function reserved(x,z)
    for _,p in ipairs(terraces) do
      if rect(x,z,p[1],p[2],p[3],p[4]) then return true end
    end
    return false
  end
  local function piecewise(p,x)
    for i=2,#p do
      local b=p[i]
      if x<=b[1] then
        local a=p[i-1]
        return a[2]+(b[2]-a[2])*(x-a[1])/(b[1]-a[1])
      end
    end
    return p[#p][2]
  end
  local strand={
    {1,33},{4,33},{9,33},{15,33},{20,32},{25,28},
    {30,29},{34,33},{37,34},{42,33},{46,30},{48,29},
  }
  local centerline={
    {4,24.5},{6,25},{8,25.5},{10,24.5},{11,24},
    {15,24},{17,25},{20,26.5},{22,25.5},{25,24.5},{29,25.5},{34,26},
  }
  local halfwidth={
    {4,.66},{6,1.72},{8,2.03},{10,1.54},{11,1.44},
    {15,1.44},{17,1.54},{20,1.64},{22,2.75},{25,3.35},{29,4.13},{34,4.31},
  }
  local function water(x,z)
    if z>=math.ceil(piecewise(strand,x)-.000001) then return true end
    if z<4 then return false end
    if math.abs(x-piecewise(centerline,z))<=piecewise(halfwidth,z) then return true end
    -- Tidewater branch into a spacious central basin, leaving a green
    -- headland around the southern town and preserving both old docks.
    return (x-26)^2/25+(z-28)^2/12<1 or (x-29)^2/8+(z-30)^2/6<1
  end
  local land,zero,cap={},{},{}
  local function index(x,z) return (z-1)*(W+1)+x end
  local function each_corner(x,z,fn)
    for b=z,z+1 do for a=x,x+1 do fn(index(a,b)) end end
  end
  for z=1,H do for x=1,W do
    local t=assert(s.tiles[Sim.id(x,z)])
    local fixed=t.site or t.house or t.build
    local block=fixed or reserved(x,z)
    local wet=not block and water(x,z)
    if wet then
      each_corner(x,z,function(i)zero[i]=true end)
    elseif block then
      each_corner(x,z,function(i)cap[i]=1 end)
    end
    land[Sim.id(x,z)]={dry=not wet,block=block,fixed=fixed}
  end end

  -- In the real full corner grid, three wooded highlands taper at
  -- unequal rates: Alder's coastal escarpment, the Eastport bluffs,
  -- and the northern river's rounded source hills. Terraces are actual
  -- height constraints, not painted-on scenery or fake cliffs.
  local peaks={{3.0,24.8,6,.90,1.28},{39.2,5.2,7,1.35,.82},
               {46.1,21.9,7,1.06,1.37},{21.3,2.8,5,.90,1.20},
               {34.3,30.5,4,.91,1.46},{8.1,22.6,5,1.31,.87}}
  local levels={}
  for z=1,H+1 do for x=1,W+1 do
    local p=index(x,z)
    local h=1
    for _,v in ipairs(peaks) do
      local dx,dz=(x-v[1])/v[4],(z-v[2])/v[5]
      h=math.max(h,math.floor(v[3]-math.sqrt(dx*dx+dz*dz)+.42))
    end
    levels[p]=zero[p] and 0 or cap[p] and math.min(h,cap[p]) or h
  end end
  -- Manhattan lower envelope of the desired levels. All constraints
  -- survive while every adjacent pair differs by at most one.
  for z=1,H+1 do for x=1,W+1 do
    local i=index(x,z)
    levels[i]=math.min(levels[i],x>1 and levels[i-1]+1 or 255,z>1 and levels[i-W-1]+1 or 255)
  end end
  for z=H+1,1,-1 do for x=W+1,1,-1 do
    local i=index(x,z)
    levels[i]=math.min(levels[i],x<=W and levels[i+1]+1 or 255,z<=H and levels[i+W+1]+1 or 255)
  end end
  local result=Terrain.new(W,H,function(x,z)return levels[index(x,z)] end,{
    max_height=grid.max_height,freeform_edges=grid.freeform_edges,unit_cost=grid.unit_cost,
  })
  for z=1,H do for x=1,W do
    local id=Sim.id(x,z)
    local t,c=s.tiles[id],land[id]
    local mask,h,top=Terrain.tile(result,x,z)
    t.h=h
    stats.peak=math.max(stats.peak,top)
    if not c.dry then
      assert(mask==0 and h==0,"Harbor tide cannot stand on a sloped cell")
      t.terrain,t.wood,t.water_class,t.coastal_water="water",nil,"sea",nil
      stats.water=stats.water+1
    else
      t.terrain,t.water_class,t.coastal_water=h>=2 and "hill" or "grass",nil,nil
      if c.block or h==0 then
        if not c.fixed or t.build or t.site then t.wood=nil end
      else
        local thicket=math.sin(x*.515+z*.132)*math.cos(z*.461-x*.143)
        local tall=math.sin(x*.917+z*.967)
        t.wood=(thicket+.21*tall>(h>=2 and .14 or .68)) or nil
      end
      if mask==0 then stats.flat=stats.flat+1 end
      if h==0 and top>0 then stats.shore=stats.shore+1 end
      stats.land=stats.land+1
    end
  end end
  return result,stats
end
