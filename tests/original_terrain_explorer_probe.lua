-- Native fixture bootstrap, copied to a disposable bayline-only world.
local path=core.get_modpath(core.get_current_modname())
local mode=dofile(path.."/original_terrain_explorer.lua")
local storage=core.get_mod_storage()
local E=assert(mode.start(core,path,storage))
local world=E.world
local restart=core.settings:get_bool("bayline_explorer_probe_restart",false)
local bounds=world.stats()
local w,h=bounds.width,bounds.depth
local full=w==64 and h==64 and bounds.seed==1751
local first_x,flight_z=full and 13 or w/2-3,full and 33 or h/2+1
local seams=full and {16,24} or {w/2,w/2+8}
local regions=full and {{1,1,64,64}} or {
  {2,2,9,9},{first_x-1,flight_z-3,seams[2]+4,flight_z+5},{w-9,h-9,w-2,h-2},
}
local pending,joined=false,false
local function verify()
  local counts={}
  local scanned=0
  for _,r in ipairs(regions) do for z=r[2],r[4] do for x=r[1],r[3] do
    local t=world.tile(x,z)
    local name=core.get_node({x=2*x,y=t.base+1,z=2*z}).name
    local v=(x*17+z*11+x*z*3)%4
    local expected=t.class==7 and "air" or
      ("bayline:original_%s_%d_%d"):format(t.class==6 and "coast" or "land",t.mask,v)
    assert(name==expected,("native anchor %d, %d is %s not %s"):format(x,z,name,expected))
    local kind=t.class+16*t.ground
    counts[kind]=(counts[kind] or 0)+1
    scanned=scanned+1
  end end end
  if full then assert(counts[7]==252 and counts[22]==1292 and counts[38]==306 and counts[0]==2246) end
  local read=dofile(path.."/terrain_stream.lua")(dofile(path.."/openttd/slope.lua"))
  for _,x in ipairs(seams) do
    local left=world.view({size=8,capacity=1}).update(x,flight_z,0,1).chunks[1]
    local right=world.view({size=8,capacity=1}).update(x+1,flight_z,0,1).chunks[1]
    assert(left.x+left.width==right.x and left.id+1==right.id)
    for z=flight_z,flight_z+7 do
      assert(read.corner(left,x+1,z)==read.corner(right,x+1,z))
      for _,v in ipairs{0,.25,.5,.75,1} do
        assert(read.height(left,x,z,1,v)==read.height(right,x+1,z,0,v))
      end
    end
  end
  local s=E.stats()
  assert(s.cache<=1)
  if restart then assert(s.mapblocks==0)
  elseif full then assert(s.max_chunks_per_block==4 and s.mapblocks>70)
  else assert(s.max_chunks_per_block<=4 and s.mapblocks>0 and s.mapblocks<10000) end
  assert(core.is_protected({x=2,y=1,z=2},"SurveyQA"))
  assert(not core.registered_chatcommands.build and not core.registered_chatcommands.purchase)
  assert(storage:get_string("campaign")=="")
  core.log("action",("ORIGINAL TERRAIN GEOGRAPHY EXACT size=%dx%d anchors=%d shore=%d sea=%d mapblocks=%d max-source-chunks=%d"):format(
    w,h,scanned,counts[38] or 0,counts[22] or 0,s.mapblocks,s.max_chunks_per_block))
  if restart then
    core.log("action","ORIGINAL TERRAIN SQLITE RESTART SAME "..scanned.." TILES")
    core.request_shutdown("Original terrain SQLite replay finished",false,0)
  end
  pending=true
  if joined then core.log("action","ORIGINAL TERRAIN COAST READY") end
end
core.register_on_mods_loaded(function()
  -- The old small QA fixture checks every native anchor. For wider maps
  -- request three disjoint areas; don't manufacture a full native map.
  core.after(0,function()
    local active=#regions
    for _,r in ipairs(regions) do
      local a=full and {x=0,y=-2,z=0} or {x=2*r[1],y=-2,z=2*r[2]}
      local b=full and {x=129,y=16,z=129} or {x=2*r[3]+1,y=16,z=2*r[4]+1}
      core.emerge_area(a,b,function(_,action,left)
        assert(action~=core.EMERGE_CANCELLED and action~=core.EMERGE_ERRORED)
        if left==0 then
          active=active-1
          if active==0 then core.after(0,verify) end
        end
      end)
    end
  end)
end)
core.register_on_joinplayer(function()
  joined=true
  if pending then core.log("action","ORIGINAL TERRAIN COAST READY") end
end)
local watching,last,remaining
core.register_chatcommand("explorer_probe",{func=function(name)
  local p=assert(core.get_player_by_name(name))
  local pos=p:get_pos()
  last=math.floor((pos.x+.5)/2)
  assert(last==first_x and math.floor((pos.z+.5)/2)==flight_z)
  watching=name
  remaining={[seams[1]+1]=true,[seams[2]+1]=true}
  core.log("action","ORIGINAL TERRAIN FLIGHT ARMED")
  return true
end})
core.register_globalstep(function()
  if not watching then return end
  local player=core.get_player_by_name(watching)
  if not player then return end
  local pos=player:get_pos()
  local x=math.floor((pos.x+.5)/2)
  for _,limit in ipairs{seams[1]+1,seams[2]+1} do
    if remaining[limit] and last<limit and x>=limit then
      assert(math.floor((pos.z+.5)/2)==flight_z)
      remaining[limit]=nil
      core.log("action","ORIGINAL TERRAIN PLAYER CROSSED SEAM "..limit)
    end
  end
  last=x
end)
