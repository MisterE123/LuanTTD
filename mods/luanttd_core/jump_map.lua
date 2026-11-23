-- Navigation only. The detailed, palette-indexed worker raster and the
-- modest interactive area grid deliberately have different resolutions.
return function(api)
  local M={}
  local Sim,S=api.Sim,api.s
  local RASTER,HITS,DETAIL=144,24,64
  local palette={
    "#172A36","#2D6985","#4F9AB1","#42694C",
    "#628954","#72975D","#86A069","#9AA875","#ABAC79","#B9AA80","#C8BC94",
    "#E9B991","#E9D394","#AABCC9","#FFE185","#D58F50","#EAD893","#FFF8DF",
  }
  local C={void=1,sea=2,river=3,wood=4,house=12,road=13,rail=14,station=15,industry=16,landmark=17,you=18}
  local rgba={}
  for i,hex in ipairs(palette) do
    rgba[string.char(i)]=string.char(tonumber(hex:sub(2,3),16),tonumber(hex:sub(4,5),16),tonumber(hex:sub(6,7),16),255)
  end
  local function classify(t,id)
    if not t or t.stock_void then return C.void,-1 end
    if t.station or t.rail_station_id or t.ship and t.ship.kind=="dock" then return C.station,8 end
    local site=t.site and S.sites[t.site]
    if t.stock_industry or site and site.kind~="town" then return C.industry,7 end
    if t.stock_landmark then return C.landmark,7 end
    if t.house or site then return C.house,6 end
    if t.rail_tracks or t.level_crossing or t.build=="rail" or S.rail_bridge_above and S.rail_bridge_above[id] then
      return C.rail,5
    end
    local build=t.build and Sim.tools[t.build]
    if build and build.mode=="road" or t.road_bits or t.tram or
        S.bridge_above and S.bridge_above[id] then return C.road,5 end
    if t.water_class=="river" or t.stock_canal or t.build=="canal" then return C.river,4 end
    if t.terrain=="water" then return C.sea,3 end
    if t.wood or t.stock_tree then return C.wood,2 end
    return 5+math.min(6,math.floor(math.sqrt(math.max(0,t.h or 0))*1.45)),1
  end
  local function player_tile(p)
    local pos=p:get_pos()
    return pos and Sim.id(math.floor((pos.x+.5)/2),math.floor((pos.z+.5)/2))
  end
  local function layout(zoom,focus)
    local w,h=Sim.W,Sim.H
    local wide=w>DETAIL or h>DETAIL
    local x,z=1,1
    if wide and zoom then
      local u,v=Sim.xy(focus or Sim.id(1,1))
      w,h=math.min(w,DETAIL),math.min(h,DETAIL)
      x=math.max(1,math.min(Sim.W-w+1,u-math.floor(w/2)))
      z=math.max(1,math.min(Sim.H-h+1,v-math.floor(h/2)))
    end
    return x,z,w,h,wide
  end
  local function resolution(w,h,cap)
    local stride=math.max(1,math.ceil(math.max(w,h)/cap))
    return math.ceil(w/stride),math.ceil(h/stride),stride
  end
  local function bounds(origin,n,i,k)
    return origin+math.floor(i*n/k),origin+math.floor((i+1)*n/k)-1
  end
  local function sample(lo,hi)
    if hi==lo then return lo,lo end
    return lo+math.floor((hi-lo)/4),hi-math.floor((hi-lo)/4)
  end
  local function towns_in(x,z,w,h)
    -- One strongest candidate per spatial bin avoids city-name crowds at
    -- continent scale without losing isolated small towns in other regions.
    local bins={}
    for _,t in ipairs(S.sites) do
      if t.kind=="town" and not t.closed and t.tile and type(t.name)=="string" then
        local a,b=Sim.xy(t.tile)
        if a>=x and a<x+w and b>=z and b<z+h then
          local bin=math.floor((a-x)*12/w)+math.floor((b-z)*8/h)*12
          local prior=bins[bin]
          local score=t.population or 0
          if not prior or score>prior.population or score==prior.population and t.tile<prior.tile then
            bins[bin]={kind="town",name=t.name:sub(1,56),tile=t.tile,population=score}
          end
        end
      end
    end
    local towns={}
    for _,t in pairs(bins) do towns[#towns+1]=t end
    table.sort(towns,function(a,b)
      if a.population~=b.population then return a.population>b.population end
      return a.tile<b.tile
    end)
    return towns
  end
  function M.snapshot(zoom,here,focus)
    local x,z,w,h,wide=layout(zoom,focus or here)
    local pw,ph,raster_stride=resolution(w,h,RASTER)
    local cols,rows,stride=resolution(w,h,HITS)
    local pixels,targets,fallback={},{},{}
    local function sample_tile(a,b)
      local id=Sim.id(a,b)
      local color,rank=classify(S.tiles[id],id)
      return color,rank,a,b,id
    end
    -- At most four samples per raster pixel regardless of world size;
    -- 64 and 128 maps get actual, unsampled one-pixel-per-tile.
    local function strongest(color,rank,a,b,id,c,r,u,v,i)
      if r>rank then return c,r,u,v,i end
      return color,rank,a,b,id
    end
    for row=0,ph-1 do
      local zs,ze=sample(bounds(z,h,row,ph))
      for col=0,pw-1 do
        local xs,xe=sample(bounds(x,w,col,pw))
        local color,rank,a,b,id=sample_tile(xs,zs)
        if xe~=xs then color,rank,a,b,id=strongest(color,rank,a,b,id,sample_tile(xe,zs)) end
        if ze~=zs then color,rank,a,b,id=strongest(color,rank,a,b,id,sample_tile(xs,ze)) end
        if xe~=xs and ze~=zs then color,rank,a,b,id=strongest(color,rank,a,b,id,sample_tile(xe,ze)) end
        pixels[#pixels+1]=string.char(color)
        if rank>=0 then
          -- Map a known playable sample to its own hit region. This is
          -- an escape hatch for thin coasts missed by center/edge probes.
          local ix,iz=math.ceil((a-x+1)*cols/w),math.ceil((b-z+1)*rows/h)
          fallback[(iz-1)*cols+ix]=id
        end
      end
    end
    for row=0,rows-1 do for col=0,cols-1 do
      local lo,hi=bounds(x,w,col,cols)
      local north,south=bounds(z,h,row,rows)
      local u,v=math.floor((lo+hi+1)/2),math.floor((north+south+1)/2)
      local function playable(a,b)
        local id=Sim.id(a,b)
        local t=S.tiles[id]
        return t and not t.stock_void and id or nil
      end
      -- A nearby tile within the same clicked area, not a distant
      -- higher-ranked building. Keep wholly void areas non-interactive.
      local id=playable(u,v) or playable(lo,v) or playable(hi,v) or playable(u,north) or playable(u,south)
        or playable(lo,north) or playable(hi,north) or playable(lo,south) or playable(hi,south)
      local region=row*cols+col+1
      targets[region]=id or fallback[region]
    end end
    local marker
    if here then
      local u,v=Sim.xy(here)
      if u>=x and u<x+w and v>=z and v<z+h then marker={(u-x+.5)/w,(v-z+.5)/h} end
    end
    return {pixels=table.concat(pixels),pixel_cols=pw,pixel_rows=ph,targets=targets,cols=cols,rows=rows,
      stride=stride,raster_stride=raster_stride,wide=wide,marker=marker,towns=towns_in(x,z,w,h),x=x,z=z,w=w,h=h}
  end

  function M.pan(V,direction,here)
    local p=V.map_packet
    if not (V.map_zoom and p) then return end
    local dx,dz=0,0
    if direction=="map_west" then dx=-math.ceil(p.w*.72)
    elseif direction=="map_east" then dx=math.ceil(p.w*.72)
    elseif direction=="map_north" then dz=-math.ceil(p.h*.72)
    elseif direction=="map_south" then dz=math.ceil(p.h*.72)
    else return end
    local x=math.max(1,math.min(Sim.W,p.x+math.floor(p.w/2)+dx))
    local z=math.max(1,math.min(Sim.H,p.z+math.floor(p.h/2)+dz))
    V.map_center=Sim.id(x,z) or here
    return true
  end

  function M.pick(V,f)
    for field in pairs(f) do
      local num=tonumber(field:match("^jump_(%d+)$"))
      if num and V.map_targets and V.map_targets[num] then return V.map_targets[num],"area" end
      local place=tonumber(field:match("^jump_site_(%d+)$") or field:match("^jump_place_(%d+)$"))
      if place and V.map_sites and V.map_sites[place] then return V.map_sites[place],"place" end
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

  function M.labels(p,mx,my,mw,mh,clip)
    local marks,occupied={},{}
    clip=clip or {mx,my,mx+mw,my+mh}
    local wide=p.w>p.h and p.w/p.h or 1
    local max_names=math.max(5,math.floor(32/wide))
    if p.marker then
      local px,py=mx+p.marker[1]*mw,my+p.marker[2]*mh
      occupied[1]={px-.16,py-.16,px+.16,py+.16}
    end
    for i,t in ipairs(p.towns) do
      if #marks>=max_names then break end
      local a,b=Sim.xy(t.tile)
      local x,y=mx+(a-p.x+.5)*mw/p.w,my+(b-p.z+.5)*mh/p.h
      local chars=#t.name
      local w,h=math.max(.68,.135*chars+.30),.31
      for _,r in ipairs({{x+.13,y-h/2},{x-w-.13,y-h/2},{x-w/2,y-h-.10},{x-w/2,y+.10}}) do
        local left,top=r[1],r[2]
        local fits=left>=clip[1]+.025 and top>=clip[2]+.025 and left+w<=clip[3]-.025 and top+h<=clip[4]-.025
        if fits then
          for _,other in ipairs(occupied) do
            if left<other[3]+.075 and left+w>other[1]-.075 and top<other[4]+.05 and top+h>other[2]-.05 then
              fits=false;break
            end
          end
        end
        if fits then
          occupied[#occupied+1]={left,top,left+w,top+h}
          marks[#marks+1]={index=i,x=x,y=y,left=left,top=top,w=w,h=h}
          break
        end
      end
    end
    return marks
  end

  function M.draw(V,p,form,packet)
    local push,rect,label,button=form.push,form.rect,form.label,form.button
    local P=packet or M.snapshot(V.map_zoom,player_tile(p),V.map_center)
    V.map_packet,V.map_targets,V.map_sites=P,P.targets,{}
    local step=math.min(13.24/P.w,10.38/P.h)
    local mw,mh=step*P.w,step*P.h
    local mx,my=.52+(13.24-mw)/2,2.46+(10.38-mh)/2
    local detail=V.map_zoom and P.wide
    rect(.32,1.88,14.12,11.45,"#20394A")
    label(.55,2.16,(detail and "LOCAL DETAIL" or "REGION OVERVIEW")..
      ("   /   %d × %d tiles   /   N ↑"):format(P.w,P.h),"#AACCC2")
    local data=P.pixels:gsub(".",rgba)
    local tex=core.formspec_escape("[png:"..core.encode_base64(core.encode_png(P.pixel_cols,P.pixel_rows,data)))
    push(("image[%.6f,%.6f;%.6f,%.6f;%s]"):format(mx,my,mw,mh,tex))
    if P.marker then
      local x,y=mx+P.marker[1]*mw,my+P.marker[2]*mh
      rect(x-.13,y-.13,.26,.26,"#25323D")
      rect(x-.082,y-.082,.164,.164,palette[C.you])
    end
    local function hit(x,y,w,h,id)
      push(("image_button[%.6f,%.6f;%.6f,%.6f;bl_map_clear.png;%s;;false;false]")
        :format(x,y,w,h,id))
    end
    push("style_type[image_button;border=false;sound=]")
    for at=1,P.cols*P.rows do
      if P.targets[at] then
        local cw,ch=mw/P.cols,mh/P.rows
        hit(mx+(at-1)%P.cols*cw,my+math.floor((at-1)/P.cols)*ch,cw,ch,"jump_"..at)
      end
    end
    push("style_type[label;font_size=-2;font=bold]")
    -- A very thin 64×4096 slice still gets names beside it instead
    -- of silently dropping every label whose badge is wider than the map.
    local names_clip=mw<4 and {.52,2.46,13.76,12.84} or nil
    for _,spot in ipairs(M.labels(P,mx,my,mw,mh,names_clip)) do
      local town=P.towns[spot.index]
      V.map_sites[spot.index]=town.tile
      rect(spot.x-.063,spot.y-.063,.126,.126,"#FFE4A2")
      rect(spot.left,spot.top,spot.w,spot.h,"#152734DA")
      label(spot.left+.11,spot.top+spot.h*.54,town.name,"#FFF0C6")
      hit(spot.left,spot.top,spot.w,spot.h,"jump_place_"..spot.index)
    end
    push("style_type[label;font_size=;font=normal]")
    rect(14.65,1.88,5.73,11.45,"#182C3D")
    label(14.93,2.17,"JUMP MAP","#FFE1A0")
    label(14.93,2.61,V.map_inspect and "Pick an area to show it in detail." or "Pick an area or town to fly there.","#ACCBC9")
    if P.wide then
      button(14.93,3.00,5.10,.50,"map_zoom",detail and "Show full region" or "Detail near me")
      if detail then
        for i,a in ipairs({{"west","←"},{"north","↑"},{"south","↓"},{"east","→"}}) do
          button(14.93+(i-1)*1.30,3.62,1.20,.44,"map_"..a[1],a[2])
        end
      else
        button(14.93,3.62,5.10,.44,"map_inspect",V.map_inspect and "Cancel area selection" or "Zoom into another area",V.map_inspect and "active")
      end
    else
      label(14.93,3.10,"One image pixel per world tile.","#AACCC2")
    end
    local keys={{"You",palette[C.you]},{"Towns",palette[C.house]},{"Industry",palette[C.industry]},
      {"Roads",palette[C.road]},{"Rail",palette[C.rail]},{"Water",palette[C.sea]}}
    for i,pair in ipairs(keys) do
      local x,y=14.95+((i-1)%2)*2.47,4.41+math.floor((i-1)/2)*.36
      rect(x,y-.075,.15,.15,pair[2]);label(x+.22,y,pair[1],"#ACCBC9")
    end
    label(14.93,5.61,detail and "PLACES IN THIS AREA" or "QUICK JUMPS","#FFE1A0")
    local y=5.96
    for i,town in ipairs(P.towns) do
      if y>=10.30 then break end
      V.map_sites[i]=town.tile
      button(14.93,y,5.10,.43,"jump_site_"..i,town.name)
      y=y+.48
    end
    if #P.towns==0 then label(14.93,y+.13,"No towns in this view.","#ACCBC9") end
    push("field[14.93,11.15;1.20,.53;map_x;Tile X;]"..
      "field[16.30,11.15;1.20,.53;map_z;Tile Z;]"..
      "field_close_on_enter[map_x;false]field_close_on_enter[map_z;false]")
    button(17.67,11.15,2.36,.53,"map_coordinates","Jump to tile")
    button(14.93,12.22,5.10,.53,"map_return","Return to 3D world","primary")
  end
  return M
end
