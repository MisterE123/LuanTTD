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
  for _,chain in ipairs({"coal","timber","oil","farm"}) do
    for _,industry in pairs(disk["stock_"..chain.."_industries"] or {}) do
      local l=industry.layout or 0
      if l>0 and (industry.kind=="coal_mine" or industry.kind=="power_station" or industry.kind=="sawmill" or industry.kind=="oil_well" or industry.kind=="oil_refinery" or industry.kind=="farm" or industry.kind=="factory" or industry.kind=="forest") then
        local label=industry.kind.."_l"..l
        scenes[label]=industry
      end
    end
  end
  local keys={}
  for label in pairs(scenes) do keys[#keys+1]=label end
  table.sort(keys)
  local required=core.settings:get("luanttd_qa_industry_layouts") or
    "factory_l1,farm_l1,oil_refinery_l1,oil_well_l1"
  for tag in required:gmatch("[^,]+") do
    assert(scenes[tag],"Missing expected "..tag.." in "..table.concat(keys,", "))
  end
  assert(#keys>0,"No alternate industry layouts were generated")
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
        local ref=assert(disk.tiles[id].stock_industry)
        -- Machinery frames are independent actors. The source can
        -- report animated coal GFX 1 while its static footprint stays 0.
        local gfx=scene.kind=="coal_mine" and row.gfx==1 and 0 or row.gfx
        if scene.kind=="coal_mine" then assert(ref.gfx==gfx) end
        local expect="luanttd_core:"..art.asset(gfx)
        if scene.kind=="forest" then
          expect=("luanttd_core:forest_%d_%d_%d"):format(scene.layout,row.x-scene.x,row.z-scene.z)
        end
        if scene.kind=="oil_well" or scene.kind=="oil_refinery" or scene.kind=="farm" or scene.kind=="factory" then
          expect=("luanttd_core:industry_%s_l%d_%d_%d"):format(scene.kind,scene.layout,row.x-scene.x,row.z-scene.z)
        end
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
