-- Native hotbar actions in a worker-owned session. The canonical quote
-- and commit stay on the owner; the host gets only the receipt.
return function(client)
  local requests={}
  local B={}
  local observe=client.observe or client.query
  local hovers,shown,rail_presented={},{},{}
  local function key(value)
    if type(value)~="table" then return tostring(value) end
    local parts={}
    for k,v in pairs(value) do parts[#parts+1]=tostring(k).."="..key(v) end
    table.sort(parts)
    return "{"..table.concat(parts,",").."}"
  end
  local function signature(kind,gesture) return kind..":"..key(gesture) end
  local function priced(kind,gesture)
    return kind=="road" or kind=="rail" and gesture.tool=="autotrack"
  end
  function B.preview(player,kind,gesture,now)
    local signature=signature(kind,gesture)
    local function present(q)
      shown[player]=priced(kind,gesture) and q.value and {signature=signature,value=q.value} or nil
      if kind=="rail" and gesture.tool=="autotrack" and q.value and q.value.ticket then
        rail_presented[player]=q.value.ticket
      end
      return q.value,q.why
    end
    local prior=hovers[player]
    local same=prior and prior.signature==signature
    if same and prior.at and now-prior.at<650000 then
      return present(prior)
    end
    if not prior or not prior.waiting then
      local q=same and prior or {signature=signature}
      q.waiting=true
      hovers[player]=q
      local accepted=observe({kind=kind.."_quote",player=player,request=gesture,peek=true},function(r)
        if hovers[player]~=q then return end
        q.waiting=nil;q.at=now;q.value=r.value;q.why=r.why
      end)
      if not accepted then q.waiting=nil end
    end
    -- Retain a complete result only for the exact same gesture. This
    -- keeps a stationary road ghost stable during an occupancy refresh.
    -- A newer endpoint never borrows an older shape or price.
    if priced(kind,gesture) and same and prior.at then return present(prior) end
    shown[player]=nil
    return nil,"Checking construction…",true
  end
  function B.begin_rail(player)
    rail_presented[player]=nil
  end
  function B.leave(player) hovers[player]=nil;shown[player]=nil;requests[player]=nil;rail_presented[player]=nil end
  function B.commit(player,kind,gesture,done)
    if requests[player] then return nil,"Another build is being checked." end
    local id={}
    requests[player]=id
    local function finish(ok,why,quote,changed)
      if requests[player]~=id then return end
      requests[player]=nil
      done(ok,why,quote,changed)
    end
    if kind=="road" then
      local old=shown[player]
      local prior=old and old.signature==signature(kind,gesture) and old.value or nil
      local ok,why=client.query({kind="road_place",player=player,request=gesture,quote=prior},function(r)
        hovers[player]=nil;shown[player]=nil
        if r.ok and client.refresh_scene then client.refresh_scene() end
        finish(r.ok,r.why,prior,r.value)
      end)
      if not ok then requests[player]=nil;return nil,why end
      return true
    end
    if kind=="rail" and gesture.tool=="autotrack" then
      local from,to=gesture.start,gesture.finish
      local ticket=rail_presented[player]
      -- A quick click still builds a single tile. A multi-tile drag may
      -- not spend money until the player has actually seen a priced ghost.
      local drag=from and to and (math.floor(from.x/16)~=math.floor(to.x/16)
        or math.floor(from.z/16)~=math.floor(to.z/16))
      if drag and not ticket then
        requests[player]=nil
        return nil,"Hold on the end of the drag until the track and price appear."
      end
      local ok,why=client.query({kind="rail_place",player=player,request=gesture,ticket=ticket},function(r)
        hovers[player]=nil;shown[player]=nil;rail_presented[player]=nil
        if r.ok and client.refresh_scene then client.refresh_scene() end
        local paid=r.value
        finish(r.ok,r.why,r.ok and {cost=paid.cost,tiles=paid.tiles} or nil,paid and paid.tiles)
      end)
      if not ok then requests[player]=nil;return nil,why end
      return true
    end
    local ok,error_=client.query({kind=kind.."_quote",player=player,request=gesture},function(offer)
      if not offer.ok then return finish(false,offer.why) end
      local cmd={kind=kind.."_commit",revision=offer.revision,token=offer.value.token}
      local sent,msg=client.query({kind="command",player=player,command=cmd},function(receipt)
        finish(receipt.ok,receipt.why,offer.value,receipt.value)
      end)
      if not sent then finish(false,msg) end
    end)
    if not ok then requests[player]=nil;return nil,error_ end
    return true
  end
  return B
end
