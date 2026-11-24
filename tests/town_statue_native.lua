-- Authentic Local Authority dialog opens from right-clicking a generated town.
local funds,request,ready,approached,form_y
local town,position,plinth
local raw_show=core.show_formspec
core.show_formspec=function(name,form,text)
  if name=="SteelReview" and form=="luanttd_core:town_authority" then
    local y=text:match("button%[%.45,([%d.]+);9%.7,%.57;build_statue;")
    if y and not form_y then
      form_y=tonumber(y)
      core.log("action","NATIVE STATUE OFFER "..form_y)
    end
  end
  return raw_show(name,form,text)
end
local function check()
  local p=core.get_player_by_name("SteelReview")
  if not (p and authority and authority.status()=="owned") then core.after(.2,check); return end
  local s=assert(OwnerCheckpoint.read())
  local c=s.companies.SteelReview
  if not c then core.after(.2,check);return end
  if not funds and not request then
    request=true
    assert(authority.query({kind="company",player="SteelReview"},function(answer)
      assert(answer.ok,tostring(answer.why))
      local next_cmd
      if answer.value.cash<190000 then next_cmd={kind="company_loan",amount=10000}
      elseif answer.value.speed~=0 then next_cmd={kind="speed",speed=0}
      else funds=answer.value.cash;request=false;return end
      next_cmd.revision=answer.revision
      assert(authority.query({kind="command",player="SteelReview",command=next_cmd},function(r)
        assert(r.ok,tostring(r.why));request=false
      end))
    end))
  end
  if not funds or s.speed~=0 then core.after(.2,check);return end
  if not town then
    town=assert(s.stock_town_growth.order[1])
    position=s.sites[town].tile
  end
  if not ready and api.world.target(p)==position then
    ready=true;core.log("action","NATIVE STATUE READY")
  elseif not ready then
    local x,z=Sim.xy(position)
    local _,_,top=api.terrain.tile(position)
    p:set_pos({x=x*2+.5,y=top+8,z=z*2+.5})
    p:set_look_horizontal(0);p:set_look_vertical(1.56)
  end
  plinth=s.stock_town_growth.towns[town].statues and s.stock_town_growth.towns[town].statues.SteelReview
  if plinth and not approached then
    assert(form_y and c.cash==funds-187500 and s.tiles[plinth].stock_landmark.kind=="statue")
    local x,z=Sim.xy(plinth)
    local _,_,top=api.terrain.tile(plinth)
    if core.get_node({x=x*2,y=top+1,z=z*2}).name=="luanttd_core:stock_town_statue" then
      core.close_formspec("SteelReview","luanttd_core:town_authority")
      p:set_pos({x=x*2+.5,y=top+3.1,z=z*2-6})
      p:set_look_horizontal(0);p:set_look_vertical(.45)
      approached=true
      core.log("action","PASS NATIVE TOWN STATUE: Local Authority click, paid company, native monument node")
      return
    end
  end
  core.after(.14,check)
end
core.after(.2,check)
