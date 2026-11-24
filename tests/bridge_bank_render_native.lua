-- Road bridge across real, opposed coastal slopes in the production renderer.
local terrain=dofile(mod.."/openttd/terrain.lua")
local lo,hi,z,modern,rail,dry=11,17,14,18,22,26
local function id(x,a) return assert(Sim.id(x,a)) end
local new=terrain.new(Sim.W,Sim.H,function(x,row)
  -- A bend in the coast next to the timber abutment exposes its
  -- side, unlike a perfectly straight coast where the bank hides it.
  if row==z-1 and x==lo or row==z+2 and x==hi+1 then return 0 end
  return (x<=lo or x>=hi+1) and 1 or 0
end)
S.corner_grid.levels=new.levels
local dirty={}
for a=1,Sim.H do for x=1,Sim.W do
  local k=id(x,a)
  local slope,h=terrain.tile(S.corner_grid,x,a)
  local sea=x>=lo and x<=hi and a~=dry and (a~=rail or x>lo and x<hi)
  S.tiles[k]={terrain=sea and "water" or "grass",variant=(x+a)%4,h=h,
    water_class=sea and "sea" or nil,coastal_water=sea and slope~=0 or nil}
  if x>=lo-5 and x<=hi+5 and a>=z-7 and a<=dry+2 then dirty[#dirty+1]=k end
end end
S.speed=0
local owner="PierQA"
Sim.company(S,owner).cash=200000
local before=table.concat(S.corner_grid.levels,",")
for _,build in ipairs({{z,0},{modern,2},{dry,0}}) do
  local yes,note,_,deck=Sim.road_bridge(S,owner,id(lo,build[1]),id(hi,build[1]),build[2])
  assert(yes,note);assert(deck==1)
  assert(not S.tiles[id(lo,build[1])].coastal_water and not S.tiles[id(hi,build[1])].coastal_water)
end
local quote,why=api.rail_spans.quote_bridge(S,owner,id(lo,rail),id(hi,rail))
assert(quote,why)
assert(api.rail_spans.commit(S,owner,quote))
assert(table.concat(S.corner_grid.levels,",")==before,"Construction altered neighboring corners")
api.render.raise_bound(1)
local ready=false
core.register_on_joinplayer(function(p)
  if p:get_player_name()~=owner then return end
  local first,last={x=2*(lo-5),y=-1,z=2*(z-7)},{x=2*(hi+5),y=6,z=2*(dry+3)}
  core.emerge_area(first,last,function(_,_,left)
    if left~=0 then return end
    api.render.update(dirty)
    local function node(x,y,a,dx,dz)
      return core.get_node({x=x*2+dx,y=y,z=a*2+dz}).name
    end
    for _,mode in ipairs({{z,"road_bridge_wood"},{modern,"road_bridge_girder"},{rail,"rail_bridge_wood"},{dry,"road_bridge_wood"}}) do
      local zg,stem=mode[1],mode[2]
      for _,x in ipairs({lo,hi}) do
        local deck=node(x,1,zg,0,0)
        assert(deck:find("stock_"..stem.."_head_flat",1,true),deck)
        local want=zg==dry and "bridge_bank_" or "bridge_shore_"
        local shape=node(x,1,zg,1,0)
        assert(shape:find(want,1,true),shape)
        for dx=0,1 do for dz=0,1 do
          local support=node(x,0,zg,dx,dz)
          assert(zg==dry and support=="luanttd_core:slope_fill_open" or
            zg~=dry and support:find("ocean_top",1,true),support)
        end end
      end
    end
    assert(node((lo+hi)/2,0,z,0,0):find("ocean_top",1,true),"true water under the span must remain")
    assert(node(lo,0,z+1,0,0):find("ocean_top",1,true),"unbuilt adjacent coast must keep genuine sea")
    local inside=id(lo+1,dry)
    S.tiles[inside].terrain,S.tiles[inside].water_class="water","sea"
    api.render.update({inside})
    assert(node(lo,1,dry,1,0):find("bridge_shore_",1,true),"changing inward neighbor must repaint the head")
    S.tiles[inside].terrain,S.tiles[inside].water_class="grass",nil
    api.render.update({inside})
    assert(node(lo,1,dry,1,0):find("bridge_bank_",1,true))
    p:override_day_night_ratio(.92)
    ready=true
    core.log("action","BRIDGE_BANK_NATIVE_READY coastal timber, girder and rail heads match stock shore; dry control, deck, terrain and adjacent sea preserved")
  end)
end)
local old
core.register_globalstep(function()
  if not ready then return end
  local f=io.open(core.get_worldpath().."/pier-view.txt","r")
  if not f then return end
  local mode=f:read("*l");f:close()
  local p=core.get_player_by_name(owner)
  if not p or old==mode or not ({left_bank=true,right_bank=true,modern=true,rail=true,upper=true})[mode] then return end
  old=mode
  local x=mode=="right_bank" and hi or lo
  local zg=mode=="modern" and modern or mode=="rail" and rail or z
  local d=x==lo and 1 or -1
  local from={x=x*2+d*4.1,y=.54,z=zg*2-4.7}
  if mode=="upper" then from={x=x*2+d*2.1,y=3.0,z=zg*2-3.9} end
  local to={x=x*2+.5,y=1.17,z=zg*2+.5}
  local dx,dy,dz=to.x-from.x,to.y-from.y-1.625,to.z-from.z
  p:set_pos(from)
  p:set_look_horizontal(math.atan2(-dx,dz))
  p:set_look_vertical(math.atan2(-dy,math.sqrt(dx*dx+dz*dz)))
  p:hud_set_flags({hotbar=false,crosshair=false})
  core.log("action","BRIDGE_BANK_NATIVE_VIEW "..mode)
end)
