return function(root,over_fixture)
  local Sim=dofile(root.."sim.lua")
  local F=over_fixture(root,Sim)
  local Slope=dofile(root.."openttd/road_slope.lua")
  local Follow=dofile(root.."openttd/yapf_road_follow.lua")
  local Terrain=dofile(root.."openttd/terrain.lua")
  local OneWay=dofile(root.."openttd/road_oneway.lua")(Slope,Follow)
  local World=dofile(root.."road_oneway_world.lua")(Sim,Terrain,Follow,OneWay)
  local owner="Traffic Test"
  local id=Sim.id
  local target=id(12,12)

  local function fixture()
    local s,lead,car=F.setup("stopped")
    s.fleet[lead]=nil
    Sim.mount_road_oneway(s,World)
    return s,car,s.fleet[car].dest
  end
  local function reached(s,car,dest)
    local target_tile=s.stations[dest].tile
    local timeline=Sim.road_motion_timeline(s,car)
    for _,i in ipairs(timeline and timeline.cursors or {}) do
      if i>0 and timeline.frames[i][4]==target_tile then return true end
    end
    return false
  end
  local function setup_sign(s)
    assert(World.build(s,owner,id(14,12),target,0))
    assert(World.read(s.tiles[target])==2)
  end
  local function held(s,car)
    for _=1,8 do
      Sim.daily(s)
      local v=s.fleet[car]
      local c=v.road_speed_state
      assert(c and not v.last_road_arrival_tick)
      if c.waiting=="oneway" then
        assert(c.oneway_tile==target and c.oneway_reason=="WRONG_ONE_WAY_DIRECTION")
        local f=Sim.road_motion_frame(s,v)
        assert(f[4]==id(11,12) and f[1]==12*16-1 and v.status=="Waiting at one-way road")
        return c.index,f[1]
      end
    end
    error("precompiled leg crossed an incompatible one-way tile")
  end
  return {Sim=Sim,World=World,owner=owner,id=id,target=target,fixture=fixture,held=held,
    reached=reached,setup_sign=setup_sign}
end
