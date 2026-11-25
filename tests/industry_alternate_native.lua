-- Temporary native driver appended after the actual game initializes.
local started
local function start()
  local p=core.get_player_by_name("IndustryLayoutsQA")
  if not (p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0) then
    core.after(.20,start)
    return
  end
  if started then return end
  started=true
  local disk=assert(OwnerCheckpoint.read())
  local art=dofile(mod.."/industry_layout_art.lua")
  local scenes={}
  for _,chain in ipairs({"coal","timber"}) do
    for _,industry in pairs(disk["stock_"..chain.."_industries"] or {}) do
      local l=industry.layout or 0
      if l>0 and (industry.kind=="coal_mine" or industry.kind=="power_station" or industry.kind=="sawmill") then
        local label=industry.kind.."_l"..l
        scenes[label]=industry
      end
    end
  end
  local keys={}
  for label in pairs(scenes) do keys[#keys+1]=label end
  table.sort(keys)
  assert(#keys==6,"Expected all six alternate layouts on this native fixture seed")
  core.log("action","NATIVE ALTERNATE GENERATED: "..table.concat(keys,", "))
  local function verify(i)
    local label=keys[i]
    if not label then
      core.log("action","PASS NATIVE INDUSTRY LAYOUTS: stock occupied cells rendered, holes left clear in normal worker world")
      return
    end
    local scene=scenes[label]
    local mx,mz=0,0
    local occupied={}
    for _,row in ipairs(scene.tiles) do
      mx,mz=math.max(row.x,mx),math.max(row.z,mz)
      occupied[Sim.id(row.x+1,row.z+1)]=row
    end
    local x,z=scene.x+1,scene.z+1
    local ground=disk.tiles[Sim.id(scene.tiles[1].x+1,scene.tiles[1].z+1)].h
    p:set_pos({x=x+mx+1,y=ground+7,z=2*z-7})
    p:set_look_horizontal(0);p:set_look_vertical(.64)
    local function check(n)
      for id,row in pairs(occupied) do
        local u,v=Sim.xy(id)
        local base=disk.tiles[id].h
        local node=core.get_node_or_nil({x=2*u,y=base+1,z=2*v})
        local expect="luanttd_core:"..art.asset(row.gfx)
        if not node or node.name~=expect then
          assert(n<55,("Wrong mesh in %s @ %d,%d: %s expected %s"):format(label,u,v,node and node.name or "nil",expect))
          core.after(.25,function()check(n+1)end)
          return
        end
      end
      for w=z,mz+1 do for u=x,mx+1 do
        local id=Sim.id(u,w)
        if not occupied[id] then
          local tile=disk.tiles[id]
          assert(not tile.stock_industry or tile.stock_industry.id~=scene.id)
          local node=core.get_node_or_nil({x=2*u,y=tile.h+1,z=2*w})
          assert(not node or not node.name:match("^luanttd_core:industry_layout_gfx_"),"A stock layout hole was painted")
        end
      end end
      core.after(1.35,function()
        core.log("action","NATIVE INDUSTRY FRAME "..label)
        core.after(1.3,function() verify(i+1) end)
      end)
    end
    core.after(.45,function()check(0)end)
  end
  verify(1)
end
core.after(.20,start)
