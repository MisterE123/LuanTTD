-- The two starter settlements are authored scenarios, not a substitute
-- for OpenTTD's procedural town growth. Roads are real municipal roads.
return function(Sim,s)
  local centerline={
    {1,-2,6,-2}, {1,1,6,1}, {1,-2,1,1}, {6,-2,6,1},
    {1,1,1,2}, {6,1,6,2},
  }
  local quay_streets={
    {1,-2,6,-2}, {6,-2,6,2}, {2,1,6,1},
    {1,-2,1,0}, {1,0,2,0}, {2,0,2,2},
  }
  local outskirts={
    {1,-3},{2,-3},{4,-3},{6,-3},
    {0,-2},{7,-2},{0,0},{7,0},
    {0,1},{7,1},{2,2},{3,2},{5,2},
  }
  local function between(a,b)
    local x,z=Sim.xy(a);local u,v=Sim.xy(b)
    for d,p in ipairs(Sim.dir) do if x+p[1]==u and z+p[2]==v then return d end end
  end
  local function include(bits,d)
    local b=2^(d-1)
    return bits+((math.floor(bits/b)%2==0) and b or 0)
  end
  local function draft(town,mirror,style)
    local cx,cz=Sim.xy(town.tile)
    local function xy(c,z)
      return cx+(mirror and 3-c or c-3),cz+z
    end
    local function at(c,z) return Sim.id(xy(c,z)) end
    local plan={}
    for _,seg in ipairs(style==0 and centerline or quay_streets) do
      local a=Sim.line(at(seg[1],seg[2]),at(seg[3],seg[4]))
      for i=2,#a do
        local left,right=a[i-1],a[i]
        local dir=between(left,right)
        plan[left]=include(plan[left] or 0,dir)
        plan[right]=include(plan[right] or 0,(dir+1)%4+1)
      end
    end
    local function prepare(id)
      local t=id and s.tiles[id]
      if not t or t.site or t.build or t.terrain=="water" then return end
      t.house=nil;t.wood=nil;t.terrain="grass";t.h=0;t.parcel=nil
      return t
    end
    local ids={}
    for id in pairs(plan) do ids[#ids+1]=id end
    table.sort(ids)
    for _,id in ipairs(ids) do
      assert(prepare(id),"Starter street must be on dry, unoccupied land")
      assert(Sim.seed_town_road(s,town.id,id,plan[id]))
    end
    for z=-1,0 do
      for c=2,5 do
        local id=at(c,z)
        local t=prepare(id)
        if t then
          t.house=true
          t.variant=(c+2*z+style)%4
          if z==0 and c==4 then t.parcel=style==0 and "green" or "market"
          elseif z==0 and c==5 then t.parcel="shop"
          elseif z==-1 and c==2 then t.parcel=style==0 and "market" or "green" end
        end
      end
    end
    for i,p in ipairs(outskirts) do
      local t=prepare(at(p[1],p[2]))
      if t then
        t.variant=(i+style)%4
        if i==3 or i==7 or i==12 then t.wood=true else t.house=true end
      end
    end
  end
  draft(s.sites[1],false,0)
  draft(s.sites[2],true,1)
end
