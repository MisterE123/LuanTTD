-- Native QA observes the running worker form but never injects input events.
local JumpProbe={page=0}
local native_jump_form="luanttd_core:worker_jump"
local show_jump_probe=core.show_formspec
local name_jump_probe="JumpMapQA"
local function png_dimension(blob,i)
  local a,b,c,d=blob:byte(i,i+3)
  return ((a*256+b)*256+c)*256+d
end
function core.show_formspec(name,key,markup)
  if name==name_jump_probe and key==native_jump_form and markup:find(";bl_map_clear.png;",1,true) then
    local mode=markup:find("LOCAL DETAIL",1,true) and "detail" or
      markup:find("Cancel area selection",1,true) and "select" or JumpProbe.page>0 and "overview2" or "overview"
    JumpProbe.page=JumpProbe.page+1
    local areas,labels=0,0
    for _ in markup:gmatch(";bl_map_clear%.png;jump_%d+;") do areas=areas+1 end
    for _ in markup:gmatch(";bl_map_clear%.png;jump_place_%d+;") do labels=labels+1 end
    assert(areas>300 and areas<=576)
    if mode~="detail" then assert(labels>=3,"Expected three or more visible town badges") end
    local fx,fy,fw,fh=markup:match("image%[([%d%.]+),([%d%.]+);([%d%.]+),([%d%.]+);")
    assert(fx and fy and fw and fh,"Worker map did not draw its raster")
    core.log("action","JUMP_NATIVE_FRAME "..table.concat({fx,fy,fw,fh}," "))
    local png=assert(core.decode_base64(assert(markup:match("%[png:([%w+/=]+)"))))
    local width,height=png_dimension(png,17),png_dimension(png,21)
    assert(width==(mode=="detail" and 64 or 128) and height==width)
    if mode=="select" or mode=="detail" then
      local pos=assert(core.get_player_by_name(name):get_pos())
      assert(math.abs(pos.x-JumpProbe.origin.x)<.05 and math.abs(pos.z-JumpProbe.origin.z)<.05,"Detail zoom teleported the player")
    end
    core.log("action",("JUMP_NATIVE_RENDER %s (%d×%d, %d areas, %d labels)"):format(mode,width,height,areas,labels))
    for x,y,w,h,button in markup:gmatch("button%[([%d%.]+),([%d%.]+);([%d%.]+),([%d%.]+);(map_[%w_]+);") do
      core.log("action","JUMP_NATIVE_BUTTON "..table.concat({button,x,y,w,h}," "))
    end
    for x,y,w,h,button in markup:gmatch("image_button%[([%d%.]+),([%d%.]+);([%d%.]+),([%d%.]+);bl_map_clear%.png;(jump_place_%d+);") do
      core.log("action","JUMP_NATIVE_BUTTON "..table.concat({button,x,y,w,h}," "))
    end
    local x,y,w,h=markup:match("image_button%[([%d%.]+),([%d%.]+);([%d%.]+),([%d%.]+);bl_map_clear%.png;jump_184;")
    if x then core.log("action","JUMP_NATIVE_BUTTON "..table.concat({"jump_184",x,y,w,h}," ")) end
    if mode=="overview2" then JumpProbe.landing=true end
  end
  return show_jump_probe(name,key,markup)
end
table.insert(core.registered_on_player_receive_fields,1,function(p,key,fields)
  if p:get_player_name()~=name_jump_probe or key~=native_jump_form or not JumpProbe.landing then return end
  for k in pairs(fields) do
    local i=tonumber(k:match("^jump_place_(%d+)$"))
    if i then
      local disk=assert(OwnerCheckpoint.read())
      local J=dofile(mod.."/jump_map.lua")({s=disk,Sim=Sim})
      local packet=J.snapshot(false,Sim.id(math.floor((JumpProbe.origin.x+.5)/2),math.floor((JumpProbe.origin.z+.5)/2)))
      local town=assert(packet.towns[i])
      local x,z=Sim.xy(town.tile)
      local yaw,pitch=p:get_look_horizontal(),p:get_look_vertical()
      core.after(.9,function()
        local now=p:get_pos()
        assert(math.abs(now.x-(x*2+.5))<.07 and math.abs(now.z-(z*2+.5))<.07,"Map badge did not reach its authoritative town")
        assert(math.abs(yaw-p:get_look_horizontal())<.002 and math.abs(pitch-p:get_look_vertical())<.002,
          "Map jump changed the player's camera angle")
        core.log("action","PASS NATIVE WORKER JUMP MAP: physical overlay click → "..town.name.." at exact center; camera angle kept")
      end)
    end
  end
end)
local function jump_native_probe()
  local p=core.get_player_by_name(name_jump_probe)
  if not (p and authority and authority.status()=="owned" and #world.hotbar_layout(p)>0) then
    core.after(.2,jump_native_probe);return
  end
  p:set_look_horizontal(.83);p:set_look_vertical(.56)
  core.log("action","JUMP_NATIVE_HOTBAR")
  local function nav()
    if world.menu(p)=="navigation" then
      JumpProbe.origin=p:get_pos()
      for slot,logical in ipairs(world.hotbar_layout(p)) do
        if logical==5 then core.log("action","JUMP_NATIVE_NAV_SLOT "..slot);return end
      end
      error("Navigation didn't expose Jump map")
    end
    core.after(.12,nav)
  end
  nav()
end
core.after(.2,jump_native_probe)
