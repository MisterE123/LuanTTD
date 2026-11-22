-- Local fresh-world setup. Persist only world generation options here; the
-- campaign is deliberately not constructed until the next game launch.
local M={form="bayline:world_setup",storage_key="world_setup_v1"}
local items={
  {key="size",setting="bayline_generated_map_size",default=64,values={64,128},labels={"64 x 64","128 x 128"}},
  {key="relief",setting="bayline_generated_relief",default=1,values={0,1,2,3,4},
    labels={"Very flat","Flat","Hilly","Mountainous","Alpinist"}},
  {key="sea",setting="bayline_generated_sea",default=0,values={0,1,2,3},
    labels={"Very low","Low","Medium","High"}},
  {key="rivers",setting="bayline_generated_rivers",default=0,values={0,1,2,3},
    labels={"None","Few","Normal","Many"}},
  {key="towns",setting="bayline_generated_towns",default=2,values={0,1,2,3},
    labels={"Very low","Low","Normal","High"}},
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
  {key="variety",setting="bayline_generated_variety",default=0,values={0,1,2,3,4,5},
    labels={"None","Very low","Low","Medium","High","Very high"},advanced="Regional variety"},
}
local function index(values,v)
  for i,value in ipairs(values) do if value==v then return i end end
end
local function integer(n,low,high)
  return type(n)=="number" and n==math.floor(n) and n>=low and n<=high
end
function M.defaults(settings)
  local seed=tonumber(settings:get("bayline_seed"))
  local out={seed=integer(seed,0,4294967295) and seed or 1751}
  for _,item in ipairs(items) do
    local v=settings:get(item.setting)
    if type(item.default)=="number" then v=tonumber(v) end
    out[item.key]=index(item.values,v) and v or item.default
  end
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
  local seed=tonumber(fields.setup_seed or current.seed)
  if not integer(seed,0,4294967295) then return nil,"Enter a whole-number seed from 0 to 4,294,967,295." end
  out.seed=seed
  return out
end
function M.read(core,storage)
  local raw=storage:get_string(M.storage_key)
  if raw=="" then return end
  local cfg=core.parse_json(raw,nil,true)
  if type(cfg)~="table" or not integer(cfg.seed,0,4294967295) then return end
  for _,item in ipairs(items) do
    if item.advanced and cfg[item.key]==nil then cfg[item.key]=item.default end
    if not index(item.values,cfg[item.key]) then return end
  end
  return cfg
end
local function formspec(core,cfg,advanced,note)
  local esc=core.formspec_escape
  local out={"formspec_version[7]size[12.4,9.1]bgcolor[#101D2C;both;#101D2C]",
    "box[0,0;12.4,1.44;#173043]style_type[label;textcolor=#E6ECE6]",
    "style_type[button;border=false;bgimg=bl_button.png;bgimg_middle=6;textcolor=#F6F1DF]",
    "style_type[button:hovered;bgimg=bl_button_hover.png]",
    "style_type[label;font=bold;font_size=+6]label[.46,.46;Create your LuanTTD world]",
    "style_type[label;font=normal;font_size=]label[.46,1.02;OpenTTD 14.1 TerraGenesis  /  Temperate]",
    "field[.49,2.15;4.42,.54;setup_seed;World seed;"..esc(tostring(cfg.seed)).."]",
    "field_close_on_enter[setup_seed;false]",
    "button[5.04,2.15;2.40,.54;setup_random;Randomize]",
  }
  out[#out+1]="button[8.43,2.15;3.47,.54;setup_advanced;"..
    (advanced and "Basic options" or "Landscape options").."]"
  local labels={"Map size","Terrain relief","Sea level","Rivers","Town density","Town roads","Industry density","Tree placement"}
  local n=0
  for i,item in ipairs(items) do
    if advanced==not not item.advanced then
      local x,y=n%2==0 and .49 or 6.43,3.02+math.floor(n/2)*.89
      out[#out+1]=("label[%g,%g;%s]dropdown[%g,%g;5.46,.52;setup_%s;%s;%d;true]")
        :format(x,y,item.advanced or labels[i],x,y+.20,item.key,table.concat(item.labels,","),index(item.values,cfg[item.key]))
      n=n+1
    end
  end
  if advanced then
    out[#out+1]="label[.49,5.07;Choose which edges to shape into sea, or let TerraGenesis choose.]"
    out[#out+1]="label[.49,5.51;No forced coast still allows inland water and sea-level terrain.]"
  end
  out[#out+1]="box[.42,6.70;11.56,.025;#466277]"
  out[#out+1]="label[.49,7.03;"..esc(note or "Save your choices below, then reopen this same world.").."]"
  out[#out+1]="label[.49,7.42;The next Play generates the world using these settings.]"
  out[#out+1]="button[.49,8.02;2.40,.60;setup_defaults;Reset options]"
  out[#out+1]="button[3.08,8.02;2.30,.60;setup_cancel;Cancel setup]"
  out[#out+1]="style[setup_generate;bgimg=bl_button_primary.png;textcolor=#101C2B]"
  out[#out+1]="button[7.62,8.02;4.28,.60;setup_generate;Save and return]"
  return table.concat(out)
end
function M.mount(core,storage)
  local draft=M.defaults(core.settings)
  local finished,advanced=false,false
  local rng=PcgRandom(core.get_us_time()%2147483647)
  local function show(p,note)
    core.show_formspec(p:get_player_name(),M.form,formspec(core,draft,advanced,note))
  end
  core.register_on_joinplayer(function(p)
    p:set_pos({x=0,y=8,z=0})
    p:set_physics_override({speed=0,jump=0,gravity=0})
    p:hud_set_flags({hotbar=false,healthbar=false,crosshair=false,wielditem=false,breathbar=false,minimap=false})
    p:set_sky({type="plain",base_color="#132A3A",clouds=false})
    core.after(.2,function()
      if p:is_player() and not finished then show(p) end
    end)
  end)
  core.register_on_player_receive_fields(function(p,name,fields)
    if name~=M.form then return false end
    if finished then return true end
    if fields.setup_cancel then
      finished=true
      core.request_shutdown("World setup canceled. Nothing was generated.",false,.15)
      return true
    end
    local value,error_text=M.parse(draft,fields)
    if value then draft=value end
    if fields.setup_defaults then draft=M.defaults(core.settings);show(p)
    elseif fields.setup_advanced then
      if not value then show(p,error_text);return true end
      advanced=not advanced;show(p)
    elseif fields.setup_random then draft.seed=rng:next(0,2147483646);show(p)
    elseif fields.setup_generate then
      if not value then show(p,error_text);return true end
      finished=true
      storage:set_string(M.storage_key,core.write_json(draft))
      core.request_shutdown("World options saved. Start this same world again to generate it.",true,.15)
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
