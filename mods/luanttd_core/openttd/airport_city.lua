-- SPDX-License-Identifier: GPL-2.0-only
-- OpenTTD contributors. Generated from the pinned 16.0-RC1 movement table.
local A={W=6,H=6,TILE=16,intro_year=1955,catchment_radius=5,
  hangar={x=5,z=0,dir=3,id=0},entries={[0]=26,29,27,28}}
local S={ALL=0,HANGAR=1,TERM1=2,TERM2=3,TERM3=4,TAKEOFF=10,STARTTAKEOFF=11,ENDTAKEOFF=12,
  HELITAKEOFF=13,FLYING=14,LANDING=15,ENDLANDING=16,HELILANDING=17,HELIENDLANDING=18,TERMGROUP=255}
local B={TERM1=1,TERM2=2,TERM3=4,RUNWAY=256,TAXIWAY=1024,OUT=2048,IN=4096,NOTHING=2^30}
local F={NOSPDCLAMP=1,TAKEOFF=2,SLOWTURN=4,LAND=8,EXACTPOS=16,BRAKE=32,HELI_RAISE=64,HELI_LOWER=128,HOLD=256}
A.state,A.block,A.flag=S,B,F
A.terminal_bits,A.terminal_states={B.TERM1,B.TERM2,B.TERM3},{S.TERM1,S.TERM2,S.TERM3}
A.block_bits={B.TERM1,B.TERM2,B.TERM3,B.RUNWAY,B.TAXIWAY,B.OUT,B.IN,B.NOTHING}
A.points={
  [0]={85,3,16,3},
  {85,22,0,0},
  {26,41,16,5},
  {56,22,16,3},
  {38,8,16,5},
  {65,6,0,0},
  {80,27,0,0},
  {44,63,0,0},
  {58,71,0,0},
  {72,85,0,0},
  {89,85,16,1},
  {3,85,1,0},
  {-79,85,3,0},
  {177,87,260,0},
  {89,87,264,0},
  {20,87,33,0},
  {20,87,0,0},
  {36,71,0,0},
  {160,87,260,0},
  {140,1,5,0},
  {257,1,260,0},
  {273,49,260,0},
  {44,63,64,0},
  {28,74,5,0},
  {28,74,128,0},
  {145,1,260,0},
  {-32,1,5,0},
  {300,-48,5,0},
  {140,-48,5,0},
  {-32,120,5,0},
}
A.layout={
  [0]={{1,1073741824,1},{10,2048,1},{0,0,1}},
  {{255,1024,0},{1,0,0},{3,0,6},{4,0,6},{0,0,7}},
  {{2,1,7},{10,2048,7},{0,0,7}},
  {{3,2,5},{10,2048,6},{0,0,6}},
  {{4,4,5},{10,2048,5},{0,0,5}},
  {{255,1024,0},{3,2,3},{4,4,4},{0,0,6}},
  {{255,1024,0},{3,2,3},{4,0,5},{1,0,1},{0,0,7}},
  {{255,1024,0},{2,1,2},{10,2048,8},{13,0,22},{1,0,1},{0,0,6}},
  {{0,2048,9}},
  {{0,256,10}},
  {{10,256,11}},
  {{11,1073741824,12}},
  {{12,1073741824,0}},
  {{14,1073741824,18},{15,0,14},{17,0,23}},
  {{15,256,15}},
  {{0,256,17}},
  {{0,256,17}},
  {{16,4096,7}},
  {{0,1073741824,25}},
  {{0,1073741824,20}},
  {{0,1073741824,21}},
  {{0,1073741824,13}},
  {{13,1073741824,0}},
  {{17,4096,24}},
  {{18,4096,17}},
  {{0,1073741824,20}},
  {{0,1073741824,19}},
  {{0,1073741824,28}},
  {{0,1073741824,19}},
  {{0,1073741824,26}},
}
local mod=core and core.get_modpath("luanttd_core") or "mods/luanttd_core"
return dofile(mod.."/openttd/airport_fta.lua")(A)
