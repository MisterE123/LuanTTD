-- Invoked only in the disposable native game fixture. Both painters use
-- the original real renderer, assets and VoxelManip backend.
core.after(0,function()
  local T=dofile(mod.."/openttd/terrain.lua")
  local P=dofile(mod.."/campaign_terrain_projection.lua")
  Sim.W,Sim.H=128,128
  local peak=tonumber(core.settings:get("luanttd_qa_paint_peak")) or 54
  local map={tiles={},companies={},news={},day=0,topology=0,corner_grid=T.new(Sim.W,Sim.H,function(x,z)
    if x>=35 then return math.min(peak,1+x-34) end
    return (x>12 and z>=15) and 2 or 1
  end)}
  for z=1,Sim.H do for x=1,Sim.W do
    local id=Sim.id(x,z)
    local _,h=T.tile(map.corner_grid,x,z)
    map.tiles[id]={h=h,variant=(x+z)%4,terrain="grass"}
    if x>=13 and x<=28 and z==20 then
      map.tiles[id].build="road";map.tiles[id].road_bits=10
    elseif x>=13 and x<=28 and z==24 then
      map.tiles[id].build="stock_rail";map.tiles[id].rail_tracks=1
    elseif (x+z*3)%17==0 and x<33 and z~=27 then
      map.tiles[id].wood=true
    end
  end end
  map.road_economy=true
  Sim.company(map,"Tester")
  assert(Sim.road_bridge(map,"Tester",Sim.id(18,27),Sim.id(22,27),0))
  local heights,receipts={},{}
  local function window(x,z,w,h)
    local rows={}
    for zz=z,z+h-1 do for xx=x,x+w-1 do
      local id=Sim.id(xx,zz)
      local slope,level,top=T.tile(map.corner_grid,xx,zz)
      local row={id=id,top=top,level=level,slope=slope,surface=P.tile(map.tiles[id])}
      rows[#rows+1]=row;heights[id]=row
    end end
    receipts[#receipts+1]={revision=1,value={x=x,z=z,width=w,height=h,tiles=rows,
      corners=P.corners(T,map.corner_grid,x,z,w,h),registries=P.registries(map,rows)}}
  end
  window(1,1,32,32);window(89,1,32,32)
  render.use_worker_projection({
    windows=function() return receipts end,
    terrain=function(x,z)return heights[Sim.id(x,z)] end,
  })
  local low,high={x=2,y=-1,z=2},{x=65,y=render.max_target_level(),z=65}
  assert(high.y>=peak+3)
  local stale_y=math.min(high.y,44)
  local function snapshot()
    local vm,a,b=core.get_voxel_manip(low,high)
    if not a then a,b=vm:get_emerged_area() end
    return vm:get_data(),vm:get_param2_data(),VoxelArea:new({MinEdge=a,MaxEdge=b})
  end
  local function repaint(p,inject)
    if inject then
      -- Old tall scenery and stale facedir must still be removed, even
      -- well above the current tile ceiling. This node is disposable.
      core.swap_node({x=7,y=stale_y,z=9},{name="luanttd_core:grass0",param2=3})
      core.swap_node({x=8,y=stale_y,z=9},{name="air",param2=13})
    end
    local t=core.get_us_time()
    local vm,a,b=core.get_voxel_manip(low,high)
    if not a then a,b=vm:get_emerged_area() end
    p(vm,a,b,low,high,false)
    return (core.get_us_time()-t)/1000
  end
  core.emerge_area(low,high,function(_,action,left)
    assert(action~=core.EMERGE_CANCELLED and action~=core.EMERGE_ERRORED)
    if left~=0 then return end
    core.after(0,function()
      local old,new=render.qa_baseline,render.qa_paint
      repaint(old,true)
      local g1,p1,area=snapshot()
      repaint(new,true)
      local g2,p2=snapshot()
      local n=0
      for i in area:iter(low.x,low.y,low.z,high.x,high.y,high.z) do
        assert(g1[i]==g2[i] and p1[i]==p2[i],"Different node or param2 at "..i)
        n=n+1
      end
      local function median(t) table.sort(t);return t[math.floor((#t+1)/2)] end
      for _,mode in ipairs({"unchanged","stale"}) do
        local a,b={},{}
        local dirty=mode=="stale"
        for i=1,7 do
          if i%2==1 then a[i]=repaint(old,dirty);b[i]=repaint(new,dirty)
          else b[i]=repaint(new,dirty);a[i]=repaint(old,dirty) end
        end
        core.log("action",("NATIVE PAINT BENCH %s %.3f -> %.3f ms %d identical voxels"):format(mode,median(a),median(b),n))
      end
      core.request_shutdown("Native paint parity and benchmark passed",false,0)
    end)
  end)
end)
