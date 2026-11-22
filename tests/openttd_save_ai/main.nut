class SaveProbe extends AIController {
    function Require(ok, message) {
        if (!ok) throw message + ": " + AIError.GetLastErrorString();
    }

    function FixtureSite(cargo) {
        // Pin the stock seeded test world, not a player map.
        local x=96, y=173, origin=AIMap.GetTileIndex(x,y);
        local h=AITile.GetMinHeight(origin);
        for (local dy=-1; dy<=1; dy++) for (local dx=0; dx<=8; dx++) {
            local tile=AIMap.GetTileIndex(x+dx,y+dy);
            Require(AITile.IsBuildable(tile) && AITile.GetSlope(tile)==AITile.SLOPE_FLAT
                && AITile.GetMinHeight(tile)==h,"Seeded fixture site changed");
        }
        Require(AITile.GetCargoProduction(origin+3,cargo,1,1,3)>0 &&
            AITile.GetCargoAcceptance(origin+8,cargo,1,1,3)>=8,"Fixture town catchment changed");
        return origin;
    }

    function LogTerrain() {
        local count=0, hills=0;
        for (local z=1; z<AIMap.GetMapSizeY()-1; z+=17) {
            for (local x=1; x<AIMap.GetMapSizeX()-1; x+=11) {
                local tile=AIMap.GetTileIndex(x,z), slope=AITile.GetSlope(tile);
                if (slope!=AITile.SLOPE_FLAT) hills++;
                AILog.Info("SAVE_SLOPE "+tile+" "+AITile.GetMinHeight(tile)+" "+slope);
                count++;
            }
        }
        Require(hills>20 && count>100,"Need round-trip terrain samples");
    }

    function Start() {
        this.SetCommandDelay(1);
        AIRoad.SetCurrentRoadType(AIRoad.ROADTYPE_ROAD);
        local cargo=-1;
        local cargos=AICargoList();
        for (local c=cargos.Begin();!cargos.IsEnd();c=cargos.Next()) {
            if (AICargo.HasCargoClass(c,AICargo.CC_PASSENGERS)) { cargo=c;break; }
        }
        Require(cargo>=0,"Find stock passengers cargo");
        local a=FixtureSite(cargo), w=AIMap.GetMapSizeX(), d=a-w, b=a+8, s=a+3;
        Require(AIRoad.BuildRoadFull(a,b-1),"Build east-west road");
        Require(AIRoad.BuildRoadDepot(d,a),"Build depot");
        Require(AIRoad.BuildRoadFull(a,a+w),"Add depot frontage");
        Require(AIRoad.BuildRoadStation(b,b-1,AIRoad.ROADVEHTYPE_BUS,AIStation.STATION_NEW),
                "Build bay stop");
        Require(AIRoad.BuildDriveThroughRoadStation(s,s+1,AIRoad.ROADVEHTYPE_BUS,AIStation.STATION_NEW),
                "Build through stop");
        Require(AIRoad.IsRoadDepotTile(d) && AIRoad.IsRoadStationTile(b) && AIRoad.IsRoadStationTile(s),
                "Verify built road facilities");
        local owner=AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);
        AILog.Info("SAVE_DEPOT "+d+" "+AIRoad.GetRoadDepotFrontTile(d)+" "+owner);
        AILog.Info("SAVE_BAY "+b+" "+AIRoad.GetRoadStationFrontTile(b)+" "+AIStation.GetStationID(b)+" "+owner);
        AILog.Info("SAVE_THROUGH "+s+" "+AIStation.GetStationID(s)+" "+owner);
        for (local t=a; t<b; t++) {
            for (local i=0; i<4; i++) {
                local next=t+[-1, w, 1, -w][i];
                AILog.Info("SAVE_CONNECTED "+t+" "+next+" "+(AIRoad.AreRoadTilesConnected(t,next)?1:0));
            }
        }
        LogTerrain();
        local engine=-1;
        local engines=AIEngineList(AIVehicle.VT_ROAD);
        for (local e=engines.Begin();!engines.IsEnd();e=engines.Next()) {
            if (AIEngine.GetCargoType(e)==cargo) { engine=e;break; }
        }
        Require(engine>=0,"Find a road engine carrying passengers");
        local v=AIVehicle.BuildVehicle(d,engine);
        Require(AIVehicle.IsValidVehicle(v),"Build stock bus");
        Require(AIOrder.AppendOrder(v,s,AIOrder.OF_NON_STOP_INTERMEDIATE),"Order boarding stop");
        Require(AIOrder.AppendOrder(v,b,AIOrder.OF_NON_STOP_INTERMEDIATE),"Order bay stop");
        Require(AIVehicle.StartStopVehicle(v),"Dispatch stock bus");
        local in_flight=false;
        for (local i=0;i<6500;i++) {
            this.Sleep(1);
            local at=AIVehicle.GetLocation(v), load=AIVehicle.GetCargoLoad(v,cargo);
            if (at==s+2 && AIVehicle.GetState(v)==AIVehicle.VS_RUNNING && load>0) {
                AILog.Info("SAVE_BUS "+v+" "+at+" "+engine+" "+cargo+" "+load+" "
                    +AIStation.GetStationID(s)+" "+AIStation.GetStationID(b));
                in_flight=true;
                break;
            }
        }
        Require(in_flight,"Need a bus in flight carrying real passengers");
        AILog.Info("SAVE_DONE");
        while (true) this.Sleep(1000);
    }
}
