-- An actual saved terrain, built road, purchased vehicles and YAPF route.
-- Pin both stock clocks into the approaching phase for deterministic QA.
return function(root,Sim)
  local S=Sim or dofile(root.."sim.lua")
  local Terrain=dofile(root.."openttd/terrain.lua")
  local F={Sim=S}
  function F.setup(kind,existing,owner)
    local s=existing or S.new(1751)
    s.corner_grid=s.corner_grid or dofile(root.."terrain_preview.lua")(S,Terrain,s)
    s.road_economy=true;s.road_stock_clock=true;s.road_stock_loading=true
    if s.day<9000 then
      s.day=9000
      if s.stock_load_tick then s.stock_load_tick=s.day*74 end
    end
    local a,b,d=S.id(7,12),S.id(20,12),S.id(8,13)
    owner=owner or "Traffic Test"
    local changed={}
    local function build(tool,tiles)
      local ok,msg,edits=S.build(s,owner,tool,tiles)
      assert(ok,msg)
      for _,tile in ipairs(edits or {}) do changed[#changed+1]=tile end
    end
    build("road",S.line(a,b))
    build("road_station",{a,b})
    build("road_depot",{d})
    local function dispatch(engine)
      local id=assert(S.purchase(s,owner,engine,"passenger",nil,d))
      assert(S.add_order(s,owner,id,s.tiles[b].station))
      assert(S.add_order(s,owner,id,s.tiles[a].station))
      assert(S.toggle(s,owner,id))
      return s.fleet[id]
    end
    local lead=dispatch("bus")
    local follow=dispatch(kind=="moving" and "leopard_bus" or "coach")
    S.daily(s)
    local function point(v,index,speed)
      local f=assert(v.road_motion_frames[index])
      assert(f[3]==5 and f[6]==8 and f[15]~=nil)
      v.road_speed_state={index=index,speed=speed,subspeed=0,progress=0,heading=f[3],ticks=0}
    end
    if kind=="moving" then point(lead,53,16)
    else point(lead,63,0);lead.running=false end
    point(follow,44,kind=="moving" and 40 or 10)
    if kind=="opposing" then
      local id=assert(S.purchase(s,owner,"bus","passenger",nil,d))
      local v=s.fleet[id]
      -- Park a front engine on the real other lane of the next tile.
      -- It must veto the pass even though it is not in the same-direction probe.
      v.road_stop_pose={184,201,1,S.id(11,12),1,0,[15]=7}
    end
    return s,lead.id,follow.id,changed
  end
  function F.sample(s,leader,follower)
    local a,b=S.road_motion_timeline(s,leader),S.road_motion_timeline(s,follower)
    assert(a and b and #a.cursors==75 and #b.cursors==75)
    local changed,passed,returned_ahead=false,false,false
    local previous
    for k=1,75 do
      local l,f=a.frames[a.cursors[k]],b.frames[b.cursors[k]]
      if l and f and l[3]==5 and f[3]==5 and l[6]==8 and f[6]==8 then
        if l[2]==f[2] then
          assert(math.abs(l[1]-f[1])>=7,("eastbound vehicles overlapped in the same lane at day %d tick %d: %d vs %d"):format(s.day,k,l[1],f[1]))
          if previous==201 and f[1]-l[1]>=8 then returned_ahead=true end
        else
          assert(f[2]==201 and l[2]==197,"non-stock lane sample")
          changed=true
          if f[1]>=l[1] then passed=true end
        end
      end
      previous=f and f[2]
    end
    return changed,passed,returned_ahead
  end
  function F.checkpoint(kind,existing,owner)
    local s,a,b,changed=F.setup(kind,existing,owner)
    S.daily(s);F.sample(s,a,b)
    local v=s.fleet[b]
    local c=v.road_speed_state
    local f=assert(S.road_motion_frame(s,v))
    local x=kind=="moving" and 187 or 172
    local ctr=kind=="moving" and 26 or 19
    assert(f[1]==x and f[2]==201 and c.lane_pose==f and c.overtaking==16 and c.overtaking_ctr==ctr)
    assert(c.overtakes==1 and c.last_overtake_kind==kind and not c.overtake_returns)
    return {s=s,lead=a,follow=b,kind=kind,x=f[1],y=f[2],ctr=c.overtaking_ctr},changed
  end
  function F.resume(cp)
    local s,a,b=cp.s,cp.lead,cp.follow
    local v=s.fleet[b]
    local before=S.road_motion_frame(s,v)
    assert(before[1]==cp.x and before[2]==cp.y and v.road_speed_state.overtaking_ctr==cp.ctr)
    local passed,returned=false,false
    for _=1,5 do
      S.daily(s)
      local _,p,r=F.sample(s,a,b)
      passed=passed or p
      returned=returned or r
      if passed and returned then break end
    end
    assert(passed and returned,"no completed pass and merge ahead after restore: "..cp.kind)
  end
  return F
end
