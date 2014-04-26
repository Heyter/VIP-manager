#include <sourcemod>

// Plugin information
#define Author "Shadow_Man"
#define Version "0.1 Dev"

public Plugin:info =
{
	name = "VIP-Manager",
	author = Author,
	description = "VIP-Manager for CTaF-Server",
	version = Version,
	url = "http://cf-server.pfweb.eu"
};

// CVars
public Handle:VIP_Check_Activated = INVALID_HANDLE;
public Handle:VIP_Check_Time = INVALID_HANDLE;

public Handle:VIP_Log = INVALID_HANDLE;

// Timer
new Handle:CheckTimer = INVALID_HANDLE;

// Plugin start
public onPluginStart()
{
	// Init CVars
	VIP_Check_Activated = CreateConVar("vipm_check_activated", "true", "Activating checking for outdated VIPs");
	VIP_Check_Time = CreateConVar("vipm_check_time", "720", "Time duration, in minutes, to check for outdated VIPs");
	
	VIP_Log = CreateConVar("vipm_log", "false", "Activate logging. Logs all added and removed VIPs");
	
	// Use config file
	AutoExecConfig(true, "VIP-Manager");
	
	// Register all commands
	//RegAdminCmd("vipm", VIP_Manager_Menu, ADMFLAG_ROOT, "Show the VIP-Manager menu");
	RegAdminCmd("vipm_add", VIP_Add, ADMFLAG_ROOT, "Add a VIP");
	RegAdminCmd("vipm_check", VIP_Check, ADMFLAG_ROOT, "Checks for oudated VIPs");
	RegAdminCmd("vipm_rm", VIP_Remove, ADMFLAG_ROOT, "Delete a VIP");
	
	// Init Timer
	if(GetConVarBool(VIP_Check_Activated)) CheckTimer = CreateTimer(GetConVarFloat(VIP_Check_Time) * 60.0, VIP_Check, INVALID_HANDLE, TIMER_REPEAT);
}

// Checking for outdated VIPs
public Action:VIP_Check(Handle:timer)
{
	// Create SQL connection
	decl String:error[255];
	new Handle:connection = SQL_DefConnect(error, sizeof(error));
	
	// Check for connection error
	if(connection == INVALID_HANDLE)
	{
		// Log error
		if(GetConVarBool(VIP_Log)) LogMessage("[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
		PrintToServer("[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
		
		return;
	}
	else
	{
		decl String:query[255];
		new Handle:hQuery;
		
		// Check for oudated VIPs
		Format(query, sizeof(query), "SELECT name, identity FROM sm_admins WHERE TIMEDIFF(DATE_ADD(joindate, INTERVAL expirationday DAY), NOW()) < 0 AND expirationday >= 0");
		hQuery = SQL_Query(connection, query);
		
		if(hQuery == INVALID_HANDLE)
		{
			// Log error
			SQL_GetError(connection, error, sizeof(error));
			if(GetConVarBool(VIP_Log)) LogMessage("[VIP-Manager] Error on Query! Error: %s", error);
			PrintToServer("[VIP-Manager] Error on Query! Error: %s", error);
			
			return;
		}
		else
		{
			// Return if none VIP is oudated
			if(SQL_GetRowCount(hQuery) == 0) return;
			
			// Delete all oudated VIPs
			if(!SQL_FastQuery(connection, "DELETE FROM sm_admins WHERE TIMEDIFF(DATE_ADD(joindate, INTERVAL expirationday DAY), NOW()) < 0 AND expirationday >= 0"))
			{
				// Log error
				SQL_GetError(connection, error, sizeof(error));
				if(GetConVarBool(VIP_Log)) LogMessage("[VIP-Manager] Error while deleting VIPs! Error: %s", error);
				PrintToServer("[VIP-Manager] Error while deleting VIPs! Error: %s", error);
			
				return;
			}
			else
			{
				// Log all oudated VIPs
				if(GetConVarBool(VIP_Log))
				{
					decl String:name[255];
					decl String:steamid[128];
					
					while(SQL_FetchRow(hQuery))
					{
						SQL_FetchString(hQuery, 0, name, sizeof(name));
						SQL_FetchString(hQuery, 1, steamid, sizeof(steamid));
						LogMessage("[VIP-Manager] VIP '%s' (steamid: %s) deleted.", name, steamid);
					}
				}
			}
			
			// Close Query
			CloseHandle(hQuery);
		}
		
		// Close connection
		CloseHandle(connection);
	}
}

public Action:VIP_Add(client, args)
{
	// Check arguments count
	if(args < 2)
	{
		PrintToChat(client, "[VIP-Manager] Use vipm_add <days> <name> [\"SteamID\"]");
		return;
	}
	
	// Get days count, name and SteamID
	decl String:SteamID[64];
	decl String:Name[255];
	decl String:days[16];
	
	GetCmdArg(1, days, sizeof(days));
	GetCmdArg(2, Name, sizeof(Name));
	if(args == 3) GetCmdArg(3, SteamID, sizeof(SteamID));
	else
	{
		// Search client by name
		for(new i = 1; i <= MaxClients; i++)
		{
			if(!IsClientConnected(i)) continue;
			
			// Get client name
			decl String:cName[255];
			GetClientName(i, cName, sizeof(cName));
			
			if(StrEqual(Name, cName))
			{
				// Get SteamID
				GetClientAuthString(i, SteamID, sizeof(SteamID));
				break;
			}
		}
	}
	
	// Create connection to sql server
	decl String:error[255];
	new Handle:connection = SQL_DefConnect(error, sizeof(error));
	
	if(connection == INVALID_HANDLE)
	{
		// Log error
		if(GetConVarBool(VIP_Log)) LogMessage("[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
		PrintToChat(client, "[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
		
		return;
	}
	else
	{
		new Handle:hQuery;
		decl String:Query[255];
		
		// Set SQL query
		Format(Query, sizeof(Query), "INSERT INTO sm_admins (authtype, identity, flags, name, expirationday) VALUES ('steam', %s, 'a', %s, %i)", SteamID, Name, days);
		hQuery = SQL_Query(connection, Query);
		
		if(hQuery == INVALID_HANDLE)
		{
			// Log error
			SQL_GetError(connection, error, sizeof(error));
			if(GetConVarBool(VIP_Log)) LogMessage("[VIP-Manager] Error on Query! Error: %s", error);
			PrintToChat(client, "[VIP-Manager] Error on Query! Error: %s", error);
			
			return;
		}
		else
		{
			// Log new VIP
			if(GetConVarBool(VIP_Log)) LogMessage("[VIP-Manager] Added VIP %s (SteamID: %s) for %i days", Name, SteamID, days);
			PrintToChat(client, "[VIP-Manager] Added VIP %s (SteamID: %s) for %i days", Name, SteamID, days);
		}
		
		// Close Query
		CloseHandle(hQuery);
	}
	
	// Close connection
	CloseHandle(connection);
}

/*
public Action:VIP_Manager_Menu(client, args)
{
	// Build menu
	new Handle:menu = CreateMenu(MenuHandler, MENU_ACTIONS_ALL);
	SetMenuTitle(menu, "VIP-Manager Main Menu");
	AddMenuItem(menu, "#addvip", "Add VIP");
	AddMenuItem(menu, "#rmvip", "Remove VIP");
	AddMenuItem(menu, "#addtime", "Add Time to VIP");
	SetMenuExitButton(menu, true);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public MenuHandler(Handle:menu, MenuAction:action, param1, param2)
{
	switch(action)
	{
		case MENU_ACTION_SELECT:
		{
			// Get selected Item
			decl String:info;
			GetMenuItem(menu, param2, info, sizeof(info));
			
			if(StrEqual(info, "#addvip"))
			{
				new Handle:menu = CreateMenu(MenuHandler, MENU_ACTIONS_ALL);
				SetMenuTitle(menu, "VIP-Manager Main Menu");
				AddMenuItem(menu, "#addvip", "Add VIP");
				AddMenuItem(menu, "#rmvip", "Remove VIP");
				AddMenuItem(menu, "#addtime", "Add Time to VIP");
				SetMenuExitButton(menu, true);
				DisplayMenu(menu, client, MENU_TIME_FOREVER);
			}
			else if(StrEqual(info, "#rmvip"))
			{
			}
			else if(StrEqual(info, "#addtime"))
			{
			}
		}
		
		case MENU_ACTION_END:
		{
			CloseHandle(menu);
		}
	}
}
*/
