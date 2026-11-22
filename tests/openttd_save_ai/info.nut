class SaveProbeInfo extends AIInfo {
    function GetAuthor()       { return "LuanTTD test suite"; }
    function GetName()         { return "SaveProbe"; }
    function GetDescription()  { return "verify saved road tiles traversing two matched road forks."; }
    function GetVersion()      { return 1; }
    function GetDate()         { return "2026-11-22"; }
    function CreateInstance()  { return "SaveProbe"; }
    function GetShortName()    { return "SVQA"; }
    function GetAPIVersion()   { return "14"; }
}
RegisterAI(SaveProbeInfo());
