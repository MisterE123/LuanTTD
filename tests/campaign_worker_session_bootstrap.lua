local mod="mods/luanttd_core"
local load_session=dofile(mod.."/campaign_worker_session.lua")
local noop=function() end
local n=256^2
local marker={terrain="grass",h=1}
local function probe(fresh,fail_seal)
  local tiles={}
  for i=1,n do tiles[i]=marker end
  local api={s={tiles=tiles}}
  local jobs,events,clock,after={},{},{},{}
  local add=function(event) events[#events+1]=event end
  local core={register_on_shutdown=noop,register_async_dofile=noop,log=noop,
    get_connected_players=function() return {} end,
    get_worldpath=function() return "/disposable" end,
    ipc_set=function(key,v) clock[key]=v end,
    ipc_get=function(key) return clock[key] end,
    after=function(_,f) after[#after+1]=f end,
    handle_async=function(_,done,_,channel,_,filename)
      assert(api.authority_handoff and #api.s.tiles==0 and api.s.tiles[n]==marker)
      assert(filename=="owner.chk")
      jobs[#jobs+1]={done=done,channel=channel};add("async")
      return true
    end}
  local checkpoint={write_state=function(s)
    assert(fresh and api.authority_handoff and s==api.s and s.tiles==tiles)
    add("seal")
    if fail_seal then error("simulated failed write") end
  end}
  local session=load_session(core,mod,api,{install_worker_controls=noop,use_worker_projection=noop,hud=noop},{
    use_worker_projection=noop,draw_worker_actors=noop
  },checkpoint,"owner.chk",fresh,{
    compact_bootstrap=function(dense)
      assert(dense==tiles and #dense==n and dense[n]==marker)
      add("compact")
      return setmetatable({},{__index=function(_,id) if id==n then return marker end end})
    end,open=noop,wait=noop,
  })
  local start=session.start({},256,256)
  if fail_seal then
    assert(not start and api.s.tiles==tiles and #jobs==0 and table.concat(events,",")=="seal")
    return
  end
  assert(start and session.status()=="opening")
  assert(table.concat(events,",")==(fresh and "seal,compact,async" or "compact,async"))
  local first=jobs[1]
  clock[first.channel..":reply"]={ready=true,seq=0,day=7}
  table.remove(after,1)()
  assert(session.status()=="owned" and api.s.tiles[n]==marker)
  first.done("failed",nil,nil,"worker interrupted")
  assert(session.status()=="failed")
  -- An obsolete poll may still be queued; only the recovery creates a job.
  while #jobs<2 do table.remove(after,1)() end
  assert(#events==(fresh and 4 or 3) and events[#events]=="async")
end
probe(true,false)
probe(false,false)
probe(true,true)
print("PASS frozen host seals before compaction and starts only the durable worker; recovery never rewrites compact tiles")
