local E=dofile("mods/bayline/original_terrain_explorer.lua")
local function gate(enabled,marker,campaign,world)
  local untouched=true
  local core={settings={get_bool=function(_,key,default)
      assert(key==E.setting and default==false);return enabled
    end},
    get_worldpath=function()return world or "/nonexistent" end,
    sha256=function()return string.rep("a",64) end}
  local storage={get_string=function(_,k)return k=="campaign" and campaign or marker end,
    set_string=function() untouched=false end}
  local ok,out=pcall(E.start,core,"/nonexistent",storage)
  assert(untouched)
  return ok,out
end
local ok,out=gate(false,"","")
assert(ok and out==nil)
ok,out=gate(false,"original","")
assert(not ok and out:find("keep "..E.setting,1,true))
ok,out=gate(true,"","saved ordinary campaign")
assert(not ok and out:find("a campaign already exists",1,true))
ok,out=gate(true,"","")
assert(not ok and out:find("Missing local "..E.mask_file,1,true))
print("PASS Original terrain exploration default isolation, mode switch refusal and missing-mask guard")

local function config(values)
  return {get=function(_,k) return values[k:match("bayline_original_terrain_(.+)")] end}
end
local defaults=E.options(config({}))
assert(defaults.width==64 and defaults.depth==64 and defaults.seed==1751)
local opts=E.options(config({width="4096",depth="128",seed="4294967295"}))
assert(opts.width==4096 and opts.depth==128 and opts.seed==4294967295)
for _,bad in ipairs{{width="63"},{depth="1000"},{seed="1.5"},{seed="str"},{seed="4294967296"}} do
  assert(not pcall(E.options,config(bad)))
end
local samples=0
local function fake(w,h,seed)
  return {
    stats=function()return {width=w,depth=h,seed=seed} end,
    tile=function(x,z)
      assert(x>=2 and x<w and z>=2 and z<h)
      samples=samples+1
      local hill=x%9+z%5
      return {ground=hill<5 and 1 or 0,base=hill,high=hill+1}
    end,
  }
end
assert(E.profiles(fake(64,64,1751)).transect.x==13 and samples==0)
local views=E.profiles(fake(4096,128,1751))
assert(samples<5200 and views.transect.x==2045 and views.transect.z==65)
for _,p in pairs(views) do assert(p.x~=p.look_x or p.z~=p.look_z) end
print("PASS Original explorer size/seed validation and bounded deterministic lookouts")
