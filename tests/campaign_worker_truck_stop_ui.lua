local pending,form
local core={formspec_escape=function(s) return s:gsub("[;]",":") end,
  show_formspec=function(_,name,shown) assert(name=="luanttd_core:worker_truck_stop");form=shown end}
local view=dofile("mods/luanttd_core/campaign_worker_truck_stop_ui.lua")(core,{
  defer=function(req,cb)
    assert(req.kind=="truck_stop" and req.player=="QA" and req.tile==122)
    pending=cb;return true
  end},tostring)
local player={get_player_name=function() return "QA" end}
local report={ok=true,value={name="Steel; yard",cargo={
  {name="Iron Ore",waiting=42,accepts=true},
  {name="Steel",waiting=2,collects=true,rating=255},
}}}
assert(view.open(player,122) and form:find("Reading the catchment",1,true))
local old=pending
view.fields(player,{quit=true})
old(report)
assert(not form:find("Iron Ore",1,true))
assert(view.open(player,122))
old(report)
assert(not form:find("Iron Ore",1,true))
pending(report)
for _,txt in ipairs({"Steel: yard","Iron Ore","42 waiting","Accepts deliveries","Collects","100%"}) do
  assert(form:find(txt,1,true),txt)
end
print("PASS ordinary truck stop catchment form, cargo/ratings, escaped text and dismissed worker reply")
