-- Loaded only in the disposable native inspector world.
local qa="RailDragQA"
local storage=core.get_mod_storage()
local Track=dofile(mod.."/openttd/rail_track.lua")
local Auto=dofile(mod.."/openttd/autorail.lua")(Track)
local stage=false
local function run()
  local p=core.get_player_by_name(qa)
  if not (p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0) then
    core.after(.2,run);return
  end
  if stage then return end
  stage=true
  local function ask(q,done)
    q.player=qa
    assert(authority.query(q,function(r) assert(r.ok,r.why);done(r) end))
  end
  local saved=storage:get_string("rail_drag_witness")
  if saved~="" then
    local witness=assert(core.deserialize(saved))
    ask({kind="checkpoint"},function()
      local disk=assert(OwnerCheckpoint.read())
      for _,part in ipairs(witness.track) do assert(disk.tiles[part.id].rail_tracks==part.tracks) end
      for _,part in ipairs(witness.roof) do assert(disk.tiles[part.id].rail_station_gfx==part.gfx) end
      ask({kind="snapshots",windows=witness.windows},function(r)
        assert(r.value[1].tiles[1].rail_diagonal==witness.diagonal)
        assert(r.value[2].tiles[1].rail_canopy==witness.canopy)
        local u,v=Sim.xy(witness.track[3].id)
        p:set_pos({x=2*u-3,y=witness.level+10,z=2*v+3})
        p:set_look_vertical(1.21)
        local roof=witness.windows[2]
        local function materialized(attempt)
          local track=core.get_node({x=u*2,y=witness.level+1,z=v*2}).name
          local glazing=core.get_node({x=roof.x*2+1,y=witness.level+1,z=roof.z*2}).name
          if track:find("rail_eased_",1,true) and glazing:find("_join_"..witness.canopy,1,true) then
            core.log("action","PASS NATIVE AUTORAIL REOPEN: paid diagonal and actual joined canopy meshes survived worker restart")
          else
            assert(attempt<42,track.." + "..glazing)
            core.after(.4,materialized,attempt+1)
          end
        end
        materialized(1)
      end)
    end)
    return
  end
  local disk=assert(OwnerCheckpoint.read())
  local T=dofile(mod.."/openttd/terrain.lua")
  local gx,gz,base
  for z=4,Sim.H-9 do
    for x=4,Sim.W-9 do
      local clear=true
      local _,h=T.tile(disk.corner_grid,x,z)
      for dv=0,6 do for du=0,7 do
        local t=disk.tiles[Sim.id(x+du,z+dv)]
        local mask,level=T.tile(disk.corner_grid,x+du,z+dv)
        if mask~=0 or level~=h or t.terrain=="water" or t.house or t.site or t.owner or t.stock_industry or t.build
          or t.stock_void or disk.stock_farm_fields and disk.stock_farm_fields[Sim.id(x+du,z+dv)] then clear=false;break end
      end end
      if clear then gx,gz,base=x,z,h;break end
    end
    if gx then break end
  end
  assert(gx,"No clear diagonal/canopy QA field")
  local function command(c,done)
    ask({kind="company"},function(r)
      c.revision=r.revision
      ask({kind="command",command=c},done)
    end)
  end
  -- Two-row, five-long stock canopy placed through the actual worker.
  local first,last=Sim.id(gx+1,gz+5),Sim.id(gx+5,gz+6)
  ask({kind="rail_quote",request={tool="station",first=first,last=last,axis=0,
    length=5,tracks=2,drag=true,separate=true}},function(st)
    command({kind="rail_commit",token=st.value.token},function()
      ask({kind="company"},function(credit)
        local cash=credit.value.cash
        local from={x=gx+1,z=gz+1}
        local to={x=gx+4,z=gz+4}
        local above={x=2*gx+5,y=base+11,z=2*gz+6}
        p:set_pos(above)
        local function aim(target)
          local dx,dy,dz=2*target.x+.5-above.x,base+.5-above.y-1.47,2*target.z+.5-above.z
          p:set_look_horizontal(math.atan2(-dx,dz))
          p:set_look_vertical(math.atan2(-dy,math.sqrt(dx*dx+dz*dz)))
        end
        aim(from)
        assert(world.go_menu(p,"railworks"))
        local slot
        for i,logical in ipairs(world.hotbar_layout(p)) do if logical==2 then slot=i end end
        assert(slot)
        local peek,commit=api.worker_build.preview,api.worker_build.commit
        local observed,paid=false,false
        function api.worker_build.preview(player,kind,req,now)
          local q,why,pending=peek(player,kind,req,now)
          if player==qa and kind=="rail" and req.tool=="autotrack" and q and q.draw and #q.draw>3 and not observed then
            assert(q.ticket and q.cost>0 and q.draw[2].mesh:find("eased",1,true))
            observed={draw=q.draw,cost=q.cost,tiles=q.tiles,ticket=q.ticket}
            assert(assert(OwnerCheckpoint.read()).companies[qa].cash==cash,"hover spent money")
            core.log("action",("NATIVE AUTORAIL PAID PREVIEW %d %d"):format(q.cost,#q.tiles))
          end
          return q,why,pending
        end
        function api.worker_build.commit(player,kind,req,cb)
          if player~=qa or kind~="rail" or req.tool~="autotrack" then return commit(player,kind,req,cb) end
          assert(observed,"released a drag without an authoritative displayed preview")
          return commit(player,kind,req,function(ok,note,quote,tiles)
            cb(ok,note,quote,tiles)
            assert(ok,note)
            assert(quote.cost==observed.cost and #tiles==#observed.tiles)
            local saved=assert(OwnerCheckpoint.read())
            assert(saved.companies[qa].cash==cash-observed.cost)
            local track={}
            for i,id in ipairs(tiles) do
              assert(id==observed.tiles[i])
              track[i]={id=id,tracks=assert(saved.tiles[id].rail_tracks)}
            end
            local r={track=track,roof={},level=base}
            for row=gz+5,gz+6 do for x=gx+1,gx+5 do
              local id=Sim.id(x,row)
              r.roof[#r.roof+1]={id=id,gfx=saved.tiles[id].rail_station_gfx}
            end end
            local x,z=Sim.xy(track[3].id)
            local roof
            for _,p_ in ipairs(r.roof) do
              if p_.gfx and p_.gfx>=4 then roof=p_.id;break end
            end
            assert(roof)
            local u,v=Sim.xy(roof)
            r.windows={{x=x,z=z,w=1,h=1},{x=u,z=v,w=1,h=1}}
            ask({kind="snapshots",windows=r.windows},function(reply)
              r.diagonal=assert(reply.value[1].tiles[1].rail_diagonal)
              r.canopy=assert(reply.value[2].tiles[1].rail_canopy)
              assert(r.canopy>=4,"paired roof must include a transverse closure")
              storage:set_string("rail_drag_witness",core.serialize(r))
              core.log("action",("PASS NATIVE AUTORAIL DRAG: %d diagonal tiles, $%d exact, same streamed railway and roof context"):format(#tiles,quote.cost))
            end)
          end)
        end
        core.register_globalstep(function()
          if paid then return end
          local keys=p:get_player_control()
          if keys.dig and keys.aux1 then aim(to);paid=true end
        end)
        core.log("action","NATIVE AUTORAIL READY "..slot)
      end)
    end)
  end)
end
core.after(.2,run)
