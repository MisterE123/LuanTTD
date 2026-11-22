class YAPFProbeInfo extends AIInfo {
    function GetAuthor()       { return "LuanTTD test suite"; }
    function GetName()         { return "YAPFProbe"; }
    function GetDescription()  { return "Record a stock bus traversing two matched road forks."; }
    function GetVersion()      { return 1; }
    function GetDate()         { return "2026-11-22"; }
    function CreateInstance()  { return "YAPFProbe"; }
    function GetShortName()    { return "YYQA"; }
    function GetAPIVersion()   { return "14"; }
}
RegisterAI(YAPFProbeInfo());
