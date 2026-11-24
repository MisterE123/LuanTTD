-- Pack an already-selected stock YAPF leg into OpenTTD position/rotation
-- frames. This is not yet the stock clock, occupancy or per-junction driver.
local source=debug and debug.getinfo(1,"S").source
local base=source and source:match("^@(.*/)road_motion_leg%.lua$")
base=base or (core and core.get_modpath("luanttd_core").."/") or "mods/luanttd_core/"
local Bridge=dofile(base.."road_bridge_motion.lua")
return function(Motion,F,board)
  local M={}
  local SIDE=1 -- right-hand traffic, consistent with the current campaign art
  local function station_state(t,td,bay)
    if t.kind=="bay_stop" then
      -- RVSB_USING_SECOND_BAY is bit 1. Cardinal straight entrances
      -- are stock trackdirs 0, 1, 8 and 9.
      return 32+td+(bay or 0)*2
    end
    if t.kind=="drive_stop" and not t.waypoint then return 64+td end
    return td
  end
  local function stop_frame(tile,state)
    if tile.kind=="bay_stop" then return Motion.bay_stop_frame(state,SIDE) end
    if tile.kind=="drive_stop" then return Motion.DRIVE_THROUGH_STOP end
  end
  local last_frame={}
  local function projection(td,state,frame)
    local leaving=F.exit_direction(td)
    local entering=F.exit_direction(F.reverse_trackdir(td))
    if not leaving or not entering then return .5 end
    local a,b=1-entering%2,1-leaving%2
    if a==b then return a end
    if not last_frame[state] then
      local f=0
      while Motion.sample(state,SIDE,f+1)=="position" do f=f+1 end
      last_frame[state]=math.max(1,f)
    end
    local f=math.max(0,math.min(1,(frame/last_frame[state]-.23)/.54))
    return a+(b-a)*f*f*(3-2*f)
  end
  function M.compile(trace,origin,options)
    if #trace<2 then return end
    options=options or {}
    local first=trace[1]
    local tile=board.tile(first.tile)
    if not tile then return end
    local state=station_state(tile,first.td)
    local v={direction=2*F.exit_direction(first.td)+1}
    local frame
    if origin then
      if tile.kind~="road" or origin[4]~=first.tile or origin[6]~=first.td or
          origin[10] or origin[12] or origin[13] or origin[14] then return end
      frame,v.direction=origin[15],origin[3]
    elseif tile.kind=="depot" then
      frame=Motion.DEPOT_START
    elseif tile.kind=="bay_stop" then
      -- The path starts after departure, whereas the vehicle is still at
      -- the bay's stop frame. The bay data itself includes the turnaround.
      state=station_state(tile,F.direction_trackdir(F.reverse_direction(tile.dir)),options.departure_bay)
      frame=stop_frame(tile,state)
    else
      frame=stop_frame(tile,state)
    end
    if not frame then return end
    local qx,qy=board.xy(first.tile)
    local kind,x,y=Motion.sample(state,SIDE,frame)
    if kind~="position" then return end
    v.x,v.y,v.state,v.frame=qx*16+x,qy*16+y,state,frame
    if origin and (v.x~=origin[1] or v.y~=origin[2]) then return end
    if tile.kind=="bay_stop" then
      -- Recover the heading from the same table stream before this frame.
      -- A stopped vehicle on a bay curve may face a different direction.
      local in_td=F.direction_trackdir(F.reverse_direction(tile.dir))
      local _,ix,iy=Motion.sample(state,SIDE,0)
      local tmp={direction=2*F.exit_direction(in_td)+1,x=qx*16+ix,y=qy*16+iy,state=state,frame=0}
      for _=1,128 do
        if tmp.frame==frame then break end
        local k,px,py,d,f=Motion.step(tmp,SIDE)
        if k~="move" and k~="rotate" then return end
        tmp.x,tmp.y,tmp.direction,tmp.frame=px,py,d,f
      end
      if tmp.frame~=frame then return end
      v.direction=tmp.direction
    end
    local frames,part={},1
    local extra=0
    for _,piece in ipairs(trace) do
      local t=board.tile(piece.tile)
      if not t then return end
      if t.kind=="bridge" or t.kind=="tunnel" then extra=extra+16*t.skip end
    end
    local physical_tile
    local function append(check_x,check_y,entered)
      local p=trace[part]
      local tile=board.tile(p.tile)
      local bridge=tile.kind=="bridge" and tile or nil
      local wormhole=v.state==Bridge.WORMHOLE
      frames[#frames+1]={v.x,v.y,v.direction,physical_tile or p.tile,projection(p.td,v.state,v.frame),
        v.state,check_x,check_y,entered,
        bridge and bridge.span,bridge and bridge.bridge_speed*2,wormhole and true or nil,
        tile.kind=="tunnel" and wormhole or nil,tile.tunnel,v.frame}
    end
    append()
    for _=1,#trace*96+extra do
      local part_tile=board.tile(trace[part].tile)
      local final_station=v.frame==stop_frame(part_tile,v.state)
      local depot_entry=options.depot and part_tile.kind=="depot" and
        v.state==F.direction_trackdir(F.reverse_direction(part_tile.dir)) and v.frame==Motion.DEPOT_STOP
      if part==#trace and (final_station or depot_entry) then
        return frames
      end
      local check_x,check_y,entered
      local outgoing=trace[part+1]
      if part_tile.kind=="depot" and outgoing and outgoing.tile==trace[part].tile and
          v.state==F.direction_trackdir(F.reverse_direction(part_tile.dir)) and v.frame==Motion.DEPOT_STOP then
        -- RC1 VehicleEnterTile_Road hides an inward head at frame 11,
        -- regardless of whether this depot was an explicit order. The
        -- next tick uses RoadVehLeaveDepot's outward lane and frame 6.
        local td=F.direction_trackdir(part_tile.dir)
        if outgoing.td~=td then return end
        frames[#frames][16]=true
        local x,y=board.xy(outgoing.tile)
        local kind,px,py=Motion.sample(td,SIDE,Motion.DEPOT_START)
        if kind~="position" then return end
        v.x,v.y,v.direction,v.state,v.frame=x*16+px,y*16+py,part_tile.dir*2+1,td,Motion.DEPOT_START
        part=part+1
      elseif v.state==Bridge.WORMHOLE then
        local k,px,py,target,exit_frame=Bridge.step(board,part_tile,v)
        if not k then return end
        v.x,v.y=px,py
        physical_tile=target
        if k=="exit" then
          local next_piece=trace[part+1]
          local straight=F.direction_trackdir(part_tile.dir)
          if not next_piece or next_piece.tile~=target or next_piece.td~=straight then return end
          v.state,v.frame=straight,exit_frame or Motion.DEFAULT_START
          entered=true
          part=part+1
          physical_tile=nil
        end
      else
        local k,px,py,d,f=Motion.step(v,SIDE)
        if k=="move" or k=="rotate" then
          if k=="rotate" then
            local _,rx,ry=Motion.sample(v.state,SIDE,v.frame+1)
            check_x,check_y=v.x-v.x%16+rx,v.y-v.y%16+ry
          end
          v.x,v.y,v.direction,v.frame=px,py,d,f
          if k=="move" and (part_tile.kind=="bridge" or part_tile.kind=="tunnel") and Bridge.enters(part_tile,d,px,py) then
            v.state=Bridge.WORMHOLE
            physical_tile=trace[part].tile
          end
        elseif k=="next_tile" or k=="turned" then
          local next_piece=trace[part+1]
          if not next_piece then return end
          local here=trace[part].tile
          local reverses=k=="next_tile" and next_piece.tile==here
          local target,next_state,start
          if reverses then
            -- RC1 RoadVehController: when the road ahead is a dead end,
            -- run the RvRev row on this tile. Do not consume the YAPF
            -- reversal edge until its RDE_TURNED sample. Turning while
            -- leaving an occupied stop or signed normal road must wait.
            if part_tile.kind~="road" or (part_tile.disallowed or 0)~=0 then return end
            target,next_state,start=here,Motion.reversing_state(px),Motion.DEFAULT_START
            if not next_state then return end
          else
            target=k=="turned" and here or board.adjacent(here,px)
            if target~=next_piece.tile then return end
            next_state=station_state(board.tile(target),next_piece.td,
              part+1==#trace and options.arrival_bay or nil)
            start=k=="turned" and Motion.TURN_AROUND_START or Motion.DEFAULT_START
          end
          local tx,ty=board.xy(target)
          local event
          event,v.x,v.y,v.direction,v.frame=Motion.enter(v,tx,ty,next_state,SIDE,start)
          if not event then return end
          v.state=next_state
          if not reverses then
            part=part+1
            entered=true
          end
        else
          return
        end
      end
      append(check_x,check_y,entered)
    end
  end
  return M
end
