-- Mount only fully authored piecewise families. Stock supplies the
-- structural piece (and thereby which faces have supports); the Luanti
-- asset manifest only maps that class to an original native model.
return function(architecture,Bridge,xy)
  local R={}
  function R.mount(prefix,manifest,geometry)
    geometry=geometry or prefix
    local function model(suffix)
      return architecture("stock_"..prefix..suffix,geometry..suffix,prefix)
    end
    local def={span={[0]={},[1]={}},pier={[0]={},[1]={}},feet={[0]={},[1]={}},
      under={[0]={},[1]={}},choices=manifest.choices}
    for axis=0,1 do
      for _,name in ipairs(manifest.pieces) do
        local key="_span_"..axis.."_"..name
        def.span[axis][name]=model(key)
        if manifest.bearing[name] then
          local clear=key.."_road_clear"
          def.under[axis][name]=model(clear)
          key="_pier_"..axis.."_"..name
          def.pier[axis][name]=model(key)
          local feet={}
          for _,depth in ipairs({1,2,"water"}) do
            local name_="_foot_"..axis.."_"..name.."_"..depth
            feet[depth]=model(name_)
          end
          def.feet[axis][name]=feet
        end
      end
    end
    function def.models(span,id)
      local piece,pillar=Bridge.middle_layout(span,id,xy)
      if piece==nil then return end
      local key=assert(def.choices[piece],"Missing stock bridge piece model")
      local axis=span.axis
      return def.span[axis][key],def.under[axis][key],def.pier[axis][key],def.feet[axis][key],pillar
    end
    return def
  end
  return R
end
