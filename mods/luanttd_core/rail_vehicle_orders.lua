-- The forms and worker use the same order revision and stock command adapter.
return function(S,Owned,flags)
  local A={}
  function A.read(owner,id)
    local d,note=Owned.order_state(S,owner,id)
    if not d then return d,note end
    local labels,items={},{}
    for _,x in ipairs(d.stops or {}) do labels[x.id]=x.label end
    for i,x in ipairs(d.orders or {}) do
      local f=d.cargo and d.cargo[i]
      items[i]={id=x,label=(labels[x] or ("Station #"..x))..
        (f and f.automatic and " · Automatic stop" or f and f.summary or ""),cargo=f,
        automatic=f and f.automatic or nil}
    end
    local c=d.capabilities or {}
    return {items=items,targets=d.read_only and {} or d.stops,active=d.active,parked=d.parked,can_start=d.can_start,depot=d.depot,revision=d.revision,read_only=d.read_only,can_insert=c.add==true,
      can_reorder=c.move==true,can_remove=c.remove==true,can_skip=c.skip==true,can_replace=c.replace==true,summary=d.reason,
      cargo_rules=c.load and {load=flags.load,unload=flags.unload,nonstop=c.nonstop and flags.stop_choices or nil} or nil}
  end
  function A.edit(owner,id,rev,op,i,dest)
    local verbs={append="add",up="move",down="move"}
    if (op=="up" or op=="down") and (type(i)~="number" or i<1 or i%1~=0) then
      return false,"Select an order first."
    end
    local val=op=="up" and i-1 or op=="down" and i+1 or dest
    if op=="append" then i=nil end
    return Owned.edit_orders(S,owner,id,rev,verbs[op] or op,i,val)
  end
  function A.copy_sources(owner,id,depot)
    return Owned.copy_order_sources(S,owner,id,depot)
  end
  function A.copy(owner,id,depot,source,source_revision,target_revision)
    return Owned.copy_orders(S,owner,id,depot,source,source_revision,target_revision)
  end
  return A
end
