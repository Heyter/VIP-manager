#include <sourcemod>

// Plugin information
#define Author "Shadow_Man"
#define Version "0.2 Dev"

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
public OnPluginStart()
{
	// Init CVars
	VIP_Check_Activated = CreateConVar("vipm_check_activated", "true", "Activating checking for outdated VIPs");
	VIP_Check_Time = CreateConVar("vipm_check_time", "720", "Time duration, in minutes, to check for outdated VIPs");
	
	VIP_Log = CreateConVar("vipm_log", "false", "Activate logging. Logs all added and removed VIPs");
	
	// Use config file
	AutoExecConfig(true, "VIP-Manager");
	
	// Register all commands
	RegAdminCmd("vipm_help", VIP_Help, ADMFLAG_ROOT, "Show a list of commands");
	//RegAdminCmd("vipm", VIP_Manager_Menu, ADMFLAG_ROOT, "Show the VIP-Manager menu");
	RegAdminCmd("vipm_add", VIP_Add, ADMFLAG_ROOT, "Add a VIP");
	RegAdminCmd("vipm_rm", VIP_Remove, ADMFLAG_ROOT, "Delete a VIP");
	RegAdminCmd("vipm_check", VIP_Check_Cmd, ADMFLAG_ROOT, "Checks for oudated VIPs");
	
	// Init Timer
	if(GetConVarBool(VIP_Check_Activated)) CheckTimer = CreateTimer(GetConVarFloat(VIP_Check_Time) * 60.0, VIP_Check_Timer, INVALID_HANDLE, TIMER_REPEAT);
}

public Action:VIP_Help(client, args)
{
	// Print all commands with syntax
	if(client > 0)
	{
		// For client
		PrintToChat(client, "vipm_help 								| Show this text.");
		PrintToChat(client, "vipm_add <days> <name> [\"SteamID\"]	| Adds a new VIP for give days.");
		PrintToChat(client, "vipm_rm <name>							| Remove a VIP.");
		PrintToChat(client, "vipm_check								| Checks for outdated VIPs.");
	}
	else
	{
		// For server
		PrintToServer("vipm_help 								| Show this text.");
		PrintToServer("vipm_add <days> <name> [\"SteamID\"]	| Adds a new VIP for give days.");
		PrintToServer("vipm_rm <name>							| Remove a VIP.");
		PrintToServer("vipm_check								| Checks for outdated VIPs.");
	}
	
	return Plugin_Handled;
}

public Action:VIP_Check_Cmd(client, args)
{
	VIP_Check_Timer(INVALID_HANDLE);
	
	return Plugin_Handled;
}

// Checking for outdated VIPs
public Action:VIP_Check_Timer(Handle:timer)
{
	// Create SQL connection
	decl String:error[255];
	new Handle:connection = SQL_DefConnect(error, sizeof(error));
	
	// Check for connection error
	if(connection == INVALID_HANDLE)
	{
		// Log error
		if(GetConVarBool(VIP_Log)) LogError("[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
		PrintToServer("[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
		
		return Plugin_Continue;
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
			if(GetConVarBool(VIP_Log)) LogError("[VIP-Manager] Error on Query! Error: %s", error);
			PrintToServer("[VIP-Manager] Error on Query! Error: %s", error);
			
			return Plugin_Continue;
		}
		else
		{
			// Return if none VIP is oudated
			if(SQL_GetRowCount(hQuery) == 0) return Plugin_Continue;
			
			// Delete all oudated VIPs
			if(!SQL_FastQuery(connection, "DELETE FROM sm_admins WHERE TIMEDIFF(DATE_ADD(joindate, INTERVAL expirationday DAY), NOW()) < 0 AND expirationday >= 0"))
			{
				// Log error
				SQL_GetError(connection, error, sizeof(error));
				if(GetConVarBool(VIP_Log)) LogError("[VIP-Manager] Error while deleting VIPs! Error: %s", error);
				PrintToServer("[VIP-Manager] Error while deleting VIPs! Error: %s", error);
			
				return Plugin_Continue;
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
	
	return Plugin_Handled;
}

public Action:VIP_Add(client, args)
{
	// Check arguments count
	if(args < 2)
	{
		if(client > 0) PrintToChat(client, "[VIP-Manager] Use vipm_add <days> <name> [\"SteamID\"]");
		else PrintToServer("[VIP-Manager] Use vipm_add <days> <name> [\"SteamID\"]");
		
		return Plugin_Continue;
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
			else if(i == MaxClients)
			{
				if(client > 0) PrintToChat(client, "[VIP-Manager] Can't find player %s", Name);
				else PrintToServer("[VIP-Manager] Can't find player %s", Name);
				
				return Plugin_Continue;
			}
		}
	}
	
	// Create connection to sql server
	decl String:error[255];
	new Handle:connection = SQL_DefConnect(error, sizeof(error));
	
	if(connection == INVALID_HANDLE)
	{
		// Log error
		if(GetConVarBool(VIP_Log)) LogError("[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
		if(client > 0) PrintToChat(client, "[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
		else PrintToServer("[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
		
		return Plugin_Continue;
	}
	else
	{
		new Handle:hQuery;
		decl String:Query[255];
		
		// Set SQL query
		Format(Query, sizeof(Query), "INSERT INTO sm_admins (authtype, identity, flags, name, expirationday) VALUES ('steam', '%s', 'a', '%s', %i)", SteamID, Name, days);
		hQuery = SQL_Query(connection, Query);
		
		if(hQuery == INVALID_HANDLE)
		{
			// Log error
			SQL_GetError(connection, error, sizeof(error));
			if(GetConVarBool(VIP_Log)) LogError("[VIP-Manager] Error on Query! Error: %s", error);
			if(client > 0) PrintToChat(client, "[VIP-Manager] Error on Query! Error: %s", error);
			else PrintToServer("[VIP-Manager] Error on Query! Error: %s", error);
			
			return Plugin_Continue;
		}
		else
		{
			// Log new VIP
			if(GetConVarBool(VIP_Log)) LogMessage("[VIP-Manager] Added VIP %s (SteamID: %s) for %i days", Name, SteamID, days);
			if(client > 0) PrintToChat(client, "[VIP-Manager] Added VIP %s (SteamID: %s) for %i days", Name, SteamID, days);
			else PrintToServer("[VIP-Manager] Added VIP %s (SteamID: %s) for %i days", Name, SteamID, days);
		}
		
		// Close Query
		CloseHandle(hQuery);
	}
	
	// Close connection
	CloseHandle(connection);
	
	return Plugin_Handled;
}

public Action:VIP_Remove(client, args)
{
	// Check arguments count
	if(args < 1)
	{
		if(client > 0) PrintToChat(client, "[VIP-Manager] Use vipm_rm <name>");
		else PrintToServer("[VIP-Manager] Use vipm_rm <name>");
		
		return Plugin_Continue;
	}
	
	// Get Name
	decl String:Name[255];
	GetCmdArg(1, Name, sizeof(Name));
	
	// Create connection to sql server
	decl String:error[255];
	new Handle:connection = SQL_DefConnect(error, sizeof(error));
	
	if(connection == INVALID_HANDLE)
	{
		// Log error
		if(GetConVarBool(VIP_Log)) LogError("[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
		if(client > 0) PrintToChat(client, "[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
		else PrintToServer("[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
		
		return Plugin_Continue;
	}
	else
	{
		new Handle:hQuery;
		decl String:Query[255];
		
		// Set SQL query
		Format(Query, sizeof(Query), "SELECT identity, name FROM sm_admins WHERE name LIKE '\%%s\%'");
		hQuery = SQL_Query(connection, Query);
		
		if(hQuery == INVALID_HANDLE)
		{
			// Log error
			SQL_GetError(connection, error, sizeof(error));
			if(GetConVarBool(VIP_Log)) LogError("[VIP-Manager] Error on Query! Error: %s", error);
			if(client > 0) PrintToChat(client, "[VIP-Manager] Error on Query! Error: %s", error);
			else PrintToServer("[VIP-Manager] Error on Query! Error: %s", error);
			
			return Plugin_Continue;
		}
		else
		{
			// Check count of founded VIPs
			if(SQL_GetRowCount(hQuery) > 1)
			{
				// Log error
				if(GetConVarBool(VIP_Log)) LogError("[VIP-Manager] Found more than one VIP by searching for %s!", Name);
				if(client > 0) PrintToChat(client, "[VIP-Manager] Found more than one VIP!");
				else PrintToServer("[VIP-Manager] Found more than one VIP!");
				
				return Plugin_Continue;
			}
			
			// Get SteamID
			decl String:SteamID[64];
			if(SQL_FetchRow(hQuery))
			{
				SQL_FetchString(hQuery, 1, SteamID, sizeof(SteamID));
				SQL_FetchString(hQuery, 2, Name, sizeof(Name));
			}
			else
			{
				// Log error
				SQL_GetError(connection, error, sizeof(error));
				if(GetConVarBool(VIP_Log)) LogError("[VIP-Manager] Error on Query! Error: %s", error);
				if(client > 0) PrintToChat(client, "[VIP-Manager] Error on Query! Error: %s", error);
				else PrintToServer("[VIP-Manager] Error on Query! Error: %s", error);
				
				return Plugin_Continue;
			}
			
			// Delete VIP
			Format(Query, sizeof(Query), "DELETE FROM sm_admins WHERE identity = %s", SteamID);
			
			if(!SQL_FastQuery(connection, Query))
			{
				// Log error
				SQL_GetError(connection, error, sizeof(error));
				if(GetConVarBool(VIP_Log)) LogError("[VIP-Manager] Error while deleting VIPs! Error: %s", error);
				if(client > 0) PrintToChat(client, "[VIP-Manager] Error while deleting VIPs! Error: %s", error);
				else PrintToServer("[VIP-Manager] Error while deleting VIPs! Error: %s", error);
			
				return Plugin_Continue;
			}
			else
			{
				// Log deleted VIP
				if(GetConVarBool(VIP_Log)) LogMessage("[VIP-Manager] Deleted VIP %s (SteamID: %s)", Name, SteamID);
				if(client > 0) PrintToChat(client, "[VIP-Manager] Deleted VIP %s (SteamID: %s)", Name, SteamID);
				else PrintToServer("[VIP-Manager] Deleted VIP %s (SteamID: %s)", Name, SteamID);
			}
		}
		
		// Close Query
		CloseHandle(hQuery);
	}
	
	//Close connection
	CloseHandle(connection);
	
	return Plugin_Handled;
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
