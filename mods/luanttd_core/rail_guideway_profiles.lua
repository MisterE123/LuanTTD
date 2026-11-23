-- SPDX-License-Identifier: GPL-2.0-only
-- Native presentation and admission profiles for mounted stock. Economics,
-- powered compatibility and introduction dates are still owned by the RC1 port.
local P={
  [2]={slug="mono",title="Monorail",engine=54,passenger=57,mail=58,
       engine_visual="x2001",passenger_visual="mono_passenger",mail_visual="mono_mail",
       offset=.746,pin_y=.095,pin_z=.454,suspension="mono_bogie",coupler="mono_drawbar"},
  [3]={slug="maglev",title="Maglev",engine=84,passenger=89,mail=90,
       engine_visual="lev1",passenger_visual="maglev_passenger",mail_visual="maglev_mail",
       offset=.713,pin_y=.094,pin_z=.455,suspension="maglev_suspension",coupler="maglev_drawbar"},
}
local M={by_gauge=P,gauges={2,3},by_engine={},by_stock={},visuals={}}
for gauge,p in pairs(P) do
  p.gauge=gauge
  p.stocks={p.engine,p.passenger,p.mail}
  M.by_engine[p.engine]=p
  for _,part in ipairs({"engine","passenger","mail"}) do
    local id,visual=p[part],p[part.."_visual"]
    M.by_stock[id]=p
    M.visuals[id]=visual
  end
end
return M
