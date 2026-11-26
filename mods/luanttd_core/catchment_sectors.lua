-- Coarse lookup only. Callers still test the exact station catchment.
-- Inputs are zero-based map squares; bounds are inclusive.
return function(width,height)
  local unit=16
  local columns=math.ceil(width/unit)
  local sectors,ordinal={},0
  local empty={}
  local floor,min,max=math.floor,math.min,math.max
  local I={}
  function I.add(box,value)
    local left,right=max(0,box.left),min(width-1,box.right)
    local top,bottom=max(0,box.top),min(height-1,box.bottom)
    if left>right or top>bottom then return end
    ordinal=ordinal+1
    local entry={value=value,ordinal=ordinal}
    for z=floor(top/unit),floor(bottom/unit) do
      for x=floor(left/unit),floor(right/unit) do
        local at=z*columns+x
        local list=sectors[at]
        if not list then list={};sectors[at]=list end
        list[#list+1]=entry
      end
    end
  end
  local function order(a,b) return a.ordinal<b.ordinal end
  -- Returned rows are read-only. A one-sector query uses the stored
  -- list directly; multi-sector queries deduplicate in insertion order.
  function I.query(x,z,area)
    area=area or 1
    local left,right=max(0,x),min(width-1,x+area-1)
    local top,bottom=max(0,z),min(height-1,z+area-1)
    if left>right or top>bottom then return empty end
    left,right,top,bottom=floor(left/unit),floor(right/unit),floor(top/unit),floor(bottom/unit)
    if left==right and top==bottom then return sectors[top*columns+left] or empty end
    local rows,seen={},{}
    for iz=top,bottom do for ix=left,right do
      local list=sectors[iz*columns+ix]
      if list then for _,entry in ipairs(list) do
        if not seen[entry] then seen[entry]=true;rows[#rows+1]=entry end
      end end
    end end
    table.sort(rows,order)
    return rows
  end
  return I
end
