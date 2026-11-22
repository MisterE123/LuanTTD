-- Rail Engineering art. The middle deck is an overlay, not a replacement
-- of whichever water, road or ground happens to be below that tile.
return function(World,s,architecture,terrain,bridge_wire,xy)
  local R={}
  local wood="rail_bridge_wood"
  local clear_span=dofile(core.get_modpath("bayline").."/bridge_clearance_render.lua")(architecture,wood)
  local foot=dofile(core.get_modpath("bayline").."/bridge_pier_render.lua")(architecture,terrain,{wood})
  function R.foot(id,x,y,z)
    if clear_span.under(s.tiles[id]) then return end
    return foot(id,x,y,z,World.by_bridge_middle(s,id),1,s.tiles[id].terrain=="water")
  end
  local parts={span={},head_flat={},head_ramp={},pier={}}
  for part,list in pairs(parts) do
    local limit=(part=="span" or part=="pier") and 1 or 3
    for dir=0,limit do
      local asset=wood.."_"..part.."_"..dir
      list[dir]=architecture("stock_"..asset,asset,wood)
    end
  end
  local tunnels={}
  for dir=0,3 do
    local asset="rail_tunnel_portal_"..dir
    tunnels[dir]=architecture("stock_"..asset,asset,"rail_tunnel_portal")
  end
  local wire_nodes={}
  local function mount(d)
    if not wire_nodes[d.name] then
      wire_nodes[d.name]=architecture("stock_"..d.name,d.name,"rail_catenary_atlas")
    end
  end
  if bridge_wire then
    for _,part in ipairs({"head_flat","head_ramp"}) do
      for dir=0,3 do mount(bridge_wire.overlay(part,dir)) end
    end
    for axis=0,1 do
      for mid=1,2 do mount(bridge_wire.overlay("span",axis,mid,3)) end
    end
  end
  function R.extent()
    local peak=0
    for _,span in pairs(s.stock_rail_spans or {}) do
      peak=math.max(peak,span.deck or span.base)
    end
    return peak
  end
  function R.node(id,x,y,z,ground,retaining)
    local span=World.by_portal(s,id)
    local anchor=x%2==0 and z%2==0
    if span then
      local head=span.start==id and span.head or span.tail
      if span.kind=="tunnel" then
        if y<=span.base then return ground end
        if anchor and y==span.base+1 then return tunnels[head.inside_direction] end
      else
        if bridge_wire and span.railtype==1 and anchor and y==span.deck+bridge_wire.offset then
          local cable=bridge_wire.overlay(head.flat_ramp and "head_flat" or "head_ramp",head.inside_direction)
          if cable then return wire_nodes[cable.name] end
        end
        if anchor and y==span.deck then
          return parts[head.flat_ramp and "head_flat" or "head_ramp"][head.inside_direction]
        end
        if y<=head.base then return head.foundation~="none" and retaining or ground end
      end
      return "air"
    end
    local elevated=World.by_bridge_middle(s,id)
    if elevated and anchor then
      if bridge_wire and elevated.railtype==1 and y==elevated.deck+bridge_wire.offset then
        local xx,zz=xy(elevated.start)
        local end_x,end_z=xy(elevated["end"])
        local i=elevated.axis==0 and x/2-math.min(xx,end_x) or z/2-math.min(zz,end_z)
        local cable=bridge_wire.overlay("span",elevated.axis,i,#elevated.middle)
        if cable then return wire_nodes[cable.name] end
      end
      local clear=clear_span.under(s.tiles[id])
      if y==elevated.deck then return (clear and clear_span or parts.span)[elevated.axis] end
      if not clear and y<elevated.deck then
        local _,_,top=terrain.tile(id)
        if y>top then return parts.pier[elevated.axis] end
      end
    end
  end
  return R
end
