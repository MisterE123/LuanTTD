local slopes=dofile("mods/luanttd_core/openttd/slope.lua")
local registered,instances={},{}
local function set(p,entry)
  for k,v in pairs(entry) do p[k]=v end
end
local positions={[1]={3,4},[2]={4,4},[3]={4,5}}
local Sim={
  xy=function(id) return unpack(positions[id]) end,
}
local state={tiles={{h=8},{h=6},{h=4}}}
local players={}
for _,name in ipairs({"one","two"}) do
  players[name]={get_player_name=function() return name end}
end
core={
  register_entity=function(name,def) registered[name]=def end,
  get_modpath=function() return "mods/luanttd_core" end,
  get_player_by_name=function(n) return players[n] end,
  add_entity=function(pos,id,n)
    local def=assert(registered[id])
    local e={pos=pos,props={},position_updates=0,property_updates=0}
    for k,v in pairs(def.initial_properties) do e.props[k]=v end
    function e:get_pos() return self.pos end
    function e:set_pos(p) self.pos=p;self.position_updates=self.position_updates+1 end
    function e:set_properties(overrides)
      set(self.props,overrides);self.property_updates=self.property_updates+1
    end
    function e:set_observers(r) self.observers=r end
    function e:remove() self.pos=nil end
    def.on_activate({object=e},n)
    instances[#instances+1]=e
    return e
  end,
}
local cells={{slope=29,base=.5},{slope=6,base=2.5}}
local api={Sim=Sim,s=state,slope=slopes,render={}}
function api.render.uses_slope(id) return cells[id]~=nil end
function api.render.surface(id,x,z)
  local cell=assert(cells[id])
  local a,b=Sim.xy(id)
  return cell.base+slopes.surface((x-2*a+.5)/2,(z-2*b+.5)/2,cell.slope)
end
local sel=dofile("mods/luanttd_core/tile_selector.lua")(api)
sel.show(players.one,1,"inspect")
local main=instances[1]
assert(main.props.mesh=="bl_selector_29.obj" and main.props.textures[1]=="bl_selector_inspect.png")
assert(main.props.static_save==false and main.props.physical==false and main.props.pointable==false)
assert(main.observers.one and not main.observers.two)
assert(main.pos.x==6.5 and main.pos.z==8.5 and math.abs(main.pos.y-.557)<1e-9)
sel.show(players.one,1,"inspect")
assert(#instances==1 and main.position_updates==1 and main.property_updates==1)
sel.show(players.one,2,"invalid")
assert(#instances==1 and main.props.mesh=="bl_selector_6.obj" and main.props.textures[1]=="bl_selector_invalid.png")
assert(main.pos.x==8.5 and main.pos.z==8.5 and math.abs(main.pos.y-2.557)<1e-9)
sel.show(players.one,2,"anchor")
local anchor=instances[2]
assert(anchor.observers.one and not anchor.observers.two)
assert(anchor.props.textures[1]=="bl_selector_anchor.png" and anchor.pos.y<main.pos.y)

-- A different player can inspect the same tile in a different state.
sel.show(players.two,2,"valid")
local other=instances[3]
assert(other.observers.two and not other.observers.one)
assert(other.props.textures[1]=="bl_selector_valid.png")
sel.show(players.one,nil)
assert(not main:get_pos() and anchor:get_pos() and other:get_pos())
sel.show(players.one,nil,"anchor")
assert(not anchor:get_pos() and other:get_pos())
sel.show(players.two,3)
assert(other.props.mesh=="bl_selector_0.obj" and math.abs(other.pos.y-4.557)<1e-9)
assert(other.pos.x==8.5 and other.pos.z==10.5)
sel.leave("two")
assert(not other:get_pos())

-- Check the mesh envelope and all four corner heights in entity units.
for mask=0,30 do
  if mask<15 or mask==23 or mask==27 or mask==29 or mask==30 then
    local paths={}
    for line in io.lines("mods/luanttd_core/models/bl_selector_"..mask..".obj") do
      if line:sub(1,2)=="v " then
        local a,b,c=line:match("^v ([^ ]+) ([^ ]+) ([^ ]+)$")
        local x,y,z=-tonumber(a)/10,tonumber(b)/10,tonumber(c)/10
        assert(x>=-1 and x<=1 and z>=-1 and z<=1)
        assert(math.abs(y-slopes.surface((x+1)/2,(z+1)/2,mask))<1e-7)
        if math.abs(x)==1 and math.abs(z)==1 then paths[x..","..z]=true end
      end
    end
    assert(paths["-1,-1"] and paths["1,-1"] and paths["-1,1"] and paths["1,1"])
  end
end
print("PASS: observer isolation, separate anchor/cursor, surface positioning and 19 exact tile meshes")

-- Entire footprint uses private bound meshes, never particles or stale
-- ghosts. Cursor and anchor are excluded from the footprint layer.
sel.area(players.one,{1,2,3,3},1,2,"valid")
local area=instances[#instances]
assert(#instances==4 and area.observers.one and area.props.textures[1]=="bl_selector_valid.png")
sel.area(players.one,{3,3},2,1,"invalid")
assert(#instances==4 and area.props.textures[1]=="bl_selector_invalid.png")
sel.area(players.one,{1},2,3,"valid")
assert(not area:get_pos() and #instances==5 and instances[5].props.mesh=="bl_selector_29.obj")
sel.area(players.one,nil,nil,nil,"inspect")
assert(not instances[5]:get_pos())
local ids={}
for i=1,300 do ids[i]=i;positions[i]=positions[i] or {i,4};state.tiles[i]=state.tiles[i] or {h=0} end
sel.area(players.two,ids,401,nil,"valid")
assert(#instances==5+math.ceil(300/7))
sel.leave("two")
for _,e in ipairs(instances) do assert(not e:get_pos()) end
print("PASS: multi-tile outlines exclude anchor and cursor, reuse objects and remain bounded and private")
