/*******************************************************/
/*                                                     */
/*           DON`T USE THIS IN PRODUCTION!             */
/*                                                     */
/*  Choose one (steamworks or system2) what you like   */
/*                                                     */
/*******************************************************/

//To do
// Music Stop -> https://github.com/AgentWesker/StopMusic

#define DEBUG

#pragma semicolon 1
#pragma newdecls required

// require extensions
#include <clientprefs>
#include <system2>

// cg test function (options)
#include <cg_core>
#include <store>

// other library
#undef REQUIRE_PLUGIN
#include <mapmusic>

//#define DEBUG
#define PREFIX            "[\x10Music\x01]  "
#define SEARCH            "https://csgogamers.com/musicserver/api/search.php?s="
#define LYRICS            "https://csgogamers.com/musicserver/api/lyrics.php?id="
#define PLAYER            "https://csgogamers.com/musicserver/api/player.php?id="
#define logFile           "addons/sourcemod/logs/advmusicplayer.log"
#define PLAYALL           0

float g_fNextPlay;
bool g_bMapMusicLib;

bool g_bLyrics[MAXPLAYERS+1];
bool g_bDiable[MAXPLAYERS+1];
bool g_bBanned[MAXPLAYERS+1];
bool g_bListen[MAXPLAYERS+1];
bool g_bPlayed[MAXPLAYERS+1];
int  g_iVolume[MAXPLAYERS+1];
int  g_iBGMVol[MAXPLAYERS+1];
int  g_iSelect[MAXPLAYERS+1];

enum songinfo
{
    iSongId,
    String:szName[128],
    String:szSinger[64],
    String:szAlbum[64],
    Float:fLength
}

songinfo g_Sound[MAXPLAYERS+1][songinfo];
Handle g_tTimer[MAXPLAYERS+1];

Handle g_cDisable;
Handle g_cVolume;
Handle g_cBanned;
Handle g_cBGMVol;
Handle g_cLyrics;

ArrayList array_timer[MAXPLAYERS+1];
ArrayList array_lyric[MAXPLAYERS+1];

public Plugin myinfo = 
{
    name        = "Advance Music Player",
    author      = "Kyle",
    description = "Media System , Powered by CG Community",
    version     = "1.1.<commit_count>.<commit_branch> - <commit_date>",
    url         = "https://ump45.moe"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    MarkNativeAsOptional("MapMusic_SetVolume");

    return APLRes_Success;
}

public void OnPluginStart()
{
    g_cDisable = RegClientCookie("media_disable", "", CookieAccess_Private);
    g_cVolume  = RegClientCookie("media_volume",  "", CookieAccess_Private);
    g_cBanned  = RegClientCookie("media_banned",  "", CookieAccess_Private);
    g_cBGMVol  = RegClientCookie("media_bgmvol",  "", CookieAccess_Private);
    g_cLyrics  = RegClientCookie("media_lyrics",  "", CookieAccess_Private);

    RegConsoleCmd("sm_music",        Command_Music);
    RegConsoleCmd("sm_dj",           Command_Music);
    RegConsoleCmd("sm_stop",         Command_Music);
    RegConsoleCmd("sm_stopmusic",    Command_Music);
    RegConsoleCmd("sm_mapmusic",     Command_Music);

    RegAdminCmd("sm_adminmusicstop", Command_AdminStop, ADMFLAG_BAN);
    RegAdminCmd("sm_musicban",       Command_MusicBan,  ADMFLAG_BAN);

    for(int index = 0; index <= MaxClients; ++index)
    {
        array_timer[index] = new ArrayList();
        array_lyric[index] = new ArrayList(ByteCountToCells(128));
    }

    UTIL_CheckDirector();

    for(int client = 1; client <= MaxClients; ++client)
        if(IsValidClient(client))
        {
            OnClientConnected(client);
            if(AreClientCookiesCached(client))
                OnClientCookiesCached(client);
        }
}

public void OnMapStart()
{
    g_bMapMusicLib = LibraryExists("MapMusic");
}

public void OnLibraryAdded(const char[] name)
{
    if(strcmp(name, "MapMusic") == 0)
        g_bMapMusicLib = true;
}

public void OnLibraryRemoved(const char[] name)
{
    if(strcmp(name, "MapMusic") == 0)
        g_bMapMusicLib = false;
}

public void OnMapEnd()
{
    g_fNextPlay = 0.0;
    g_tTimer[PLAYALL] = INVALID_HANDLE;
    g_Sound[PLAYALL][iSongId] = 0;
    g_Sound[PLAYALL][fLength] = 0.0;
    g_Sound[PLAYALL][szName][0] = '\0';
    g_Sound[PLAYALL][szSinger][0] = '\0';
    g_Sound[PLAYALL][szAlbum][0] = '\0';
    array_timer[PLAYALL].Clear();
    array_lyric[PLAYALL].Clear();
}

public void OnClientConnected(int client)
{
    g_bPlayed[client] = false;
    g_bDiable[client] = false;
    g_bBanned[client] = false;
    g_bListen[client] = false;
    g_bLyrics[client] = true;
    g_iVolume[client] = 100;
    g_iBGMVol[client] = 100;
}

public void OnClientDisconnect(int client)
{
    while(GetArraySize(array_timer[client]))
    {
        Handle timer = array_timer[client].Get(0);
        KillTimer(timer);
        array_timer[client].Erase(0);
    }
    
    array_lyric[client].Clear();

    if(g_tTimer[client] != INVALID_HANDLE)
        KillTimer(g_tTimer[client]);
    g_tTimer[client] = INVALID_HANDLE;

    g_bPlayed[client] = false;
}

public void OnClientCookiesCached(int client)
{
    char buf[5][4];
    GetClientCookie(client, g_cDisable, buf[0], 4);
    GetClientCookie(client, g_cVolume,  buf[1], 4);
    GetClientCookie(client, g_cBanned,  buf[2], 4);
    GetClientCookie(client, g_cBGMVol,  buf[3], 4);
    GetClientCookie(client, g_cLyrics,  buf[4], 4);

    g_bDiable[client] = (StringToInt(buf[0]) ==  1);
    g_iVolume[client] = (StringToInt(buf[1]) >= 10) ? StringToInt(buf[1]) : 65;
    g_bBanned[client] = (StringToInt(buf[2]) ==  1);
    g_iBGMVol[client] = (strlen(buf[3]) >= 2) ? StringToInt(buf[3]) : 100;
    g_bLyrics[client] = (StringToInt(buf[4]) != 1);

    if(g_bMapMusicLib)
        MapMusic_SetVolume(client, g_iBGMVol[client]);
}

public Action Command_Music(int client, int args)
{
    if(!IsValidClient(client))
        return Plugin_Handled;

    DisplayMainMenu(client);

    return Plugin_Handled;
}

public Action Command_AdminStop(int client, int args)
{
    UTIL_ClearMotdAll();

    // notify sound end
    CreateTimer(0.1, Timer_SoundEnd);

    PrintToChatAll("%s \x02权限X强行停止了音乐播放!", PREFIX);

    while(GetArraySize(array_timer[PLAYALL]))
    {
        Handle timer = array_timer[PLAYALL].Get(0);
        KillTimer(timer);
        array_timer[PLAYALL].Erase(0);
    }

    for(int i = 1; i <= MaxClients; ++i)
        if(IsClientInGame(i) && g_bPlayed[i])
            UTIL_LyricHud(i, ">>> 歌曲已停止播放 <<<");
}

public Action Command_MusicBan(int client, int args)
{
    if(args < 1)
        return Plugin_Handled;

    char buffer[16];
    GetCmdArg(1, buffer, 16);
    int target = FindTarget(client, buffer, true);

    if(!IsValidClient(target))
        return Plugin_Handled;

    g_bBanned[target] = !g_bBanned[target];
    SetClientCookie(target, g_cBanned, g_bBanned[target] ? "1" : "0");
    PrintToChatAll("%s \x02%N\x01%s", PREFIX, target, g_bBanned[target] ? "因为乱玩点歌系统,已被\x07封禁\x01点歌权限" : "点歌权限已被\x04解禁");

    return Plugin_Handled;
}

void DisplayMainMenu(int client)
{
    Handle menu = CreateMenu(MenuHanlder_Main);
    
    if(g_Sound[client][iSongId] > 0)
        SetMenuTitle(menu, "正在播放▼\n \n歌名: %s\n歌手: %s\n专辑: %s\n ", g_Sound[client][szName], g_Sound[client][szSinger], g_Sound[client][szAlbum]); 
    else
        SetMenuTitle(menu, "[多媒体系统]  主菜单\n ");

    AddMenuItemEx(menu, g_bPlayed[client] ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT, "search",  "搜索音乐");
    AddMenuItemEx(menu, ITEMDRAW_DEFAULT, "toggle", "点歌接收: %s", g_bDiable[client] ? "关" : "开");
    AddMenuItemEx(menu, ITEMDRAW_DEFAULT, "lyrics", "歌词显示: %s", g_bLyrics[client] ? "开" : "关");
    AddMenuItemEx(menu, ITEMDRAW_DEFAULT, "volume", "点歌音量: %d", g_iVolume[client]);
    AddMenuItemEx(menu, ITEMDRAW_DEFAULT, "stop",   "停止播放");
    AddMenuItemEx(menu, g_bMapMusicLib ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED, "mapbgm", "地图音量: %d", g_iBGMVol[client]);

    DisplayMenu(menu, client, 30);
}

public int MenuHanlder_Main(Handle menu, MenuAction action, int client, int itemNum)
{
    if(action == MenuAction_Select)
    {
        char info[32];
        GetMenuItem(menu, itemNum, info, 32);

        bool reply = true;

        if(strcmp(info, "search") == 0)
        {
            if(g_bBanned[client])
            {
                PrintToChat(client, "%s  \x10你点歌权限被BAN了", PREFIX);
                return;
            }

            reply = false;
            g_bListen[client] = true;
            PrintToChat(client, "%s  按Y输入 歌名( - 歌手) [小括号内选填]", PREFIX);
        }
        else if(strcmp(info, "toggle") == 0)
        {
            g_bDiable[client] = !g_bDiable[client];
            SetClientCookie(client, g_cDisable, g_bDiable[client] ? "1" : "0");
            PrintToChat(client, "%s  \x10点歌接收已%s", PREFIX, g_bDiable[client] ? "\x07关闭" : "\x04开启");
            if(g_bDiable[client] && g_bPlayed[client])
            {
                CG_RemoveMotd(client);
                g_bPlayed[client] = false;
                UTIL_ClearLyric(client);
            }
        }
        else if(strcmp(info, "lyrics") == 0)
        {
            g_bLyrics[client] = !g_bLyrics[client];
            SetClientCookie(client, g_cLyrics, g_bLyrics[client] ? "1" : "0");
            PrintToChat(client, "%s  \x10歌词显示已%s", PREFIX, g_bLyrics[client] ? "\x04开启" : "\x07关闭");
        }
        else if(strcmp(info, "volume") == 0)
        {
            switch(g_iVolume[client])
            {
                case 100: g_iVolume[client] =  90;
                case  90: g_iVolume[client] =  80;
                case  80: g_iVolume[client] =  70;
                case  70: g_iVolume[client] =  60;
                case  60: g_iVolume[client] =  50;
                case  50: g_iVolume[client] =  40;
                case  40: g_iVolume[client] =  30;
                case  30: g_iVolume[client] =  20;
                case  20: g_iVolume[client] =  10;
                case  10: g_iVolume[client] = 100;
                default : g_iVolume[client] = 100;
            }
            PrintToChat(client, "%s  \x10音量设置将在下次播放时生效", PREFIX);
        }
        else if(strcmp(info, "stop") == 0)
        {
            UTIL_StopMusic(client);
            PrintToChat(client, "%s  \x04音乐已停止播放", PREFIX);
        }
        else if(strcmp(info, "mapbgm") == 0)
        {
            if(g_bMapMusicLib)
            {
                if(g_iBGMVol[client] >= 10)
                    g_iBGMVol[client] -= 10;
                else
                    g_iBGMVol[client] = 100;
                
                MapMusic_SetVolume(client, g_iBGMVol[client]);
            }
            else
                PrintToChat(client, "%s  \x04MapMusic库不存在,请联系管理员", PREFIX);
        }

        if(reply) DisplayMainMenu(client);
    }
    else if(action == MenuAction_End)
        CloseHandle(menu);
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
    if(!client || !g_bListen[client])
        return Plugin_Continue;

    g_bListen[client] = false;

    if(g_bBanned[client])
    {
        PrintToChat(client, "%s  \x07你已被封禁点歌", PREFIX);
        return Plugin_Stop;
    }

    if(Store_GetClientCredits(client) < 1000)
    {
        PrintToChat(client, "%s  \x07你的信用点不足\x041000\x07!", PREFIX);
        return Plugin_Stop;
    }

    PrintToChat(client, "%s  \x04正在搜索音乐(当前引擎: 网易云音乐)", PREFIX);

    char url[256];
    FormatEx(url, 256, "%s%s", SEARCH, sArgs);
    ReplaceString(url, 256, " ", "+", false);

#if defined DEBUG
    UTIL_DebugLog("OnClientSayCommand -> %N -> %s -> %s", client, sArgs, url);
#endif

    char path[128];
    BuildPath(Path_SM, path, 128, "data/music/search_%d.kv", GetClientUserId(client));
    System2_DownloadFile(API_SearchMusic, url, path, GetClientUserId(client));
    /*
    System2 3.0 New API
    System2HTTPRequest request = new System2HTTPRequest(url, API_SearchMusic);
    request.SetProgressCallback(API_SearchMusic);
    request.SetURL(url);
    request.SetOutputFile(path);
    request.AutoClean = true;
    request.Timeout = 4000;
    request.Any = GetClientUserId(client);
    request.GET();
    */
    return Plugin_Stop;
}

/*
    System2 3.0 New API
public void API_SearchMusic(bool success, System2HTTPRequest request, System2HTTPResponse response)
{
    if(!success)
        LogError("System2 -> API_SearchMusic -> Download result Error");
    else
        UTIL_ProcessResult(request.Any);
}
*/
public void API_SearchMusic(bool finished, const char[] error, float dltotal, float dlnow, float ultotal, float ulnow, int userid)
{
    if(finished)
    {
        if(!StrEqual(error, ""))
        {
            LogError("System2 -> API_SearchMusic -> Download result Error: %s", error);
            return;
        }

        UTIL_ProcessResult(userid);
    }
}

void UTIL_ProcessResult(int userid)
{
    int client = GetClientOfUserId(userid);
    
    if(!IsValidClient(client))
        return;

    KeyValues _kv = new KeyValues("songs");
    
    char path[128];
    BuildPath(Path_SM, path, 128, "data/music/search_%d.kv", userid);
   
    if(!FileExists(path))
    {
        delete _kv;
        LogError("UTIL_ProcessResult -> Download error!");
        return;
    }

    if(!_kv.ImportFromFile(path))
    {
        delete _kv;
        LogError("UTIL_ProcessResult -> Import error!");
        return;
    }

    if(!_kv.GotoFirstSubKey(true))
    {
        delete _kv;
        LogError("UTIL_ProcessResult -> No result!");
        return;
    }

    Handle menu = CreateMenu(MenuHandler_DisplayList);
    int count = 0;
    
    do
    {
        char key[32], name[64], arlist[128], album[128];

        _kv.GetSectionName(key, 32);
        _kv.GetString("name", name, 32);

        if(_kv.JumpToKey("ar"))
        {
            if(_kv.GotoFirstSubKey(true))
            {
                do
                {
                    char ar[32];
                    _kv.GetString("name", ar, 32);
                    if(arlist[0] != '\0')
                        Format(arlist, 128, "%s/%s", arlist, ar);
                    else
                        FormatEx(arlist, 128, "%s", ar);
                } while (_kv.GotoNextKey(true));
                _kv.GoBack();
            }
            _kv.GoBack();
        }
        else
            strcopy(arlist, 128, "unnamed");

        if(_kv.JumpToKey("al"))
        {
            _kv.GetString("name", album, 128);
            _kv.GoBack();
        }
        else
            strcopy(album, 128, "unknown");

        AddMenuItemEx(menu, ITEMDRAW_DEFAULT, key, "%s\n歌手: %s\n专辑: %s", name, arlist, album);
        if(++count % 5 == 0)
            AddMenuItem(menu, "0", "0", ITEMDRAW_SPACER);
    } while (_kv.GotoNextKey(true));

    SetMenuTitle(menu, "[CG] 音乐搜索结果 (找到 %d 首单曲)\n ", count);
    DisplayMenu(menu, client, 60);

    delete _kv;
}

public int MenuHandler_DisplayList(Handle menu, MenuAction action, int client, int itemNum)
{
    if(action == MenuAction_Select) 
    {
        g_iSelect[client] = itemNum;

        char path[128];
        BuildPath(Path_SM, path, 128, "data/music/search_%d.kv", GetClientUserId(client));
        
        KeyValues _kv = new KeyValues("songs");
        _kv.ImportFromFile(path);

        char key[32];
        IntToString(itemNum, key, 32);
        _kv.JumpToKey(key, true);

        char name[128];
        _kv.GetString("name", name, 128);

        int length = _kv.GetNum("dt")/1000;

        char arlist[64];
        if(_kv.JumpToKey("ar"))
        {
            if(_kv.GotoFirstSubKey(true))
            {
                do
                {
                    char ar[32];
                    _kv.GetString("name", ar, 32);
                    if(arlist[0] != '\0')
                        Format(arlist, 64, "%s/%s", arlist, ar);
                    else
                        FormatEx(arlist, 64, "%s", ar);
                } while (_kv.GotoNextKey(true));
                _kv.GoBack();
            }
            _kv.GoBack();
        }
        else
            strcopy(arlist, 64, "unnamed");
        
        char album[64];
        if(_kv.JumpToKey("al"))
        {
            _kv.GetString("name", album, 128);
            _kv.GoBack();
        }
        else
            strcopy(album, 128, "unknown");
        
        delete _kv;

        int cost = RoundFloat(length*2.0);
        if(Store_GetClientCredits(client) < cost)
        {
            PrintToChat(client, "%s  \x07你的信用点不足\x04%d\x07!", PREFIX, cost);
            return;
        }

        DisplayConfirmMenu(client, cost, name, arlist, album, length);
    }
    else if(action == MenuAction_End)
        CloseHandle(menu);
}

void DisplayConfirmMenu(int client, int cost, const char[] name, const char[] arlist, const char[] album, int time)
{
    Handle menu = CreateMenu(MenuHandler_Confirm);
    SetMenuTitle(menu, "您确定要点播以下歌曲吗\n ");
    
    AddMenuItemEx(menu, ITEMDRAW_DISABLED, " ", "歌名: %s", name);
    AddMenuItemEx(menu, ITEMDRAW_DISABLED, " ", "歌手: %s", arlist);
    AddMenuItemEx(menu, ITEMDRAW_DISABLED, " ", "专辑: %s", album);
    AddMenuItemEx(menu, ITEMDRAW_DISABLED, " ", "时长: %d分%d秒\n ", time/60, time%60);

    AddMenuItemEx(menu, ITEMDRAW_DEFAULT, "1", "所有人[花费: %d信用点]", cost);
    AddMenuItemEx(menu, ITEMDRAW_DEFAULT, "2", "自己听[免费]");

    DisplayMenu(menu, client, 15);
}

public int MenuHandler_Confirm(Handle menu, MenuAction action, int client, int itemNum)
{
    if(action ==  MenuAction_Select)
    {
        char info[32];
        GetMenuItem(menu, itemNum, info, 32);

        if(StringToInt(info) == 1)
            UTIL_InitPlayer(client);
        else if(StringToInt(info) == 2)
            UTIL_ListenMusic(client);
    }
    else if(action == MenuAction_End)
        CloseHandle(menu);
}

void UTIL_ListenMusic(int client)
{
    if(g_bBanned[client])
    {
        PrintToChat(client, "%s  \x07你已被封禁点歌", PREFIX);
        return;
    }

    OnClientDisconnect(client);

    char path[128];
    BuildPath(Path_SM, path, 128, "data/music/search_%d.kv", GetClientUserId(client));
    
    KeyValues _kv = new KeyValues("songs");
    _kv.ImportFromFile(path);

    char key[32];
    IntToString(g_iSelect[client], key, 32);
    
    _kv.JumpToKey(key, true);

    _kv.GetString("name", g_Sound[client][szName], 128);

    g_Sound[client][iSongId] = _kv.GetNum("id");
    g_Sound[client][fLength] = _kv.GetNum("dt")*0.001;

    if(_kv.JumpToKey("ar"))
    {
        if(_kv.GotoFirstSubKey(true))
        {
            do
            {
                char ar[32];
                _kv.GetString("name", ar, 32);
                if(g_Sound[client][szSinger][0] != '\0')
                    Format(g_Sound[client][szSinger], 64, "%s/%s", g_Sound[client][szSinger], ar);
                else
                    FormatEx(g_Sound[client][szSinger], 64, "%s", ar);
            } while (_kv.GotoNextKey(true));
            _kv.GoBack();
        }
        _kv.GoBack();
    }
    else
        strcopy(g_Sound[client][szSinger], 64, "unnamed");
    
    if(_kv.JumpToKey("al"))
    {
        _kv.GetString("name", g_Sound[client][szAlbum], 64);
        _kv.GoBack();
    }
    else
        strcopy(g_Sound[client][szAlbum], 64, "unknown");

    delete _kv;

#if defined DEBUG
    UTIL_DebugLog("UTIL_InitPlayer -> %N -> %s -> %d -> %.2f", client, g_Sound[client][szName], g_Sound[client][iSongId], g_Sound[client][fLength]);
#endif

    g_iSelect[client] = g_Sound[client][iSongId];

    char murl[192];
    FormatEx(murl, 192, "%s%d&volume=%d", PLAYER, g_Sound[client][iSongId], g_iVolume[client]);
    CG_ShowHiddenMotd(client, murl);

    if(g_bLyrics[client])
        CreateTimer(0.1, Timer_GetLyric, client, TIMER_FLAG_NO_MAPCHANGE);

    g_tTimer[client] = CreateTimer(g_Sound[client][fLength]+0.1, Timer_SoundEnd, client);
    
    PrintToChatAll("%s  \x04%N\x01正在收听[\x10%s\x01]", PREFIX, client, g_Sound[client][szName]);
    
    DisplayMainMenu(client);
}

void UTIL_InitPlayer(int client)
{
    if(GetGameTime() < g_fNextPlay)
    {
        PrintToChat(client, "%s  \x10上次点歌未过期,请等待时间结束", PREFIX);
        return;
    }
    
    if(g_bBanned[client])
    {
        PrintToChat(client, "%s  \x07你已被封禁点歌", PREFIX);
        return;
    }

    char path[128];
    BuildPath(Path_SM, path, 128, "data/music/search_%d.kv", GetClientUserId(client));
    
    KeyValues _kv = new KeyValues("songs");
    _kv.ImportFromFile(path);

    char key[32];
    IntToString(g_iSelect[client], key, 32);
    
    _kv.JumpToKey(key, true);

    _kv.GetString("name", g_Sound[PLAYALL][szName], 128);

    g_Sound[PLAYALL][iSongId] = _kv.GetNum("id");
    g_Sound[PLAYALL][fLength] = _kv.GetNum("dt")*0.001;

    if(_kv.JumpToKey("ar"))
    {
        if(_kv.GotoFirstSubKey(true))
        {
            do
            {
                char ar[32];
                _kv.GetString("name", ar, 32);
                if(g_Sound[PLAYALL][szSinger][0] != '\0')
                    Format(g_Sound[PLAYALL][szSinger], 64, "%s/%s", g_Sound[PLAYALL][szSinger], ar);
                else
                    FormatEx(g_Sound[PLAYALL][szSinger], 64, "%s", ar);
            } while (_kv.GotoNextKey(true));
            _kv.GoBack();
        }
        _kv.GoBack();
    }
    else
        strcopy(g_Sound[PLAYALL][szSinger], 64, "unnamed");
    
    if(_kv.JumpToKey("al"))
    {
        _kv.GetString("name", g_Sound[PLAYALL][szAlbum], 64);
        _kv.GoBack();
    }
    else
        strcopy(g_Sound[PLAYALL][szAlbum], 64, "unknown");
    
    delete _kv;

#if defined DEBUG
    UTIL_DebugLog("UTIL_InitPlayer -> %N -> %s -> %d -> %.2f", client, g_Sound[PLAYALL][szName], g_Sound[PLAYALL][iSongId], g_Sound[PLAYALL][fLength]);
#endif

    char reason[128];
    FormatEx(reason, 128, "点歌系统点歌[%d.%s]", g_Sound[PLAYALL][iSongId], g_Sound[PLAYALL][szName]);
    int cost = RoundFloat(g_Sound[PLAYALL][fLength]*2.0);
    Store_SetClientCredits(client, Store_GetClientCredits(client) - cost, reason);
    PrintToChat(client, "%s  \x04您支付了\x10%d\x04信用点来点播[\x0C%s\x04].", PREFIX, cost, g_Sound[PLAYALL][szName]);
    PrintToChatAll("%s \x04%N\x01点播歌曲[\x0C%s\x01]", PREFIX, client, g_Sound[PLAYALL][szName]);
    LogToFileEx(logFile, "\"%L\" 点播了歌曲[%s - %s]", client, g_Sound[PLAYALL][szName],  g_Sound[PLAYALL][szSinger]);

    g_fNextPlay = GetGameTime()+g_Sound[PLAYALL][fLength];

    for(int i = 1; i <= MaxClients; ++i)
    {
        g_bListen[i] = false;

        if(!IsValidClient(i))
            continue;
        
        if(g_bDiable[i])
            continue;
        
        OnClientDisconnect(i);
        g_bPlayed[i] = true;
        g_Sound[i] = g_Sound[PLAYALL];

        char murl[192];
        FormatEx(murl, 192, "%s%d&volume=%d", PLAYER, g_Sound[PLAYALL][iSongId], g_iVolume[i]);
        DisplayMainMenu(i);
        CG_ShowHiddenMotd(i, murl);

#if defined DEBUG
        UTIL_DebugLog("UTIL_InitPlayer -> %N -> %s", i, murl);
#endif
    }

    g_iSelect[PLAYALL] = g_Sound[PLAYALL][iSongId];
    CreateTimer(0.1, Timer_GetLyric, PLAYALL, TIMER_FLAG_NO_MAPCHANGE);
    g_tTimer[PLAYALL] = CreateTimer(g_Sound[PLAYALL][fLength]+0.1, Timer_SoundEnd, PLAYALL);
}

public Action Timer_SoundEnd(Handle timer, int index)
{
    g_Sound[index][iSongId] = 0;
    g_Sound[index][fLength] = 0.0;
    g_Sound[index][szName][0] = '\0';
    g_Sound[index][szSinger][0] = '\0';
    g_Sound[index][szAlbum][0] = '\0';
    
    g_tTimer[index] = INVALID_HANDLE;

    if(index == 0)
        for(int i = 1; i <= MaxClients; ++i)
        {
            g_bPlayed[i] = false;
            g_Sound[i][iSongId] = 0;
            if(IsClientInGame(i) && !g_bDiable[i] && g_bPlayed[i] && g_bLyrics[i])
                UTIL_LyricHud(i, ">>> 播放完毕 <<<");
        }

    return Plugin_Stop;
}

public Action Timer_GetLyric(Handle timer, int client)
{
    char path[128];
    BuildPath(Path_SM, path, 128, "data/music/lyric_%d.lrc", g_Sound[client][iSongId]);
    
    if(!FileExists(path))
    {
        char url[256];
        FormatEx(url, 256, "%s%d", LYRICS, g_Sound[client][iSongId]);
        
#if defined DEBUG
        UTIL_DebugLog("Timer_GetLyric -> %d -> %s", g_Sound[client][iSongId], url);
#endif

        System2_DownloadFile(API_GetLyric, url, path, client);
        /*
        System2HTTPRequest request = new System2HTTPRequest(url, API_GetLyric);
        request.SetURL(url);
        request.SetOutputFile(path);
        request.AutoClean = true;
        request.Timeout = 4000;
        request.GET();
        */
    }
    else
        UTIL_ProcessLyric(client);
}
/*
public void API_GetLyric(bool success, System2HTTPRequest request, System2HTTPResponse response)
{
    if(success)
        UTIL_ProcessLyric();
    else
        LogError("System2 -> API_GetLyric -> Download lyric Error");
}
*/
public void API_GetLyric(bool finished, const char[] error, float dltotal, float dlnow, float ultotal, float ulnow, int client)
{
    if(finished)
    {
        if(!StrEqual(error, ""))
        {
            LogError("System2 -> API_GetLyric -> Download lyric Error: %s", error);
            return;
        }

        UTIL_ProcessLyric(client);
    }
}

void UTIL_ProcessLyric(int index)
{
    if(index != 0 && !IsClientInGame(index))
        return;
    
    array_lyric[index].Clear();

    char path[128];
    BuildPath(Path_SM, path, 128, "data/music/lyric_%d.lrc", g_iSelect[index]);

    Handle hFile = OpenFile(path, "r");
    if(hFile == null)
    {
        LogError("UTIL_ProcessLyric -> OpenFile -> null -> Load Lyric failed [%d].", g_iSelect[index]);
        return;
    }

    UTIL_LyricHud(index, "....等待歌词中....");

    array_lyric[index].PushString(">>> Music <<<\n");

    char fileline[128];
    while(ReadFileLine(hFile, fileline, 128))
    {
        if(fileline[0] != '[')
            continue;

        Format(fileline, 128, "%s", fileline[1]);

        int pos;
        while((pos = FindCharInString(fileline, ']')) != -1)
        {
            fileline[pos] = '\\';
            if(fileline[pos+1] == '\0')
                fileline[pos+1] = '\n';
        }

        ReplaceString(fileline, 128, "\\", "]");

        char data[2][128], time[2][16];
        if(ExplodeString(fileline, "]", data, 2, 128) != 2)
            continue;

        if(ExplodeString(data[0], ":", time, 2, 16) != 2)
            continue;
        
#if defined DEBUG
        UTIL_DebugLog("UTIL_ProcessLyric -> Index[%d] -> Delay[%.2f] -> Line -> %s", index, StringToFloat(time[0])*60.0+StringToFloat(time[1]), data[1]);
#endif
        array_timer[index].Push(CreateTimer(StringToFloat(time[0])*60.0+StringToFloat(time[1]), Timer_Lyric, (array_lyric[index].PushString(data[1])) | (index << 7), TIMER_FLAG_NO_MAPCHANGE));
    }

    delete hFile;
}

public Action Timer_Lyric(Handle timer, int values)
{
    int lyrics_index = values & 0x7f;
    int player_index = values >> 7;
    
#if defined DEBUG
    UTIL_DebugLog("Timer_Lyric -> lyrics_index[%d] -> player_index[%d]", lyrics_index, player_index);
#endif

    int idx = array_timer[player_index].FindValue(timer);
    if(idx != -1)
        array_timer[player_index].Erase(idx);

    char lyric[3][128];
    array_lyric[player_index].GetString(lyrics_index-1, lyric[0], 128);
    array_lyric[player_index].GetString(lyrics_index-0, lyric[1], 128);
    if(lyrics_index+1 < GetArraySize(array_lyric[player_index]))
    array_lyric[player_index].GetString(lyrics_index+1, lyric[2], 128);
    else strcopy(lyric[2], 128, " >>> End <<< ");

    char buffer[256];
    FormatEx(buffer, 256, "%s%s%s", lyric[0], lyric[1], lyric[2]);
    UTIL_LyricHud(player_index, buffer);
}

void UTIL_StopMusic(int client)
{
    CG_RemoveMotd(client);
    g_bPlayed[client] = false;
    UTIL_ClearLyric(client);
}

void UTIL_LyricHud(int index, const char[] message)
{
    if(index == PLAYALL)
    {
        ArrayList array_client = new ArrayList();
        for(int client = 1; client <= MaxClients; ++client)
            if(IsValidClient(client) && !g_bDiable[client] && g_bPlayed[client] && g_bLyrics[client])
                array_client.Push(client);

        CG_ShowGameText(message, "30.0", "57 197 187", "-1.0", "0.8", array_client);
        delete array_client;
    }
    else
        CG_ShowGameTextToClient(message, "30.0", "57 197 187", "-1.0", "0.8", index);
}

void UTIL_ClearLyric(int client)
{
    if(!g_bLyrics[client])
        return;

    CG_ShowGameTextToClient(">>> 歌曲已停止播放 <<<", "3.0", "57 197 187", "-1.0", "0.8", client);
}

#if defined DEBUG
void UTIL_DebugLog(const char[] log, any ...)
{
    char buffer[512];
    VFormat(buffer, 512, log, 2);
    LogToFileEx("addons/sourcemod/logs/mediasystem.debug.log", buffer);
}
#endif

void UTIL_ClearAll()
{
    for(int i = 0; i <= MaxClients; i++)
    {
        if(g_bDiable[i])
            continue;

        while(GetArraySize(array_timer[i]))
        {
            Handle timer = array_timer[i].Get(0);
            KillTimer(timer);
            array_timer[i].Erase(0);
        }
        
        array_lyric[i].Clear();
    }
}

void UTIL_ClearMotdAll()
{
    for(int i = 1; i <= MaxClients; i++)
        if(IsValidClient(i) && g_bPlayed[i])
            CG_RemoveMotd(i);
}

bool IsValidClient(int client)
{
    return (1 <= client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}

bool AddMenuItemEx(Handle menu, int style, const char[] info, const char[] display, any ...)
{
	char m_szBuffer[256];
	VFormat(m_szBuffer, 256, display, 5);
	return AddMenuItem(menu, info, m_szBuffer, style);
}

void UTIL_CheckDirector()
{
    char path[128];
    BuildPath(Path_SM, path, 128, "data/music");
    if(!DirExists(path))
        CreateDirectory(path, 511);
    else
    {
        // we need clear logs of searching
        Handle hDirectory;
        if((hDirectory = OpenDirectory("addons/sourcemod/data/music")) != INVALID_HANDLE)
        {
            FileType type = FileType_Unknown;
            char filename[128];
            while(ReadDirEntry(hDirectory, filename, 128, type))
            {
                if(type != FileType_File || StrContains(filename, "search_", false) != 0)
                    continue;

                FormatEx(path, 128, "addons/sourcemod/data/music/%s", filename);
                DeleteFile(path);
            }
            CloseHandle(hDirectory);
        }
    }
}