-- Some Luanti versions cancel a block request when another emerge thread
-- is already generating the same mapchunk. Do not redo an entire region
-- for that race, but do not hand incomplete terrain to the painter either.
return function(core)
  return function(low,high,ready,progress)
    local uncertain,errored={},false
    local function verify(pass)
      local missing=0
      for _,p in ipairs(uncertain) do
        local node=core.get_node_or_nil(p)
        if not node or node.name=="ignore" then
          missing=missing+1
          uncertain[missing]=p
        end
      end
      for i=missing+1,#uncertain do uncertain[i]=nil end
      if missing==0 then ready(true)
      elseif pass<3 then core.after(.075*pass,verify,pass+1)
      else ready(false) end
    end
    core.emerge_area(low,high,function(block,action,remaining)
      if action==core.EMERGE_ERRORED then
        errored=true
      elseif action==core.EMERGE_CANCELLED then
        -- Callback positions are in mapblocks of 16 nodes. Clamp the
        -- sample to the requested portion of a partial boundary block.
        uncertain[#uncertain+1]={
          x=math.max(low.x,block.x*16),
          y=math.max(low.y,block.y*16),
          z=math.max(low.z,block.z*16),
        }
      end
      if progress then progress(remaining) end
      if remaining==0 then
        -- Map reads and painting happen only after the engine callback
        -- returns. A genuine error is never treated as a benign race.
        if errored then core.after(0,ready,false)
        else core.after(0,verify,1) end
      end
    end)
  end
end
