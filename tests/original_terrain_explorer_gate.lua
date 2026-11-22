local E=dofile("mods/luanttd_core/original_terrain_explorer.lua")
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

local shown,name,closed,positioned,submitted
local player={get_player_name=function()return "SurveyQA" end}
local players={SurveyQA={}}
local core={
  formspec_escape=function(s)return s end,
  show_formspec=function(_,form,data) name,shown=form,data end,
  close_formspec=function(_,form) assert(form==name);closed=true end,
  register_on_player_receive_fields=function(callback) submitted=callback end,
}
E.bind_controls(core,players,{
  point=function()return 6,43 end,
  describe=function()return "Shore: exact slope mask 3" end,
  coast=function() positioned="coast" end,
  transect=function() positioned="transect" end,
  summit=function() positioned="summit" end,
  visit=function(_,x,z)
    if not x or not z or x<2 or z<2 or x>=64 or z>=64 then return false,"Outside playable grid" end
    positioned={x,z};return true
  end,
})
assert(E.inventory_form:find("survey_controls;Survey controls",1,true))
assert(not submitted(player,"wrong form",{survey_controls=true}))
assert(submitted(player,"",{survey_controls=true}))
assert(shown:find("Shore: exact slope mask 3",1,true) and shown:find("survey_go;Jump to tile",1,true))
assert(submitted(player,name,{survey_go=true,survey_x="64",survey_z="17"}) and not positioned)
assert(shown:find("Outside playable grid",1,true))
assert(submitted(player,name,{survey_go=true,survey_x="2.5",survey_z="17"}) and not positioned)
for _,key in ipairs({"coast","transect","summit"}) do
  submitted(player,"",{survey_controls=true})
  assert(submitted(player,name,{["survey_"..key]=true}) and positioned==key and closed)
end
submitted(player,"",{survey_controls=true})
submitted(player,name,{key_enter=true,key_enter_field="survey_x",survey_x="27",survey_z="17"})
assert(positioned[1]==27 and positioned[2]==17)
submitted(player,name,{survey_coast=true})
assert(positioned[1]==27) -- stale fields cannot move the player
print("PASS Inventory opens survey, all viewpoint buttons jump, exact coordinates validate, stale forms ignored")
