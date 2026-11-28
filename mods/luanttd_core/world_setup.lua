-- Local fresh-world setup. Persist only world generation options here; the
-- campaign is deliberately not constructed until the next game launch.
local M={form="luanttd_core:world_setup",storage_key="world_setup_v1"}
local scenarios={"generated","farm","oil","coastal","south_coast","original"}
local scenario_labels="Generate a world,Farm and Factory,Oil and Refinery,Coastal Landscaping,South Coast Coal,Original Terrain Survey"
local survey_sizes={64,128,256,512,1024,2048,4096}
local labels={"64","128","256","512","1024","2048","4096"}
-- Tested working-set threshold, not a restriction on the stock sizes.
M.tested_playable_tiles=512*512
local items={
  {key="width",default=64,values=survey_sizes,labels=labels},
  {key="depth",default=64,values=survey_sizes,labels=labels},
  {key="relief",setting="bayline_generated_relief",default=1,values={0,1,2,3,4},
    labels={"Very flat","Flat","Hilly","Mountainous","Alpinist"}},
  {key="sea",setting="bayline_generated_sea",default=0,values={0,1,2,3},
    labels={"Very low","Low","Medium","High"}},
  {key="rivers",setting="bayline_generated_rivers",default=2,values={0,1,2,3},
    labels={"None","Few","Normal","Many"}},
  {key="towns",setting="bayline_generated_towns",default=2,values={0,1,2,3,4},
    labels={"Very low","Low","Normal","High","Custom"}},
  {key="layout",setting="bayline_generated_town_layout",default="original",
    values={"original","better","grid2","grid3","random"},
    labels={"Original","Better roads","2 x 2 grid","3 x 3 grid","Random"}},
  {key="industries",setting="bayline_generated_industries",default=4,values={0,1,2,3,4,5,6},
    labels={"Fund only","Minimal","Very low","Low","Normal","High","Custom"}},
  {key="trees",setting="bayline_generated_tree_placer",default=2,values={0,1,2},
    labels={"None","Original","Improved"}},
  -- OpenTTD 14.1 tgp.cpp. Edges below follow LuanTTD's top-down
  -- compass: west=bit 0, south=1, east=2, north=3.
  {key="smooth",setting="bayline_generated_smoothness",default=1,values={0,1,2,3},
    labels={"Very smooth","Smooth","Rough","Very rough"},advanced="Terrain smoothness"},
  {key="coast",setting="bayline_generated_coasts",default=15,values={15,0,1,2,4,8,5,10,16},
    labels={"All edges","No forced coast","West only","South only","East only","North only",
      "West and east","North and south","Random edges"},advanced="Forced coastlines"},
  {key="growth_rate",setting="luanttd_town_growth_rate",default=2,values={0,1,2,3,4},
    labels={"None","Slow","Normal","Fast","Very fast"},advanced="Town growth speed"},
  {key="town_cargo",setting="luanttd_town_cargo_mode",default=1,values={0,1},
    labels={"Quadratic (original)","Linear"},advanced="Town cargo generation"},
  {key="variety",setting="bayline_generated_variety",default=0,values={0,1,2,3,4,5},
    labels={"None","Very low","Low","Medium","High","Very high"},advanced="Regional variety"},
}
-- 16.0-RC1 economy_settings.ini and world_settings.ini.
local town_numbers={
  {key="custom_towns",setting="bayline_generated_custom_towns",label="Custom town count",min=1,max=5000,default=1},
  {key="larger_towns",setting="bayline_generated_larger_towns",label="Every Nth town is a city",min=0,max=255,default=4},
  {key="initial_city_size",setting="bayline_generated_initial_city_size",label="Initial city size multiplier",min=1,max=10,default=2},
  {key="town_min_distance",setting="bayline_generated_town_min_distance",label="Minimum town separation (tiles)",min=10,max=500,default=20},
}
local function index(values,v)
  for i,value in ipairs(values) do if value==v then return i end end
end
local function integer(n,low,high)
  return type(n)=="number" and n==math.floor(n) and n>=low and n<=high
end
function M.axis_log(n)
  local i=index(survey_sizes,n)
  return i and i+5
end
function M.supports_size(width,depth)
  return M.axis_log(width)~=nil and M.axis_log(depth)~=nil
end
function M.dimensions(settings,cfg)
  if cfg then
    return cfg.width or cfg.size,cfg.depth or cfg.size
  end
  local size=tonumber(settings:get("bayline_generated_map_size")) or 64
  local width=tonumber(settings:get("bayline_generated_map_width")) or 0
  local depth=tonumber(settings:get("bayline_generated_map_depth")) or 0
  return width==0 and size or width,depth==0 and size or depth
end
local function set_size(cfg,width,depth)
  cfg.width,cfg.depth=width,depth
  cfg.size=width==depth and width or nil -- legacy square profiles
end
local size_error="Choose a stock power-of-two width and depth from 64 to 4096."
function M.random_seed(rng)
  -- Signed RNG bounds are too narrow for the original uint32 seed.
  return rng:next(0,65535)*65536+rng:next(0,65535)
end
function M.defaults(settings,fresh)
  local seed=tonumber(settings:get("bayline_seed"))
  if not integer(seed,0,4294967295) and fresh then seed=fresh() end
  local year=tonumber(settings:get("bayline_stock_bus_start_year"))
  local out={seed=integer(seed,0,4294967295) and seed or 1751,scenario="generated",survey_size=64,
    year=integer(year,1950,2050) and year or 1950}
  for _,item in ipairs(items) do
    if item.setting then
      local v=settings:get(item.setting)
      if type(item.default)=="number" then v=tonumber(v) end
      out[item.key]=index(item.values,v) and v or item.default
    end
  end
  for _,item in ipairs(town_numbers) do
    local value=tonumber(settings:get(item.setting))
    out[item.key]=integer(value,item.min,item.max) and value or item.default
  end
  local width,depth=M.dimensions(settings)
  if not M.supports_size(width,depth) then width,depth=64,64 end
  set_size(out,width,depth)
  return out
end
function M.parse(current,fields)
  local out={}
  for _,item in ipairs(items) do
    local field=fields["setup_"..item.key]
    local v=item.values[tonumber(field) or 0]
    if field~=nil and v==nil then return nil,"Choose a valid generator option." end
    out[item.key]=v or current[item.key]
  end
  for _,item in ipairs(town_numbers) do
    local value=fields["setup_"..item.key]
    value=value==nil and (current[item.key] or item.default) or tonumber(value)
    if not integer(value,item.min,item.max) then
      return nil,("%s must be a whole number from %d to %d."):format(item.label,item.min,item.max)
    end
    out[item.key]=value
  end
  local legacy=fields.setup_size
  if legacy~=nil then
    local size=survey_sizes[tonumber(legacy) or 0]
    if not size then return nil,"Choose a valid map side." end
    if fields.setup_width==nil then out.width=size end
    if fields.setup_depth==nil then out.depth=size end
  end
  if not M.supports_size(out.width,out.depth) then return nil,size_error end
  set_size(out,out.width,out.depth)
  out.scenario=current.scenario or "generated"
  if fields.setup_scenario then
    out.scenario=scenarios[tonumber(fields.setup_scenario) or 0]
    if not out.scenario then return nil,"Choose a valid world type." end
  end
  out.survey_size=current.survey_size or 64
  if fields.setup_survey_size then
    out.survey_size=survey_sizes[tonumber(fields.setup_survey_size) or 0]
    if not out.survey_size then return nil,"Choose a valid survey size." end
  end
  local seed=tonumber(fields.setup_seed or current.seed)
  if not integer(seed,0,4294967295) then return nil,"Enter a whole-number seed from 0 to 4,294,967,295." end
  out.seed=seed
  local year=tonumber(fields.setup_year or current.year)
  if not integer(year,1950,2050) then return nil,"Enter a starting year from 1950 to 2050." end
  out.year=year
  return out
end
function M.read(core,storage)
  local raw=storage:get_string(M.storage_key)
  if raw=="" then return end
  local cfg=core.parse_json(raw,nil,true)
  if type(cfg)~="table" or not integer(cfg.seed,0,4294967295) then return end
  if cfg.year==nil then cfg.year=M.defaults(core.settings).year end
  if not integer(cfg.year,1950,2050) then return end
  if not index(scenarios,cfg.scenario) or not index(survey_sizes,cfg.survey_size) then return end
  local width,depth=M.dimensions(core.settings,cfg)
  if not M.supports_size(width,depth) then return end
  set_size(cfg,width,depth)
  for _,item in ipairs(items) do
    if item.advanced and cfg[item.key]==nil then cfg[item.key]=item.default end
    if not index(item.values,cfg[item.key]) then return end
  end
  for _,item in ipairs(town_numbers) do
    if cfg[item.key]==nil then cfg[item.key]=item.default end
    if not integer(cfg[item.key],item.min,item.max) then return end
  end
  return cfg
end
local function formspec(core,cfg,advanced,note)
  local esc=core.formspec_escape
  local out={"formspec_version[7]size[12.4,10.1]bgcolor[#101D2C;both;#101D2C]",
    "box[0,0;12.4,1.44;#173043]style_type[label;textcolor=#E6ECE6]",
    "style_type[button;border=false;bgimg=bl_button.png;bgimg_middle=6;textcolor=#F6F1DF]",
    "style_type[button:hovered;bgimg=bl_button_hover.png]",
    "style_type[label;font=bold;font_size=+6]label[.46,.46;Create your LuanTTD world]",
    "style_type[label;font=normal;font_size=]label[.46,1.02;Temperate transport  /  Choose a map]",
    "field[.49,2.15;4.42,.54;setup_seed;World seed;"..esc(tostring(cfg.seed)).."]",
    "field_close_on_enter[setup_seed;false]",
    "button[5.04,2.15;2.40,.54;setup_random;Randomize]",
  }
  out[#out+1]="button[8.43,2.03;3.47,.46;setup_advanced;"..
    (advanced and "Basic options" or "Advanced options").."]"
  local labels={"Map width (tiles)","Map depth (tiles)","Terrain relief","Sea level","Rivers","Town density","Town roads","Industry density","Tree placement"}
  local n=0
  out[#out+1]="dropdown[.49,2.82;7.16,.52;setup_scenario;"..scenario_labels..";"..
    index(scenarios,cfg.scenario)..";true]"
  if cfg.scenario~="original" then
    out[#out+1]="field[8.43,2.82;3.47,.52;setup_year;Starting year;"..esc(tostring(cfg.year)).."]"
    out[#out+1]="field_close_on_enter[setup_year;false]"
  end
  if cfg.scenario=="generated" then
    for i,item in ipairs(items) do
      if advanced==not not item.advanced then
        local x,y=n%2==0 and .49 or 6.43,3.59+math.floor(n/2)*(advanced and .84 or .76)
        out[#out+1]=("label[%g,%g;%s]dropdown[%g,%g;5.46,%g;setup_%s;%s;%d;true]")
          :format(x,y,item.advanced or labels[i],x,y+.20,advanced and .44 or .50,
            item.key,table.concat(item.labels,","),index(item.values,cfg[item.key]))
        n=n+1
      end
    end
    if not advanced then
      local big=cfg.width*cfg.depth>M.tested_playable_tiles
      out[#out+1]="label[6.43,6.91;"..
        (big and "High RAM use. May run out of memory." or "Larger maps need more RAM.").."]"
    else
      for _,item in ipairs(town_numbers) do
        local x,y=n%2==0 and .49 or 6.43,3.59+math.floor(n/2)*.84
        local label=item.key=="larger_towns" and item.label.." (0 = no cities)" or item.label
        out[#out+1]=("label[%g,%g;%s]field[%g,%g;5.46,.43;setup_%s;;%d]field_close_on_enter[setup_%s;false]")
          :format(x,y,label,x,y+.20,item.key,cfg[item.key],item.key)
        n=n+1
      end
      out[#out+1]="label[6.43,6.95;Custom count needs Custom density.]"
      out[#out+1]="label[6.43,7.30;No forced coast still allows inland water.]"
    end
  elseif cfg.scenario=="original" then
    out[#out+1]="label[.49,3.86;Survey map side length]"
    out[#out+1]="dropdown[.49,4.18;5.46,.50;setup_survey_size;64,128,256,512,1024,2048,4096;"..
      index(survey_sizes,cfg.survey_size)..";true]"
    out[#out+1]="label[.49,5.02;Fly and inspect the original terrain without a transport company.]"
    out[#out+1]="label[.49,5.60;Place a verified original-mapgen.bin in this world folder first.]"
  else
    out[#out+1]="label[.49,4.20;This scenario uses fixed terrain and industry sites.]"
    out[#out+1]="label[.49,4.83;Road, rail, harbor and air tools are available as usual.]"
  end
  out[#out+1]="box[.42,7.70;11.56,.025;#466277]"
  out[#out+1]="label[.49,8.03;"..esc(note or "Generate immediately using the selected parameters.").."]"
  out[#out+1]="label[.49,8.42;The game may reconnect once to load the finished world.]"
  out[#out+1]="button[.49,9.02;2.40,.60;setup_defaults;Reset options]"
  out[#out+1]="button[3.08,9.02;2.30,.60;setup_cancel;Cancel setup]"
  out[#out+1]="style[setup_generate;bgimg=bl_button_primary.png;textcolor=#101C2B]"
  out[#out+1]="button[7.62,9.02;4.28,.60;setup_generate;Generate world]"
  return table.concat(out)
end
function M.progress_form(core,title,pct,stage,detail)
  local esc=core.formspec_escape
  return "formspec_version[7]size[10,3.2]bgcolor[#111F2C;both;#111F2C]"..
    "style_type[label;textcolor=#EEE6C9]"..
    "label[.55,.58;"..esc(title).."]label[.55,1.20;"..esc(stage).."]"..
    ("label[8.75,1.20;%d%%]box[.55,1.62;8.9,.20;#314959]"):format(pct)..
    (pct>0 and ("box[.55,1.62;%g,.20;#67B6A0]"):format(8.9*pct/100) or "")..
    "label[.55,2.28;"..esc(detail or "Please wait. The game is still preparing your world.").."]"
end
function M.mount(core,storage,prepare)
  -- RC1 _ShowGenerateLandscape uses the interactive RNG, not the
  -- terrain generator's stream. Respect an explicit configured seed.
  local rng=PcgRandom(core.get_us_time()%2147483647)
  local function random() return M.random_seed(rng) end
  local draft=M.defaults(core.settings,random)
  local finished,advanced,busy=false,false,false
  local stage,percent="Starting the generator",0
  local progress_id="luanttd_core:generating_world"
  local function progress(p,detail)
    core.show_formspec(p:get_player_name(),progress_id,M.progress_form(core,
      "Generating your LuanTTD world",percent,stage,detail))
  end
  local function show(p,note)
    core.show_formspec(p:get_player_name(),M.form,formspec(core,draft,advanced,note))
  end
  core.register_on_joinplayer(function(p)
    p:set_pos({x=0,y=8,z=0})
    p:set_physics_override({speed=0,jump=0,gravity=0})
    p:hud_set_flags({hotbar=false,healthbar=false,crosshair=false,wielditem=false,breathbar=false,minimap=false})
    p:set_sky({type="plain",base_color="#132A3A",clouds=false})
    core.after(.2,function()
      if not p:is_player() or finished then return end
      if busy then progress(p) else show(p) end
    end)
  end)
  core.register_on_player_receive_fields(function(p,name,fields)
    if name==progress_id then
      if busy and fields.quit then
        local n=p:get_player_name()
        core.after(.06,function()
          local player=core.get_player_by_name(n)
          if player and busy then progress(player) end
        end)
      end
      return true
    end
    if name~=M.form then return false end
    if finished or busy then return true end
    if fields.setup_cancel then
      finished=true
      core.request_shutdown("World setup canceled. Nothing was generated.",false,.15)
      return true
    end
    local value,error_text=M.parse(draft,fields)
    if value then draft=value end
    if fields.setup_defaults then
      local seed=draft.seed
      draft=M.defaults(core.settings,function() return seed end)
      advanced=false;show(p)
    elseif fields.setup_advanced then
      if not value then show(p,error_text);return true end
      advanced=not advanced;show(p)
    elseif fields.setup_random then draft.seed=random();show(p)
    elseif fields.setup_generate then
      if not value then show(p,error_text);return true end
      if draft.scenario=="original" then
        local mask=io.open(core.get_worldpath().."/original-mapgen.bin","rb")
        if not mask then show(p,"See docs/original-terrain-exploration.md for the local terrain data.");return true end
        local data=mask:read(131073);mask:close()
        if not data or #data>131072 or
           core.sha256(data)~="7ff877ad58ebcdc15cb49824c5c2bab434b2c19d7e48319b38ad94434003f432" then
          show(p,"This file is not the supported OpenGFX 7.1 mask bank.");return true
        end
      end
      local function reconnect()
        busy=false;finished=true
        storage:set_string(M.storage_key,core.write_json(draft))
        core.request_shutdown("World prepared. Reopen this world once if Luanti returns to the menu.",true,.4)
      end
      if not prepare or draft.scenario~="generated" then reconnect();return true end
      busy=true;percent=0;stage="Starting the generator"
      local n=p:get_player_name()
      progress(p)
      local settled
      local function finish(ok,why)
        if settled then return end
        settled=true
        local player=core.get_player_by_name(n)
        if not ok then
          busy=false
          core.log("error","LuanTTD world generation failed: "..tostring(why))
          if player then
            core.close_formspec(n,progress_id)
            show(player,"Generation failed. Try a smaller map or different seed.")
          end
          return
        end
        percent=90;stage="Map generated and saved"
        if player then progress(player,"Reconnecting once to load the landscape.") end
        core.after(.65,reconnect)
      end
      local queued,why=prepare(draft,function(pct,description)
        if settled then return end
        percent=math.max(percent,pct);stage=description
        local player=core.get_player_by_name(n)
        if player then progress(player) end
      end,finish)
      if not queued then finish(false,why) end
    elseif (fields.setup_scenario or fields.setup_width or fields.setup_depth) and not fields.quit then show(p,error_text)
    elseif fields.quit then
      local n=p:get_player_name()
      core.after(.2,function()
        local player=core.get_player_by_name(n)
        if player and not finished then show(player) end
      end)
    end
    return true
  end)
end
return M
