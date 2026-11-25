-- Real generated campaign, priced worker quotes and bulldozer; no
-- scripted town, scenery, noise/finances or airport placement.
local owner="StockResidentialQA"
local function begin()
  local p=core.get_player_by_name(owner)
  if not(p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0) then
    core.after(.25,begin);return
  end
  local disk=assert(OwnerCheckpoint.read())
  assert(disk.stock_road_town_policy.station_noise_level)
  local Noise=dofile(mod.."/openttd/airport_noise.lua")
  local T=dofile(mod.."/openttd/terrain.lua")
  local H=dofile(mod.."/openttd/airport_heliport.lua")
  local Net=dofile(mod.."/airport_network.lua")(Sim,T,dofile(mod.."/openttd/airport_small.lua"),
    dofile(mod.."/openttd/airport_city.lua"),nil,H,{},Noise)
  local function ask(req,cb,may_reject)
    req.player=owner
    assert(authority.query(req,function(r)
      if not may_reject then assert(r.ok,req.kind..": "..tostring(r.why)) end
      cb(r)
    end))
  end
  local function budget(id,fn)
    ask({kind="town_authority",town=id},function(r) fn(assert(r.value.airport_noise)) end)
  end
  local function place(id,fn)
    local req={mode="air",operation="build",layout="heliport",tile=id}
    ask({kind="transport_quote",request=req},function(r)
      assert(r.value.cost==600 and r.value.noise.add==1 and r.value.noise.used<r.value.noise.limit)
      ask({kind="command",command={kind="transport_commit",token=r.value.token,revision=r.revision}},fn)
    end)
  end
  if core.settings:get_bool("luanttd_qa_airport_noise_reopen",false) then
    local saved=assert(core.deserialize(storage:get_string("qa_airport_noise"),true))
    budget(saved.town,function(b)
      assert(b.used==saved.used and b.limit==saved.limit)
      local t=assert(OwnerCheckpoint.read())
      assert(t.tiles[saved.added].airfield and not t.tiles[saved.removed].airfield)
      core.log("action",("PASS NATIVE AIRPORT NOISE REOPEN: %d/%d, replacement persists"):format(b.used,b.limit))
    end)
    return
  end
  local best,want,pads
  for _,town in ipairs(disk.sites) do
    if town.kind=="town" and town.population>0 and town.population<1600 then
      local limit=Noise.town_capacity(town.population,800)
      local x,z=Sim.xy(town.tile)
      local legal={}
      for dz=-9,9 do for dx=-9,9 do
        local id=Sim.id(x+dx,z+dz)
        local q=Net.quote(disk,owner,id,"heliport")
        if q and q.noise and q.noise.town==town.id then legal[#legal+1]=id end
      end end
      if #legal>limit then
        table.sort(legal,function(a,b) return Sim.distance(a,town.tile)<Sim.distance(b,town.tile) or
          Sim.distance(a,town.tile)==Sim.distance(b,town.tile) and a<b end)
        best,want,pads=town,limit,legal;break
      end
    end
  end
  assert(best and want>=3,"No stock town with enough buildable pads")
  local function finish()
    budget(best.id,function(b)
      assert(b.used==want and b.limit==want)
      local qualified={mode="air",operation="build",layout="heliport",tile=pads[want+1]}
      ask({kind="transport_quote",request=qualified},function(r)
        assert(not r.ok and r.why:find(best.name,1,true) and r.why:find("noise",1,true))
        ask({kind="demolition",tile=pads[1]},function(q)
          local layer
          for _,o in ipairs(q.value.options) do if o.ok and o.key=="airfield" then layer=o.key end end
          assert(layer,"Airport layer not selectable in the bulldozer")
          ask({kind="command",command={kind="demolition",token=q.value.token,layer=layer,revision=q.revision}},function()
            budget(best.id,function(after)
              assert(after.used==want-1 and after.limit==want)
              place(pads[want+1],function()
                local from,to=pads[1],pads[want+1]
                storage:set_string("qa_airport_noise",core.serialize({town=best.id,used=want,limit=want,added=to,removed=from}))
                local x,z=Sim.xy(to)
                local _,_,top=T.tile(disk.corner_grid,x,z)
                p:set_pos({x=2*x-4,y=top+3.8,z=2*z-6})
                p:set_look_horizontal(math.atan2(-4,6));p:set_look_vertical(.52)
                core.after(1.5,function()
                  ui.open_town_authority(p,best.id)
                  core.after(.6,function()
                    core.log("action","NATIVE AIRPORT NOISE FRAME")
                    core.after(.9,function()
                      core.log("action",("PASS NATIVE AIRPORT NOISE SERVICE: %s capped at %d, denial, clear and rebuild"):format(best.name,want))
                    end)
                  end)
                end)
              end)
            end)
          end)
        end)
      end,true)
    end)
  end
  local function fill(i)
    if i>want then finish();return end
    place(pads[i],function() fill(i+1) end)
  end
  budget(best.id,function(b) assert(b.used==0 and b.limit==want);fill(1) end)
end
core.after(.20,begin)
