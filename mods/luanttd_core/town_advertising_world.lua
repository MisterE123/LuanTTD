-- Adapt the stock GoodsEntry flags from each ordinary worker ledger.
-- Road and commercial views can point to the same GoodsEntry.
return function(Sim,Kernel)
  local A={}
  local function active(g,accepts)
    return accepts or g.has_rating or g.ever_accepted or g.last_month or g.current_month or g.accepted_bigtick
  end
  function A.apply(s,owner,x,z,amount,radius)
    local rows,seen={},{}
    local function row(st,xx,zz,accepts_passengers,accepts_mail)
      if not xx or not zz or st.owner~=owner or math.abs(xx-x)+math.abs(zz-z)>radius then return end
      local g={}
      local function add(state,acceptance)
        if type(state)=="table" and type(state.rating)=="number" and not seen[state] and active(state,acceptance) then
          seen[state]=true
          g[#g+1]={state=state,active=true}
        end
      end
      add(st.passenger_rating_state,accepts_passengers)
      add(st.mail_rating_state,accepts_mail)
      for _,entry in pairs(st.goods or {}) do
        if type(entry)=="table" then add(entry,entry.acceptance==true or (tonumber(entry.acceptance) or 0)>=8) end
      end
      if #g>0 then rows[#rows+1]={owner=owner,x=xx,y=zz,goods=g} end
    end
    local c=s.stock_ship_commercial and s.stock_ship_commercial.service
    for _,st in pairs(c and c.stations or {}) do
      local sign=st.sign or st.tiles and st.tiles[1]
      if sign then row(st,sign.x,sign.y,(st.passenger_acceptance or 0)>=8,(st.mail_acceptance or 0)>=8) end
    end
    for _,st in pairs(s.stations) do
      if st.mode=="road" and st.owner==owner then
        local group=s.stock_joined_stations and st.stock_station_id~=nil and s.stock_joined_stations[st.stock_station_id]
        local at=group and group.tile or st.tile
        local xx,zz=Sim.xy(at)
        if math.abs(xx-x)+math.abs(zz-z)<=radius then
          Sim.passenger_rating(s,st)
          local pax=st.passenger_acceptance or Sim.road_passenger_acceptance(s,st.tile) or 0
          row(st,xx,zz,pax>=8,(st.mail_acceptance or 0)>=8)
        end
      end
    end
    return Kernel.modify_around(rows,owner,x,z,amount,radius)
  end
  -- Bribe failure clears every represented GoodsEntry at a station
  -- assigned to this TownID, irrespective of distance from its sign.
  function A.clear(s,owner,town)
    local seen={}
    local function clear(st,id)
      if st.owner~=owner or id~=town or seen[st] then return end
      seen[st]=true
      st.passenger_rating_state=st.passenger_rating_state or Kernel.new()
      st.mail_rating_state=st.mail_rating_state or Kernel.new()
      st.passenger_rating_state.rating=0
      st.mail_rating_state.rating=0
      for _,g in pairs(st.goods or {}) do if type(g)=="table" and type(g.rating)=="number" then g.rating=0 end end
    end
    local c=s.stock_ship_commercial and s.stock_ship_commercial.service
    for _,st in pairs(c and c.stations or {}) do clear(st,st.town) end
    for _,st in pairs(s.stations) do
      local group=s.stock_joined_stations and st.stock_station_id~=nil and s.stock_joined_stations[st.stock_station_id]
      clear(st,group and group.town or st.town or st.site)
    end
  end
  return A
end
