#include <sourcemod>

// Plugin information
#define Author "Shadow_Man"
#define Version "0.2 Alpha"

public Plugin:myinfo =
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

// Logfile path
new String:logFilePath[512];

// Plugin start
public OnPluginStart()
{
	// Print start message
	PrintToServer("[VIP-Manager] Starting...");
	
	// Init CVars
	VIP_Check_Activated = CreateConVar("vipm_check_activated", "1", "Activating checking for outdated VIPs", FCVAR_NONE, true, 0.0, true, 1.0);
	VIP_Check_Time = CreateConVar("vipm_check_time", "720", "Time duration, in minutes, to check for outdated VIPs", FCVAR_NONE, true, 1.0);
	
	VIP_Log = CreateConVar("vipm_log", "0", "Activate logging. Logs all added and removed VIPs", FCVAR_NONE, true, 0.0, true, 1.0);
	
	// Set CVars hooks
	HookConVarChange(VIP_Check_Activated, OnCheckActivatedChanged);
	HookConVarChange(VIP_Check_Time, OnCheckTimeChanged);
	
	// Use config file
	AutoExecConfig(true, "VIP-Manager");
	
	// Register all commands
	RegAdminCmd("vipm_help", VIP_Help, ADMFLAG_ROOT, "Show a list of commands");
	//RegAdminCmd("vipm", VIP_Manager_Menu, ADMFLAG_ROOT, "Show the VIP-Manager menu");
	RegAdminCmd("vipm_add", VIP_Add, ADMFLAG_ROOT, "Add a VIP");
	RegAdminCmd("vipm_rm", VIP_Remove, ADMFLAG_ROOT, "Delete a VIP");
	RegAdminCmd("vipm_time", VIP_Change_Time, ADMFLAG_ROOT, "Change time of a VIP");
	RegAdminCmd("vipm_check", VIP_Check_Cmd, ADMFLAG_ROOT, "Checks for oudated VIPs");	
}

public OnConfigsExecuted()
{
	// Init Timer
	SetCheckTimer();
	
	// Print log status
	if(GetConVarBool(VIP_Log))
	{
		PrintToServer("[VIP-Manager] Logging enabled.");
		
		// Build Logfile path
		BuildPath(Path_SM, logFilePath, sizeof(logFilePath), "logs/VIP-Manager.log");
		PrintToServer("[VIP-Manager] Logfile loaction is %s", logFilePath);
	}
	else PrintToServer("[VIP-Manager] Logging disabled.");
	
	// Print finish message
	PrintToServer("[VIP-Manager] Loaded successfully");
}

public Action:VIP_Help(client, args)
{
	// Print all commands with syntax
	if(client > 0)
	{
		// For client
		PrintToChat(client, "vipm_help | Show this text.");
		PrintToChat(client, "vipm_add <name> <days> [\"SteamID\"] | Adds a new VIP for give days.");
		PrintToChat(client, "vipm_rm <name> | Remove a VIP.");
		PrintToChat(client, "vipm_time <set|add|sub> <\"name\"> <time> | Change time of a VIP.");
		PrintToChat(client, "vipm_check | Checks for outdated VIPs.");
		PrintToChat(client, "[VIP-Manager] by %s (Version %s)", Author, Version);
	}
	else
	{
		// For server
		PrintToServer("vipm_help | Show this text.");
		PrintToServer("vipm_add <days> <\"name\"> [\"SteamID\"] | Adds a new VIP for give days.");
		PrintToServer("vipm_rm <\"name\"> | Remove a VIP.");
		PrintToServer("vipm_time <set|add|sub> <\"name\"> <time> | Change time of a VIP.");
		PrintToServer("vipm_check | Checks for outdated VIPs.");
		PrintToServer("[VIP-Manager] by %s (Version %s)", Author, Version);
	}
	
	return Plugin_Handled;
}

VIP_Check(client)
{
	if(client > 0) PrintToChat(client, "[VIP-Manager] Starting VIP check!");
	else PrintToServer("[VIP-Manager] Starting VIP check!");
	
	// Create SQL connection
	decl String:error[255] = "\0";
	new Handle:connection = SQL_DefConnect(error, sizeof(error));
	
	// Check for connection error
	if(connection == INVALID_HANDLE)
	{
		// Log error
		if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
		if(client > 0) PrintToChat(client, "[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
		else PrintToServer("[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
		
		return false;
	}
	else
	{
		decl String:query[255] = "\0";
		new Handle:hQuery;
		
		// Check for oudated VIPs
		Format(query, sizeof(query), "SELECT name, identity FROM sm_admins WHERE TIMEDIFF(DATE_ADD(joindate, INTERVAL expirationday DAY), NOW()) < 0 AND expirationday >= 0 AND flags = 'a'");
		hQuery = SQL_Query(connection, query);
		
		if(hQuery == INVALID_HANDLE)
		{
			// Log error
			SQL_GetError(connection, error, sizeof(error));
			if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Error on Query! Error: %s", error);
			if(client > 0) PrintToChat(client, "[VIP-Manager] Error on Query! Error: %s", error);
			else PrintToServer("[VIP-Manager] Error on Query! Error: %s", error);
			
			return false;
		}
		else
		{
			// Return if none VIP is oudated
			if(SQL_GetRowCount(hQuery) == 0)
			{
				if(client > 0) PrintToChat(client, "[VIP-Manager] None VIPs are outdated!");
				else PrintToServer("[VIP-Manager] None VIPs are outdated!");
				
				return false;
			}
			
			// Delete all oudated VIPs
			if(!SQL_FastQuery(connection, "DELETE FROM sm_admins WHERE TIMEDIFF(DATE_ADD(joindate, INTERVAL expirationday DAY), NOW()) < 0 AND expirationday >= 0 AND flags = 'a'"))
			{
				// Log error
				SQL_GetError(connection, error, sizeof(error));
				if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Error while deleting VIPs! Error: %s", error);
				if(client > 0) PrintToChat(client, "[VIP-Manager] Error while deleting VIPs! Error: %s", error);
				else PrintToServer("[VIP-Manager] Error while deleting VIPs! Error: %s", error);
			
				return false;
			}
			else
			{
				decl String:name[255] = "\0";
				decl String:steamid[128] = "\0";
				
				while(SQL_FetchRow(hQuery))
				{
					SQL_FetchString(hQuery, 0, name, sizeof(name));
					SQL_FetchString(hQuery, 1, steamid, sizeof(steamid));
					
					// Execute custom SQL queries
					Execute_Custom_OnRemove_Queries(client, connection, steamid, name);
					
					// Log all oudated VIPs
					if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] VIP '%s' (steamid: %s) deleted. Reason: Time expired!", name, steamid);
					if(client > 0) PrintToChat(client, "[VIP-Manager] VIP '%s' (steamid: %s) deleted. Reason: Time expired!", name, steamid);
					else PrintToServer("[VIP-Manager] VIP '%s' (steamid: %s) deleted. Reason: Time expired!", name, steamid);
				}
			}
			
			// Close Query
			CloseHandle(hQuery);
		}
		
		// Close connection
		CloseHandle(connection);
	}
	
	if(client > 0) PrintToChat(client, "[VIP-Manager] VIP check finished!");
	else PrintToServer("[VIP-Manager] VIP check finished!");
	
	return true;
}

public Action:VIP_Check_Cmd(client, args)
{
  if(!VIP_Check(client)) return Plugin_Continue;
  else return Plugin_Handled;
}

// Checking for outdated VIPs
public Action:VIP_Check_Timer(Handle:timer)
{
	if(!VIP_Check(0)) return Plugin_Continue;
	else return Plugin_Handled;
}

public OnCheckTimeChanged(Handle:cvar, String:oldVal[], String:newVal[])
{
	SetCheckTimer();
}

public OnCheckActivatedChanged(Handle:cvar, String:oldVal[], String:newVal[])
{
	SetCheckTimer();
}

public Action:VIP_Add(client, args)
{
	// Check arguments count
	if(args < 2)
	{
		if(client > 0) PrintToChat(client, "[VIP-Manager] Use vipm_add <\"name\"> <days> [\"SteamID\"]");
		else PrintToServer("[VIP-Manager] Use vipm_add <\"name\"> <days> [\"SteamID\"]");
		
		return Plugin_Continue;
	}
	
	// Get days count, name and SteamID
	decl String:SteamID[64] = "\0";
	decl String:Name[255] = "\0";
	decl String:days[16] = "\0";
	
	GetCmdArg(1, Name, sizeof(Name));
	GetCmdArg(2, days, sizeof(days));
	if(args == 3)
	{
		GetCmdArg(3, SteamID, sizeof(SteamID));
		if(!CheckSteamID(SteamID))
		{
			if(client > 0) PrintToChat(client, "[VIP-Manager] Please use valid SteamID format (STEAM_X:X:XXXXXX)");
			else PrintToServer("[VIP-Manager] Please use valid SteamID format (STEAM_X:X:XXXXXX)");
			
			return Plugin_Continue;
		}
	}
	else
	{
		// Search client by name
		for(new i = 1; i <= MaxClients; i++)
		{
			if(IsClientConnected(i))
			{
				// Get client name
				decl String:cName[255] = "\0";
				GetClientName(i, cName, sizeof(cName));
				
				if(StrContains(cName, Name, false) >= 0)
				{
					// Get SteamID and set name to full name
					GetClientAuthString(i, SteamID, sizeof(SteamID));
					Name = cName;
					
					break;
				}
			}
			else if(i == MaxClients)
			{
				if(client > 0) PrintToChat(client, "[VIP-Manager] Can't find player '%s'", Name);
				else PrintToServer("[VIP-Manager] Can't find player '%s'", Name);
				
				return Plugin_Continue;
			}
		}
	}
	
	// Create connection to sql server
	decl String:error[255] = "\0";
	new Handle:connection = SQL_DefConnect(error, sizeof(error));
	
	if(connection == INVALID_HANDLE)
	{
		// Log error
		if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
		if(client > 0) PrintToChat(client, "[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
		else PrintToServer("[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
		
		return Plugin_Continue;
	}
	else
	{
		new Handle:hQuery;
		decl String:Query[255] = "\0";
		
		// Set SQL query
		Format(Query, sizeof(Query), "INSERT INTO sm_admins (authtype, identity, flags, name, expirationday) VALUES ('steam', '%s', 'a', '%s', %s)", SteamID, Name, days);
		hQuery = SQL_Query(connection, Query);
		
		if(hQuery == INVALID_HANDLE)
		{
			// Log error
			SQL_GetError(connection, error, sizeof(error));
			if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Error on Query! Error: %s", error);
			if(client > 0) PrintToChat(client, "[VIP-Manager] Error on Query! Error: %s", error);
			else PrintToServer("[VIP-Manager] Error on Query! Error: %s", error);
			
			return Plugin_Continue;
		}
		else
		{
			// Execute custom SQL queries
			Execute_Custom_OnAdd_Queries(client, connection, SteamID, Name, days);
			
			// Log new VIP
			if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Added VIP '%s' (SteamID: %s) for %s days", Name, SteamID, days);
			if(client > 0) PrintToChat(client, "[VIP-Manager] Added VIP '%s' (SteamID: %s) for %s days", Name, SteamID, days);
			else PrintToServer("[VIP-Manager] Added VIP '%s' (SteamID: %s) for %s days", Name, SteamID, days);
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
		if(client > 0) PrintToChat(client, "[VIP-Manager] Use vipm_rm <\"name\">");
		else PrintToServer("[VIP-Manager] Use vipm_rm <\"name\">");
		
		return Plugin_Continue;
	}
	
	// Get Name
	decl String:Name[255] = "\0";
	GetCmdArg(1, Name, sizeof(Name));
	
	// Create connection to sql server
	decl String:error[255] = "\0";
	new Handle:connection = SQL_DefConnect(error, sizeof(error));
	
	if(connection == INVALID_HANDLE)
	{
		// Log error
		if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
		if(client > 0) PrintToChat(client, "[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
		else PrintToServer("[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
		
		return Plugin_Continue;
	}
	else
	{
		new Handle:hQuery;
		decl String:Query[255] = "\0";
		
		// Set SQL query
		Format(Query, sizeof(Query), "SELECT identity, name FROM sm_admins WHERE name LIKE '%s%s%s' AND flags = 'a'", '%', Name, '%');
		hQuery = SQL_Query(connection, Query);
		
		if(hQuery == INVALID_HANDLE)
		{
			// Log error
			SQL_GetError(connection, error, sizeof(error));
			if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Error on Query! Error: %s", error);
			if(client > 0) PrintToChat(client, "[VIP-Manager] Error on Query! Error: %s", error);
			else PrintToServer("[VIP-Manager] Error on Query! Error: %s", error);
			
			return Plugin_Continue;
		}
		else
		{
			// Check count of founded VIPs
			if(SQL_GetRowCount(hQuery) > 1)
			{
				// Print error
				if(client > 0) PrintToChat(client, "[VIP-Manager] Found more than one VIP with the name like '%s'!", Name);
				else PrintToServer("[VIP-Manager] Found more than one VIP with the name like '%s'!", Name);
				
				return Plugin_Continue;
			}
			else if(SQL_GetRowCount(hQuery) == 0)
			{
				// Print error
				if(client > 0) PrintToChat(client, "[VIP-Manager] Can't found VIP with the name like '%s'!", Name);
				else PrintToServer("[VIP-Manager] Can't found VIP with the name like '%s'!", Name);
				
				return Plugin_Continue;
			}
			
			// Get SteamID
			decl String:SteamID[64] = "\0";
			if(SQL_FetchRow(hQuery))
			{
				SQL_FetchString(hQuery, 0, SteamID, sizeof(SteamID));
				SQL_FetchString(hQuery, 1, Name, sizeof(Name));
			}
			else
			{
				// Log error
				SQL_GetError(connection, error, sizeof(error));
				if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Error on Query! Error: %s", error);
				if(client > 0) PrintToChat(client, "[VIP-Manager] Error on Query! Error: %s", error);
				else PrintToServer("[VIP-Manager] Error on Query! Error: %s", error);
				
				return Plugin_Continue;
			}
			
			// Delete VIP
			Format(Query, sizeof(Query), "DELETE FROM sm_admins WHERE identity = '%s' AND flags = 'a'", SteamID);
			
			if(!SQL_FastQuery(connection, Query))
			{
				// Log error
				SQL_GetError(connection, error, sizeof(error));
				if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Error while deleting VIPs! Error: %s", error);
				if(client > 0) PrintToChat(client, "[VIP-Manager] Error while deleting VIPs! Error: %s", error);
				else PrintToServer("[VIP-Manager] Error while deleting VIPs! Error: %s", error);
			
				return Plugin_Continue;
			}
			else
			{
				// Execute custom SQL queries
				Execute_Custom_OnRemove_Queries(client, connection, SteamID, Name);
				
				// Log deleted VIP
				decl String:cName[255] = "\0";
				if(client > 0) GetClientName(client, cName, sizeof(cName));
				else cName = "Server console";
				
				if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Deleted VIP '%s' (SteamID: %s). Reason: Removed by %s!", Name, SteamID, cName);
				if(client > 0) PrintToChat(client, "[VIP-Manager] Deleted VIP '%s' (SteamID: %s). Reason: Removed by %s!", Name, SteamID, cName);
				else PrintToServer("[VIP-Manager] Deleted VIP '%s' (SteamID: %s). Reason: Removed by %s!", Name, SteamID, cName);
			}
		}
		
		// Close Query
		CloseHandle(hQuery);
	}
	
	//Close connection
	CloseHandle(connection);
	
	return Plugin_Handled;
}

public Action:VIP_Change_Time(client, args)
{
	// Check arguments
	if(args < 3)
	{
		if(client > 0) PrintToChat(client, "[VIP-Manager] Use vipm_time <set|add|sub> <\"name\"> <time>");
		else PrintToServer("[VIP-Manager] Use vipm_time <set|add|sub> <\"name\"> <days>");
	}
	else
	{
		// Init variables
		decl String:query[255] = "\0";
		decl String:cMode[16] = "\0";
		decl String:name[255] = "\0";
		decl String:days[16] = "\0";
		
		// Get command arguments
		GetCmdArg(1, cMode, sizeof(cMode));
		GetCmdArg(2, name, sizeof(name));
		GetCmdArg(3, days, sizeof(days));
		
		// Check change mode
		if(StrEqual(cMode, "set", false)) Format(query, sizeof(query), "UPDATE sm_admins SET expirationday = %s WHERE name LIKE '%s%s%s'", days, '%', name, '%');
		else if(StrEqual(cMode, "add", false)) Format(query, sizeof(query), "UPDATE sm_admins SET expirationday = expirationday + %s WHERE name LIKE '%s%s%s'", days, '%', name, '%');
		else if(StrEqual(cMode, "sub", false)) Format(query, sizeof(query), "UPDATE sm_admins SET expirationday = expirationday - %s WHERE name LIKE '%s%s%s'", days, '%', name, '%');
		else
		{
			if(client > 0) PrintToChat(client, "[VIP-Manager] No mode \"%s\" found. Available: set | add | sub", cMode);
			else PrintToServer("[VIP-Manager] No mode \"%s\" found. Available: set | add | sub", cMode);
			
			return Plugin_Continue;
		}
	
		// Create connection to sql server
		decl String:error[255] = "\0";
		new Handle:connection = SQL_DefConnect(error, sizeof(error));
		
		if(connection == INVALID_HANDLE)
		{
			// Log error
			if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
			if(client > 0) PrintToChat(client, "[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
			else PrintToServer("[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
			
			return Plugin_Continue;
		}
		else
		{
			new Handle:hQuery;
			decl String:sQuery[255] = "\0";
			
			// Set SQL query
			Format(sQuery, sizeof(sQuery), "SELECT name FROM sm_admins WHERE name LIKE '%s%s%s'", '%', name, '%');
			hQuery = SQL_Query(connection, sQuery);
			
			if(hQuery == INVALID_HANDLE)
			{
				// Log error
				SQL_GetError(connection, error, sizeof(error));
				if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Error on Query! Error: %s", error);
				if(client > 0) PrintToChat(client, "[VIP-Manager] Error on Query! Error: %s", error);
				else PrintToServer("[VIP-Manager] Error on Query! Error: %s", error);
				
				return Plugin_Continue;
			}
			else
			{
				// Check count of founded VIPs
				if(SQL_GetRowCount(hQuery) > 1)
				{
					// Print error
					if(client > 0) PrintToChat(client, "[VIP-Manager] Found more than one VIP with the name like '%s'!", name);
					else PrintToServer("[VIP-Manager] Found more than one VIP with the name like '%s'!", name);
					
					return Plugin_Continue;
				}
				else if(SQL_GetRowCount(hQuery) == 0)
				{
					// Print error
					if(client > 0) PrintToChat(client, "[VIP-Manager] Can't found VIP with the name like '%s'!", name);
					else PrintToServer("[VIP-Manager] Can't found VIP with the name like '%s'!", name);
					
					return Plugin_Continue;
				}
				
				// Get full VIP name
				if(SQL_FetchRow(hQuery)) SQL_FetchString(hQuery, 0, name, sizeof(name));
				else
				{
					// Log error
					SQL_GetError(connection, error, sizeof(error));
					if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Error on Query! Error: %s", error);
					if(client > 0) PrintToChat(client, "[VIP-Manager] Error on Query! Error: %s", error);
					else PrintToServer("[VIP-Manager] Error on Query! Error: %s", error);
					
					return Plugin_Continue;
				}
				
				// Update time
				if(!SQL_FastQuery(connection, query))
				{
					// Log error
					SQL_GetError(connection, error, sizeof(error));
					if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Error on Query! Error: %s", error);
					if(client > 0) PrintToChat(client, "[VIP-Manager] Error on Query! Error: %s", error);
					else PrintToServer("[VIP-Manager] Error on Query! Error: %s", error);
					
					return Plugin_Continue;
				}
				else
				{
					// Get new time and steamID
					decl String:nDays[16] = "\0";
					decl String:steamID[128] = "\0";
					
					CloseHandle(hQuery);
					Format(sQuery, sizeof(sQuery), "SELECT expirationday,identity FROM sm_admins WHERE name LIKE '%s%s%s'", '%', name, '%');
					hQuery = SQL_Query(connection, sQuery);
					
					if(hQuery == INVALID_HANDLE)
					{
						// Log error
						SQL_GetError(connection, error, sizeof(error));
						if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Error on Query! Error: %s", error);
						if(client > 0) PrintToChat(client, "[VIP-Manager] Error on Query! Error: %s", error);
						else PrintToServer("[VIP-Manager] Error on Query! Error: %s", error);
						
						return Plugin_Continue;
					}
					else
					{
						// Set new time and steamid
						if(SQL_FetchRow(hQuery))
						{
							SQL_FetchString(hQuery, 0, nDays, sizeof(nDays));
							SQL_FetchString(hQuery, 1, steamID, sizeof(steamID));
						}
						else
						{
							// Log error
							SQL_GetError(connection, error, sizeof(error));
							if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Error on Query! Error: %s", error);
							if(client > 0) PrintToChat(client, "[VIP-Manager] Error on Query! Error: %s", error);
							else PrintToServer("[VIP-Manager] Error on Query! Error: %s", error);
							
							return Plugin_Continue;
						}
						
						// Log change
						if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Changed time of %s (SteamID: %s) to %s days. Changed: %s %s days", name, steamID, nDays, cMode, days);
						
						if(client > 0) PrintToChat(client, "[VIP-Manager] Changed time of %s (SteamID: %s) to %s days. Changed: %s %s days", name, steamID, nDays, cMode, days);
						else PrintToServer("[VIP-Manager] Changed time of %s (SteamID: %s) to %s days. Changed: %s %s days", name, steamID, nDays, cMode, days);
					}
				}
			}
			
			// Close hQuery
			CloseHandle(hQuery);
		}
		
		// Close connection
		CloseHandle(connection);
	}
	
	return Plugin_Handled;
}

Execute_Custom_OnAdd_Queries(client, Handle:connection, String:steamID[], String:VIPname[], String:VIPtime[])
{
	// Check file
	new String:queryFilePath[255] = "cfg/sourcemod/VIP-Manager-OnAdd.cfg";
	if(!FileExists(queryFilePath))
	{
		PrintToServer("[VIP-Manager] Can't find file %s", queryFilePath);
		return;
	}
	
	new Handle:queryFile = OpenFile(queryFilePath, "r");
	new String:query[1024];
	
	new Handle:hQuery;
	new String:error[255];
	
	while(!IsEndOfFile(queryFile))
	{
		ReadFileLine(queryFile, query, sizeof(query));
		
		if(IsStringEmpty(query))
		{
			PrintToServer("Query is empty!");
			continue;
		}
		
		FormatQuery(query, sizeof(query), steamID, VIPname, VIPtime);
		
		if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Execute custom query: %s", query);
		if(client > 0) PrintToChat(client, "[VIP-Manager] Execute custom query: %s", query);
		else PrintToServer("[VIP-Manager] Execute custom query: %s", query);
		
		hQuery = SQL_Query(connection, query);
		
		if(hQuery == INVALID_HANDLE)
		{
			// Log error
			SQL_GetError(connection, error, sizeof(error));
			if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Error on Query! Error: %s", error);
			if(client > 0) PrintToChat(client, "[VIP-Manager] Error on Query! Error: %s", error);
			else PrintToServer("[VIP-Manager] Error on Query! Error: %s", error);
		}
		else CloseHandle(hQuery);
	}
	
	CloseHandle(queryFile);
}

Execute_Custom_OnRemove_Queries(client, Handle:connection, String:steamID[], String:VIPname[])
{
	// Check file
	new String:queryFilePath[255] = "cfg/sourcemod/VIP-Manager-OnRemove.cfg";
	if(!FileExists(queryFilePath))
	{
		PrintToServer("[VIP-Manager] Can't find file %s", queryFilePath);
		return;
	}
	
	new Handle:queryFile = OpenFile(queryFilePath, "r");
	new String:query[1024];
	
	new Handle:hQuery;
	new String:error[255];
	
	while(!IsEndOfFile(queryFile))
	{
		ReadFileLine(queryFile, query, sizeof(query));
		
		if(IsStringEmpty(query))
		{
			PrintToServer("Query is empty!");
			continue;
		}
		
		FormatQuery(query, sizeof(query), steamID, VIPname, "");
		
		if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Execute custom query: %s", query);
		if(client > 0) PrintToChat(client, "[VIP-Manager] Execute custom query: %s", query);
		else PrintToServer("[VIP-Manager] Execute custom query: %s", query);
		
		hQuery = SQL_Query(connection, query);
		
		if(hQuery == INVALID_HANDLE)
		{
			// Log error
			SQL_GetError(connection, error, sizeof(error));
			if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Error on Query! Error: %s", error);
			if(client > 0) PrintToChat(client, "[VIP-Manager] Error on Query! Error: %s", error);
			else PrintToServer("[VIP-Manager] Error on Query! Error: %s", error);
		}
		else CloseHandle(hQuery);
	}
	
	CloseHandle(queryFile);
}

FormatQuery(String:query[], maxlenght, String:steamID[], String:VIPname[], String:VIPtime[])
{
	TrimString(query);
	
	// Replace Steam id
	ReplaceString(query, maxlenght, "{steamid}", steamID, false);
	
	// Replace VIP name
	ReplaceString(query, maxlenght, "{name}", VIPname, false);
	
	// Replace VIP time
	ReplaceString(query, maxlenght, "{time}", VIPtime, false);
}

SetCheckTimer()
{
	if(CheckTimer != INVALID_HANDLE)
	{
		KillTimer(CheckTimer);
		CheckTimer = INVALID_HANDLE;
	}
	
	if(GetConVarBool(VIP_Check_Activated))
	{
		CheckTimer = CreateTimer(GetConVarFloat(VIP_Check_Time) * 60.0, VIP_Check_Timer, INVALID_HANDLE, TIMER_REPEAT);
		PrintToServer("[VIP-Manager] Will check for expired VIPs every %i minutes.", GetConVarInt(VIP_Check_Time));
	}
	else PrintToServer("[VIP-Manager] Auto check disabled.");
}

bool:IsStringEmpty(String:str[])
{
	// todo make this works
	return !str[0];
}

bool:CheckSteamID(String:steamID[])
{	
	return (strncmp(steamID, "STEAM_", 6, false) == 0 &&
			steamID[7] == ':' &&
			steamID[9] == ':');
}
