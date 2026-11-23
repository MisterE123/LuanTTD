-- Native presentation for two independently dispatched rail consists.
-- All motion and the decision to show a signal aspect are controller-owned.
local M={}
function M.create(api,Run,Track,Pose,SignalArt,seconds_per_day,surface,span_wire,signal_pixel,verified_art)
  local V={}
  local Sim,S=api.Sim,api.s
  local refs,signs={},{}
  local function entity(name,mesh,atlas,size)
    core.register_entity("luanttd_core:"..name,{initial_properties={physical=false,pointable=false,
      collide_with_objects=false,static_save=false,visual="mesh",mesh=mesh,textures={atlas},
      shaded=true,backface_culling=true,visual_size=size}})
  end
  local path=core.get_modpath and core.get_modpath("luanttd_core")
  local Art=dofile((path or "mods/luanttd_core").."/rail_dispatch_manifest.lua")
  local art=verified_art or Art.scan(path,S.stock_electrification,span_wire~=nil)
  local models,stock_kind=Art.models,Art.stock_kind
  local function diagonal(id,td,p)
    if api.render and api.render.rail_diagonal_pose then return api.render.rail_diagonal_pose(id,td,p) end
  end
  local fit_couplings=path and Track.entry_side and
    dofile(path.."/rail_body_spacing.lua")(Sim,Track,diagonal,Pose.sample)
  local ready,split_ready,collector=art.ready,art.split
  for kind,d in pairs(models) do
    if ready[kind] then entity("dispatch_"..kind,d.mesh,d.atlas,d.size) end
    if split_ready[kind] then
      local body=d.mesh:gsub("%.obj$","_body.obj")
      local mast="bl_rail_sh_collector.obj"
      entity("dispatch_"..kind.."_body",body,d.atlas,d.size)
      -- Both locomotive atlases qualify the shared collector UVs.
      entity("dispatch_"..kind.."_collector",mast,d.atlas,d.size)
    end
  end
  if next(split_ready) then collector=dofile(path.."/rail_pantograph.lua") end
  function V.split_electric_ready() return split_ready.sh_30==true and split_ready.sh_40==true end
  function V.goods_wagon_ready() return ready.goods_van==true end
  function V.oil_wagon_ready() return ready.oil_tanker==true end
  for _,variant in ipairs({"light","semaphore"}) do
    for _,aspect in ipairs({"green","red"}) do
      entity("dispatch_signal_"..variant.."_"..aspect,SignalArt.mesh(variant,aspect=="green"),
        SignalArt.atlas,{x=.65,y=.65,z=.65})
    end
  end
  local function forget(collection,key)
    local saved=collection[key]
    if saved and saved.ref and saved.ref:get_pos() then saved.ref:remove() end
    collection[key]=nil
  end
  local function pose(collection,key,name,pos,rotation,extension,flip_epoch)
    local saved=collection[key]
    if saved and saved.name~=name then forget(collection,key);saved=nil end
    if not saved or not saved.ref or not saved.ref:get_pos() then
      saved={ref=core.add_entity(pos,"luanttd_core:"..name),name=name}
      collection[key]=saved
    end
    if saved.ref then
      -- The stock flip changes ends immediately; interpolating those old
      -- and new slots makes the locomotive and coach slide through one another.
      if saved.flip_epoch~=nil and saved.flip_epoch~=flip_epoch then saved.ref:set_pos(pos)
      else saved.ref:move_to(pos,true) end
      saved.flip_epoch=flip_epoch
      saved.ref:set_rotation(rotation)
      if extension and (not saved.extension or math.abs(extension-saved.extension)>.002) then
        saved.ref:set_properties({visual_size={x=1,y=extension,z=1}})
        saved.extension=extension
      end
      return saved.ref
    end
  end
  local function board_base(id)
    local b=S.tiles[id].h
    if api.terrain then local _,height=api.terrain.tile(id);b=height end
    return b
  end
  local function vacuum(collection,keep)
    for k in pairs(collection) do if not keep[k] then forget(collection,k) end end
  end
  function V.step(dt,online,fraction)
    if not online then vacuum(refs,{});vacuum(signs,{});return end
    local dispatch=Run.current(S)
    local show_parts,show_signs={},{}
    if dispatch then
      local commercial=dispatch.runs[1] and dispatch.runs[1].paid_clock
      if commercial and V.observe then V.observe(Sim.rail_paid_motion_events(S)) end
      local coal=Sim.rail_coal_status and Sim.rail_coal_status(S)
      for _,train in ipairs(dispatch.runs) do
        local engine=stock_kind[train.stock_engine] or "locomotive"
        local wagon="wagon"
        if train.stock_engine==11 and not train.stock_wagon then wagon="manley"
        elseif train.stock_wagon==29 then
          wagon=coal and (coal.onboard or 0)>0 and "coal_loaded" or "coal_empty"
        elseif train.stock_wagon==32 then
          wagon="goods_van" -- sealed stock body, original image 38 has no full-adder.
        elseif train.stock_wagon==30 then
          -- Stock image 36 has a zero full-adder. The sealed vessel
          -- never changes mesh when loading or unloading.
          wagon="oil_tanker"
        end
        local parts=train.consist.parts
        local push_pull=train.stock_engine==11 and #parts>1
        local samples={}
        for i,_ in ipairs(parts) do
          local id,td,progress,reversed,wormhole
          if train.paid_clock then id,td,progress,reversed,wormhole=Sim.rail_paid_pose(S,i,fraction,train.fleet_id)
          else id,td,progress,wormhole=Run.sample(train,i);reversed=train.consist.reversed end
          if id then samples[i]={id=id,td=td,progress=progress,reversed=reversed,wormhole=wormhole} end
        end
        if fit_couplings then samples=fit_couplings(samples,parts,push_pull) or samples end
        for i=1,#parts do
          local sample=samples[i]
          if sample and ready[engine] and ready[wagon] then
            local id,td,progress,reversed,wormhole=sample.id,sample.td,sample.progress,sample.reversed,sample.wormhole
            -- OpenTTD 16.0-RC1 ReverseTrainDirection:
            -- default single-ended trains swap positions *and* turn.
            -- A rear driving cab leads in the opposite direction without
            -- reorienting the bodies. Keep those cab identities on their
            -- physical ends when consuming the travel-ordered samples.
            local backing=push_pull and reversed==true
            local body_index=backing and #parts-i+1 or i
            local rear_cab=push_pull and body_index==#parts
            local kind=(body_index==1 or rear_cab) and engine or wagon
            local key=train.id..":"..body_index
            local flip_epoch
            if not push_pull then flip_epoch=reversed==true end
            local tx,tz=Sim.xy(id)
            local x,z,dx,dz
            if sample.x then x,z,dx,dz=sample.x-2*tx,sample.z-2*tz,sample.dx,sample.dz
            elseif not wormhole then x,z,dx,dz=diagonal(id,td,progress) end
            if x==nil then x,z,dx,dz=Pose.sample(td,progress) end
            local level,tilt
            if surface then level,tilt=surface(id,td,progress,{wormhole=wormhole}) end
            local flipped=rear_cab~=backing
            local body={x=2*tx+.5+x,y=(level or board_base(id))+models[kind].offset,z=2*tz+.5+z}
            local rotation={x=(tilt or 0)*(flipped and 1 or -1),
              y=math.pi-math.atan2(dx,dz)+(flipped and math.pi or 0),z=0}
            local visible=not api.interest or api.interest.near(body,refs[key]~=nil)
            local ref
            if visible and i==1 and train.bridge_collectors and split_ready[kind] then
              local rows,axis,side=span_wire(S,id,td,wormhole)
              local move=rows and collector.mount(rows,axis,side,body,rotation,vector.rotate,.03,.45)
              local heel=move and move.heel or vector.add(body,vector.rotate(collector.heel,rotation))
              -- If an optional visual contact is missing, don't hover
              -- above the rail or move the authoritative vehicle.
              local scale=move and move.scale_y or (rows and .03/collector.nominal_extension or 1)
              ref=pose(refs,key,"dispatch_"..kind.."_body",body,rotation,nil,flip_epoch)
              pose(refs,key..":collector","dispatch_"..kind.."_collector",heel,rotation,scale,flip_epoch)
              show_parts[key..":collector"]=true
              if V.observe_collector then V.observe_collector(train,id,move,rows,scale,td) end
            elseif visible then
              ref=pose(refs,key,"dispatch_"..kind,body,rotation,nil,flip_epoch)
            end
            if api.vehicle_ui and train.fleet_id then api.vehicle_ui.track("rail",train.fleet_id,body,ref,i==1) end
            if visible then show_parts[key]=true end
          end
        end
      end
      local function visible(id)
        local x,z=Sim.xy(id)
        for _,p in ipairs(core.get_connected_players()) do
          local a=p:get_pos()
          if a and (a.x-2*x)^2+(a.z-2*z)^2<96^2 then return true end
        end
      end
      for id,r in pairs(dispatch.signals.records) do
        if visible(id) then
          local tx,tz=Sim.xy(id)
          for _,td in ipairs({0,1,2,3,4,5,8,9,10,11,12,13}) do
            local signal=Track.signal_along(td)
            local mask=S.tiles[id].rail_tracks or 0
            if Track.has(mask,Track.track(td)) and Track.intersect(r.present_signals,signal)~=0 then
              local secondary=Track.track(td)==3 or Track.track(td)==5
              local variant=secondary and r.lower_variant or r.upper_variant
              local model=variant==1 and "semaphore" or "light"
              local green=Track.intersect(r.green_signals,signal)~=0
              -- Sample the exact rendered rail foundation at the mast.
              local u,v=SignalArt.world_anchor(td,false,mask)
              if u~=nil then
                local pixel=signal_pixel and signal_pixel(id,u,v)
                local y=(pixel and pixel/8 or board_base(id))+.5
                local position,rotation=SignalArt.pose(tx,tz,y,td,false,mask)
                local key=id..":"..td
                pose(signs,key,"dispatch_signal_"..model.."_"..(green and "green" or "red"),position,rotation)
                show_signs[key]=true
              end
            end
          end
        end
      end
    end
    vacuum(refs,show_parts);vacuum(signs,show_signs)
  end
  return V
end
return M
