local mod="mods/luanttd_core/openttd/"
local specs=dofile(mod.."town_house_demolition_data.lua")
local Clear=dofile(mod.."town_house_demolition.lua")(specs)
local function denied(id,score,policy,tolerance,want)
  local q,why=Clear.quote(id,score,tolerance or 0,policy)
  assert(q==nil and why==want,why)
end
for id=0,109 do assert(specs[id] and specs[id][1]>=0 and specs[id][2]>=0) end
denied(6,465,{automatic=true},nil,"BUILDING_MUST_BE_DEMOLISHED")
denied(6,465,{protected=true},nil,"BUILDING_IS_PROTECTED")
denied(6,79,nil,nil,"HOUSE_AUTHORITY_RATING")
local q=assert(Clear.quote(6,465,0))
assert(q.cost==500 and q.after==385 and q.penalty==80)
assert(Clear.quote(6,80,0).after==0)
assert(Clear.quote(6,79,3).after==-1)
assert(Clear.quote(6,-990,3).after==-1000)
assert(Clear.quote(6,-900,0,{no_test_rating=true}).after==-980)
assert(Clear.quote(6,-900,0,{magic_bulldozer=true}).after==-900)
assert(Clear.quote(6,465,0,{no_modify_rating=true}).after==465)
-- The caller uses the original price scaled by economy inflation.
assert(Clear.quote(6,465,0,nil,1700).cost==531)
assert(Clear.quote(0x14,500,0).cost==Clear.quote(0x15,500,0).cost)
print("PASS RC1 explicit house demolition data, signed council costs, limits and automatic-command refusal")
