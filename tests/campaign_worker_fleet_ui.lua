local hooks,shown,opened={}
local p={get_player_name=function() return "Company" end}
local api={
  formspec_escape=function(s) return tostring(s) end,
  show_formspec=function(n,form,b) assert(n=="Company"); shown={form,b} end,
  explode_textlist_event=function(i) return {index=tonumber(i)} end,
}
local worker={query=function(request,done)
  assert(request.player=="Company" and request.kind=="company_fleet")
  hooks[#hooks+1]={request=request,done=done}
  return true
end}
local F=dofile("mods/luanttd_core/campaign_worker_fleet_ui.lua")(api,worker,{
  open=function(who,mode,id,back)
    opened={who,mode,id,back}
    return true
  end,
})
local function answer(call,page,id)
  assert(hooks[call].request.page==page)
  hooks[call].done({ok=true,value={total=21,page=page,pages=2,records={{mode="rail",id=id,label="Train "..id}}}})
end
F.open(p);answer(1,1,6)
assert(shown[2]:find("Rail · Train 6",1,true))
F.fields(p,{f1_next=true})
answer(2,2,23)
F.fields(p,{f1_open=true});assert(not opened)
F.fields(p,{f2_open=true})
assert(opened[2]=="rail" and opened[3]==23 and opened[4].directory)
opened[4].return_()
assert(hooks[3].request.page==2)
F.leave("Company")
local old=shown
answer(3,2,23)
assert(old==shown)
print("PASS fleet paging and selection use authenticated worker and live panels; late replies cannot bring back a closed menu")
