#include <sourcemod>

#define Author "Shadow_Man"
#define Version "1.0"

public Plugin:myinfo =
{
	name = "VIP-Manager",
	author = Author,
	description = "VIP-Manager for CTaF-Server",
	version = Version,
	url = "http://cf-server.pfweb.eu"
};

// CVars
new Handle:VIP_Check_Activated = INVALID_HANDLE;
new Handle:VIP_Check_Time = INVALID_HANDLE;
new Handle:VIP_Log = INVALID_HANDLE;

new Handle:CheckTimer = INVALID_HANDLE;
new String:logFilePath[512];

public OnPluginStart()
{
	// Init CVars
	VIP_Check_Activated = CreateConVar("vipm_check_activated", "1", "Activating checking for outdated VIPs", FCVAR_NONE, true, 0.0, true, 1.0);
	VIP_Check_Time = CreateConVar("vipm_check_time", "720", "Time duration, in minutes, to check for outdated VIPs", FCVAR_NONE, true, 1.0);
	VIP_Log = CreateConVar("vipm_log", "0", "Activate logging. Logs all added and removed VIPs", FCVAR_NONE, true, 0.0, true, 1.0);

	HookConVarChange(VIP_Check_Activated, OnCheckActivatedChanged);
	HookConVarChange(VIP_Check_Time, OnCheckTimeChanged);

	// Register all commands
	RegAdminCmd("vipm_help", VIP_Help, ADMFLAG_ROOT, "Show a list of commands");
	//RegAdminCmd("vipm", VIP_Manager_Menu, ADMFLAG_ROOT, "Show the VIP-Manager menu");
	RegAdminCmd("vipm_add", VIP_Add, ADMFLAG_ROOT, "Add a VIP");
	RegAdminCmd("vipm_rm", VIP_Remove, ADMFLAG_ROOT, "Delete a VIP");
	RegAdminCmd("vipm_time", VIP_Change_Time, ADMFLAG_ROOT, "Change time of a VIP");
	RegAdminCmd("vipm_check", VIP_Check_Cmd, ADMFLAG_ROOT, "Checks for oudated VIPs");

	AutoExecConfig(true, "VIP-Manager");
}

public OnConfigsExecuted()
{
	SetCheckTimer();

	// Print log status
	if(GetConVarBool(VIP_Log))
	{
		PrintToServer("[VIP-Manager] Logging enabled.");
		BuildPath(Path_SM, logFilePath, sizeof(logFilePath), "logs/VIP-Manager.log");
		PrintToServer("[VIP-Manager] Logfile loaction is %s", logFilePath);
	}
	else PrintToServer("[VIP-Manager] Logging disabled.");
}

public Action:VIP_Help(client, args)
{
	ReplyToCommand(client, "vipm_help | Show this text.");
	ReplyToCommand(client, "vipm_add <name> <days> [\"SteamID\"] | Adds a new VIP for give days.");
	ReplyToCommand(client, "vipm_rm <name> | Remove a VIP.");
	ReplyToCommand(client, "vipm_time <set|add|sub> <\"name\"> <time> | Change time of a VIP.");
	ReplyToCommand(client, "vipm_check | Checks for outdated VIPs.");
	ReplyToCommand(client, "[VIP-Manager] by %s (Version %s)", Author, Version);

	return Plugin_Handled;
}

VIP_Check(client)
{
	ReplyToCommand(client, "[VIP-Manager] Starting VIP check!");

	// Create SQL connection
	decl String:error[255];
	new Handle:connection = SQL_DefConnect(error, sizeof(error));

	// Check for connection error
	if(connection == INVALID_HANDLE)
	{
		// Log error
		if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
		ReplyToCommand(client, "[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);

		return;
	}
	else
	{
		decl String:query[255];
		new Handle:hQuery;

		// Check for oudated VIPs
		Format(query, sizeof(query), "SELECT name, identity FROM sm_admins WHERE TIMEDIFF(DATE_ADD(joindate, INTERVAL expirationday DAY), NOW()) < 0 AND expirationday >= 0 AND flags = 'a'");
		hQuery = SQL_Query(connection, query);

		if(hQuery == INVALID_HANDLE)
		{
			// Log error
			SQL_GetError(connection, error, sizeof(error));
			if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Error on Query! Error: %s", error);
			ReplyToCommand(client, "[VIP-Manager] Error on Query! Error: %s", error);

			return;
		}
		else
		{
			// Return if none VIP is oudated
			if(SQL_GetRowCount(hQuery) == 0)
			{
				ReplyToCommand(client, "[VIP-Manager] None VIPs are outdated!");

				return;
			}

			// Delete all oudated VIPs
			if(!SQL_FastQuery(connection, "DELETE FROM sm_admins WHERE TIMEDIFF(DATE_ADD(joindate, INTERVAL expirationday DAY), NOW()) < 0 AND expirationday >= 0 AND flags = 'a'"))
			{
				// Log error
				SQL_GetError(connection, error, sizeof(error));
				if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Error while deleting VIPs! Error: %s", error);
				ReplyToCommand(client, "[VIP-Manager] Error while deleting VIPs! Error: %s", error);

				return;
			}
			else
			{
				decl String:name[255];
				decl String:steamid[128];

				while(SQL_FetchRow(hQuery))
				{
					SQL_FetchString(hQuery, 0, name, sizeof(name));
					SQL_FetchString(hQuery, 1, steamid, sizeof(steamid));

					// Execute custom SQL queries
					Execute_Custom_OnRemove_Queries(client, connection, steamid, name);

					// Log all oudated VIPs
					if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] VIP '%s' (steamid: %s) deleted. Reason: Time expired!", name, steamid);
					ReplyToCommand(client, "[VIP-Manager] VIP '%s' (steamid: %s) deleted. Reason: Time expired!", name, steamid);
				}
			}
			CloseHandle(hQuery);
		}
		CloseHandle(connection);
	}
	ReplyToCommand(client, "[VIP-Manager] VIP check finished!");
}

public Action:VIP_Check_Cmd(client, args)
{
	VIP_Check(client);
	return Plugin_Handled;
}

public Action:VIP_Check_Timer(Handle:timer)
{
	VIP_Check(0);
	return Plugin_Handled;
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
	if(args < 2)
	{
		ReplyToCommand(client, "[VIP-Manager] Use vipm_add <\"name\"> <days> [\"SteamID\"]");

		return Plugin_Handled;
	}

	decl String:SteamID[64];
	decl String:Name[255];
	decl String:days[16];

	GetCmdArg(1, Name, sizeof(Name));
	GetCmdArg(2, days, sizeof(days));
	if(args == 3)
	{
		GetCmdArg(3, SteamID, sizeof(SteamID));
		if(!CheckSteamID(SteamID))
		{
			ReplyToCommand(client, "[VIP-Manager] Please use valid SteamID format");

			return Plugin_Handled;
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
				decl String:cName[255];
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
				ReplyToCommand(client, "[VIP-Manager] Can't find player '%s'", Name);

				return Plugin_Handled;
			}
		}
	}

	// Create connection to sql server
	decl String:error[255];
	new Handle:connection = SQL_DefConnect(error, sizeof(error));

	if(connection == INVALID_HANDLE)
	{
		// Log error
		if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
		ReplyToCommand(client, "[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);

		return Plugin_Handled;
	}
	else
	{
		new Handle:hQuery;
		decl String:Query[255];

		// Set SQL query
		Format(Query, sizeof(Query), "INSERT INTO sm_admins (authtype, identity, flags, name, expirationday) VALUES ('steam', '%s', 'a', '%s', %s)", SteamID, Name, days);
		hQuery = SQL_Query(connection, Query);

		if(hQuery == INVALID_HANDLE)
		{
			// Log error
			SQL_GetError(connection, error, sizeof(error));
			if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Error on Query! Error: %s", error);
			ReplyToCommand(client, "[VIP-Manager] Error on Query! Error: %s", error);

			return Plugin_Handled;
		}
		else
		{
			// Execute custom SQL queries
			Execute_Custom_OnAdd_Queries(client, connection, SteamID, Name, days);

			// Log new VIP
			if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Added VIP '%s' (SteamID: %s) for %s days", Name, SteamID, days);
			ReplyToCommand(client, "[VIP-Manager] Added VIP '%s' (SteamID: %s) for %s days", Name, SteamID, days);
		}
		CloseHandle(hQuery);
	}
	CloseHandle(connection);

	return Plugin_Handled;
}

public Action:VIP_Remove(client, args)
{
	if(args < 1)
	{
		ReplyToCommand(client, "[VIP-Manager] Use vipm_rm <\"name\">");

		return Plugin_Handled;
	}

	decl String:Name[255];
	GetCmdArg(1, Name, sizeof(Name));

	// Create connection to sql server
	decl String:error[255];
	new Handle:connection = SQL_DefConnect(error, sizeof(error));

	if(connection == INVALID_HANDLE)
	{
		// Log error
		if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
		ReplyToCommand(client, "[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);

		return Plugin_Handled;
	}
	else
	{
		new Handle:hQuery;
		decl String:Query[255];

		// Set SQL query
		Format(Query, sizeof(Query), "SELECT identity, name FROM sm_admins WHERE name LIKE '%s%s%s' AND flags = 'a'", '%', Name, '%');
		hQuery = SQL_Query(connection, Query);

		if(hQuery == INVALID_HANDLE)
		{
			// Log error
			SQL_GetError(connection, error, sizeof(error));
			if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Error on Query! Error: %s", error);
			ReplyToCommand(client, "[VIP-Manager] Error on Query! Error: %s", error);

			return Plugin_Handled;
		}
		else
		{
			// Check count of founded VIPs
			if(SQL_GetRowCount(hQuery) > 1)
			{
				// Print error
				ReplyToCommand(client, "[VIP-Manager] Found more than one VIP with the name like '%s'!", Name);

				return Plugin_Handled;
			}
			else if(SQL_GetRowCount(hQuery) == 0)
			{
				// Print error
				ReplyToCommand(client, "[VIP-Manager] Can't found VIP with the name like '%s'!", Name);

				return Plugin_Handled;
			}

			// Get SteamID
			decl String:SteamID[64];
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
				ReplyToCommand(client, "[VIP-Manager] Error on Query! Error: %s", error);

				return Plugin_Handled;
			}

			// Delete VIP
			Format(Query, sizeof(Query), "DELETE FROM sm_admins WHERE identity = '%s' AND flags = 'a'", SteamID);

			if(!SQL_FastQuery(connection, Query))
			{
				// Log error
				SQL_GetError(connection, error, sizeof(error));
				if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Error while deleting VIPs! Error: %s", error);
				ReplyToCommand(client, "[VIP-Manager] Error while deleting VIPs! Error: %s", error);

				return Plugin_Handled;
			}
			else
			{
				// Execute custom SQL queries
				Execute_Custom_OnRemove_Queries(client, connection, SteamID, Name);

				// Log deleted VIP
				decl String:cName[255];
				if(client > 0) GetClientName(client, cName, sizeof(cName));
				else cName = "Server console";

				if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Deleted VIP '%s' (SteamID: %s). Reason: Removed by %s!", Name, SteamID, cName);
				ReplyToCommand(client, "[VIP-Manager] Deleted VIP '%s' (SteamID: %s). Reason: Removed by %s!", Name, SteamID, cName);
			}
		}
		CloseHandle(hQuery);
	}
	CloseHandle(connection);

	return Plugin_Handled;
}

public Action:VIP_Change_Time(client, args)
{
	// Check arguments
	if(args < 3) ReplyToCommand(client, "[VIP-Manager] Use vipm_time <set|add|sub> <\"name\"> <days>");
	else
	{
		decl String:query[255];
		decl String:cMode[16];
		decl String:name[255];
		decl String:days[16];

		GetCmdArg(1, cMode, sizeof(cMode));
		GetCmdArg(2, name, sizeof(name));
		GetCmdArg(3, days, sizeof(days));

		// Check change mode
		if(StrEqual(cMode, "set", false)) Format(query, sizeof(query), "UPDATE sm_admins SET expirationday = %s WHERE name LIKE '%s%s%s'", days, '%', name, '%');
		else if(StrEqual(cMode, "add", false)) Format(query, sizeof(query), "UPDATE sm_admins SET expirationday = expirationday + %s WHERE name LIKE '%s%s%s'", days, '%', name, '%');
		else if(StrEqual(cMode, "sub", false)) Format(query, sizeof(query), "UPDATE sm_admins SET expirationday = expirationday - %s WHERE name LIKE '%s%s%s'", days, '%', name, '%');
		else
		{
			ReplyToCommand(client, "[VIP-Manager] No mode \"%s\" found. Available: set | add | sub", cMode);

			return Plugin_Handled;
		}

		// Create connection to sql server
		decl String:error[255];
		new Handle:connection = SQL_DefConnect(error, sizeof(error));

		if(connection == INVALID_HANDLE)
		{
			// Log error
			if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
			ReplyToCommand(client, "[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);

			return Plugin_Handled;
		}
		else
		{
			new Handle:hQuery;
			decl String:sQuery[255];

			// Set SQL query
			Format(sQuery, sizeof(sQuery), "SELECT name FROM sm_admins WHERE name LIKE '%s%s%s'", '%', name, '%');
			hQuery = SQL_Query(connection, sQuery);

			if(hQuery == INVALID_HANDLE)
			{
				// Log error
				SQL_GetError(connection, error, sizeof(error));
				if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Error on Query! Error: %s", error);
				ReplyToCommand(client, "[VIP-Manager] Error on Query! Error: %s", error);

				return Plugin_Handled;
			}
			else
			{
				// Check count of founded VIPs
				if(SQL_GetRowCount(hQuery) > 1)
				{
					// Print error
					ReplyToCommand(client, "[VIP-Manager] Found more than one VIP with the name like '%s'!", name);

					return Plugin_Handled;
				}
				else if(SQL_GetRowCount(hQuery) == 0)
				{
					// Print error
					ReplyToCommand(client, "[VIP-Manager] Can't found VIP with the name like '%s'!", name);

					return Plugin_Handled;
				}

				// Get full VIP name
				if(SQL_FetchRow(hQuery)) SQL_FetchString(hQuery, 0, name, sizeof(name));
				else
				{
					// Log error
					SQL_GetError(connection, error, sizeof(error));
					if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Error on Query! Error: %s", error);
					ReplyToCommand(client, "[VIP-Manager] Error on Query! Error: %s", error);

					return Plugin_Handled;
				}

				// Update time
				if(!SQL_FastQuery(connection, query))
				{
					// Log error
					SQL_GetError(connection, error, sizeof(error));
					if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Error on Query! Error: %s", error);
					ReplyToCommand(client, "[VIP-Manager] Error on Query! Error: %s", error);

					return Plugin_Handled;
				}
				else
				{
					decl String:nDays[16];
					decl String:steamID[128];

					CloseHandle(hQuery);
					Format(sQuery, sizeof(sQuery), "SELECT expirationday,identity FROM sm_admins WHERE name LIKE '%s%s%s'", '%', name, '%');
					hQuery = SQL_Query(connection, sQuery);

					if(hQuery == INVALID_HANDLE)
					{
						// Log error
						SQL_GetError(connection, error, sizeof(error));
						if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Error on Query! Error: %s", error);
						ReplyToCommand(client, "[VIP-Manager] Error on Query! Error: %s", error);

						return Plugin_Handled;
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
							ReplyToCommand(client, "[VIP-Manager] Error on Query! Error: %s", error);

							return Plugin_Handled;
						}

						// Log change
						if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Changed time of %s (SteamID: %s) to %s days. Changed: %s %s days", name, steamID, nDays, cMode, days);
						ReplyToCommand(client, "[VIP-Manager] Changed time of %s (SteamID: %s) to %s days. Changed: %s %s days", name, steamID, nDays, cMode, days);
					}
				}
			}
			CloseHandle(hQuery);
		}
		CloseHandle(connection);
	}

	return Plugin_Handled;
}

Execute_Custom_OnAdd_Queries(client, Handle:connection, String:steamID[], String:VIPname[], String:VIPtime[])
{
	new String:queryFilePath[255] = "cfg/sourcemod/VIP-Manager-OnAdd.cfg";
	if(!FileExists(queryFilePath))
	{
		ReplyToCommand(client, "[VIP-Manager] Can't find file %s", queryFilePath);
		return;
	}

	new Handle:queryFile = OpenFile(queryFilePath, "r");
	decl String:query[1024];

	new Handle:hQuery;
	decl String:error[255];

	while(!IsEndOfFile(queryFile))
	{
		ReadFileLine(queryFile, query, sizeof(query));

		if(IsStringEmpty(query))
		{
			ReplyToCommand(client, "Query is empty!");
			continue;
		}

		FormatQuery(query, sizeof(query), steamID, VIPname, VIPtime);

		if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Execute custom query: %s", query);
		ReplyToCommand(client, "[VIP-Manager] Execute custom query: %s", query);

		hQuery = SQL_Query(connection, query);

		if(hQuery == INVALID_HANDLE)
		{
			// Log error
			SQL_GetError(connection, error, sizeof(error));
			if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Error on Query! Error: %s", error);
			ReplyToCommand(client, "[VIP-Manager] Error on Query! Error: %s", error);
		}
		else CloseHandle(hQuery);
	}

	CloseHandle(queryFile);
}

Execute_Custom_OnRemove_Queries(client, Handle:connection, String:steamID[], String:VIPname[])
{
	new String:queryFilePath[255] = "cfg/sourcemod/VIP-Manager-OnRemove.cfg";
	if(!FileExists(queryFilePath))
	{
		ReplyToCommand(client, "[VIP-Manager] Can't find file %s", queryFilePath);
		return;
	}

	new Handle:queryFile = OpenFile(queryFilePath, "r");
	decl String:query[1024];

	new Handle:hQuery;
	decl String:error[255];

	while(!IsEndOfFile(queryFile))
	{
		ReadFileLine(queryFile, query, sizeof(query));

		if(IsStringEmpty(query))
		{
			ReplyToCommand(client, "Query is empty!");
			continue;
		}

		FormatQuery(query, sizeof(query), steamID, VIPname, "");

		if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Execute custom query: %s", query);
		ReplyToCommand(client, "[VIP-Manager] Execute custom query: %s", query);

		hQuery = SQL_Query(connection, query);

		if(hQuery == INVALID_HANDLE)
		{
			// Log error
			SQL_GetError(connection, error, sizeof(error));
			if(GetConVarBool(VIP_Log)) LogToFileEx(logFilePath, "[VIP-Manager] Error on Query! Error: %s", error);
			ReplyToCommand(client, "[VIP-Manager] Error on Query! Error: %s", error);
		}
		else CloseHandle(hQuery);
	}

	CloseHandle(queryFile);
}

FormatQuery(String:query[], maxlenght, String:steamID[], String:VIPname[], String:VIPtime[])
{
	TrimString(query);

	ReplaceString(query, maxlenght, "{steamid}", steamID, false);
	ReplaceString(query, maxlenght, "{name}", VIPname, false);
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
	return StrEqual(str, "");
}

bool:CheckSteamID(String:steamID[])
{
	return (strncmp(steamID, "STEAM_", 6, false) == 0 &&
			steamID[7] == ':' &&
			steamID[9] == ':')
			||
			(strncmp(steamID, "[U:1:", 5, false) == 0 &&
			StrContains(steamID, "]", false) > 5);
}
