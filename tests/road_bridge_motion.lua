-- Pure-Lua integration against the actual Sim.wood_bridge save format.
local root="mods/bayline/"
local Sim=dofile(root.."sim.lua")
local Terrain=dofile(root.."openttd/terrain.lua")
local Slope=dofile(root.."openttd/slope.lua")
local Geometry=dofile(root.."openttd/road_bridge.lua")(Slope)
local F=dofile(root.."openttd/yapf_road_follow.lua")
local C=dofile(root.."openttd/yapf_road_cost.lua")(F)
local Search=dofile(root.."openttd/yapf_road_search.lua")(F,C)
local Board=dofile(root.."road_yapf_board.lua")
local Motion=dofile(root.."openttd/road_motion.lua")(dofile(root.."openttd/road_motion_data.lua"))
local Leg=dofile(root.."road_motion_leg.lua")
local Route=dofile(root.."road_yapf_route.lua")(Sim,F,C,Search,Board,Motion,Leg)
local Bridge=dofile(root.."road_bridge_motion.lua")

local function fresh()
  local s=Sim.new(1751)
  s.corner_grid=Terrain.new(Sim.W,Sim.H,function() return 0 end)
  s.road_economy=true
  for _,tile in ipairs(s.tiles) do
    tile.terrain,tile.h="grass",0
    tile.wood,tile.house,tile.site=nil,nil,nil
  end
  return s
end

local function build(axis,length,check_cross)
  local s=fresh()
  local horizontal=axis==0
  local function id(long,cross)
    return Sim.id(horizontal and long+3 or cross+3,horizontal and cross+3 or long+3)
  end
  local along=horizontal and 10 or 5
  local across=horizontal and 5 or 10
  local plus,minus=horizontal and F.SW or F.SE,horizontal and F.NE or F.NW
  local function road(n,cross,bits,kind)
    local t=s.tiles[id(n,cross)]
    t.build,t.road_bits,t.owner=kind or "road",bits,"A"
    return t
  end
  local function station(n,cross,bits)
    local t=road(n,cross,bits,"road_station")
    local st={id=#s.stations+1,tile=id(n,cross),mode="road",owner="A"}
    s.stations[st.id]=st;t.station=st.id
    return st
  end

  local start=station(0,2,along)
  road(1,2,along)
  local finish=station(length+4,2,along)
  road(length+3,2,along)
  local head,tail=id(2,2),id(length+2,2)
  local below_a,below_b
  if check_cross then
    below_a=station(3,0,across)
    below_b=station(3,4,across)
    for cross=1,3 do road(3,cross,across) end
  end
  assert(Sim.wood_bridge(s,"A",tail,head))
  local plan=s.stock_road_bridges[1]
  assert(plan.start==head and plan["end"]==tail and plan.axis==axis)
  assert(plan.head.road_slope~=0 and plan.tail.road_slope~=0)
  local board=Board(Sim,s,F)
  local a,b=board.tile(head),board.tile(tail)
  assert(a.kind=="bridge" and a.dir==plus and a.skip==length-1 and a.other==tail)
  assert(b.kind=="bridge" and b.dir==minus and b.skip==length-1 and b.other==head)
  assert(a.bridge_speed==32 and b.bridge_speed==32)
  assert(board.center_z(head)==Geometry.head_pixel_height(plan.head,8,8))
  assert(board.center_z(tail)==Geometry.head_pixel_height(plan.tail,8,8))

  local function cross(src,dst,dir,near,far,delta)
    local straight=F.direction_trackdir(dir)
    local route,arrival,cost,frames=Route.route(s,src,dst,"A",{cargo="passenger",engine="bus",road_arrival_td=straight})
    assert(frames,"No stock route/motion across bridge")
    assert(#route==6 and route[3]==near and route[4]==far and arrival==straight)
    assert(cost>length*100)
    local lane,first_middle,near_mark,far_mark
    local traversed=0
    for i,f in ipairs(frames) do
      if i>1 then
        local before=frames[i-1]
        assert((horizontal and f[1]-before[1] or f[2]-before[2])==delta)
        assert((horizontal and f[2]-before[2] or f[1]-before[1])==0)
      end
      local is_head=f[4]==near or f[4]==far
      local is_middle=plan.middle_by_tile[f[4]]
      if is_head or is_middle then
        assert(f[10]==1 and f[11]==64)
        local x,z=math.floor(f[1]/16),math.floor(f[2]/16)
        assert(Sim.id(x,z)==f[4])
        local trans=horizontal and f[2] or f[1]
        assert(not lane or lane==trans);lane=trans
        if is_middle then
          assert(f[6]==Bridge.WORMHOLE and f[12] and not f[9])
          traversed=traversed+1
          first_middle=first_middle or i
        elseif f[4]==near and f[12] then
          assert(not near_mark and f[6]==Bridge.WORMHOLE)
          near_mark=i
        elseif f[4]==far and not far_mark then
          assert(f[6]==straight and not f[12] and f[9])
          far_mark=i
        end
      else
        assert(not f[10] and not f[11] and not f[12])
      end
    end
    assert(near_mark and far_mark and far_mark-near_mark==16*(length-1)+1)
    assert(traversed==16*(length-1) and (length==1 or first_middle==near_mark+1))
    return lane
  end
  local la=cross(start,finish,plus,head,tail,1)
  local lb=cross(finish,start,minus,tail,head,-1)
  assert(math.abs(la-lb)==4,"Opposing lane samples must remain apart")

  if check_cross then
    local ground=id(3,2)
    local below_td=F.direction_trackdir(horizontal and F.SE or F.SW)
    assert(board.tile(ground).kind=="road" and board.center_z(ground)==0)
    local path,_,_,frames=Route.route(s,below_a,below_b,"A",{cargo="passenger",road_arrival_td=below_td})
    assert(path and frames and #path==5 and path[3]==ground)
    local count=0
    for _,f in ipairs(frames) do
      assert(not f[10] and not f[11] and not f[12],"Bridge leaked to ground route")
      if f[4]==ground then count=count+1 end
    end
    assert(count==16)
  end

  -- A missing exterior road half remains a real break, not a teleport.
  s.tiles[id(1,2)].road_bits=across
  assert(not Route.route(s,start,finish,"A",{cargo="passenger",road_arrival_td=F.direction_trackdir(plus)}))
end

for axis=0,1 do
  build(axis,1,false)
  build(axis,5,true)
  build(axis,axis==0 and 38 or 29,true)
end
print("PASS: real paired-stock bridge routes both ways on X/Z, immediate and long spans, exact pixels, lanes, and independent road below")
