class AqueductProbe extends AIController {
    function Require(ok, why) {
        if (!ok) throw why + ": " + AIError.GetLastErrorString();
    }

    function QuoteClear(tile) {
        local costs=AIAccounting();
        local test=AITestMode();
        Require(AITile.DemolishTile(tile),"Quote original clear");
        return costs.GetCosts();
    }

    function Operate(x,z,axis,distance,inside_a,inside_b) {
        local start=AIMap.GetTileIndex(x,z), step=axis==0 ? 1 : AIMap.GetMapSizeX();
        local finish=start+distance*step;
        local base=AITile.GetMinHeight(start);
        Require(AITile.GetSlope(start)==inside_a && AITile.GetSlope(finish)==inside_b &&
                AITile.GetMinHeight(finish)==base,"Stock seeded valley changed");
        for (local i=1;i<distance;i++) {
            local t=start+i*step;
            Require(AITile.GetMaxHeight(t)<=base,"Stock seeded valley clearance changed");
            Require(AITile.IsBuildable(t),"Proving dry inland middle land");
        }
        local before=QuoteClear(start)+QuoteClear(finish);
        Require(!AIBridge.BuildBridge(AIVehicle.VT_WATER,0,start+step,finish),
                "Stock allowed unsuitable non-opposite head");
        local costs=AIAccounting();
        Require(AIBridge.BuildBridge(AIVehicle.VT_WATER,0,finish,start),
                "Stock aqueduct build");
        local price=costs.GetCosts();
        Require(AIBridge.IsBridgeTile(start) && AIBridge.IsBridgeTile(finish) &&
                 AIBridge.GetOtherBridgeEnd(start)==finish && AIBridge.GetOtherBridgeEnd(finish)==start,
                "Stock aqueduct pairing");
        Require(!AIBridge.BuildBridge(AIVehicle.VT_WATER,0,start,finish),
                "Stock allowed a duplicate aqueduct");
        local type_id=AIBridge.GetBridgeID(start);
        costs.ResetCosts();
        Require(AIBridge.RemoveBridge(finish),"Stock aqueduct clear");
        local removal=costs.GetCosts();
        Require(!AIBridge.IsBridgeTile(start) && !AIBridge.IsBridgeTile(finish),
                "Stock aqueduct did not clear both heads");
        AILog.Info("AQUEDUCT_RESULT "+axis+" "+distance+" "+base+" "+inside_a+" "+inside_b+" "
                   +before+" "+price+" "+removal+" "+type_id);
    }

    function Start() {
        this.SetCommandDelay(1);
        Require(AICompany.SetLoanAmount(AICompany.GetMaxLoanAmount()),"Fund construction probe");
        Operate(238,142,0,4,12,3);
        Operate(168,31,1,2,9,6);
        AILog.Info("AQUEDUCT_DONE");
        while (true) this.Sleep(1000);
    }
}
