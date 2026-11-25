-- Active bus route in a normal generated worker world, with exact native terrain
-- commands through the authority endpoint. No imported terrain or finance.
local owner="IndustryLayoutsQA"
local place
local function clear(x,z,h)
  local id=Sim.id(x,z)
  local t=id and S.tiles[id]
  if not t or t.stock_void or t.terrain=="water" or t.build or t.owner or t.house or t.site
      or t.stock_landmark or t.stock_industry or t.wood or (S.stock_farm_fields and S.stock_farm_fields[id]) then return end
  local slope,y=api.terrain.tile(id)
  return slope==0 and y>0 and (h==nil or h==y) and y
end
for z=8,Sim.H-9 do
  for x=8,Sim.W-16 do
    local h=clear(x,z)
    if h then
      local okay=true
      for dz=-1,1 do for dx=-1,9 do
        if not clear(x+dx,z+dz,h) then okay=false;break end
      end end
      if okay then place={x=x,z=z,h=h};break end
    end
  end
  if place then break end
end
assert(place,"No naturally high flat testing strip")
local function at(d) return Sim.id(place.x+d,place.z) end
local function query(q,f)
  q.player=owner
  assert(authority.query(q,function(r) assert(r.ok,r.why);f(r) end))
end
local function command(c,f)
  query({kind="company"},function(r)
    c.revision=r.revision;query({kind="command",command=c},f)
  end)
end
local function build(request,f)
  query({kind="road_quote",request=request},function(q)
    query({kind="command",command={kind="road_commit",revision=q.revision,request=request,
      token=q.value.token,quote=q.value}},f)
  end)
end
local function until_(label,p,f,n)
  local v=p()
  if v then f(v);return end
  n=n or 0
  assert(n<220,label)
  core.after(.25,function() until_(label,p,f,n+1) end)
end
local function finance()
  local s=assert(OwnerCheckpoint.read())
  return s.companies[owner],s
end
local function lower(q,f)
  query({kind="terrain_quote",request={operation="lower",first=q}},function(r)
    assert(r.value.cost==750,"Two neighboring road foundations and one physical corner must be charged")
    query({kind="command",command={kind="terrain_commit",revision=r.revision,token=r.value.token}},f)
  end)
end
local function run(viewer)
  viewer:set_pos({x=2*place.x+10,y=place.h+8,z=2*place.z-9})
  viewer:set_look_horizontal(0);viewer:set_look_vertical(.57)
  command({kind="road_build",first=at(1),last=at(8)},function()
    build({tool="road_depot",first=at(0)},function()
      build({tool="road_station",first=at(3)},function()
        build({tool="road_station",first=at(7)},function()
          query({kind="depot",mode="road",depot=at(0)},function(list)
            local buy
            for _,offer in ipairs(list.value.offers) do
              if offer.request.cargo=="passenger" then buy=offer.request;break end
            end
            assert(buy)
            command(buy,function(r)
              local vehicle=r.value
              local _,s=finance()
              local a,b=s.tiles[at(3)].station,s.tiles[at(7)].station
              command({kind="road_order_add",vehicle=vehicle,station=b},function()
                command({kind="road_order_add",vehicle=vehicle,station=a},function()
                  command({kind="road_toggle",vehicle=vehicle},function()
                    lower(at(5),function()
                      until_("Road and its support were not repainted",function()
                        local _,s=finance()
                        local shape,base=dofile(mod.."/openttd/terrain.lua").tile(s.corner_grid,place.x+5,place.z)
                        local physical=core.get_node_or_nil({x=2*(place.x+5),y=place.h,z=2*place.z})
                        return shape==7 and base==place.h-1 and physical and physical.name:find("foundation",1,true)
                      end,function()
                        local deck={x=2*(place.x+5)+.5,y=place.h+.55,z=2*place.z+.5}
                        until_("The actual bus never crossed the edited ground",function()
                          for _,ref in ipairs(core.get_objects_inside_radius(deck,1.35)) do
                            local obj=ref:get_luaentity()
                            local pick=obj and obj.luanttd_vehicle
                            local pos=pick and pick.kind=="road" and pick.id==vehicle and ref:get_pos()
                            if pos and math.abs(pos.y-deck.y)<.24 then return pos end
                          end
                        end,function()
                          core.after(3,function()
                            core.log("action","NATIVE ROAD TERRAFORM FRAME road-autoslope-live")
                            core.after(1,function()
                              core.log("action","PASS NATIVE ROAD AUTOSLOPE: moving bus crossed above two paid foundations without changing roadway height")
                            end)
                          end)
                        end)
                      end)
                    end)
                  end)
                end)
              end)
            end)
          end)
        end)
      end)
    end)
  end)
end
until_("Ordinary worker client not ready",function()
  local viewer=core.get_player_by_name(owner)
  return viewer and authority and authority.status()=="owned" and #world.hotbar_layout(viewer)>0 and viewer
end,run)
