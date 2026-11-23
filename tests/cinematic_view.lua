-- SPDX-License-Identifier: GPL-2.0-only
local closed
local active={A=true}
local p={name="A",flags={hotbar=true,crosshair=true},form="original",
  h={[1]={type="text",position={x=.3,y=.1}},[8]={type="waypoint",name="Alder",text=""}}}
function p:get_player_name() return self.name end
function p:hud_get_all() return self.h end
function p:hud_get(id) return self.h[id] end
function p:hud_change(id,k,v) self.h[id][k]=v end
function p:hud_get_flags()
  local t={};for k,v in pairs(self.flags) do t[k]=v end;return t
end
function p:hud_set_flags(t) for k,v in pairs(t) do self.flags[k]=v end end
function p:get_inventory_formspec() return self.form end
function p:set_inventory_formspec(s) self.form=s end
local core={get_player_by_name=function(n)return active[n] and p end,
  register_chatcommand=function(n,meta) assert(n=="cine");core_command=meta.func end,
  close_formspec=function(n) closed=n end}
local off,on=0,0
local C=dofile("mods/luanttd_core/cinematic_view.lua")(core,function()off=off+1 end,function()on=on+1 end)
assert(core_command("A") and C.active(p) and closed=="A" and off==1)
assert(not p.flags.hotbar and not p.flags.crosshair and p.h[1].position.x<0 and p.h[8].name=="")
assert(p.form:find("Restore interface",1,true))
p.h[4]={type="text",position={x=.52,y=.82}}
p.flags.hotbar=true
C.step(.2)
assert(not p.flags.hotbar and p.h[4].position.x<0)
assert(C.toggle(p) and not C.active(p) and on==1 and p.form=="original")
assert(p.flags.hotbar and p.flags.crosshair and p.h[1].position.x==.3 and p.h[4].position.x==.52 and p.h[8].name=="Alder")
print("PASS /cine hides all game HUD, invokes target cleanup, handles late overlay, and restores interface")
