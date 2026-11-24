-- The worker still owns the untouched OpenTTD corner heights. A closed
-- authoritative subsurface index may replace only the two native voxel
-- layers belonging to a bore, using the original top/side cover materials.
local B={}
local profile={road={.422,.383,.270},rail={.487,.593,.308}}

function B.section(s,id)
  local t=s.tiles[id]
  if not t or t.stock_void then return end
  local key=s.tunnel_below and s.tunnel_below[id]
  local road=key and s.stock_road_tunnels and s.stock_road_tunnels[key]
  if road and road.middle_by_tile and road.middle_by_tile[id] then
    local dir=road.head and road.head.inside_direction
    if type(dir)=="number" and type(road.base)=="number" then return road,"road",dir%2 end
  end
  key=s.rail_tunnel_below and s.rail_tunnel_below[id]
  local rail=key and s.stock_rail_spans and s.stock_rail_spans[key]
  if rail and rail.kind=="tunnel" and rail.middle_by_tile and rail.middle_by_tile[id] and
      (rail.axis==0 or rail.axis==1) and type(rail.base)=="number" then
    return rail,"rail",rail.axis
  end
end

function B.collision(mode,axis,half)
  local width,spring,rise=unpack(profile[mode])
  local sign=half==0 and -1 or 1
  local boxes={}
  local function box(a,b,y)
    a,b=sign*(a-.5),sign*(b-.5)
    local lo,hi=math.min(a,b),math.max(a,b)
    boxes[#boxes+1]=axis==0 and {-.5,y,lo,.5,.5,hi} or {lo,y,-.5,hi,.5,.5}
  end
  box(width,1,-.5)
  for i=0,7 do
    local a,b=i*width/8,(i+1)*width/8
    -- Keep the physical opening no larger than the canonical vault.
    -- Collision follows the brick opening, not a full opaque cube.
    box(a,b,-.5+spring+rise*math.sqrt(1-(b/width)^2))
  end
  return {type="fixed",fixed=boxes}
end

-- With only the set of scene-derived solid cover materials known at load
-- time, never dig an arbitrary infrastructure, flood or overlay node.
function B.cover_candidate(name)
  return name:match("^grass[0-3]$") or name:match("^hill[0-3]$")
    or name:match("^road_%d+_plain_[0-3]$")
    or name:match("^road_foundation_%d+_[0-3]$")
    or name:match("^town_street_%d+_[0-3]") or name=="road_retaining"
    or name:match("^stock_clear_ground_%d+$") or name=="slope_fill_open"
end

function B.mount(reg,definitions)
  local covers,floors,lamps,lit_floors={},{},{},{}
  local brick="bl_tunnel_lining_brick.png"
  for _,mode in ipairs({"road","rail"}) do
    covers[mode],floors[mode],lamps[mode],lit_floors[mode]={},{},{},{}
    for axis=0,1 do for half=0,1 do
      local k=axis*2+half
      local floor=("tunnel_floor_%s_%d_%d"):format(mode,axis,half)
      local function floor_node(name)
        local top="bl_"..name..".png"
        if mode=="road" then return reg(name,{top,brick,brick},{light_source=4}) end
        return reg(name,{top,"bl_panel.png^[colorize:#93958E:244"},
          {drawtype="mesh",mesh=("bl_tunnel_track_%d_%d.obj"):format(axis,half),paramtype="light",light_source=4})
      end
      floors[mode][k],lit_floors[mode][k]=floor_node(floor),floor_node(floor.."_lit")
      local variants,lighted={},{}
      covers[mode][k],lamps[mode][k]=variants,lighted
      for name,def in pairs(definitions) do
        local base=name:match(":(.+)$")
        local open=base=="slope_fill_open"
        local side=def.tiles[3] or def.tiles[1]
        local tiles=open and {side,brick} or {def.tiles[1],side,brick}
        local suffix=("%s_%d_%d_%d"):format(mode,axis,half,open and 1 or 0)
        local function section_node(asset,materials)
          return reg("tunnel_bore_"..base.."_"..asset,materials,{
            drawtype="mesh",mesh="bl_tunnel_bore_"..asset..".obj",paramtype="light",
            sunlight_propagates=false,walkable=true,collision_box=B.collision(mode,axis,half),
          })
        end
        variants[name]=section_node(suffix,tiles)
        if half==0 then
          -- Engine voxel light is omnidirectional and would brighten the
          -- roof above a shallow bore. Bake the additional warmth into
          -- only the vault/pavement; the existing ambient floor light
          -- supplies visibility, and exterior materials remain identical.
          local warm="bl_tunnel_lining_brick_lit.png"
          local housing,lens="bl_tunnel_lamp_housing.png","bl_tunnel_lamp_lens.png"
          local lit=open and {side,warm,housing,lens} or {def.tiles[1],side,warm,housing,lens}
          lighted[name]=section_node(suffix.."_lamp",lit)
        end
      end
    end end
  end
  return function(s,id,x,y,z,ordinary)
    if not definitions[ordinary] then return end
    local span,mode,axis=B.section(s,id)
    if not span or y~=span.base and y~=span.base+1 then return end
    local k=axis*2+(axis==0 and z or x)%2
    local stride=axis==0 and 1 or s.corner_grid and s.corner_grid.width
    -- One wall fixture every three source tiles, not every Luanti node.
    local lit=stride and span.start and (math.abs(id-span.start)/stride)%3==1 and (axis==0 and x or z)%2==0
    if y==span.base then return (lit and lit_floors or floors)[mode][k] end
    if y==span.base+1 then return lit and lamps[mode][k][ordinary] or covers[mode][k][ordinary] end
  end
end
return B
