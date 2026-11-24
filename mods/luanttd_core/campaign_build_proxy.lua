-- Native hotbar actions in a worker-owned session. The canonical quote
-- and commit stay on the owner; the host gets only the receipt.
return function(client)
  local requests={}
  local B={}
  local observe=client.observe or client.query
  local hovers={}
  local function key(value)
    if type(value)~="table" then return tostring(value) end
    local parts={}
    for k,v in pairs(value) do parts[#parts+1]=tostring(k).."="..key(v) end
    table.sort(parts)
    return "{"..table.concat(parts,",").."}"
  end
  local function signature(kind,gesture) return kind..":"..key(gesture) end
  function B.preview(player,kind,gesture,now)
    local signature=signature(kind,gesture)
    local prior=hovers[player]
    if prior and prior.signature==signature and prior.at and now-prior.at<650000 then
      return prior.value,prior.why
    end
    if not prior or not prior.waiting then
      local q={signature=signature,waiting=true}
      hovers[player]=q
      local accepted=observe({kind=kind.."_quote",player=player,request=gesture,peek=true},function(r)
        if hovers[player]~=q then return end
        q.waiting=nil;q.at=now;q.value=r.value;q.why=r.why
      end)
      if not accepted then hovers[player]=nil end
    end
    return nil,"Checking construction…",true
  end
  function B.leave(player) hovers[player]=nil;requests[player]=nil end
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
      local old=hovers[player]
      local prior=old and old.signature==signature(kind,gesture) and old.value or nil
      local ok,why=client.query({kind="road_place",player=player,request=gesture,quote=prior},function(r)
        hovers[player]=nil
        if r.ok and client.refresh_scene then client.refresh_scene() end
        finish(r.ok,r.why,prior,r.value)
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
