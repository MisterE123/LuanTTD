-- Rail Engineering art. The middle deck is an overlay, not a replacement
-- of whichever water, road or ground happens to be below that tile.
return function(World,s,architecture,terrain,bridge_wire,xy)
  local R={}
  local modpath=core.get_modpath("luanttd_core")
  local styles=dofile(modpath.."/bridge_style_assets.lua")
  local rules=dofile(modpath.."/openttd/road_bridge.lua")(dofile(modpath.."/openttd/slope.lua"))
  local walk_bridge=dofile(modpath.."/pedestrian_bridge.lua")
  local piece=dofile(modpath.."/bridge_piece_art.lua")(architecture,rules,xy,walk_bridge.box)
  local clearance=dofile(modpath.."/bridge_clearance_render.lua")
  local parts={}
  for style,stem in pairs(styles.rail) do
    local manifest=styles.pieces[style]
    local geometry=styles.mesh_stem("rail",style)
    local defs={head_flat={},head_ramp={}}
    if not manifest then defs.span={};defs.pier={} end
    for part,list in pairs(defs) do
      local limit=(part=="span" or part=="pier") and 1 or 3
      for dir=0,limit do
        local asset=stem.."_"..part.."_"..dir
        list[dir]=architecture("stock_"..asset,geometry.."_"..part.."_"..dir,stem,false,walk_bridge.box(part,dir))
      end
    end
    if manifest then defs.piece=piece.mount(stem,manifest,geometry) end
    defs.clear=clearance(architecture,stem,manifest~=nil,walk_bridge.box)
    parts[style]=defs
  end
  local foot=dofile(modpath.."/bridge_pier_render.lua")(architecture,terrain,styles.static("rail"))
  function R.foot(id,x,y,z)
    local span=World.by_bridge_middle(s,id)
    if not span then return end
    local style=span.bridge_type or 0
    local part=parts[style]
    if part.clear.under(s.tiles[id]) then return end
    local feet
    if part.piece then local _,_,_,f=part.piece.models(span,id);feet=f end
    return foot(id,x,y,z,span,style,s.tiles[id].terrain=="water",feet)
  end
  local tunnels={}
  for dir=0,3 do
    local asset="rail_tunnel_portal_"..dir
    tunnels[dir]=architecture("stock_"..asset,asset,"rail_tunnel_portal")
  end
  local advanced={}
  local Guide=dofile(modpath.."/rail_guideway_profiles.lua")
  for _,g in ipairs(Guide.gauges) do
    local stem="guideway_"..Guide.by_gauge[g].slug.."_span"
    local art=io.open(modpath.."/textures/bl_"..stem..".png","rb")
    if art then
      art:close()
      local shapes={span={},head_flat={},head_ramp={},tunnel={}}
      for part,list in pairs(shapes) do
        for dir=0,part=="span" and 1 or 3 do
          local asset=stem.."_"..part.."_"..dir
          list[dir]=architecture("stock_"..asset,asset,stem,false,walk_bridge.box(part,dir))
        end
      end
      shapes.clear=dofile(modpath.."/bridge_clearance_render.lua")(architecture,stem,false,walk_bridge.box)
      advanced[g]=shapes
    end
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
  function R.node(id,x,y,z,ground,bridge_bank_node)
    local span=World.by_portal(s,id)
    local anchor=x%2==0 and z%2==0
    if span then
      local head=span.start==id and span.head or span.tail
      if span.kind=="tunnel" then
        if y<=span.base then return ground end
        if anchor and y==span.base+1 then
          return advanced[span.railtype] and advanced[span.railtype].tunnel[head.inside_direction] or tunnels[head.inside_direction]
        end
      else
        if bridge_wire and span.railtype==1 and anchor and y==span.deck+bridge_wire.offset then
          local cable=bridge_wire.overlay(head.flat_ramp and "head_flat" or "head_ramp",head.inside_direction)
          if cable then return wire_nodes[cable.name] end
        end
        if anchor and y==span.deck then
          local shape=head.flat_ramp and "head_flat" or "head_ramp"
          return advanced[span.railtype] and advanced[span.railtype][shape][head.inside_direction] or parts[span.bridge_type or 0][shape][head.inside_direction]
        end
        return bridge_bank_node(head,id,s.tiles[id],x,y,z)
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
      local style=parts[elevated.bridge_type or 0]
      local clear=style.clear.under(s.tiles[id])
      if y==elevated.deck then
        local axis=elevated.axis
        local a=advanced[elevated.railtype]
        if a then return (clear and a.clear or a.span)[axis] end
        if style.piece then
          local deck,under=style.piece.models(elevated,id)
          return clear and under or deck
        end
        return (clear and style.clear or style.span)[axis]
      end
      if not clear and y<elevated.deck then
        local _,_,top=terrain.tile(id)
        if y>top then
          if style.piece then local _,_,pier=style.piece.models(elevated,id);return pier end
          return style.pier[elevated.axis]
        end
      end
    end
  end
  return R
end
