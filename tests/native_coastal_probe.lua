-- Read-only capture plus camera/time controls. Landscaping itself uses the hotbar.
return function(api,owner)
  local S,Sim=api.s,api.Sim
  local q=S.qa_coastal or {};S.qa_coastal=q
  if not q.started then S.speed=0 end
  core.register_chatcommand("qa_coast",{func=function(n,mode)
    if n~=owner then return false end
    local p=core.get_player_by_name(n)
    if mode=="go" then q.started=true;S.speed=1;api.save();return true end
    local tx,tz=mode=="trench" and 18.5 or 24.5,mode=="trench" and 36.5 or 61.5
    local dx,dz,alt=5,5,10
    if mode=="beach" then dx,dz,alt=3,5,3.6 end
    p:set_pos({x=tx+dx,y=alt,z=tz+dz})
    p:set_look_horizontal(math.atan2(dx,-dz))
    p:set_look_vertical(math.atan2(alt+p:get_properties().eye_height-.55,math.sqrt(dx*dx+dz*dz)))
    return true
  end})
  local function sample(x,z)
    local id=Sim.id(x,z)
    local t=S.tiles[id]
    local slope,h,top=api.terrain.tile(id)
    return {slope=slope,base=h,top=top,water=t.terrain=="water",shore=t.coastal_water}
  end
  return function()
    return {day=S.day,active=api.coastal_flood_tools,revision=S.corner_grid.revision,
      bay=sample(12,28),trench=sample(9,18)}
  end
end
