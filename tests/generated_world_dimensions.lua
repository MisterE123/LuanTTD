-- UI, validation, generation adapter and persisted independent axes agree.
local World=dofile("mods/luanttd_core/world_setup.lua")
local Generated=dofile("mods/luanttd_core/generated_campaign.lua")
local axes={64,128,256,512,1024,2048,4096}
for i,w in ipairs(axes) do
  assert(World.axis_log(w)==i+5)
  for _,d in ipairs(axes) do
    local legal=w*d<=World.max_playable_tiles
    assert(World.supports_size(w,d)==legal)
    assert(Generated.supports_size(w,d)==legal)
  end
end
assert(not World.supports_size(129,64) and not World.supports_size(64,4097))
local opts={bayline_generated_map_size="128",bayline_generated_map_width="4096",bayline_generated_map_depth="64"}
local settings={get=function(_,key)return opts[key] end}
local draft=World.defaults(settings)
assert(draft.width==4096 and draft.depth==64 and draft.size==nil)
local changed=assert(World.parse(draft,{setup_width="4",setup_depth="4"}))
assert(changed.width==512 and changed.depth==512 and changed.size==512)
assert(not World.parse(draft,{setup_depth="2"}))
assert(not World.parse(draft,{setup_width="8"}))
local h=assert(World.parse(draft,{setup_width="1",setup_depth="7"}))
assert(h.width==64 and h.depth==4096 and h.size==nil)
local actual,parsed
local storage={get_string=function()return "valid"end}
local core={settings=settings,parse_json=function()return parsed end}
parsed=h
actual=assert(World.read(core,storage))
assert(actual.width==64 and actual.depth==4096)
parsed=World.defaults(settings)
parsed.width,parsed.depth,parsed.size=nil,nil,128
actual=assert(World.read(core,storage))
assert(actual.width==128 and actual.depth==128 and actual.size==128)
print("PASS independent stock axes, combined area cap, and legacy square profile migration")
