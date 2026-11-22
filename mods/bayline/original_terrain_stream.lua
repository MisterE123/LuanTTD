-- Mount the Original generator's read-only raster as a sparse WorldStorage
-- base. Owners share one base and issue bounded detached view work on it.
return function(Generator,Storage,Stream,Slope)
  local M={}
  function M.open(opts,masks,saved)
    local base=Generator.generate(opts,masks)
    local storage_opts=base.storage_options()
    local handle,why
    if saved==nil then handle=Storage.new(base.width,base.depth,storage_opts)
    else handle,why=Storage.decode(saved,storage_opts) end
    if not handle then return nil,why end
    local source=Stream.for_storage(Storage,handle,Generator.describe)
    local W={}
    W.stats=source.stats
    W.commit=source.commit
    W.snapshot=source.snapshot
    W.apply_job=source.apply_job
    function W.save() return Storage.encode(handle) end
    function W.view(options) return Stream.new(source,options or {}) end
    function W.corner(x,z) return Storage.get_corner(handle,x,z) end
    function W.tile(x,z)
      local word=Storage.get_tile(handle,x,z)
      if word==nil then return nil end
      local class,ground=Generator.describe(word)
      local n,w,e,s=Storage.tile_corners(handle,x,z)
      local mask,base=Slope.classify(n,w,e,s)
      return {class=class,ground=ground,mask=mask,base=base,high=math.max(n,w,e,s),word=word}
    end
    return W
  end
  return M
end
