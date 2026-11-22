-- Disposable real generated world: fixed native views and node proof.
return function(api)
  local S,Sim=api.s,api.Sim
  assert(api.generated_world and S.stock_coastal_flood)
  local old=core.settings:get_bool("bayline_coastal_sheet_reference",false)
  local views={
    overview={from={x=12,y=9,z=29},at={x=32,y=1,z=33}},
    near={from={x=14,y=1.8,z=32},at={x=20,y=.55,z=31}},
    open={from={x=13,y=4.6,z=29},at={x=-18,y=.3,z=43}},
  }
  local function aim(p,v)
    p:set_pos(v.from)
    local d=vector.subtract(v.at,{x=v.from.x,y=v.from.y+1.47,z=v.from.z})
    p:set_look_horizontal(math.atan2(-d.x,d.z))
    p:set_look_vertical(math.atan2(-d.y,math.sqrt(d.x*d.x+d.z*d.z)))
  end
  local function read(x,y,z) return core.get_node({x=x,y=y,z=z}).name end
  core.register_on_joinplayer(function(p)
    S.speed=0
    core.set_timeofday(.40)
    p:set_physics_override({gravity=0})
    aim(p,views.overview)
    core.emerge_area({x=-40,y=-3,z=0},{x=65,y=5,z=68},function(_,_,remaining)
      if remaining~=0 then return end
      core.after(0,function()
        local tide=read(10,0,30)
        local apron=read(20,1,30)
        if old then
          assert(tide:match("^bayline:water%d$"))
          assert(core.registered_nodes[tide].drawtype=="nodebox")
        else
          assert(tide=="bayline:ocean_top_2_2")
          assert(read(11,0,30)=="bayline:ocean_top_3_2")
          assert(read(12,0,30)=="bayline:ocean_top_0_2")
          assert(S.tiles[Sim.id(10,15)].coastal_water and read(20,0,30)=="bayline:ocean_top_0_2")
          assert(apron:match("^bayline:stock_shore_"))
          assert(core.registered_nodes[apron].mesh:match("^bl_coastal_bank_"))
          assert(core.registered_nodes[tide].drawtype=="mesh" and core.registered_nodes[tide].waving==3)
        end
        local player=core.get_player_by_name("ShoreQA")
        if player then aim(player,views.overview) end
        core.log("action","COAST_SHEET_READY "..tide.." "..apron)
      end)
    end)
  end)
  -- Drive only the QA camera from a disposable named world file. This
  -- does not invoke chat or bind actions from the actual game's hotbar.
  local last
  core.register_globalstep(function()
    local f=io.open(core.get_worldpath().."/coastal-view.txt","r")
    if not f then return end
    local view=f:read("*l")
    f:close()
    if view==last or not views[view] then return end
    local player=core.get_player_by_name("ShoreQA")
    if not player then return end
    last=view
    aim(player,views[view])
    core.log("action","COAST_SHEET_VIEW "..view)
  end)
end
