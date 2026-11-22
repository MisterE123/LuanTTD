-- A navigational overview, not a construction map. Draw one compact raster,
-- then overlay bounded native hit targets so the engine handles mouse input.
return function(api)
  local M={}
  local Sim,S=api.Sim,api.s
  local max_cells=64
  local colors={
    void="#172A36",sea="#2D6985",river="#4F9AB1",wood="#416446",
    low="#71965E",mid="#8D9E64",high="#BCAA77",house="#E0AB85",
    road="#E0D0A6",rail="#B3C3CB",station="#FFE185",industry="#D08E4B",
    landmark="#F6DB89",you="#FFF8DF",
  }
  local function ground(h)
    if h<=1 then return colors.low end
    if h<=3 then return colors.mid end
    return colors.high
  end
  local function classify(t)
    if not t or t.stock_void then return colors.void,-1 end
    if t.station or t.rail_station_id or t.ship and t.ship.kind=="dock" then return colors.station,8 end
    if t.stock_industry or t.site and S.sites[t.site].kind~="town" then return colors.industry,7 end
    if t.stock_landmark then return colors.landmark,7 end
    if t.house or t.site then return colors.house,6 end
    if t.rail_tracks or t.level_crossing or t.build=="rail" then return colors.rail,5 end
    local build=t.build and Sim.tools[t.build]
    if build and build.mode=="road" or t.tram then return colors.road,5 end
    if t.water_class=="river" or t.build=="canal" then return colors.river,4 end
    if t.terrain=="water" then return colors.sea,3 end
    if t.wood or t.stock_tree then return colors.wood,2 end
    return ground(t.h or 0),1
  end
  local function player_tile(p)
    local pos=p:get_pos()
    return Sim.id(math.floor((pos.x+.5)/2),math.floor((pos.z+.5)/2))
  end
  function M.layout(V,here)
    local w,h=Sim.W,Sim.H
    local wide=w>max_cells or h>max_cells
    local stride=V.map_zoom and 1 or math.max(1,math.ceil(math.max(w,h)/max_cells))
    local cols,rows=math.min(max_cells,math.ceil(w/stride)),math.min(max_cells,math.ceil(h/stride))
    local x,z=1,1
    if wide and V.map_zoom then
      local at=here or V.chosen or Sim.id(1,1)
      local u,v=Sim.xy(at)
      x=math.max(1,math.min(w-cols+1,u-math.floor(cols/2)))
      z=math.max(1,math.min(h-rows+1,v-math.floor(rows/2)))
    end
    return x,z,cols,rows,stride,wide
  end
  function M.cells(V,here)
    local x,z,cols,rows,stride,wide=M.layout(V,here)
    local pixels,targets={},{}
    local sample_step=math.max(1,math.ceil(stride/4))
    for rz=0,rows-1 do for cx=0,cols-1 do
      local at=rz*cols+cx+1
      local winner,quality,color=nil,-2,nil
      for dz=0,stride-1,sample_step do for dx=0,stride-1,sample_step do
        local id=Sim.id(x+cx*stride+dx,z+rz*stride+dz)
        if id then
          local shade,rank=classify(S.tiles[id])
          if rank>quality then winner,quality,color=id,rank,shade end
        end
      end end
      pixels[at]=color or colors.void
      if quality>=0 then targets[at]=winner end
    end end
    local marker
    if here then
      local u,v=Sim.xy(here)
      local cx,rz=math.floor((u-x)/stride),math.floor((v-z)/stride)
      if cx>=0 and cx<cols and rz>=0 and rz<rows then marker={cx,rz} end
    end
    return pixels,targets,cols,rows,stride,wide,marker
  end
  local function button_id(i) return "jump_"..i end
  function M.pick(V,f)
    for field in pairs(f) do
      local index=tonumber(field:match("^jump_(%d+)$"))
      local id=index and V.map_targets and V.map_targets[index]
      if id then return id end
      local site=tonumber(field:match("^jump_site_(%d+)$"))
      if site and V.map_sites then
        id=V.map_sites[site]
        if id then return id end
      end
    end
  end
  function M.pick_coordinates(raw_x,raw_z)
    local function coord(raw,limit)
      local n=type(raw)=="string" and #raw<=8 and raw:match("^%s*%d+%s*$") and tonumber(raw)
      return n and n>=1 and n<=limit and n or nil
    end
    local x,z=coord(raw_x,Sim.W),coord(raw_z,Sim.H)
    local id=x and z and Sim.id(x,z)
    local t=id and S.tiles[id]
    return t and not t.stock_void and id or nil
  end

  function M.draw(V,p,form)
    local push,rect,label,button=form.push,form.rect,form.label,form.button
    local here=player_tile(p)
    local pixels,targets,cols,rows,stride,wide,marker=M.cells(V,here)
    V.map_targets,V.map_sites=targets,{}
    local step=math.min(13.24/cols,10.38/rows)
    local mw,mh=step*cols,step*rows
    local mx,my=.52+(13.24-mw)/2,2.46
    rect(.32,1.88,14.12,11.45,"#20394A")
    label(.55,2.16,(V.map_zoom and wide and "LOCAL DETAIL" or "REGION OVERVIEW")..
      ("   /   %d × %d tiles   /   N ↑"):format(Sim.W,Sim.H),"#AACCC2")
    local tex=core.formspec_escape("[png:"..core.encode_base64(core.encode_png(cols,rows,pixels)))
    push(("image[%.6f,%.6f;%.6f,%.6f;%s]"):format(mx,my,mw,mh,tex))
    if marker then
      local x,y=mx+marker[1]*step,my+marker[2]*step
      -- A light pin with a dark border stays legible against roads and sea.
      local r=math.max(.14,step*.68)
      rect(x+step/2-r,y+step/2-r,r*2,r*2,"#25323D")
      rect(x+step/2-r*.61,y+step/2-r*.61,r*1.22,r*1.22,colors.you)
    end
    push("style_type[image_button;border=false;sound=]")
    for at=1,cols*rows do
      if targets[at] then
        local x,y=mx+(at-1)%cols*step,my+math.floor((at-1)/cols)*step
        push(("image_button[%.6f,%.6f;%.6f,%.6f;bl_map_clear.png;%s;;false;false]")
          :format(x,y,step,step,button_id(at)))
      end
    end
    rect(14.65,1.88,5.73,11.45,"#182C3D")
    label(14.93,2.17,"JUMP MAP","#FFE1A0")
    label(14.93,2.61,"Pick a point to fly there.","#ACCBC9")
    if wide then
      button(14.93,3.01,5.10,.51,"map_zoom",V.map_zoom and "Show full region" or "Show detail near me")
      label(14.93,3.75,stride==1 and "One map cell per world tile." or ("Overview: one cell per %d × %d tiles."):format(stride,stride),"#AACCC2")
    else
      label(14.93,3.05,"One map cell per world tile.","#AACCC2")
    end
    local keys={{"You",colors.you},{"Towns",colors.house},{"Industry",colors.industry},{"Roads",colors.road},{"Rail",colors.rail},{"Water",colors.sea}}
    for i,pair in ipairs(keys) do
      local x,y=14.95+((i-1)%2)*2.47,4.20+math.floor((i-1)/2)*.36
      rect(x,y-.075,.15,.15,pair[2]);label(x+.22,y,pair[1],"#ACCBC9")
    end
    label(14.93,5.55,"QUICK JUMPS","#FFE1A0")
    local y=5.82
    for i,site in ipairs(S.sites) do
      if site.kind=="town" and not site.closed and y<10.24 then
        V.map_sites[i]=site.tile
        button(14.93,y,5.10,.43,"jump_site_"..i,site.name)
        y=y+.48
      end
    end
    push("field[14.93,11.15;1.20,.53;map_x;Tile X;]"..
      "field[16.30,11.15;1.20,.53;map_z;Tile Z;]"..
      "field_close_on_enter[map_x;false]field_close_on_enter[map_z;false]")
    button(17.67,11.15,2.36,.53,"map_coordinates","Jump to tile")
    button(14.93,12.22,5.10,.53,"map_return","Return to 3D world","primary")
  end
  return M
end
