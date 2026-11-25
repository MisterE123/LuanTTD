-- Isolated normal-world fixture. Prepare the construction and known phases
-- before the opening checkpoint; all observation and rendering is the
-- real Luanti client plus ordinary worker projection.
local qa={}
local owner="IndustryLayoutsQA"
local function vacant(x,z,h)
  local id=Sim.id(x,z)
  local t=id and S.tiles[id]
  if not t or t.stock_void or t.terrain=="water" or t.build or t.owner or t.house or t.site
      or t.stock_landmark or t.stock_industry or t.wood or (S.stock_farm_fields and S.stock_farm_fields[id]) then return end
  local slope,base=api.terrain.tile(id)
  if slope==0 and (not h or h==base) then return id,base end
end
local board,autoslope_tile
for z=7,Sim.H-12 do
  for x=7,Sim.W-17 do
    local _,h=vacant(x,z)
    if h then
      local ids={}
      for row=0,1 do for col=0,2 do
        ids[#ids+1]=vacant(x+5*col,z+3*row,h) or false
      end end
      for col=0,3 do ids[7+col]=vacant(x+3*col,z+7,h) or false end
      local fit=true
      for _,id in ipairs(ids) do if not id then fit=false;break end end
      -- The two ordinary terraform commands also touch neighboring land.
      if fit then
        for dz=-1,1 do for dx=-1,1 do
          if not vacant(x+9+dx,z+7+dz,h) then fit=false end
        end end
      end
      if fit then
        board={x=x,z=z,h=h,ids=ids}
        break
      end
    end
  end
  if board then break end
end
assert(board,"No contiguous uniform-height roadside QA site")
Sim.company(S,owner)
local Terrain=dofile(mod.."/openttd/terrain.lua")
local Track=dofile(mod.."/openttd/rail_track.lua")
local Cross=dofile(mod.."/level_crossing_world.lua")(Sim,Terrain,
  dofile(mod.."/openttd/level_crossing.lua")(Track),Track)
local TramGrade=dofile(mod.."/openttd/tram_grade_surface.lua")(dofile(mod.."/openttd/road_slope.lua"),
  dofile(mod.."/openttd/slope.lua"))
S.level_crossing_enabled=true
-- Freeze the one visual sample. The ordinary tile loop would otherwise
-- legally transition these intentionally different roadside classes.
S.speed=0
local ctx={vehicles_at=function()return {}end,reserved=function()return false end}
for i,rs in ipairs({"barren","grass","trees"}) do
  local id=board.ids[i]
  local t=S.tiles[id]
  t.build,t.owner,t.road_bits,t.roadside="road",owner,10,"paved"
  local p=assert(Cross.quote(S,owner,id,{kind="rail",track=1},ctx))
  assert(Cross.commit(S,owner,p,ctx))
  assert(t.roadside=="barren")
  t.roadside=rs
  qa[id]={kind="crossing",surface=rs}
  local other=board.ids[i+3]
  local tram=S.tiles[other]
  tram.tram={kind="road",tramtype=1,tram_bits=10,tram_owner=owner}
  tram.roadside=rs
  qa[other]={kind="tram",surface=rs}
end
for i,entry in ipairs({
  {3,"grass","pure_tram_grass_normal_3",3},
  {4,"barren","pure_tram_barren_foundation_12",12},
  {12,"paved","roadside_grade_paved_12_normal",12},
  {5,"grass","stock_crossing_grass_retaining",0},
}) do
  local id=board.ids[i+6]
  local t=S.tiles[id]
  local x,z=Sim.xy(id)
  local plan=assert(Terrain.plan(S.corner_grid,x,z,entry[1],true))
  assert(Terrain.apply(S.corner_grid,plan))
  local grade,h=api.terrain.tile(id)
  assert(grade==entry[1] and h==board.h)
  if i<4 then
    local sampled=assert(TramGrade.surface(grade,h,10,0))
    assert(sampled.grade==entry[4])
    t.tram={kind="road",tramtype=1,tram_bits=10,tram_owner=owner}
    t.roadside=entry[2]
    qa[id]={kind="tram",surface=entry[2],y=sampled.base+1,
      ground=entry[3],overlay="tramway_grade_"..sampled.grade}
  else
    t.build,t.owner,t.road_bits="road",owner,10
    -- Use the live authority's normal crossing quote and construction
    -- clock, not a sloped test bypass or a prefilled crossing record.
    local quote=assert(Sim.crossing_construction_quote(S,owner,id,{kind="rail",track=1}))
    assert(Sim.apply_crossing_construction(S,quote))
    Sim.refresh_crossing_construction(S)
    local c=t.level_crossing
    autoslope_tile=id
    assert(c.foundation=="flattened" and c.top==board.h+1)
    t.roadside=entry[2]
    qa[id]={kind="crossing",surface=entry[2],y=c.top,
      ground=entry[3].."_"..t.variant,overlay="level_crossing_1_"}
  end
end

local begun
local function show()
  local viewer=core.get_player_by_name(owner)
  if not (viewer and authority and authority.status()=="owned" and #world.hotbar_layout(viewer)>0) then
    core.after(.15,show);return
  end
  if begun then return end
  begun=true
  viewer:set_pos({x=2*board.x+10,y=board.h+13,z=2*board.z-10})
  viewer:set_look_horizontal(0);viewer:set_look_vertical(.80)
  local function verify_flat(n)
    local x,z=Sim.xy(autoslope_tile)
    local y=board.h+1
    local a=core.get_node_or_nil({x=2*x,y=y,z=2*z})
    local b=core.get_node_or_nil({x=2*x,y=y+1,z=2*z})
    local state=assert(OwnerCheckpoint.read())
    local t=state.tiles[autoslope_tile]
    if t.level_crossing.slope~=0 or not a or not a.name:match("^luanttd_core:grass%d$")
      or not b or not b.name:match("^luanttd_core:level_crossing_1_") then
      assert(n<65,"The actual worker did not repaint the road–rail deck after autoslope.")
      core.after(.25,function()verify_flat(n+1)end);return
    end
    assert(t.level_crossing.top==y and t.level_crossing.foundation=="none" and t.level_crossing.road_bits==10)
    core.log("action","NATIVE ROADSIDE FRAME crossing-autoslope")
    core.after(1,function()
      core.log("action","PASS NATIVE ROADSIDE GROUNDS: flat and graded crossings, pure tram, and autoslope via live worker")
    end)
  end
  local function raise_corner(id,then_)
    assert(authority.query({kind="terrain_quote",player=owner,request={first=id,operation="raise"}},function(r)
      assert(r.ok and r.value.cost==500,r.why)
      assert(authority.query({kind="command",player=owner,command={
        kind="terrain_commit",revision=r.revision,token=r.value.token,
      }},function(out) assert(out.ok,out.why);then_() end))
    end))
  end
  local function wait(n)
    for id,record in pairs(qa) do
      local x,z=Sim.xy(id)
      local y=record.y or board.h
      local ground=core.get_node_or_nil({x=2*x,y=y,z=2*z})
      local a=ground and ground.name
      local f=core.get_node_or_nil({x=2*x,y=y+1,z=2*z})
      local mesh=f and f.name
      local expected=record.kind=="crossing" and ("luanttd_core:stock_crossing_"..(record.surface=="trees" and "paved" or record.surface))
        or ("luanttd_core:pure_tram_"..record.surface)
      local matching=(record.surface=="grass" and record.kind=="crossing" and a and a:match("^luanttd_core:grass%d$"))
        or (record.surface=="trees" and record.kind=="tram" and a and a:find("town_street",1,true)) or a==expected
      if record.ground then matching=a=="luanttd_core:"..record.ground end
      local overlay=record.overlay or (record.kind=="crossing" and "level_crossing_1_" or "tramway_10")
      if not (matching and mesh and mesh:find("luanttd_core:"..overlay,1,true)==1) then
        assert(n<65,record.kind.." "..record.surface..": "..tostring(a).." / "..tostring(mesh))
        core.after(.25,function()wait(n+1)end)
        return
      end
    end
    core.after(1.4,function()
      core.log("action","NATIVE ROADSIDE FRAME roadside-crossing-ground")
      core.after(2,function()
        local x,z=Sim.xy(autoslope_tile)
        raise_corner(autoslope_tile,function()
          raise_corner(Sim.id(x+1,z+1),function() verify_flat(1) end)
        end)
      end)
    end)
  end
  core.after(.4,function()wait(1)end)
end
core.after(.2,show)
