-- A render-only, private outline of the logical 2x2 Luanti tile.
-- No map nodes, queues or simulation state are changed.
return function(api)
  local X={}
  local Sim,S=api.Sim,api.s
  local source=debug and debug.getinfo(1,"S").source
  local base=source and source:match("^@(.*/)tile_selector%.lua$")
  base=base or (core.get_modpath("luanttd_core").."/")
  local slopes=api.slope or dofile(base.."openttd/slope.lua")
  local rail_preview=api.trackworks and api.terrain and dofile(base.."rail_preview.lua")(api,base)
  local state_by_player={}
  local entity_name="luanttd_core:tile_selector"
  local rail_entity="luanttd_core:rail_selector"
  local textures={inspect="bl_selector_inspect.png",valid="bl_selector_valid.png",
    invalid="bl_selector_invalid.png",anchor="bl_selector_anchor.png"}

  core.register_entity(entity_name,{
    initial_properties={visual="mesh",mesh="bl_selector_0.obj",textures={textures.inspect},
      physical=false,pointable=false,collide_with_objects=false,static_save=false,
      backface_culling=false,glow=14,shaded=false},
    on_activate=function(self,name)
      -- Install the observer set before Luanti's first visibility update.
      if name=="" or not core.get_player_by_name(name) then self.object:remove();return end
      self.object:set_observers({[name]=true})
    end,
  })

  core.register_entity(rail_entity,{
    initial_properties={visual="mesh",mesh="bl_rail_track_1.obj",
      textures={"bl_rail_atlas.png^[colorize:#53f0c8:138^[opacity:222"},
      -- Node meshes are authored in tile units; entities normally load
      -- OBJ dimensions at one tenth of that scale.
      visual_size={x=10,y=10,z=10},use_texture_alpha=true,
      physical=false,pointable=false,collide_with_objects=false,static_save=false,glow=9,shaded=false},
    on_activate=function(self,name)
      if name=="" or not core.get_player_by_name(name) then self.object:remove();return end
      self.object:set_observers({[name]=true})
    end,
  })

  local arrow_name="luanttd_core:signal_approach_arrow"
  core.register_entity(arrow_name,{
    initial_properties={visual="mesh",mesh="bl_signal_approach_arrow.obj",
      textures={textures.valid},visual_size={x=10,y=10,z=10},
      physical=false,pointable=false,collide_with_objects=false,static_save=false,
      backface_culling=false,glow=14,shaded=false},
    on_activate=function(self,name)
      if name=="" or not core.get_player_by_name(name) then self.object:remove();return end
      self.object:set_observers({[name]=true})
    end,
  })

  local function pose(id)
    local tile=S.tiles[id]
    if not tile then return nil end
    local x,z=Sim.xy(id)
    local h,mask=(tile.h or 0)+.5,0
    local render=api.render
    if render and render.surface and (not render.uses_slope or render.uses_slope(id)) then
      local xl,xh,zl,zh=2*x-.5,2*x+1.5,2*z-.5,2*z+1.5
      local n,w,e,s=render.surface(id,xl,zl),render.surface(id,xh,zl),
                    render.surface(id,xl,zh),render.surface(id,xh,zh)
      if n and w and e and s then
        local bottom=math.min(n,w,e,s)
        local function level(y) return math.floor(y-bottom+.5) end
        local nn,ww,ee,ss=level(n),level(w),level(e),level(s)
        if math.abs(n-bottom-nn)<1e-6 and math.abs(w-bottom-ww)<1e-6 and
           math.abs(e-bottom-ee)<1e-6 and math.abs(s-bottom-ss)<1e-6 and
           slopes.valid(nn,ww,ee,ss) then
          mask,h=(slopes.classify(nn,ww,ee,ss)),bottom
        end
      end
    end
    return {x=2*x+.5,y=h,z=2*z+.5},mask
  end

  local function remove(entry)
    if entry and entry.object and entry.object:get_pos() then entry.object:remove() end
  end

  local function draw(name,bucket,key,id,state,lift)
    local prev=bucket[key]
    local pos,mask=pose(id)
    if not pos or not textures[state] then
      remove(prev);bucket[key]=nil;return
    end
    pos.y=pos.y+lift
    if not prev or not prev.object:get_pos() then
      local ref=core.add_entity(pos,entity_name,name)
      if not ref or not ref:get_pos() then return end
      prev={object=ref};bucket[key]=prev
    end
    if prev.mask~=mask or prev.state~=state then
      prev.object:set_properties({mesh="bl_selector_"..mask..".obj",textures={textures[state]}})
      prev.mask,prev.state=mask,state
    end
    if prev.id~=id or prev.height~=pos.y then
      prev.object:set_pos(pos)
      prev.id,prev.height=id,pos.y
    end
  end

  local function state_for(player)
    local name=player:get_player_name()
    if not state_by_player[name] then state_by_player[name]={} end
    return name,state_by_player[name]
  end

  function X.signal(player,id,dir)
    local name,bucket=state_for(player)
    local item=bucket.signal
    if not id or dir==nil then remove(item);bucket.signal=nil;return end
    if item and item.id==id and item.dir==dir and item.object:get_pos() then return end
    local x,z=Sim.xy(id)
    local shape,base=api.terrain.tile(id)
    local grade,level=api.trackworks.surface(shape,base,S.tiles[id].rail_tracks)
    if not grade then remove(item);bucket.signal=nil;return end
    local pos={x=2*x+.5,y=level+(grade==0 and .78 or 1.20),z=2*z+.5}
    if not item or not item.object:get_pos() then
      local object=core.add_entity(pos,arrow_name,name)
      if not object then return end
      item={object=object}
      bucket.signal=item
    end
    item.object:set_pos(pos)
    item.object:set_rotation({x=0,y=({[0]=-math.pi/2,[1]=0,[2]=math.pi/2,[3]=math.pi})[dir],z=0})
    item.id,item.dir=id,dir
  end

  function X.show(player,id,state)
    state=state or "inspect"
    local name,bucket=state_for(player)
    local anchor=state=="anchor"
    draw(name,bucket,anchor and "anchor" or "cursor",id,state,anchor and .036 or .057)
  end

  function X.area(player,ids,cursor,anchor,state)
    local name,bucket=state_for(player)
    local area=bucket.area
    if not area and (not ids or #ids<=1) then return end
    area=area or {};bucket.area=area
    local keep={}
    if ids then
      -- Bound per-player entities for huge level/canal drags, without
      -- clipping ordinary stations, infrastructure and airfield footprints.
      local stride=math.max(1,math.ceil(#ids/48))
      for i=1,#ids,stride do
        local id=ids[i]
        if id~=cursor and id~=anchor and not keep[id] then
          draw(name,area,id,id,state,.043)
          keep[id]=true
        end
      end
    end
    for id,entry in pairs(area) do
      if not keep[id] then remove(entry);area[id]=nil end
    end
  end

  function X.rail(player,pieces)
    local name,bucket=state_for(player)
    if not pieces and not bucket.rail then return end
    local rail=bucket.rail or {};bucket.rail=rail
    local keep={}
    if pieces and rail_preview then
      for _,record in ipairs(rail_preview(pieces,name,player:get_pos())) do
        local id,mesh,pos=record.id,record.mesh,record.pos
        local p=rail[id]
        if not p or not p.object:get_pos() then
          local object=core.add_entity(pos,rail_entity,name)
          if object and object:get_pos() then p={object=object,y=pos.y};rail[id]=p end
        end
        if p then
          if p.mesh~=mesh then p.object:set_properties({mesh=mesh});p.mesh=mesh end
          if p.y~=pos.y then p.object:set_pos(pos);p.y=pos.y end
          keep[id]=true
        end
      end
    end
    for id,p in pairs(rail) do if not keep[id] then remove(p);rail[id]=nil end end
  end

  function X.leave(name)
    local bucket=state_by_player[name]
    if not bucket then return end
    remove(bucket.cursor);remove(bucket.signal);remove(bucket.anchor)
    for _,entry in pairs(bucket.area or {}) do remove(entry) end
    for _,entry in pairs(bucket.rail or {}) do remove(entry) end
    state_by_player[name]=nil
  end
  return X
end
