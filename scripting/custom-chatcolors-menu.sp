#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <regex>
#include <ccc>
#include "cccm.inc"
#include "color_literals.inc"

enum {
	ACCESS_TAG,
	ACCESS_NAME,
	ACCESS_CHAT,
	ACCESS_HIDETAG,
	ACCESS_PLUGIN,
	MAX_ACCESS
}

enum {
	STRCOLOR_TAG,
	STRCOLOR_NAME,
	STRCOLOR_CHAT,
	MAX_STRCOLOR
}

enum {
	ENABLEFLAG_TAG = 1,
	ENABLEFLAG_NAME,
	ENABLEFLAG_CHAT,
	ENABLEFLAG_HIDETAG
}

#define PLUGIN_NAME "Custom Chat Colors Menu"
#define PLUGIN_VERSION "2.2"
#define MAX_COLORS 255
#define MAX_HEXSTR_SIZE 7
#define MAX_TAGTEXT_SIZE 32

Menu
	g_menuMain,
	g_menuTagColor,
	g_menuTagText,
	g_menuName,
	g_menuChat;
ConVar
	g_hCvarEnabled;
Regex
	g_hRegexHex;
Database
	g_hSQL;
int
	g_iColorCount,
	g_iCvarEnabled;
AdminFlag
	 g_iColorFlagList[MAX_COLORS][16];
bool
	g_bChatConfigLoaded[MAXPLAYERS+1],
	g_bColorAdminFlags[MAX_COLORS],
	g_bHideTag[MAXPLAYERS+1],
	g_bAccess[MAXPLAYERS+1][MAX_ACCESS],
	g_bWaitingForTagInput[MAXPLAYERS+1],
	g_bLateLoad;
char
	g_strAuth[MAXPLAYERS+1][32],
	g_strTagText[MAXPLAYERS+1][MAX_TAGTEXT_SIZE],
	g_strColor[MAXPLAYERS+1][MAX_STRCOLOR][MAX_HEXSTR_SIZE],
	g_strColorName[MAX_COLORS][255],
	g_strColorHex[MAX_COLORS][255],
	g_strColorFlags[MAX_COLORS][255],
	g_strConfigFile[PLATFORM_MAX_PATH],
	g_strSQLDriver[16];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_bLateLoad = late;
	RegPluginLibrary("cccm");
	CreateNative("CCCM_IsTagHidden", Native_IsTagHidden);
	return APLRes_Success;
}

// ====[PLUGIN]==============================================================

public Plugin myinfo = {
	name = PLUGIN_NAME,
	author = "ReFlexPoison, modified/fixed by JoinedSenses",
	description = "Change Custom Chat Colors settings through easy to access menus",
	version = PLUGIN_VERSION,
	url = "https://github.com/JoinedSenses"
}
	
// ====[EVENTS]==============================================================

public void OnPluginStart() {
	CreateConVar("sm_cccm_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_NOTIFY).SetString(PLUGIN_VERSION);

	g_hCvarEnabled = CreateConVar(
		"sm_cccm_enabled",
		"15",
		"Enable Custom Chat Colors Menu (Add up the numbers to choose)\n0 = Disabled\n1 = Tag\n2 = Name\n4 = Chat\n8 = Hide Tag",
		FCVAR_NONE, true, 0.0, true, 15.0
	);
	g_iCvarEnabled = g_hCvarEnabled.IntValue;
	g_hCvarEnabled.AddChangeHook(OnConVarChange);

	AutoExecConfig();

	RegAdminCmd("sm_ccc", Command_Color, ADMFLAG_GENERIC, "Open Custom Chat Colors Menu");
	RegAdminCmd("sm_reload_cccm", Command_Reload, ADMFLAG_ROOT, "Reloads Custom Chat Colors Menu config");
	RegAdminCmd("sm_tagcolor", Command_TagColor, ADMFLAG_ROOT, "Change tag color to a specified hexadecimal value");
	RegAdminCmd("sm_tagtext", Command_TagText, ADMFLAG_ROOT, "Change tag text to a specified value");
	RegAdminCmd("sm_namecolor", Command_NameColor, ADMFLAG_ROOT, "Change name color to a specified hexadecimal value");
	RegAdminCmd("sm_chatcolor", Command_ChatColor, ADMFLAG_ROOT, "Change chat color to a specified hexadecimal value");
	RegAdminCmd("sm_resettagcolor", Command_ResetTagColor, ADMFLAG_GENERIC, "Reset tag color to default");
	RegAdminCmd("sm_resettagtext", Command_ResetTagText, ADMFLAG_GENERIC, "Reset tag text to default");
	RegAdminCmd("sm_resetname", Command_ResetNameColor, ADMFLAG_GENERIC, "Reset name color to default");
	RegAdminCmd("sm_resetchat", Command_ResetChatColor, ADMFLAG_GENERIC, "Reset chat color to default");

	LoadTranslations("core.phrases");
	LoadTranslations("common.phrases");

	g_hRegexHex = new Regex("([A-Fa-f0-9]{6})");

	BuildPath(Path_SM, g_strConfigFile, sizeof(g_strConfigFile), "configs/custom-chatcolors-menu.cfg");

	g_hSQL = null;
	if (SQL_CheckConfig("cccm")) {
		Database.Connect(SQLQuery_Connect, "cccm");
	}

	if (g_bLateLoad) {
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i)) {
				CheckSettings(i);
			}
		}
	}
}

public void OnConVarChange(ConVar convar, const char[] strOldValue, const char[] strNewValue) {
	g_iCvarEnabled = g_hCvarEnabled.IntValue;
}

void LoadChatConfig(int client) {
	if (!IsClientAuthorized(client)) {
		return;
	}

	if (g_hSQL != null) {
		char strAuth[32], strQuery[256];
		GetClientAuthId(client, AuthId_Steam2, strAuth, sizeof(strAuth));
		strcopy(g_strAuth[client], sizeof(g_strAuth[]), strAuth);
		Format(strQuery, sizeof(strQuery), "SELECT hidetag, tagcolor, tagtext, namecolor, chatcolor FROM cccm_users WHERE auth = '%s'", g_strAuth[client]);
		g_hSQL.Query(SQL_OnChatConfigReceived, strQuery, GetClientUserId(client), DBPrio_High);
	}
}

public void OnConfigsExecuted() {
	Config_Load();
}

public void OnClientConnected(int client) {
	g_bChatConfigLoaded[client] = false;
	g_bHideTag[client] = false;
	g_bAccess[client][ACCESS_TAG] = false;
	g_bAccess[client][ACCESS_NAME] = false;
	g_bAccess[client][ACCESS_CHAT] = false;
	g_bAccess[client][ACCESS_HIDETAG] = false;

	g_strAuth[client][0] = '\0';
	g_strTagText[client][0] = '\0';
	g_strColor[client][STRCOLOR_TAG][0] = '\0';
	g_strColor[client][STRCOLOR_NAME][0] = '\0';
	g_strColor[client][STRCOLOR_CHAT][0] = '\0';
}

public void CCC_OnUserConfigLoaded(int client) {
	if (g_bChatConfigLoaded[client]) {
		return;
	}

	char strTag[MAX_HEXSTR_SIZE];
	IntToString(CCC_GetColor(client, CCC_TagColor), strTag, sizeof(strTag));
	if (IsValidHex(strTag)) {
		strcopy(g_strColor[client][STRCOLOR_TAG], sizeof(g_strColor[][]), strTag);
	}

	char strName[MAX_HEXSTR_SIZE];
	IntToString(CCC_GetColor(client, CCC_NameColor), strName, sizeof(strName));
	if (IsValidHex(strName)) {
		strcopy(g_strColor[client][STRCOLOR_NAME], sizeof(g_strColor[][]), strName);
	}

	char strChat[MAX_HEXSTR_SIZE];
	IntToString(CCC_GetColor(client, CCC_ChatColor), strChat, sizeof(strChat));
	if (IsValidHex(strChat)) {
		strcopy(g_strColor[client][STRCOLOR_CHAT], sizeof(g_strColor[][]), strChat);
	}
}

public void OnClientAuthorized(int client, const char[] strAuth) {
	strcopy(g_strAuth[client], sizeof(g_strAuth[]), strAuth);
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
	CheckSettings(client);
}

void CheckSettings(int client) {
	bool access;
	if ((access = CheckCommandAccess(client, "sm_ccc", ADMFLAG_GENERIC))) {
		LoadChatConfig(client);
	}
	g_bAccess[client][ACCESS_PLUGIN] = access;
	g_bAccess[client][ACCESS_TAG] = access && CheckCommandAccess(client, "sm_ccc_tag", ADMFLAG_GENERIC);
	g_bAccess[client][ACCESS_NAME] = access && CheckCommandAccess(client, "sm_ccc_name", ADMFLAG_GENERIC);
	g_bAccess[client][ACCESS_CHAT] = access && CheckCommandAccess(client, "sm_ccc_chat", ADMFLAG_GENERIC);
	g_bAccess[client][ACCESS_HIDETAG] = access && CheckCommandAccess(client, "sm_ccc_hidetags", ADMFLAG_GENERIC);
}

public Action CCC_OnColor(int client, const char[] strMessage, CCC_ColorType type) {
	switch (type) {
		case CCC_TagColor: {
			if (!(g_iCvarEnabled & ENABLEFLAG_TAG) || !g_bAccess[client][ACCESS_PLUGIN] || g_bHideTag[client]) {
				return Plugin_Handled;
			}
		}
		case CCC_NameColor: {
			if (!(g_iCvarEnabled & ENABLEFLAG_NAME) || !g_bAccess[client][ACCESS_PLUGIN] || !IsValidHex(g_strColor[client][STRCOLOR_NAME])) {
				return Plugin_Handled;
			}
		}
		case CCC_ChatColor: {
			if (!(g_iCvarEnabled & ENABLEFLAG_CHAT) || !g_bAccess[client][ACCESS_PLUGIN] || !IsValidHex(g_strColor[client][STRCOLOR_CHAT])) {
				return Plugin_Handled;
			}
		}
	}
	return Plugin_Continue;
}

public Action OnClientSayCommand(int client, const char[] strCommand, const char[] strArgs) {
	if (!g_bWaitingForTagInput[client]) {
		return Plugin_Continue;
	}

	strcopy(g_strTagText[client], sizeof(g_strTagText[]), strArgs);
	CCC_SetTag(client, strArgs);

	PrintUpdateMessage(client);

	if (g_hSQL != null && IsClientAuthorized(client)) {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "SELECT tagtext FROM cccm_users WHERE auth = '%s'", g_strAuth[client]);
		g_hSQL.Query(SQLQuery_TagText, strQuery, GetClientUserId(client), DBPrio_High);
	}

	g_bWaitingForTagInput[client] = false;
	return Plugin_Handled;
}

// ====[COMMANDS]============================================================

public Action Command_Color(int client, int args) {
	if (!IsValidClient(client)) {
		return Plugin_Continue;
	}

	DisplayColorMenu(g_menuMain, client);
	return Plugin_Handled;
}

public Action Command_Reload(int client, int args) {
	Config_Load();
	ReplyToCommand(client, "\x01[\x03CCC\x01] Configuration file %s reloaded.", g_strConfigFile);
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			OnClientConnected(i);
			OnClientPostAdminCheck(i);
		}
	}
	return Plugin_Handled;
}

public Action Command_TagColor(int client, int args) {
	if (!IsValidClient(client)) {
		return Plugin_Continue;
	}

	if (args != 1) {
		ReplyToCommand(client, "\x01[\x03CCC\x01] Usage: sm_tagcolor <hex>");
		return Plugin_Handled;
	}

	char strArg[32];
	GetCmdArgString(strArg, sizeof(strArg));
	ReplaceString(strArg, sizeof(strArg), "#", "", false);

	if (!IsValidHex(strArg)) {
		ReplyToCommand(client, "\x01[\x03CCC\x01] Usage: sm_tagcolor <hex>");
		return Plugin_Handled;
	}

	PrintToChat(client, "\x01[\x03CCC\x01] Tag color set to: \x07%s#%s\x01", strArg, strArg);
	strcopy(g_strColor[client][STRCOLOR_TAG], sizeof(g_strColor[][]), strArg);
	CCC_SetColor(client, CCC_TagColor, StringToInt(strArg, 16), false);

	PrintUpdateMessage(client);

	if (g_hSQL != null && IsClientAuthorized(client)) {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "SELECT tagcolor FROM cccm_users WHERE auth = '%s'", g_strAuth[client]);
		g_hSQL.Query(SQLQuery_TagColor, strQuery, GetClientUserId(client), DBPrio_High);
	}

	return Plugin_Handled;
}

public Action Command_TagText(int client, int args) {
	if (!IsValidClient(client)) {
		return Plugin_Continue;
	}

	if (args < 1) {
		ReplyToCommand(client, "\x01[\x03CCC\x01] Usage: sm_tagtext <text>");
		return Plugin_Handled;
	}

	char strArg[MAX_TAGTEXT_SIZE];
	GetCmdArgString(strArg, sizeof(strArg));
	if (strArg[0] == '\0') {
		ReplyToCommand(client, "\x01[\x03CCC\x01] Usage: sm_tagtext <text>");
		return Plugin_Handled;
	}

	strcopy(g_strTagText[client], sizeof(g_strTagText[]), strArg);
	CCC_SetTag(client, strArg);

	PrintUpdateMessage(client);

	if (g_hSQL != null && IsClientAuthorized(client)) {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "SELECT tagtext FROM cccm_users WHERE auth = '%s'", g_strAuth[client]);
		g_hSQL.Query(SQLQuery_TagText, strQuery, GetClientUserId(client), DBPrio_High);
	}

	return Plugin_Handled;
}

public Action Command_ResetTagColor(int client, int args) {
	if (!IsValidClient(client)) {
		return Plugin_Continue;
	}

	g_strColor[client][STRCOLOR_TAG][0] = '\0';
	CCC_ResetColor(client, CCC_TagColor);

	PrintUpdateMessage(client);

	if (g_hSQL != null && IsClientAuthorized(client)) {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "SELECT tagcolor FROM cccm_users WHERE auth = '%s'", g_strAuth[client]);
		g_hSQL.Query(SQLQuery_TagColor, strQuery, GetClientUserId(client), DBPrio_High);
	}

	return Plugin_Handled;
}

public Action Command_ResetTagText(int client, int args) {
	if (!IsValidClient(client)) {
		return Plugin_Continue;
	}

	g_strTagText[client][0] = '\0';
	CCC_ResetTag(client);

	PrintUpdateMessage(client);

	if (g_hSQL != null && IsClientAuthorized(client)) {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "SELECT tagtext FROM cccm_users WHERE auth = '%s'", g_strAuth[client]);
		g_hSQL.Query(SQLQuery_TagText, strQuery, GetClientUserId(client), DBPrio_High);
	}

	return Plugin_Handled;
}

public Action Command_NameColor(int client, int args) {
	if (!IsValidClient(client)) {
		return Plugin_Continue;
	}

	if (args != 1) {
		ReplyToCommand(client, "\x01[\x03CCC\x01] Usage: sm_namecolor <hex>");
		return Plugin_Handled;
	}

	char strArg[32];
	GetCmdArgString(strArg, sizeof(strArg));
	ReplaceString(strArg, sizeof(strArg), "#", "", false);

	if (!IsValidHex(strArg)) {
		ReplyToCommand(client, "\x01[\x03CCC\x01] Usage: sm_namecolor <hex>");
		return Plugin_Handled;
	}

	strcopy(g_strColor[client][STRCOLOR_NAME], sizeof(g_strColor[][]), strArg);
	CCC_SetColor(client, CCC_NameColor, StringToInt(strArg, 16), false);

	PrintUpdateMessage(client);

	if (g_hSQL != null && IsClientAuthorized(client)) {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "SELECT namecolor FROM cccm_users WHERE auth = '%s'", g_strAuth[client]);
		g_hSQL.Query(SQLQuery_NameColor, strQuery, GetClientUserId(client), DBPrio_High);
	}

	return Plugin_Handled;
}

public Action Command_ResetNameColor(int client, int args) {
	if (!IsValidClient(client)) {
		return Plugin_Continue;
	}

	g_strColor[client][STRCOLOR_NAME][0] = '\0';
	CCC_ResetColor(client, CCC_NameColor);

	PrintUpdateMessage(client);

	if (g_hSQL != null && IsClientAuthorized(client)) {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "SELECT namecolor FROM cccm_users WHERE auth = '%s'", g_strAuth[client]);
		g_hSQL.Query(SQLQuery_NameColor, strQuery, GetClientUserId(client), DBPrio_High);
	}

	return Plugin_Handled;
}

public Action Command_ChatColor(int client, int args) {
	if (!IsValidClient(client)) {
		return Plugin_Continue;
	}

	if (args != 1) {
		ReplyToCommand(client, "\x01[\x03CCC\x01] Usage: sm_chatcolor <hex>");
		return Plugin_Handled;
	}

	char strArg[32];
	GetCmdArgString(strArg, sizeof(strArg));
	ReplaceString(strArg, sizeof(strArg), "#", "", false);

	if (!IsValidHex(strArg)) {
		ReplyToCommand(client, "\x01[\x03CCC\x01] Usage: sm_chatcolor <hex>");
		return Plugin_Handled;
	}

	strcopy(g_strColor[client][STRCOLOR_CHAT], sizeof(g_strColor[][]), strArg);
	CCC_SetColor(client, CCC_ChatColor, StringToInt(strArg, 16), false);

	PrintUpdateMessage(client);

	if (g_hSQL != null && IsClientAuthorized(client)) {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "SELECT chatcolor FROM cccm_users WHERE auth = '%s'", g_strAuth[client]);
		g_hSQL.Query(SQLQuery_ChatColor, strQuery, GetClientUserId(client), DBPrio_High);
	}

	return Plugin_Handled;
}

public Action Command_ResetChatColor(int client, int args) {
	if (!IsValidClient(client)) {
		return Plugin_Continue;
	}

	g_strColor[client][STRCOLOR_CHAT][0] = '\0';
	CCC_ResetColor(client, CCC_ChatColor);

	PrintUpdateMessage(client);

	if (g_hSQL != null && IsClientAuthorized(client)) {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "SELECT chatcolor FROM cccm_users WHERE auth = '%s'", g_strAuth[client]);
		g_hSQL.Query(SQLQuery_ChatColor, strQuery, GetClientUserId(client), DBPrio_High);
	}

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
	return g_bHideTag[client];
}

// ====[MENUS]===============================================================

// ------------------------------- Build Menu
void BuildMainMenu() {
	g_menuMain = new Menu(MenuHandler_Settings, MENU_ACTIONS_DEFAULT|MenuAction_DrawItem|MenuAction_DisplayItem);
	g_menuMain.SetTitle("Custom Chat Colors");


	g_menuMain.AddItem("HideTag", "Hide Tag");
	g_menuMain.AddItem("TagColor", "Change Tag Color");
	g_menuMain.AddItem("TagText", "Change Tag Text");
	g_menuMain.AddItem("Name", "Change Name Color");
	g_menuMain.AddItem("Chat", "Change Chat Color");
}

void BuildTagColorMenu() {
	g_menuTagColor = new Menu(MenuHandler_TagColor, MENU_ACTIONS_DEFAULT|MenuAction_DrawItem);
	g_menuTagColor.SetTitle("Tag Color");
	g_menuTagColor.ExitBackButton = true;

	g_menuTagColor.AddItem("Reset", "Reset");

	char strColorIndex[4];
	for (int i = 0; i < g_iColorCount; i++) {
		IntToString(i, strColorIndex, sizeof(strColorIndex));
		g_menuTagColor.AddItem(strColorIndex, g_strColorName[i]);
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
	g_menuName = new Menu(MenuHandler_NameColor, MENU_ACTIONS_DEFAULT|MenuAction_DrawItem);
	g_menuName.SetTitle("Name Color");
	g_menuName.ExitBackButton = true;

	g_menuName.AddItem("Reset", "Reset");

	char strColorIndex[4];
	for (int i = 0; i < g_iColorCount; i++) {
		IntToString(i, strColorIndex, sizeof(strColorIndex));
		g_menuName.AddItem(strColorIndex, g_strColorName[i]);
	}
}

void BuildChatMenu() {
	g_menuChat = new Menu(MenuHandler_ChatColor, MENU_ACTIONS_DEFAULT|MenuAction_DrawItem);
	g_menuChat.SetTitle("Chat Color");
	g_menuChat.ExitBackButton = true;

	g_menuChat.AddItem("Reset", "Reset");

	char strColorIndex[4];
	for (int i = 0; i < g_iColorCount; i++) {
		IntToString(i, strColorIndex, sizeof(strColorIndex));
		g_menuChat.AddItem(strColorIndex, g_strColorName[i]);
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
				g_bHideTag[param1] = !g_bHideTag[param1];
				//PrintToChat(param1, "\x01[\x03CCC\x01] Chat tag \x03%s", g_bHideTag[param1] ? "disabled" : "enabled");

				PrintUpdateMessage(param1);

				if (g_hSQL != null && IsClientAuthorized(param1)) {
					char strQuery[256];
					Format(strQuery, sizeof(strQuery), "SELECT hidetag FROM cccm_users WHERE auth = '%s'", g_strAuth[param1]);
					g_hSQL.Query(SQLQuery_HideTag, strQuery, GetClientUserId(param1), DBPrio_High);
				}
				menu.DisplayAt(param1, menu.Selection, MENU_TIME_FOREVER);
			}
			if (StrEqual(strBuffer, "TagColor")) {
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
		case MenuAction_DrawItem: {
			char item[32];
			menu.GetItem(param2, item, sizeof(item));
			if (StrEqual(item, "TagColor")) {
				if ((g_iCvarEnabled & ENABLEFLAG_TAG) == 0 || !g_bAccess[param1][ACCESS_TAG]) {
					return ITEMDRAW_IGNORE;
				}				
			}
			else if (StrEqual(item, "TagText")) {
				if ((g_iCvarEnabled & ENABLEFLAG_TAG) == 0 || !g_bAccess[param1][ACCESS_TAG]) {
					return ITEMDRAW_IGNORE;
				}
			}
			else if (StrEqual(item, "Name")) {
				if ((g_iCvarEnabled & ENABLEFLAG_NAME) == 0 || !g_bAccess[param1][ACCESS_NAME]) {
					return ITEMDRAW_IGNORE;
				}
			}
			else if (StrEqual(item, "Chat")) {
				if ((g_iCvarEnabled & ENABLEFLAG_CHAT) == 0 || !g_bAccess[param1][ACCESS_CHAT]) {
					return ITEMDRAW_IGNORE;
				}
			}
			else if (StrEqual(item, "HideTag")) {
				if ((g_iCvarEnabled & ENABLEFLAG_HIDETAG) == 0 || !g_bAccess[param1][ACCESS_HIDETAG]) {
					return ITEMDRAW_IGNORE;
				}
			}
			return ITEMDRAW_DEFAULT;
		} 
		case MenuAction_DisplayItem: {
			char item[32];
			menu.GetItem(param2, item, sizeof(item));
			if (StrEqual(item, "HideTag")) {
				if (g_bHideTag[param1]) {
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
				g_strColor[param1][STRCOLOR_TAG][0] = '\0';
				CCC_ResetColor(param1, CCC_TagColor);
			}
			else {
				int iColorIndex = StringToInt(strBuffer);
				strcopy(g_strColor[param1][STRCOLOR_TAG], sizeof(g_strColor[][]), g_strColorHex[iColorIndex]);
				CCC_SetColor(param1, CCC_TagColor, StringToInt(g_strColorHex[iColorIndex], 16), false);
			}

			PrintUpdateMessage(param1);

			if (g_hSQL != null && IsClientAuthorized(param1)) {
				char strQuery[256];
				Format(strQuery, sizeof(strQuery), "SELECT tagcolor FROM cccm_users WHERE auth = '%s'", g_strAuth[param1]);
				g_hSQL.Query(SQLQuery_TagColor, strQuery, GetClientUserId(param1), DBPrio_High);
			}

			menu.DisplayAt(param1, menu.Selection, MENU_TIME_FOREVER);			
		}
		case MenuAction_DrawItem: {
			char colorIndex[8];
			menu.GetItem(param2, colorIndex, sizeof(colorIndex));
			int i = StringToInt(colorIndex);
			if (!g_bColorAdminFlags[i] || (g_bColorAdminFlags[i] && HasAdminFlag(param1, g_iColorFlagList[i]))) {
				return ITEMDRAW_DEFAULT;
			}
			return ITEMDRAW_DISABLED;
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
				g_strTagText[param1][0] = '\0';
				CCC_ResetTag(param1);
			}
			else if (StrEqual(strBuffer, "Change")) {
				g_bWaitingForTagInput[param1] = true;
				ReplyToCommand(param1, "\x01[\x03CCC\x01] Enter the new tag text:");
				return 0;
			}

			PrintUpdateMessage(param1);

			if (g_hSQL != null && IsClientAuthorized(param1)) {
				char strQuery[256];
				Format(strQuery, sizeof(strQuery), "SELECT tagtext FROM cccm_users WHERE auth = '%s'", g_strAuth[param1]);
				g_hSQL.Query(SQLQuery_TagText, strQuery, GetClientUserId(param1), DBPrio_High);
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
				g_strColor[param1][STRCOLOR_NAME][0] = '\0';
				CCC_ResetColor(param1, CCC_NameColor);
			}
			else {
				int iColorIndex = StringToInt(strBuffer);
				strcopy(g_strColor[param1][STRCOLOR_NAME], sizeof(g_strColor[][]), g_strColorHex[iColorIndex]);
				CCC_SetColor(param1, CCC_NameColor, StringToInt(g_strColorHex[iColorIndex], 16), false);
			}

			PrintUpdateMessage(param1);

			if (g_hSQL != null && IsClientAuthorized(param1)) {
				char strQuery[256];
				Format(strQuery, sizeof(strQuery), "SELECT namecolor FROM cccm_users WHERE auth = '%s'", g_strAuth[param1]);
				g_hSQL.Query(SQLQuery_NameColor, strQuery, GetClientUserId(param1), DBPrio_High);
			}

			menu.DisplayAt(param1, menu.Selection, MENU_TIME_FOREVER);			
		}
		case MenuAction_DrawItem: {
			char colorIndex[8];
			menu.GetItem(param2, colorIndex, sizeof(colorIndex));
			int i = StringToInt(colorIndex);
			if (!g_bColorAdminFlags[i] || (g_bColorAdminFlags[i] && HasAdminFlag(param1, g_iColorFlagList[i]))) {
				return ITEMDRAW_DEFAULT;
			}
			return ITEMDRAW_DISABLED;
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
				g_strColor[param1][STRCOLOR_CHAT][0] = '\0';
				CCC_ResetColor(param1, CCC_ChatColor);
			}
			else {
				int iColorIndex = StringToInt(strBuffer);
				strcopy(g_strColor[param1][STRCOLOR_CHAT], sizeof(g_strColor[][]), g_strColorHex[iColorIndex]);
				CCC_SetColor(param1, CCC_ChatColor, StringToInt(g_strColorHex[iColorIndex], 16), false);
			}

			PrintUpdateMessage(param1);

			if (g_hSQL != null && IsClientAuthorized(param1)) {
				char strQuery[256];
				Format(strQuery, sizeof(strQuery), "SELECT chatcolor FROM cccm_users WHERE auth = '%s'", g_strAuth[param1]);
				g_hSQL.Query(SQLQuery_ChatColor, strQuery, GetClientUserId(param1), DBPrio_High);
			}

			menu.DisplayAt(param1, menu.Selection, MENU_TIME_FOREVER);			
		}
		case MenuAction_DrawItem: {
			char colorIndex[8];
			menu.GetItem(param2, colorIndex, sizeof(colorIndex));
			int i = StringToInt(colorIndex);
			if (!g_bColorAdminFlags[i] || (g_bColorAdminFlags[i] && HasAdminFlag(param1, g_iColorFlagList[i]))) {
				return ITEMDRAW_DEFAULT;
			}
			return ITEMDRAW_DISABLED;
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

	for (int i = 0; i < MAX_COLORS; i++) {
		strcopy(g_strColorName[i], sizeof(g_strColorName[]), "");
		strcopy(g_strColorHex[i], sizeof(g_strColorHex[]), "");
		strcopy(g_strColorFlags[i], sizeof(g_strColorFlags[]), "");
		g_bColorAdminFlags[i] = false;
		for (int i2 = 0; i2 < 16; i2++) {
			g_iColorFlagList[i][i2] = view_as<AdminFlag>(-1);
		}
	}

	g_iColorCount = 0;
	do {
		keyvalues.GetString("name", g_strColorName[g_iColorCount], sizeof(g_strColorName[]));
		keyvalues.GetString("hex",	g_strColorHex[g_iColorCount], sizeof(g_strColorHex[]));
		ReplaceString(g_strColorHex[g_iColorCount], sizeof(g_strColorHex[]), "#", "", false);
		keyvalues.GetString("flags", g_strColorFlags[g_iColorCount], sizeof(g_strColorFlags[]));

		if (!IsValidHex(g_strColorHex[g_iColorCount])) {
			LogError("Invalid hexadecimal value for color %s.", g_strColorName[g_iColorCount]);
			strcopy(g_strColorName[g_iColorCount], sizeof(g_strColorName[]), "");
			strcopy(g_strColorHex[g_iColorCount], sizeof(g_strColorHex[]), "");
			strcopy(g_strColorFlags[g_iColorCount], sizeof(g_strColorFlags[]), "");
		}

		if (!StrEqual(g_strColorFlags[g_iColorCount], "")) {
			g_bColorAdminFlags[g_iColorCount] = true;
			FlagBitsToArray(ReadFlagString(g_strColorFlags[g_iColorCount]), g_iColorFlagList[g_iColorCount], sizeof(g_iColorFlagList[]));
		}
		g_iColorCount++;
	} while (keyvalues.GotoNextKey());
	delete keyvalues;

	delete g_menuMain;
	delete g_menuTagColor;
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

	g_hSQL = db;

	DBDriver driverType = g_hSQL.Driver; 
	driverType.GetProduct(g_strSQLDriver, sizeof(g_strSQLDriver));

	if (StrEqual(g_strSQLDriver, "mysql", false)) {
		LogMessage("MySQL server configured. Variable saving enabled.");
		g_hSQL.Query(
			SQLQuery_Update
			, "CREATE TABLE IF NOT EXISTS cccm_users"
			... "("
			... "id INT(64) NOT NULL AUTO_INCREMENT, "
			... "auth VARCHAR(32) UNIQUE, "
			... "hidetag VARCHAR(1), "
			... "tagcolor VARCHAR(7), "
			... "tagtext VARCHAR(32), "
			... "namecolor VARCHAR(7), "
			... "chatcolor VARCHAR(7), "
			... "PRIMARY KEY (id)"
			... ")"
			, _
			, DBPrio_High
		);
	}
	else if (StrEqual(g_strSQLDriver, "sqlite", false)) {
		LogMessage("SQlite server configured. Variable saving enabled.");
		g_hSQL.Query(
			SQLQuery_Update
			, "CREATE TABLE IF NOT EXISTS cccm_users "
			... "("
			... "id INTERGER PRIMARY KEY, "
			... "auth varchar(32) UNIQUE, "
			... "hidetag varchar(1), "
			... "tagcolor varchar(7), "
			... "tagtext varchar(32), "
			... "namecolor varchar(7), "
			... "chatcolor varchar(7)"
			... ")"
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
			LoadChatConfig(i);
		}
	}
}

void SQL_OnChatConfigReceived(Database db, DBResultSet results, const char[] error, any data) {
	int client = GetClientOfUserId(data);
	if (!IsValidClient(client)) {
		return;
	}

	if (db == null || results == null) {
		LogError("SQL Error: %s", error);
		return;
	}

	if (results.FetchRow() && results.RowCount != 0) {
		g_bHideTag[client] = view_as<bool>(results.FetchInt(0));

		char strTag[MAX_HEXSTR_SIZE], strName[MAX_HEXSTR_SIZE], strChat[MAX_HEXSTR_SIZE];
		results.FetchString(1, strTag, sizeof(strTag));
		if (IsValidHex(strTag)) {
			strcopy(g_strColor[client][STRCOLOR_TAG], sizeof(g_strColor[][]), strTag);
			CCC_SetColor(client, CCC_TagColor, StringToInt(g_strColor[client][STRCOLOR_TAG], 16), false);
		}
		else if (StrEqual(strTag, "-1")) {
			strcopy(g_strColor[client][STRCOLOR_TAG], sizeof(g_strColor[][]), "-1");
		}

		char tagText[MAX_TAGTEXT_SIZE];
		results.FetchString(2, tagText, sizeof(tagText)); 
		if(tagText[0] != '\0') {
			strcopy(g_strTagText[client], sizeof(g_strTagText[]), tagText);
			CCC_SetTag(client, g_strTagText[client]);
		}

		results.FetchString(3, strName, sizeof(strName));
		if (IsValidHex(strName)) {
			strcopy(g_strColor[client][STRCOLOR_NAME], sizeof(g_strColor[][]), strName);
			CCC_SetColor(client, CCC_NameColor, StringToInt(g_strColor[client][STRCOLOR_NAME], 16), false);
		}

		results.FetchString(4, strChat, sizeof(strChat));
		if (IsValidHex(strChat)) {
			strcopy(g_strColor[client][ACCESS_CHAT], sizeof(g_strColor[][]), strChat);
			CCC_SetColor(client, CCC_ChatColor, StringToInt(g_strColor[client][STRCOLOR_CHAT], 16), false);
		}

		g_bChatConfigLoaded[client] = true;
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
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "INSERT INTO cccm_users (hidetag, auth) VALUES (%i, '%s')", g_bHideTag[client], g_strAuth[client]);
		g_hSQL.Query(SQLQuery_Update, strQuery, _, DBPrio_High);
	}
	else {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "UPDATE cccm_users SET hidetag = '%i' WHERE auth = '%s'", g_bHideTag[client], g_strAuth[client]);
		g_hSQL.Query(SQLQuery_Update, strQuery, _, DBPrio_Normal);
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
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "INSERT INTO cccm_users (tagcolor, auth) VALUES ('%s', '%s')", g_strColor[client][STRCOLOR_TAG], g_strAuth[client]);
		g_hSQL.Query(SQLQuery_Update, strQuery, _, DBPrio_High);
	}
	else {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "UPDATE cccm_users SET tagcolor = '%s' WHERE auth = '%s'", g_strColor[client][STRCOLOR_TAG], g_strAuth[client]);
		g_hSQL.Query(SQLQuery_Update, strQuery, _, DBPrio_Normal);
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
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "INSERT INTO cccm_users (tagtext, auth) VALUES ('%s', '%s')", g_strTagText[client], g_strAuth[client]);
		g_hSQL.Query(SQLQuery_Update, strQuery, _, DBPrio_High);
	}
	else {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "UPDATE cccm_users SET tagtext = '%s' WHERE auth = '%s'", g_strTagText[client], g_strAuth[client]);
		g_hSQL.Query(SQLQuery_Update, strQuery, _, DBPrio_Normal);
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
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "INSERT INTO cccm_users (namecolor, auth) VALUES ('%s', '%s')", g_strColor[client][STRCOLOR_NAME], g_strAuth[client]);
		g_hSQL.Query(SQLQuery_Update, strQuery, _, DBPrio_High);
	}
	else {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "UPDATE cccm_users SET namecolor = '%s' WHERE auth = '%s'", g_strColor[client][STRCOLOR_NAME], g_strAuth[client]);
		g_hSQL.Query(SQLQuery_Update, strQuery, _, DBPrio_Normal);
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
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "INSERT INTO cccm_users (chatcolor, auth) VALUES ('%s', '%s')", g_strColor[client][STRCOLOR_CHAT], g_strAuth[client]);
		g_hSQL.Query(SQLQuery_Update, strQuery, _, DBPrio_High);
	}
	else {
		char strQuery[256];
		Format(strQuery, sizeof(strQuery), "UPDATE cccm_users SET chatcolor = '%s' WHERE auth = '%s'", g_strColor[client][STRCOLOR_CHAT], g_strAuth[client]);
		g_hSQL.Query(SQLQuery_Update, strQuery, _, DBPrio_Normal);
	}
}

void SQLQuery_Update(Handle owner, Handle hndl, const char[] strError, any data) {
	if (hndl == null) {
		LogError("SQL Error: %s", strError);
	}
}

// ====[STOCKS]==============================================================

bool IsValidClient(int client) {
	return (0 < client <= MaxClients && IsClientInGame(client));
}

bool IsValidHex(const char[] hex) {
	return (strlen(hex) == 6 && g_hRegexHex.Match(hex));
}

bool HasAdminFlag(int client, const AdminFlag flaglist[16]) {
	int flags = GetUserFlagBits(client);
	if (flags & ADMFLAG_ROOT) {
		return true;
	}

	for (int i = 0; i < sizeof(flaglist); i++) {
		if (flags & FlagToBit(flaglist[i])) {
			return true;
		}
	}
	return false;
}

void PrintUpdateMessage(int client) {
	if (!IsValidClient(client)) {
		return;
	}
	
	char tag[24];
	char tagcolor[12];
	if (!g_bHideTag[client]) {
		CCC_GetTag(client, tag, sizeof(tag));
		if (g_strColor[client][STRCOLOR_TAG][0] != '\0') {
			Format(tagcolor, sizeof(tagcolor), "\x07%s", g_strColor[client][STRCOLOR_TAG]);
		}
	}
	char g_sTeamColor[][] = {"FFFFFF", "CCCCCC", "FF4040", "99CCFF"};
	char namecolor[12];
	if (g_strColor[client][STRCOLOR_NAME][0] != '\0') {
		Format(namecolor, sizeof(namecolor), "\x07%s", g_strColor[client][STRCOLOR_NAME]);
	}
	else {
		Format(namecolor, sizeof(namecolor), "\x07%s", g_sTeamColor[GetClientTeam(client)]);
	}
	char chatcolor[12];
	if (g_strColor[client][STRCOLOR_CHAT][0] != '\0') {
		Format(chatcolor, sizeof(chatcolor), "\x07%s", g_strColor[client][STRCOLOR_CHAT]);
	}

	PrintColoredChat(client, "%s%s\x01%s%N\x01 :%s Color settings have been updated.", tagcolor, tag, namecolor, client, chatcolor);
}