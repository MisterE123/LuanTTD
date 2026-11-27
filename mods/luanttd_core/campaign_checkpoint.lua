-- Wide generated campaigns need a durable process-crash checkpoint:
-- Luanti can batch otherwise successful ModStorage writes in SQLite.
return function(core,codec,filename)
  local name=filename or "luanttd-wide-campaign.chk"
  local dir=core.get_worldpath()
  local path=dir.."/"..name
  local prefix="LUANTTD-WIDE-CAMPAIGN-1"
  local state_prefix="LUANTTD-WIDE-CAMPAIGN-3-STATE"
  local M={}
  function M.clear() os.remove(path) end
  function M.read()
    local found=false
    for _,file in ipairs(core.get_dir_list(dir,false)) do
      if file==name then found=true;break end
    end
    if not found then return nil end
    local file,why=io.open(path,"rb")
    assert(file,"Cannot read the wide campaign checkpoint: "..tostring(why))
    local signature,digest=file:read("*l","*l")
    local payload=file:read("*a")
    file:close()
    -- Never silently roll back to SQLite if the canonical file exists
    -- but is damaged or was created by an unsupported format.
    local damaged="The wide campaign checkpoint is damaged or has an unsupported format."
    assert((signature==prefix or signature==state_prefix) and payload and #payload>0
      and digest==core.sha256(payload),damaged)
    if signature==prefix then return payload end
    local ok,value=pcall(core.decompress,payload,"zstd")
    assert(ok and type(value)=="string" and #value>0,damaged)
    local valid,state=pcall(assert(codec).decode,value)
    assert(valid and type(state)=="table",damaged)
    return state
  end
  local function write(signature,payload)
    local data=signature.."\n"..core.sha256(payload).."\n"..payload
    assert(core.safe_file_write(path,data),
      "Could not commit the wide campaign checkpoint. Check free disk space and world folder permissions.")
  end
  function M.write(payload)
    return write(prefix,payload)
  end
  function M.write_state(state,pulse)
    local bytes=assert(codec).encode(state,pulse)
    -- Periodic saves can serve bounded read-only queries while the
    -- graph is stable. Service the mailbox at native phase boundaries
    -- too, not just during the Lua traversal.
    if pulse then pulse() end
    local payload=core.compress(bytes,"zstd",pulse and 1 or 3)
    bytes=nil
    if pulse then pulse() end
    return write(state_prefix,payload)
  end
  return M
end
