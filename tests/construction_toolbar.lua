-- Exercise the real build/preview/controller callbacks behind direct tools.
core={formspec_escape=function(s)return s end,get_modpath=function()return "mods/luanttd_core" end}
local p={get_player_name=function()return "Alex" end}
local s={tiles={[1]={},[2]={},[3]={},[4]={road_bridge_id=1},[5]={},[6]={rail_span_id=1}}}
local seen,changes={},{}
local pending
local function record(...)
  seen[#seen+1]={...}
end
local function sale(kind,n,a,b)
  assert(n=="Alex")
  if a==b then return nil,"Choose distinct bridgeheads." end
  return {ids={a,5,b},minimum=kind=="road" and 400 or 500}
end
local pick={
  quote=sale,
  open=function(_,kind,a,b,done)
    record(kind,a,b)
    local q,why=sale(kind,"Alex",a,b)
    if not q then return nil,why end
    if b==3 then done(true,"Remembered bridge built.");return true end
    pending=done
    return true
  end,
}
local span={start=6,["end"]=2,middle={3},owner="Alex",kind="bridge",deck=2}
local Sim={
  id=function()return 1 end,
  tools={inspect={name="Inspect"},clear={name="Bulldoze",price=80}},
  plan=function()error("Structure removal must not erase one record")end,
  build=function()error("Generic build must not erase a portal")end,
  remove_wood_bridge=function(_,n,id,quote)
    assert(n=="Alex" and id==4)
    if quote then return true,0,{start=4,["end"]=2,middle={5}} end
    return true,"Paired bridge cleared.",{4,2,5},3
  end,
}
local R={
  update=function(ids)changes[#changes+1]=ids end,
  raise_bound=function(h)changes.height=h end,
}
local api={Sim=Sim,s=s,render=R,road_first=true,structure_tools=true,rail_span_tools=true,bridge_picker=pick,
  save=function()changes.saved=(changes.saved or 0)+1 end,
  rail_spans={by_portal=function()return span end,clear=function()
    return false,"Clear the running train before editing spans."
  end},
}
local U=dofile("mods/luanttd_core/ui.lua")(api)
local function status()return select(2,U.world_status(p)) end
assert(U.is_world_tool("road_bridge_picker"))
assert(U.is_world_tool("rail_bridge_picker"))
U.select_tool(p,"road_bridge_picker")
assert(select(2,U.preview(p,1))==true)
U.build_world(p,1)
assert(U.anchor(p)==1 and #seen==0)
assert(U.cancel_build_selection(p) and not U.anchor(p))
assert(not U.cancel_build_selection(p))
U.build_world(p,1)
assert(select(2,U.preview(p,1))==false)
U.build_world(p,1)
assert(U.anchor(p)==1 and status()=="Choose distinct bridgeheads.")
local ids,ok,hint=U.preview(p,2)
assert(ok and table.concat(ids,",")=="1,5,2" and hint:find("From $400",1,true))
U.build_world(p,2)
assert(not U.anchor(p) and pending and status()=="Choose a bridge type.")
assert(changes.saved==nil) -- a quote/second click didn't purchase
pending(false,"Bridge selection canceled.")
assert(status()=="Bridge selection canceled.")
U.build_world(p,1)
U.build_world(p,3)
assert(not U.anchor(p) and status()=="Remembered bridge built.")
U.select_tool(p,"rail_bridge_picker")
U.build_world(p,1)
assert(select(3,U.preview(p,2)):find("From $500",1,true))
U.build_world(p,2)
assert(seen[#seen][1]=="rail" and seen[#seen][2]==1 and seen[#seen][3]==2)

U.select_tool(p,"clear")
ids,ok=U.preview(p,4)
assert(ok and table.concat(ids,",")=="4,5,2" and changes.saved==nil)
U.build_world(p,4)
assert(changes.saved==1 and changes.height==3 and #changes[1]==3 and status()=="Paired bridge cleared.")
U.build_world(p,6)
assert(changes.saved==1 and status()=="Clear the running train before editing spans.")
api.bridge_picker=nil
assert(not U.is_world_tool("rail_bridge_picker"))
print("PASS: actual construction callbacks preserve two-head selection, modal cancellation, exact mode and safe demolition authority")
