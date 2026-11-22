-- Wide generated campaigns need a durable process-crash checkpoint:
-- Luanti can batch otherwise successful ModStorage writes in SQLite.
return function(core)
  local name="luanttd-wide-campaign.chk"
  local dir=core.get_worldpath()
  local path=dir.."/"..name
  local prefix="LUANTTD-WIDE-CAMPAIGN-1"
  local M={}
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
    assert(signature==prefix and payload and #payload>0 and digest==core.sha256(payload),
      "The wide campaign checkpoint is damaged or has an unsupported format.")
    return payload
  end
  function M.write(payload)
    local data=prefix.."\n"..core.sha256(payload).."\n"..payload
    assert(core.safe_file_write(path,data),
      "Could not commit the wide campaign checkpoint. Check free disk space and world folder permissions.")
  end
  return M
end
