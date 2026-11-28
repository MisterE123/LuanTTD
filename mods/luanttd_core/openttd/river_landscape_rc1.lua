-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors, 16.0-RC1 landscape.cpp: FindSpring,
-- IsValidRiverTerminusTile, MakeLake, MakeWetlands, TryMakeRiverTerminus,
-- CountConnectedSeaTiles, FlowRiver and CreateRivers. Temperate only.
return function(valid,offset,distance,water,flows_down,circular,range)
  local R={}
  local floor,min,max=math.floor,math.min,math.max
  local function xy(B,i) return i%B.width,floor(i/B.width) end
  local function chance(a,b,draw) return floor(((draw%65536)*b+floor(b/2))/65536)<a end

  function R.find_spring(B,i,terrain_type)
    if not valid(B,i) then return false end
    local t=B.tile(i)
    if t.slope~=0 or water(B,i) then return false end
    local low=(terrain_type or 1)<2
    local hills,limit,required=0,low and 3 or 1,low and 1 or 3
    for d=1,4 do
      local j=i
      for _=1,limit do
        j=offset(B,j,d)
        if not valid(B,j) then break end
        if B.tile(j).top>t.base then hills=hills+1; break end
      end
    end
    return hills>=required
  end

  -- Keep discovery order in addition to the member set. The draining
  -- adapter receives both because shore terraforming mutates the map.
  function R.sea(B,i)
    local found,list={},{}
    local limit=min(floor(2*math.sqrt(B.width*B.height)),1024)
    local function visit(j)
      if not water(B,j) then return false end
      local t=B.tile(j)
      if t.class~="sea" or t.slope~=0 then return false end
      local x,z=xy(B,j)
      if min(x,z,B.width-1-x,B.height-1-z)<=1 then return true end
      found[j]=true
      list[#list+1]=j
      if #list>limit then return false end
      for d=1,4 do
        local k=offset(B,j,d)
        if not found[k] and valid(B,k) and visit(k) then return true end
      end
      return false
    end
    local reaches_edge=visit(i)
    return reaches_edge or #list>limit,list
  end

  -- OpenTTD visits the sea set in GNU libstdc++ bucket-chain order when
  -- draining a small disconnected patch. A prepend-only DFS reversal
  -- changes the overlapping terraforms and their RNG even on a 64² map.
  local sizes={13,29,59,127,257,541,1109,2357}
  function R.sea_drain_order(discovery)
    local groups,heads={},{}
    local index,size,count=1,sizes[1],0
    local function add(tile)
      local b=tile%size
      local group=groups[b]
      if not group then
        group={}
        groups[b]=group
        heads[#heads+1]=b
      end
      group[#group+1]=tile
    end
    local function ordered()
      local result={}
      for i=#heads,1,-1 do
        local group=groups[heads[i]]
        for j=#group,1,-1 do result[#result+1]=group[j] end
      end
      return result
    end
    for _,tile in ipairs(discovery) do
      if count>=size then
        local old=ordered()
        index=index+1;size=assert(sizes[index])
        groups,heads={},{}
        for _,j in ipairs(old) do add(j) end
      end
      add(tile);count=count+1
    end
    return ordered()
  end

  function R.outlet(B,begin,opts)
    local h=B.tile(begin).corner_height
    local q={begin}
    local marked={[begin]=true}
    local cursor=1
    while q[cursor] do
      local i=q[cursor];cursor=cursor+1
      local t=B.tile(i)
      if t.slope==0 and (t.corner_height<h or t.corner_height==h and water(B,i)) then
        if not opts.original and water(B,i) and t.class=="sea" then
          local large,list=R.sea(B,i)
          if large then return i,q end
          B.drain_sea(R.sea_drain_order(list))
        else
          return i,q
        end
      end
      for d=1,4 do
        local j=offset(B,i,d)
        if not marked[j] and valid(B,j) and flows_down(B,i,j) then
          q[#q+1]=j;marked[j]=true
        end
      end
    end
    return nil,q
  end

  local function terminus_tile(B,i,h)
    if not valid(B,i) then return false end
    local t=B.tile(i)
    return t.slope==0 and t.corner_height==h
  end

  function R.lake(B,i,h,random,make)
    make(i)
    local diameter=range(8,random())+3
    local function fill(j)
      if not terminus_tile(B,j,h) then return false end
      for d=1,4 do if water(B,offset(B,j,d)) then make(j);break end end
      return false
    end
    circular(B,i,diameter,fill)
    circular(B,i,diameter,fill)
  end

  function R.wetlands(B,i,h,length,random,make,opts)
    make(i)
    local diameter=max(length,16)
    local radius=floor(diameter/2)
    local x,z=xy(B,i)
    local has_trees=chance(1,2,random())
    circular(B,i,diameter,function(j)
      if not terminus_tile(B,j,h) then return false end
      local u,v=xy(B,j)
      if (u-x)^2+(v-z)^2>radius*radius and chance(3,4,random()) then return false end
      if chance(1,3,random()) then
        make(j)
      elseif B.tile(j).kind=="clear" then
        B.roughen(j)
        if has_trees and opts.tree_placer~=0 then B.place_tree(j,random()) end
      end
      return false
    end)
  end

  local function try_terminus(B,begin,i,random,make,opts)
    local h=B.tile(begin).corner_height
    if i==begin or not terminus_tile(B,i,h) then return false end
    if chance(1,3,random()) then R.lake(B,i,h,random,make)
    else R.wetlands(B,i,h,distance(B,begin,i),random,make,opts) end
    return true
  end

  function R.flow(B,spring,min_length,random,make,opts,build)
    local chain={}
    local current=spring
    local main=false
    while true do
      if water(B,current) then
        main=B.tile(current).base==0
        if distance(B,spring,current)<=min_length then return false,main end
        break
      end
      local last,queue=R.outlet(B,current,opts)
      if not last then
        if #queue<=32 then return false,false end
        local centre=queue[range(#queue,random())+1]
        if distance(B,spring,centre)<=min_length or not try_terminus(B,current,centre,random,make,opts) then return false,false end
        chain[#chain+1]={current,centre}
        break
      end
      chain[#chain+1]={current,last}
      current=last
    end
    for i=#chain,1,-1 do
      local s=chain[i]
      build(B,s[1],s[2],spring,main,random,make,opts)
    end
    return true,main
  end
  return R
end
