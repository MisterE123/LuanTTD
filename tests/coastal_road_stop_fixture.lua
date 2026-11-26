-- Headless and native fixtures use the same purchased stock road vehicle,
-- production loading loop, terrain visits, and real through-stop commands.
return function(S,T,H,Construction)
  local F={}
  local owner="Coastal bus QA"
  local a,b,d=S.id(11,12),S.id(17,12),S.id(12,13)
  local sea=S.id(11,11)
  function F.start(s)
    local g=assert(s.corner_grid)
    for i in ipairs(g.levels) do g.levels[i]=0 end
    for i in ipairs(s.tiles) do s.tiles[i]={terrain="grass",h=0,variant=1} end
    for z=18,22 do for x=1,g.width+1 do g.levels[(z-1)*(g.width+1)+x]=1 end end
    s.road_economy,s.road_stock_clock,s.road_stock_house_supply,s.road_stock_loading=true,true,true,true
    S.mount_coastal_flood(s)
    S.company(s,owner)
    assert(S.build(s,owner,"road",S.line(S.id(9,12),S.id(19,12))))
    local C=Construction(S,s)
    for _,id in ipairs({a,b}) do
      local req={tool="stock_terminal_auto",first=id,kind="bus"}
      local q,why=C.quote(owner,req)
      assert(q,why)
      assert(C.commit(owner,req,q))
      assert(s.tiles[id].stop_axis==10,"Expected an actual drive-through stop")
    end
    assert(S.build(s,owner,"road_depot",{d}))
    local A,B=s.tiles[a].station,s.tiles[b].station
    local busid,why=S.purchase(s,owner,"bus","passenger",nil,d)
    assert(busid,why)
    assert(S.add_order(s,owner,busid,A,"full"))
    assert(S.add_order(s,owner,busid,B))
    assert(S.toggle(s,owner,busid))
    local bus=s.fleet[busid]
    for _=1,12 do
      S.daily(s)
      if bus.load_state then break end
    end
    assert(bus.load_state and bus.load_state.full and bus.road_stop_pose[4]==a)
    assert(S.stock_road_frame_z(s,bus.road_stop_pose)==0)
    local st=s.stations[A]
    st.stock=st.stock or {}
    st.stock.passenger={{units=19,source=11,origin_station=A,age=0}}
    local reserve,aboard,reported
    -- Let the normal loading clock reserve and pick up passengers. The
    -- deterministic test adds a sea source and visits that exact tile
    -- as soon as the real vehicle is holding both kinds of packets.
    local function visit(clock,ticks,read,before)
      H.advance(clock,ticks,read,before)
      if not reserve and bus.load_state and bus.load_state.reserved_units>0 and bus.units>0 then
        reserve,aboard=bus.load_state.reserved_units,bus.units
        s.tiles[sea]={terrain="water",water_class="sea",h=0,variant=1}
        for _,id in ipairs({S.id(10,10),S.id(11,10),S.id(12,10),S.id(10,11),S.id(12,11)}) do
          s.tiles[id]={terrain="water",water_class="river",h=0,variant=1}
        end
        local x,z=S.xy(sea)
        read((z-1)*2^clock.log_x+x-1,clock.counter)
      end
    end
    S.mount_news(s,nil,function(tile,victims)
      assert(tile==a and victims>=1 and victims<=1+reserve+aboard)
      assert(not reported)
      reported=true
    end)
    S.daily(s,visit)
    assert(reserve and aboard and reported and bus.crashed and bus.road_flood_age>=2000 and bus.road_flood_age<2220)
    assert(bus.units==0 and #bus.batches==0 and not bus.load_state and #st.loading_order==0)
    local remain=0
    for _,p in ipairs(st.stock.passenger) do remain=remain+p.units end
    assert(remain==19-reserve-aboard,"A wreck must not return its reserved passengers")
    assert(s.tiles[a].station==A and s.tiles[a].terrain~="water" and s.tiles[a].stop_axis==10)
    assert(not S.toggle(s,owner,busid) and not S.sell(s,owner,busid))
    return {id=busid,wet=A,dry=B,vehicle_ticks=bus.road_vehicle_ticks}
  end
  function F.finish(s,proof)
    local bus=assert(s.fleet[proof.id])
    assert(bus.crashed and bus.road_flood_age>=2000 and bus.road_vehicle_ticks==proof.vehicle_ticks)
    assert(s.tiles[a].station==proof.wet and s.stations[proof.wet])
    for _=1,25 do
      S.daily(s)
      if not s.fleet[proof.id] and s.tiles[a].terrain=="water" then break end
    end
    assert(not s.fleet[proof.id],"Wreck did not retire")
    assert(s.tiles[a].water_class=="sea" and not s.tiles[a].station and not s.tiles[a].road_bits)
    assert(not s.stations[proof.wet] and s.tiles[b].station==proof.dry and s.stations[proof.dry])
    return true
  end
  return F
end
