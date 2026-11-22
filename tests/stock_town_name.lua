local Name=dofile("mods/luanttd_core/openttd/stock_town_name.lua")
assert(Name.display(0)=="Invenville")
assert(Name.display(4294967295)=="Fort Wenfingburg Springs")
assert(Name.display(2147483648)==Name.display(0))
for _,bad in ipairs({-1,4294967296,1.5,"1",math.huge,-math.huge,0/0}) do
  assert(not pcall(Name.display,bad),"accepted nameparts outside uint32")
end

local wanted=428288052
local used={[Name.display(0)]=true}
local draws=0
local parts,name=Name.generate(used,function()
  draws=draws+1
  if draws==1000 then return wanted end
  return 2147483648
end)
assert(draws==1000 and parts==wanted and name==Name.display(wanted) and used[name]==true)

-- A generated name reserved for a failed site remains unavailable to the next
-- ordinary placement attempt.  It may be reused after starting the fallback
-- with a separate set of actual towns only.
draws=0
parts,name=Name.generate(used,function() draws=draws+1;return wanted end)
assert(parts==nil and name==nil and draws==1000)
local actual={[Name.display(0)]=true}
local fallback_parts,fallback_name=Name.generate(actual,function() return wanted end)
assert(fallback_parts==wanted and fallback_name==Name.display(wanted) and actual[fallback_name])
print("Original English town name generation, reserved names and fallback passed")
