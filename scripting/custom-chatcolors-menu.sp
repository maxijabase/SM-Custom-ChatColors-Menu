#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <regex>
#include <ccc>
#include "cccm.inc"
#include "color_literals.inc"

#define PLUGIN_NAME "Custom Chat Colors Menu"
#define PLUGIN_VERSION "3.0"
#define MAX_COLORS 255
#define MAX_HEXSTR_SIZE 7
#define MAX_TAGTEXT_SIZE 32

enum ColorType {
  COLOR_TAG, 
  COLOR_NAME, 
  COLOR_CHAT
}

enum struct PlayerData {
  bool chatConfigLoaded;
  bool hideTag;
  bool waitingForTagInput;
  char steamid[32];
  char tag_text[MAX_TAGTEXT_SIZE];
  char tag_color[MAX_HEXSTR_SIZE];
  char name_color[MAX_HEXSTR_SIZE];
  char chat_color[MAX_HEXSTR_SIZE];
}

enum struct ColorData {
  char name[255];
  char hex[255];
}

Menu g_menuMain;
Menu g_menuTagColor;
Menu g_menuTagText;
Menu g_menuName;
Menu g_menuChat;

Regex g_hRegexHex;
Database g_Database;
int g_iColorCount;
bool g_Late;

char g_strConfigFile[PLATFORM_MAX_PATH];

PlayerData g_Players[MAXPLAYERS + 1];
ColorData g_Colors[MAX_COLORS];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
  g_Late = late;
  RegPluginLibrary("cccm");
  CreateNative("CCCM_IsTagHidden", Native_IsTagHidden);
  return APLRes_Success;
}

public Plugin myinfo = {
  name = PLUGIN_NAME, 
  author = "ReFlexPoison, JoinedSenses, ampere custom version.", 
  description = "Change Custom Chat Colors settings through easy to access menus", 
  version = PLUGIN_VERSION, 
  url = "https://github.com/maxijabase"
}

public void OnPluginStart() {
  CreateConVar("sm_cccm_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_NOTIFY).SetString(PLUGIN_VERSION);
  
  AutoExecConfig();
  
  RegConsoleCmd("sm_ccc", Command_Color, "Open Custom Chat Colors Menu");
  
  LoadTranslations("core.phrases");
  LoadTranslations("common.phrases");
  
  g_hRegexHex = new Regex("([A-Fa-f0-9]{6})");
  
  BuildPath(Path_SM, g_strConfigFile, sizeof(g_strConfigFile), "configs/custom-chatcolors-menu.cfg");
  
  g_Database = null;
  if (SQL_CheckConfig("cccm")) {
    Database.Connect(SQLQuery_Connect, "cccm");
  }
  else {
    SetFailState("Database configuration 'cccm' not found!");
  }

  if (g_Late) {
    for (int i = 1; i <= MaxClients; i++) {
      if (IsValidClient(i)) {
        LoadChatConfig(i);
      }
    }
  }
}

void LoadChatConfig(int client) {
  if (!IsClientAuthorized(client)) {
    return;
  }
  
  if (g_Database == null) {
    return;
  }

  char name[MAX_NAME_LENGTH];
  GetClientName(client, name, sizeof(name));

  char steamid[32];
  if (!GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid))) {
    return;
  }

  char query[256];
  strcopy(g_Players[client].steamid, sizeof(g_Players[].steamid), steamid);
  g_Database.Format(query, sizeof(query), "SELECT hidetag, tagcolor, tagtext, namecolor, chatcolor FROM cccm_users WHERE steamid = '%s'", g_Players[client].steamid);
  g_Database.Query(SQL_OnChatConfigReceived, query, GetClientUserId(client), DBPrio_High);
}

public void OnConfigsExecuted() {
  Config_Load();
}

public void OnClientConnected(int client) {
  g_Players[client].chatConfigLoaded = false;
  g_Players[client].hideTag = false;
  g_Players[client].waitingForTagInput = false;
  
  g_Players[client].steamid[0] = '\0';
  g_Players[client].tag_text[0] = '\0';
  g_Players[client].tag_color[0] = '\0';
  g_Players[client].name_color[0] = '\0';
  g_Players[client].chat_color[0] = '\0';
}

public void CCC_OnUserConfigLoaded(int client) {
  if (g_Players[client].chatConfigLoaded) {
    return;
  }
  
  // get tag text
  char tag_text[MAX_TAGTEXT_SIZE];
  CCC_GetTag(client, tag_text, sizeof(tag_text));
  if (tag_text[0] != '\0') {
    strcopy(g_Players[client].tag_text, sizeof(g_Players[].tag_text), tag_text);
  }

  // get tag color
  char tag_color[MAX_HEXSTR_SIZE];
  IntToString(CCC_GetColor(client, CCC_TagColor), tag_color, sizeof(tag_color));
  if (IsValidHex(tag_color)) {
    strcopy(g_Players[client].tag_color, sizeof(g_Players[].tag_color), tag_color);
  }
  
  // get name color
  char name_color[MAX_HEXSTR_SIZE];
  IntToString(CCC_GetColor(client, CCC_NameColor), name_color, sizeof(name_color));
  if (IsValidHex(name_color)) {
    strcopy(g_Players[client].name_color, sizeof(g_Players[].name_color), name_color);
  }
  
  // get chat color
  char chat_color[MAX_HEXSTR_SIZE];
  IntToString(CCC_GetColor(client, CCC_ChatColor), chat_color, sizeof(chat_color));
  if (IsValidHex(chat_color)) {
    strcopy(g_Players[client].chat_color, sizeof(g_Players[].chat_color), chat_color);
  }
}

public void OnClientAuthorized(int client, const char[] steamid) {
  strcopy(g_Players[client].steamid, sizeof(g_Players[].steamid), steamid);
}

public void OnRebuildAdminCache(AdminCachePart part) {
  for (int i = 1; i <= MaxClients; i++) {
    if (IsClientInGame(i)) {
      OnClientConnected(i);
      if (IsClientAuthorized(i)) {
        OnClientPostAdminCheck(i);
      }
    }
  }
}

public void OnClientPostAdminCheck(int client) {
  LoadChatConfig(client);
}

public Action OnClientSayCommand(int client, const char[] strCommand, const char[] strArgs) {
  if (!g_Players[client].waitingForTagInput) {
    return Plugin_Continue;
  }
  
  strcopy(g_Players[client].tag_text, sizeof(g_Players[].tag_text), strArgs);
  CCC_SetTag(client, strArgs);
  
  PrintUpdateMessage(client);
  
  if (g_Database != null && IsClientAuthorized(client)) {
    char query[256];
    Format(query, sizeof(query), "SELECT tagtext FROM cccm_users WHERE steamid = '%s'", g_Players[client].steamid);
    g_Database.Query(SQLQuery_TagText, query, GetClientUserId(client), DBPrio_High);
  }
  
  g_Players[client].waitingForTagInput = false;
  return Plugin_Handled;
}

public Action Command_Color(int client, int args) {
  if (!IsValidClient(client)) {
    return Plugin_Continue;
  }
  
  DisplayColorMenu(g_menuMain, client);
  return Plugin_Handled;
}

public int Native_IsTagHidden(Handle plugin, int numParams) {
  int client = GetNativeCell(1);
  if (client < 1 || client > MaxClients) {
    return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
  }
  if (!IsClientConnected(client)) {
    return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
  }
  return g_Players[client].hideTag;
}

// ====[MENUS]===============================================================

// ------------------------------- Build Menu
void BuildMainMenu() {
  g_menuMain = new Menu(MenuHandler_Settings, MENU_ACTIONS_DEFAULT | MenuAction_DisplayItem);
  g_menuMain.SetTitle("Custom Chat Colors");
  
  g_menuMain.AddItem("HideTag", "Hide Tag");
  g_menuMain.AddItem("TagColor", "Change Tag Color");
  g_menuMain.AddItem("TagText", "Change Tag Text");
  g_menuMain.AddItem("Name", "Change Name Color");
  g_menuMain.AddItem("Chat", "Change Chat Color");
}

void BuildTagColorMenu() {
  g_menuTagColor = new Menu(MenuHandler_TagColor, MENU_ACTIONS_DEFAULT);
  g_menuTagColor.SetTitle("Tag Color");
  g_menuTagColor.ExitBackButton = true;
  
  g_menuTagColor.AddItem("Reset", "Reset");
  
  char strColorIndex[4];
  for (int i = 0; i < g_iColorCount; i++) {
    IntToString(i, strColorIndex, sizeof(strColorIndex));
    g_menuTagColor.AddItem(strColorIndex, g_Colors[i].name);
  }
}

void BuildTagTextmenu() {
  g_menuTagText = new Menu(MenuHandler_TagText, MENU_ACTIONS_DEFAULT);
  g_menuTagText.SetTitle("Tag Text");
  g_menuTagText.ExitBackButton = true;
  
  g_menuTagText.AddItem("Change", "Change Tag Text");
  g_menuTagText.AddItem("Reset", "Reset");
}

void BuildNameMenu() {
  g_menuName = new Menu(MenuHandler_NameColor, MENU_ACTIONS_DEFAULT);
  g_menuName.SetTitle("Name Color");
  g_menuName.ExitBackButton = true;
  
  g_menuName.AddItem("Reset", "Reset");
  
  char strColorIndex[4];
  for (int i = 0; i < g_iColorCount; i++) {
    IntToString(i, strColorIndex, sizeof(strColorIndex));
    g_menuName.AddItem(strColorIndex, g_Colors[i].name);
  }
}

void BuildChatMenu() {
  g_menuChat = new Menu(MenuHandler_ChatColor, MENU_ACTIONS_DEFAULT);
  g_menuChat.SetTitle("Chat Color");
  g_menuChat.ExitBackButton = true;
  
  g_menuChat.AddItem("Reset", "Reset");
  
  char strColorIndex[4];
  for (int i = 0; i < g_iColorCount; i++) {
    IntToString(i, strColorIndex, sizeof(strColorIndex));
    g_menuChat.AddItem(strColorIndex, g_Colors[i].name);
  }
}

// ------------------------------- Display Menu

void DisplayColorMenu(Menu menu, int client) {
  if (IsVoteInProgress()) {
    ReplyToCommand(client, "\x01[\x03CCC\x01] Vote In Progress.");
    return;
  }
  menu.Display(client, MENU_TIME_FOREVER);
}

// ------------------------------- Menu Handlers

int MenuHandler_Settings(Menu menu, MenuAction action, int param1, int param2) {
  switch (action) {
    case MenuAction_Select: {
      char strBuffer[32];
      menu.GetItem(param2, strBuffer, sizeof(strBuffer));
      if (StrEqual(strBuffer, "HideTag")) {
        g_Players[param1].hideTag = !g_Players[param1].hideTag;
        
        PrintUpdateMessage(param1);
        
        if (g_Database != null && IsClientAuthorized(param1)) {
          char query[256];
          Format(query, sizeof(query), "SELECT hidetag FROM cccm_users WHERE steamid = '%s'", g_Players[param1].steamid);
          g_Database.Query(SQLQuery_HideTag, query, GetClientUserId(param1), DBPrio_High);
        }
        menu.DisplayAt(param1, menu.Selection, MENU_TIME_FOREVER);
      }
      else if (StrEqual(strBuffer, "TagColor")) {
        DisplayColorMenu(g_menuTagColor, param1);
      }
      else if (StrEqual(strBuffer, "TagText")) {
        DisplayColorMenu(g_menuTagText, param1);
      }
      else if (StrEqual(strBuffer, "Name")) {
        DisplayColorMenu(g_menuName, param1);
      }
      else if (StrEqual(strBuffer, "Chat")) {
        DisplayColorMenu(g_menuChat, param1);
      }
    }
    case MenuAction_DisplayItem: {
      char item[32];
      menu.GetItem(param2, item, sizeof(item));
      if (StrEqual(item, "HideTag")) {
        if (g_Players[param1].hideTag) {
          return RedrawMenuItem("Show Tag");
        }
      }
    }
  }
  return 0;
}

int MenuHandler_TagColor(Menu menu, MenuAction action, int param1, int param2) {
  switch (action) {
    case MenuAction_Cancel: {
      if (param2 == MenuCancel_ExitBack) {
        DisplayColorMenu(g_menuMain, param1);
      }
    }
    case MenuAction_Select: {
      char strBuffer[32];
      menu.GetItem(param2, strBuffer, sizeof(strBuffer));
      
      if (StrEqual(strBuffer, "Reset")) {
        g_Players[param1].tag_color[0] = '\0';
        CCC_ResetColor(param1, CCC_TagColor);
      }
      else {
        int iColorIndex = StringToInt(strBuffer);
        strcopy(g_Players[param1].tag_color, sizeof(g_Players[].tag_color), g_Colors[iColorIndex].hex);
        CCC_SetColor(param1, CCC_TagColor, StringToInt(g_Colors[iColorIndex].hex, 16), false);
      }
      
      PrintUpdateMessage(param1);
      
      if (g_Database != null && IsClientAuthorized(param1)) {
        char query[256];
        Format(query, sizeof(query), "SELECT tagcolor FROM cccm_users WHERE steamid = '%s'", g_Players[param1].steamid);
        g_Database.Query(SQLQuery_TagColor, query, GetClientUserId(param1), DBPrio_High);
      }
      
      menu.DisplayAt(param1, menu.Selection, MENU_TIME_FOREVER);
    }
  }
  return 0;
}

int MenuHandler_TagText(Menu menu, MenuAction action, int param1, int param2) {
  switch (action) {
    case MenuAction_Cancel: {
      if (param2 == MenuCancel_ExitBack) {
        DisplayColorMenu(g_menuMain, param1);
      }
    }
    case MenuAction_Select: {
      char strBuffer[32];
      menu.GetItem(param2, strBuffer, sizeof(strBuffer));
      
      if (StrEqual(strBuffer, "Reset")) {
        g_Players[param1].tag_text[0] = '\0';
        CCC_ResetTag(param1);
      }
      else if (StrEqual(strBuffer, "Change")) {
        g_Players[param1].waitingForTagInput = true;
        ReplyToCommand(param1, "\x01[\x03CCC\x01] Enter the new tag text:");
        return 0;
      }
      
      PrintUpdateMessage(param1);
      
      if (g_Database != null && IsClientAuthorized(param1)) {
        char query[256];
        Format(query, sizeof(query), "SELECT tagtext FROM cccm_users WHERE steamid = '%s'", g_Players[param1].steamid);
        g_Database.Query(SQLQuery_TagText, query, GetClientUserId(param1), DBPrio_High);
      }
      
      menu.DisplayAt(param1, menu.Selection, MENU_TIME_FOREVER);
    }
  }
  return 0;
}

int MenuHandler_NameColor(Menu menu, MenuAction action, int param1, int param2) {
  switch (action) {
    case MenuAction_Cancel: {
      if (param2 == MenuCancel_ExitBack) {
        DisplayColorMenu(g_menuMain, param1);
      }
    }
    case MenuAction_Select: {
      char strBuffer[32];
      menu.GetItem(param2, strBuffer, sizeof(strBuffer));
      
      if (StrEqual(strBuffer, "Reset")) {
        g_Players[param1].name_color[0] = '\0';
        CCC_ResetColor(param1, CCC_NameColor);
      }
      else {
        int iColorIndex = StringToInt(strBuffer);
        strcopy(g_Players[param1].name_color, sizeof(g_Players[].name_color), g_Colors[iColorIndex].hex);
        CCC_SetColor(param1, CCC_NameColor, StringToInt(g_Colors[iColorIndex].hex, 16), false);
      }
      
      PrintUpdateMessage(param1);
      
      if (g_Database != null && IsClientAuthorized(param1)) {
        char query[256];
        Format(query, sizeof(query), "SELECT namecolor FROM cccm_users WHERE steamid = '%s'", g_Players[param1].steamid);
        g_Database.Query(SQLQuery_NameColor, query, GetClientUserId(param1), DBPrio_High);
      }
      
      menu.DisplayAt(param1, menu.Selection, MENU_TIME_FOREVER);
    }
  }
  return 0;
}

int MenuHandler_ChatColor(Menu menu, MenuAction action, int param1, int param2) {
  switch (action) {
    case MenuAction_Cancel: {
      if (param2 == MenuCancel_ExitBack) {
        DisplayColorMenu(g_menuMain, param1);
      }
    }
    case MenuAction_Select: {
      char strBuffer[32];
      menu.GetItem(param2, strBuffer, sizeof(strBuffer));
      
      if (StrEqual(strBuffer, "Reset")) {
        g_Players[param1].chat_color[0] = '\0';
        CCC_ResetColor(param1, CCC_ChatColor);
      }
      else {
        int iColorIndex = StringToInt(strBuffer);
        strcopy(g_Players[param1].chat_color, sizeof(g_Players[].chat_color), g_Colors[iColorIndex].hex);
        CCC_SetColor(param1, CCC_ChatColor, StringToInt(g_Colors[iColorIndex].hex, 16), false);
      }
      
      PrintUpdateMessage(param1);
      
      if (g_Database != null && IsClientAuthorized(param1)) {
        char query[256];
        Format(query, sizeof(query), "SELECT chatcolor FROM cccm_users WHERE steamid = '%s'", g_Players[param1].steamid);
        g_Database.Query(SQLQuery_ChatColor, query, GetClientUserId(param1), DBPrio_High);
      }
      
      menu.DisplayAt(param1, menu.Selection, MENU_TIME_FOREVER);
    }
  }
  return 0;
}

// ====[CONFIGURATION]=======================================================

void Config_Load() {
  if (!FileExists(g_strConfigFile)) {
    SetFailState("Configuration file %s not found!", g_strConfigFile);
    return;
  }
  
  KeyValues keyvalues = new KeyValues("CCC Menu Colors");
  if (!keyvalues.ImportFromFile(g_strConfigFile)) {
    SetFailState("Improper structure for configuration file %s!", g_strConfigFile);
    return;
  }
  
  if (!keyvalues.GotoFirstSubKey()) {
    SetFailState("Can't find configuration file %s!", g_strConfigFile);
    return;
  }
  
  // Reset all color data
  for (int i = 0; i < MAX_COLORS; i++) {
    g_Colors[i].name[0] = '\0';
    g_Colors[i].hex[0] = '\0';
  }
  
  g_iColorCount = 0;
  do {
    keyvalues.GetString("name", g_Colors[g_iColorCount].name, sizeof(g_Colors[].name));
    keyvalues.GetString("hex", g_Colors[g_iColorCount].hex, sizeof(g_Colors[].hex));
    ReplaceString(g_Colors[g_iColorCount].hex, sizeof(g_Colors[].hex), "#", "", false);
    
    if (!IsValidHex(g_Colors[g_iColorCount].hex)) {
      LogError("Invalid hexadecimal value for color %s.", g_Colors[g_iColorCount].name);
      g_Colors[g_iColorCount].name[0] = '\0';
      g_Colors[g_iColorCount].hex[0] = '\0';
    }
    
    g_iColorCount++;
  } while (keyvalues.GotoNextKey());
  delete keyvalues;
  
  // Rebuild menus with new color data
  delete g_menuMain;
  delete g_menuTagColor;
  delete g_menuTagText;
  delete g_menuName;
  delete g_menuChat;
  
  BuildMainMenu();
  BuildTagColorMenu();
  BuildTagTextmenu();
  BuildNameMenu();
  BuildChatMenu();
  
  LogMessage("Loaded %i colors from configuration file %s.", g_iColorCount, g_strConfigFile);
}

// ====[SQL QUERIES]=========================================================

void SQLQuery_Connect(Database db, const char[] error, any data) {
  if (db == null) {
    return;
  }
  
  g_Database = db;
  char driver[16];
  db.Driver.GetIdentifier(driver, sizeof(driver));
  
  if (StrEqual(driver, "mysql", false)) {
    LogMessage("MySQL server configured. Variable saving enabled.");
    g_Database.Query(
      SQLQuery_Update
      , "CREATE TABLE IF NOT EXISTS cccm_users"
      ..."("
      ..."id INT(64) NOT NULL AUTO_INCREMENT, "
      ..."steamid VARCHAR(32) UNIQUE, "
      ..."hidetag VARCHAR(1), "
      ..."tagcolor VARCHAR(7), "
      ..."tagtext VARCHAR(32), "
      ..."namecolor VARCHAR(7), "
      ..."chatcolor VARCHAR(7), "
      ..."PRIMARY KEY (id)"
      ...")"
      , _
      , DBPrio_High
      );
  }
  else if (StrEqual(driver, "sqlite", false)) {
    LogMessage("SQlite server configured. Variable saving enabled.");
    g_Database.Query(
      SQLQuery_Update
      , "CREATE TABLE IF NOT EXISTS cccm_users "
      ..."("
      ..."id INTERGER PRIMARY KEY, "
      ..."steamid varchar(32) UNIQUE, "
      ..."hidetag varchar(1), "
      ..."tagcolor varchar(7), "
      ..."tagtext varchar(32), "
      ..."namecolor varchar(7), "
      ..."chatcolor varchar(7)"
      ...")"
      , _
      , DBPrio_High
      );
  }
  else {
    LogMessage("Saved variable server not configured. Variable saving disabled.");
    return;
  }
  
  for (int i = 1; i <= MaxClients; i++) {
    if (IsClientInGame(i)) {
      char name[MAX_NAME_LENGTH];
      GetClientName(i, name, sizeof(name));
      
      if (IsClientAuthorized(i)) {
        LoadChatConfig(i);
      }
    }
  }
}

void SQL_OnChatConfigReceived(Database db, DBResultSet results, const char[] error, int userid) {
  int client = GetClientOfUserId(userid);
  if (!IsValidClient(client)) {
    return;
  }
  
  if (db == null || results == null) {
    return;
  }
  
  char name[MAX_NAME_LENGTH];
  GetClientName(client, name, sizeof(name));
  
  if (results.RowCount == 0) {
    return;
  }

  while (results.FetchRow()) {
    // get hide tag
    g_Players[client].hideTag = view_as<bool>(results.FetchInt(0));
    
    // get tag color
    char tag_color[MAX_HEXSTR_SIZE];
    results.FetchString(1, tag_color, sizeof(tag_color));
    if (IsValidHex(tag_color)) {
      strcopy(g_Players[client].tag_color, sizeof(g_Players[].tag_color), tag_color);
      CCC_SetColor(client, CCC_TagColor, StringToInt(g_Players[client].tag_color, 16), false);
    }

    // get tag text
    char tag_text[MAX_TAGTEXT_SIZE];
    results.FetchString(2, tag_text, sizeof(tag_text));
    if (tag_text[0] != '\0') {
      strcopy(g_Players[client].tag_text, sizeof(g_Players[].tag_text), tag_text);
      CCC_SetTag(client, g_Players[client].tag_text);
    }
    
    // get name color
    char name_color[MAX_HEXSTR_SIZE];
    results.FetchString(3, name_color, sizeof(name_color));
    if (IsValidHex(name_color)) {
      strcopy(g_Players[client].name_color, sizeof(g_Players[].name_color), name_color);
      CCC_SetColor(client, CCC_NameColor, StringToInt(g_Players[client].name_color, 16), false);
    }
    
    // get chat color
    char chat_color[MAX_HEXSTR_SIZE];
    results.FetchString(4, chat_color, sizeof(chat_color));
    if (IsValidHex(chat_color)) {
      strcopy(g_Players[client].chat_color, sizeof(g_Players[].chat_color), chat_color);
      CCC_SetColor(client, CCC_ChatColor, StringToInt(g_Players[client].chat_color, 16), false);
    }
    
    g_Players[client].chatConfigLoaded = true;
  }
}

void SQLQuery_HideTag(Database db, DBResultSet results, const char[] error, any data) {
  int client = GetClientOfUserId(data);
  if (!IsValidClient(client)) {
    return;
  }
  
  if (db == null || results == null) {
    LogError("SQL Error: %s", error);
    return;
  }
  
  if (results.RowCount == 0) {
    char query[256];
    Format(query, sizeof(query), "INSERT INTO cccm_users (hidetag, steamid) VALUES (%i, '%s')", g_Players[client].hideTag, g_Players[client].steamid);
    g_Database.Query(SQLQuery_Update, query);
  }
  else {
    char query[256];
    Format(query, sizeof(query), "UPDATE cccm_users SET hidetag = '%i' WHERE steamid = '%s'", g_Players[client].hideTag, g_Players[client].steamid);
    g_Database.Query(SQLQuery_Update, query);
  }
}

void SQLQuery_TagColor(Database db, DBResultSet results, const char[] error, any data) {
  int client = GetClientOfUserId(data);
  if (!IsValidClient(client)) {
    return;
  }
  
  if (db == null || results == null) {
    LogError("SQL Error: %s", error);
    return;
  }
  
  if (results.RowCount == 0) {
    char query[256];
    Format(query, sizeof(query), "INSERT INTO cccm_users (tagcolor, steamid) VALUES ('%s', '%s')", g_Players[client].tag_color, g_Players[client].steamid);
    g_Database.Query(SQLQuery_Update, query);
  }
  else {
    char query[256];
    Format(query, sizeof(query), "UPDATE cccm_users SET tagcolor = '%s' WHERE steamid = '%s'", g_Players[client].tag_color, g_Players[client].steamid);
    g_Database.Query(SQLQuery_Update, query);
  }
}

void SQLQuery_TagText(Database db, DBResultSet results, const char[] error, any data) {
  int client = GetClientOfUserId(data);
  if (!IsValidClient(client)) {
    return;
  }
  
  if (db == null || results == null) {
    LogError("SQL Error: %s", error);
    return;
  }
  
  if (results.RowCount == 0) {
    char query[256];
    Format(query, sizeof(query), "INSERT INTO cccm_users (tagtext, steamid) VALUES ('%s', '%s')", g_Players[client].tag_text, g_Players[client].steamid);
    g_Database.Query(SQLQuery_Update, query);
  }
  else {
    char query[256];
    Format(query, sizeof(query), "UPDATE cccm_users SET tagtext = '%s' WHERE steamid = '%s'", g_Players[client].tag_text, g_Players[client].steamid);
    g_Database.Query(SQLQuery_Update, query);
  }
}

void SQLQuery_NameColor(Database db, DBResultSet results, const char[] error, any data) {
  int client = GetClientOfUserId(data);
  if (!IsValidClient(client)) {
    return;
  }
  
  if (db == null || results == null) {
    LogError("SQL Error: %s", error);
    return;
  }
  
  if (results.RowCount == 0) {
    char query[256];
    Format(query, sizeof(query), "INSERT INTO cccm_users (namecolor, steamid) VALUES ('%s', '%s')", g_Players[client].name_color, g_Players[client].steamid);
    g_Database.Query(SQLQuery_Update, query);
  }
  else {
    char query[256];
    Format(query, sizeof(query), "UPDATE cccm_users SET namecolor = '%s' WHERE steamid = '%s'", g_Players[client].name_color, g_Players[client].steamid);
    g_Database.Query(SQLQuery_Update, query);
  }
}

void SQLQuery_ChatColor(Database db, DBResultSet results, const char[] error, any data) {
  int client = GetClientOfUserId(data);
  if (!IsValidClient(client)) {
    return;
  }
  
  if (db == null || results == null) {
    LogError("SQL Error: %s", error);
    return;
  }
  
  if (results.RowCount == 0) {
    char query[256];
    Format(query, sizeof(query), "INSERT INTO cccm_users (chatcolor, steamid) VALUES ('%s', '%s')", g_Players[client].chat_color, g_Players[client].steamid);
    g_Database.Query(SQLQuery_Update, query);
  }
  else {
    char query[256];
    Format(query, sizeof(query), "UPDATE cccm_users SET chatcolor = '%s' WHERE steamid = '%s'", g_Players[client].chat_color, g_Players[client].steamid);
    g_Database.Query(SQLQuery_Update, query);
  }
}

void SQLQuery_Update(Handle owner, Handle hndl, const char[] strError, any data) {
  if (hndl == null) {
    LogError("SQL Error: %s", strError);
  }
}

// ====[UTILITY FUNCTIONS]==============================================================

bool IsValidClient(int client) {
  return (0 < client <= MaxClients && IsClientInGame(client));
}

bool IsValidHex(const char[] hex) {
  return (strlen(hex) == 6 && g_hRegexHex.Match(hex));
}

void PrintUpdateMessage(int client) {
  if (!IsValidClient(client)) {
    return;
  }
  
  char tag[24];
  char tagcolor[12];
  if (!g_Players[client].hideTag) {
    CCC_GetTag(client, tag, sizeof(tag));
    if (g_Players[client].tag_color[0] != '\0') {
      Format(tagcolor, sizeof(tagcolor), "\x07%s", g_Players[client].tag_color);
    }
  }
  
  char g_sTeamColor[][] = { "FFFFFF", "CCCCCC", "FF4040", "99CCFF" };
  char namecolor[12];
  if (g_Players[client].name_color[0] != '\0') {
    Format(namecolor, sizeof(namecolor), "\x07%s", g_Players[client].name_color);
  }
  else {
    Format(namecolor, sizeof(namecolor), "\x07%s", g_sTeamColor[GetClientTeam(client)]);
  }
  
  char chatcolor[12];
  if (g_Players[client].chat_color[0] != '\0') {
    Format(chatcolor, sizeof(chatcolor), "\x07%s", g_Players[client].chat_color);
  }
  
  PrintColoredChat(client, "%s%s\x01%s%N\x01 :%s Color settings have been updated.", tagcolor, tag, namecolor, client, chatcolor);
} 