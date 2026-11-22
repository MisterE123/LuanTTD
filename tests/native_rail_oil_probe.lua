-- Fixture only: prepare stock corridors, camera pose, and pause/reopen.
-- Stage designation, buying and dispatch are via normal mouse and menus.
return function(api,owner,qa_ui)
  local S,Sim=api.s,api.Sim
  S.qa_rail_oil=S.qa_rail_oil or {}
  local q=S.qa_rail_oil
  if not q.ready then S.speed=0 end
  core.register_chatcommand("qa_railoil",{func=function(n,mode)
    if n~=owner then return false end
    if mode=="layout" and not q.ready then
      q.wells,q.sink,q.truck=dofile(core.get_modpath("luanttd_core").."/rail_oil_live_layout.lua")(api,n,true)
      q.ready=true
    end
    if mode=="go" or mode=="resume" then S.speed=1 end
    local p=core.get_player_by_name(n)
    local x,y,z,tx,ty,tz=25,12,16,25,.45,10.5
    if mode=="refinery" then
      x,y,z,tx,ty,tz=29,9,42,24.5,.50,34.5
    elseif mode=="photo" and q.partial then
      local w=q.partial.wagon
      x,y,z,tx,ty,tz=w.x+4,2.75,w.z+5,w.x,.85,w.z
    end
    p:set_pos({x=x,y=y,z=z})
    p:set_look_horizontal(math.atan2(x-tx,tz-z))
    p:set_look_vertical(math.atan2(y+p:get_properties().eye_height-ty,math.sqrt((x-tx)^2+(z-tz)^2)))
    return true
  end})
  return function()
    local status=Sim.rail_oil_status(S)
    local unit=api.rail_owned.list(S,owner)[1]
    local meshes={}
    local last_wagon
    for _,obj in ipairs(core.get_objects_inside_radius({x=23,y=3,z=22},46)) do
      local e=obj:get_luaentity()
      if e and e.name=="luanttd_core:dispatch_oil_tanker" then
        last_wagon=obj:get_pos()
        meshes[#meshes+1]=last_wagon
      end
    end
    if not q.partial and status and status.onboard>0 and status.onboard<30 and
        status.loading and q.wells==status.last_platform and last_wagon then
      S.speed=0
      q.partial={oil=status.onboard,tick=status.tick,source=status.last_platform,wagon=last_wagon,kind="luanttd_core:dispatch_oil_tanker"}
      api.save()
    end
    local stations=S.stock_rail_stations or {}
    local a,b=stations[q.wells],stations[q.sink]
    local f=S.stock_oil_industries[0x3001]
    local truck=S.fleet[q.truck]
    local player=core.get_player_by_name(owner)
    local _,toast
    if player then _,toast=qa_ui.world_status(player,nil,false) end
    if toast and toast~=q.toast then
      core.log("action","Native Rail Oil QA status: "..toast)
      q.toast=toast
    end
    return {toast=toast,ready=q.ready,partial=q.partial,train=status,unit=unit,mesh=meshes,
      wells=a and a.oil_role,refinery=b and b.oil_role,oil=f.received and f.received.oil or 0,
      goods=truck and truck.delivered,goods_fare=truck and truck.revenue,house_tick=S.passenger_house_clock.counter}
  end
end
