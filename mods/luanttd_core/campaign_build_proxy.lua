-- Native hotbar actions in a worker-owned session. The canonical quote
-- and commit stay on the owner; the host gets only the receipt.
return function(client)
  local requests={}
  local B={}
  function B.commit(player,kind,gesture,done)
    if requests[player] then return nil,"Another build is being checked." end
    local id={}
    requests[player]=id
    local function finish(ok,why,quote,changed)
      if requests[player]~=id then return end
      requests[player]=nil
      done(ok,why,quote,changed)
    end
    local ok,error_=client.query({kind=kind.."_quote",player=player,request=gesture},function(offer)
      if not offer.ok then return finish(false,offer.why) end
      local cmd={kind=kind.."_commit",revision=offer.revision,token=offer.value.token}
      if kind=="road" then cmd.request,cmd.quote=gesture,offer.value end
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
