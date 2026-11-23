-- Fixed vehicle art mapping at actual paid dispatcher presentation layer.
local View=dofile("mods/luanttd_core/rail_dispatch_view.lua")
local WAGON="luanttd_core:dispatch_oil_tanker"
local function fixture(missing_file,electric,eased)
  local d={runs={},signals={records={}}}
  local s={tiles={[1]={h=0},[2]={h=0}},speed=1,coal=0,oil=0,stock_electrification=electric}
  local registered,actors,mounted,motions={},{},{},{}
  core={
    get_modpath=function()return "mods/luanttd_core" end,
    register_entity=function(name,props)
      assert(not registered[name],name)
      registered[name]=props.initial_properties
    end,
    add_entity=function(pos,name)
      assert(registered[name],name)
      local v={name=name,pos=pos}
      function v:get_pos() return self.pos end
      function v:move_to(next_pos,continuous)
        assert(continuous)
        self.pos=next_pos
      end
      function v:set_rotation(r)self.rot=r end
      function v:remove()self.pos=nil end
      actors[#actors+1]=v
      return v
    end,
  }
  local Sim={
    xy=function(id)return id,3 end,
    rail_paid_pose=function(state,i,fraction,fleet)
      assert(state==s and fraction==.5 and fleet==91)
      return i,1,.25,false,eased and i==2 and {} or nil
    end,
    rail_paid_motion_events=function(state)
      assert(state==s)
      motions[#motions+1]=true
    end,
    rail_coal_status=function(state)return {onboard=state.coal} end,
    rail_oil_status=function()error("sealed visual must not query the oil ledger")end,
  }
  local Run={current=function()return d end,mount_owned_model=function(id)
    assert(id==8 or id==9 or id==10 or id==11 or id==13 or id==14 or id==15 or electric and (id==23 or id==24),
      "cargo or inactive electric art must not be registered as engines")
    mounted[id]=true
    return true
  end}
  local SignalArt={mesh=function()return "unrelated_signal.obj"end,atlas="unrelated_signal.png"}
  local Pose={sample=function(...)return .125,.45,0,1 end}
  local orig=io.open
  if missing_file then
    io.open=function(name,...)
      if name:sub(-#missing_file)==missing_file then return nil end
      return orig(name,...)
    end
  end
  local render=eased and {rail_diagonal_pose=function(id,td,progress)
    assert(id==1 and td==1 and progress==.25, "a wormhole must keep its stock pose")
    return -.2,.2,1,1
  end}
  local ok,V=pcall(View.create,{s=s,Sim=Sim,render=render},Run,{},Pose,SignalArt,2,
    function(id,td,progress)
      assert(td==1 and progress==.25)
      return id==2 and .82 or 0,.125
    end)
  io.open=orig
  assert(ok,V)
  V.observe=function()end
  assert(mounted[15])
  return V,d,s,registered,actors,motions
end
local function step(V)
  V.step(.1,true,.5)
end
local dtrain={id="stock paid train",fleet_id=91,paid_clock=true,stock_engine=15,stock_wagon=30,
              consist={parts={{},{}}}}

local V,d,s,catalog,actors,motions=fixture()
assert(not catalog["luanttd_core:dispatch_sh_30"])
local p=assert(catalog[WAGON])
assert(V.oil_wagon_ready() and p.mesh=="bl_rail_oil_tanker.obj")
assert(p.textures[1]=="bl_rail_oil_tanker.png")
assert(p.visual_size.x==1 and p.visual_size.y==1 and p.visual_size.z==1 and p.backface_culling)
assert(p.static_save==false and p.physical==false and p.collide_with_objects==false)
d.runs[1]=dtrain
step(V)
assert(#actors==2 and actors[1].name=="luanttd_core:dispatch_floss" and actors[2].name==WAGON)
assert(actors[2].pos.x==4.625 and math.abs(actors[2].pos.y-1.434)<1e-7 and actors[2].pos.z==6.95)
assert(actors[2].rot.x==-.125 and actors[2].rot.y==math.pi)
for _,amount in ipairs({6,15,30,0}) do
  s.oil=amount
  dtrain.cargo_count=amount
  step(V)
  assert(#actors==2 and actors[2].name==WAGON and actors[2]:get_pos())
end
assert(#motions==5)
dtrain.stock_wagon=29
step(V)
assert(#actors==3 and not actors[2]:get_pos() and actors[3].name=="luanttd_core:dispatch_coal_empty")
s.coal=18
step(V)
assert(#actors==4 and not actors[3]:get_pos() and actors[4].name=="luanttd_core:dispatch_coal_loaded")
dtrain.stock_wagon=27
step(V)
assert(#actors==5 and not actors[4]:get_pos() and actors[5].name=="luanttd_core:dispatch_wagon")

local DV,DD,_,_,dactors=fixture(nil,nil,true)
DD.runs[1]=dtrain
step(DV)
assert(dactors[1].pos.x==2.3 and dactors[1].pos.z==6.7 and dactors[1].rot.y==.75*math.pi)
assert(dactors[2].pos.x==4.625 and dactors[2].pos.z==6.95 and dactors[2].rot.y==math.pi)

local EV,ED,_,ecatalog,eactors=fixture(nil,true)
assert(ecatalog["luanttd_core:dispatch_sh_30"].mesh=="bl_rail_sh_30.obj")
ED.runs[1]={id="electric",fleet_id=91,paid_clock=true,stock_engine=23,stock_wagon=27,
  consist={parts={{},{}}}}
step(EV)
assert(#eactors==2 and eactors[1].name=="luanttd_core:dispatch_sh_30" and
  eactors[2].name=="luanttd_core:dispatch_wagon")
if ecatalog["luanttd_core:dispatch_sh_40"] then
  assert(ecatalog["luanttd_core:dispatch_sh_40"].mesh=="bl_rail_sh_40.obj")
  ED.runs[1]={id="electric-later",fleet_id=91,paid_clock=true,stock_engine=24,stock_wagon=27,
    consist={parts={{},{}}}}
  step(EV)
  assert(eactors[3].name=="luanttd_core:dispatch_sh_40" and eactors[4].name=="luanttd_core:dispatch_wagon")
  local _,_,_,missing=fixture("bl_rail_sh_40.obj",true)
  assert(not missing["luanttd_core:dispatch_sh_40"] and missing["luanttd_core:dispatch_sh_30"])
end

for _,file in ipairs({"bl_rail_oil_tanker.obj","bl_rail_oil_tanker.png"}) do
  local U,state,_,registered,fleet=fixture(file)
  assert(not U.oil_wagon_ready() and not registered[WAGON])
  state.runs[1]=dtrain
  dtrain.stock_wagon=30
  step(U)
  assert(#fleet==0, "a missing wagon must not masquerade as a coach")
  dtrain.stock_wagon=27
  step(U)
  assert(#fleet==2 and fleet[2].name=="luanttd_core:dispatch_wagon")
end
print("RAIL_DISPATCH_VIEW_PASS: paid Oil #30 uses the sealed original at all cargo, missing mesh/atlas detected, unchanged Coal #29 and Passenger #27.")
