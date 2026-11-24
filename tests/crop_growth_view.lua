-- Presentation is sourced from the existing farm phase; it does not tick it.
local models,objects={},{}
core={register_entity=function(n,d)models[n]=d.initial_properties end,
  add_entity=function(p,n)
    local r={p=p,n=n};objects[#objects+1]=r
    function r:set_yaw() end
    function r:get_pos() return self.p end
    function r:remove() self.p=nil end
    return r
  end}
local dir="mods/luanttd_core/"
local slope=dofile(dir.."openttd/slope.lua")
local S={stock_farm_fields={}}
local function field(stage,slope_nr)
  return {base=0,slope=slope_nr or 0,variant=stage}
end
local function live()
  local a={}
  for _,o in ipairs(objects) do if o.p then a[#a+1]=o end end
  return a
end
local view=dofile(dir.."farm_field_view.lua")({slope=slope,s=S,Sim={xy=function(id) return id%10,math.floor(id/10) end},
  farm_world={field=function(state,id) return state.stock_farm_fields[id] end}},nil)
local function at(x,y,z) view.step(.4,{{x=x,y=y,z=z}}) end
local id=11
S.stock_farm_fields[id]=field(0)
at(2.5,2,2.5);assert(#live()==0)
S.stock_farm_fields[id].variant=4
at(2.5,2,2.5); assert(#live()==1 and live()[1].n:match("crop_growth_4$"))
assert(not models[live()[1].n].physical)
at(44,2,2.5); assert(#live()==1) -- retained hysteresis band
at(49,2,2.5); assert(#live()==0)
at(38,21,2.5); assert(#live()==1 and live()[1].n:match("_lite$")) -- survey range and height
at(38,29,2.5); assert(#live()==0) -- above vertical retention
at(44,2,2.5); assert(#live()==0) -- do not respawn before returning
at(2.5,2,2.5); assert(#live()==1)
S.stock_farm_fields[id]=field(6,23)
at(2.5,2,2.5); assert(#live()==4)
for _,r in ipairs(live()) do
  assert(r.n:match("crop_growth_6_patch$"))
  assert(math.abs(r.p.y-.504-slope.surface((r.p.x-1.5)/2,(r.p.z-1.5)/2,23))<1e-6)
end
for id=1,100 do S.stock_farm_fields[id]=field(5,3) end
at(10.5,2,10.5);assert(#live()==64)
at(10.5,50,10.5);assert(#live()==0)
print("CROP_GROWTH_PASS: stock stage receipts, near/far hysteresis, exact sloped anchors, immaterial crops, 64 object cap")
