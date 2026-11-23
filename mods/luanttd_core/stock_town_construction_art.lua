-- Turn RC1's exact ground/upper pairs into original site art without
-- altering the house clock, population, or footprint of any building.
return function(rows,art)
  local C={}
  local ground_name={[-1]="bare",[-2]="paved",[-3]="grass"}
  function C.resolve(id,slot,stage)
    -- Stock drawing rows are source data; only styles present in the
    -- active native catalogue can be selected or registered.
    local root,style=rows[id],art[id]
    if not (root and style and style.asset) then return nil end
    local seq=root[root.slots[1+slot]]
    local phase=assert(seq[1+stage])
    local done=seq[4]
    local ground,upper=phase[1],phase[2]
    local look=style.looks and style.looks[1+slot] or 0
    if ground==done[1] and upper==done[2] then
      return "complete",ground,upper,look
    elseif upper~=0 and upper==done[2] then
      -- The building has exactly the finished silhouette. Cover the
      -- landscaping with the source's unfinished dirt, not new framing.
      assert(ground==-1)
      local suffix=("%02x"):format(id)..(look~=0 and ("_"..look) or "")
      return "town_site_shell_"..suffix,ground,upper,look
    elseif upper==0 and ground==-1 then
      return "town_site_bare",ground,upper,look
    elseif upper==0 and ground==-2 then
      return "town_site_paved",ground,upper,look
    else
      return ("town_site_%s_%d"):format(ground_name[ground] or ground,upper),ground,upper,look
    end
  end
  function C.selection(id,x,z,stage)
    return C.resolve(id,art.tile_hash(x,z),stage)
  end
  function C.files()
    local files={}
    for id=0,0xFF do
      if rows[id] then for slot=0,3 do
        for stage=0,2 do
          local name,ground,upper,look=C.resolve(id,slot,stage)
          if name and name~="complete" and not files[name] then
            files[name]={id=id,slot=slot,stage=stage,ground=ground,upper=upper,look=look,
              shell=name:find("^town_site_shell_")~=nil}
          end
        end
      end end
    end
    return files
  end
  return C
end
