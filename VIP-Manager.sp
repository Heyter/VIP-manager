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

new Handle:VIP_Check_Activated = INVALID_HANDLE;
new Handle:VIP_Check_Time = INVALID_HANDLE;
new Handle:VIP_Log = INVALID_HANDLE;

new Handle:CheckTimer = INVALID_HANDLE;
new String:logFilePath[512];

public OnPluginStart()
{
	VIP_Check_Activated = CreateConVar("vipm_check_activated", "1", "Activating checking for outdated VIPs", FCVAR_NONE, true, 0.0, true, 1.0);
	VIP_Check_Time = CreateConVar("vipm_check_time", "720", "Time duration, in minutes, to check for outdated VIPs", FCVAR_NONE, true, 1.0);
	VIP_Log = CreateConVar("vipm_log", "0", "Activate logging. Logs all added and removed VIPs", FCVAR_NONE, true, 0.0, true, 1.0);

	HookConVarChange(VIP_Check_Activated, OnCVarChanged);
	HookConVarChange(VIP_Check_Time, OnCVarChanged);

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
	
	new Handle:connection = SQL_ConnectToServer();
	if(connection == INVALID_HANDLE)
	{
		ReplyToCommand(client, "[VIP-Manager] There's a problem with the SQL connection! Please check the logs.");
		return;
	}
	
	decl String:query[255];
	Format(query, sizeof(query), "SELECT name, identity FROM sm_admins WHERE TIMEDIFF(DATE_ADD(joindate, INTERVAL days DAY), NOW()) < 0 AND days >= 0 AND flags = 'a'");
	
	new Handle:hQuery = SQL_SendQuery(connection, query);
	if(hQuery == INVALID_HANDLE)
	{
		ReplyToCommand(client, "[VIP-Manager] There's a problem with the VIP-check query! Please check the logs.");
		return;
	}
	
	if(SQL_GetRowCount(hQuery) == 0)
	{
		ReplyToCommand(client, "[VIP-Manager] None VIPs are outdated!");
		return;
	}

	decl String:name[255];
	decl String:steamID[128];

	while(SQL_FetchRow(hQuery))
	{
		SQL_FetchString(hQuery, 0, name, sizeof(name));
		SQL_FetchString(hQuery, 1, steamID, sizeof(steamID));

		if(!RemoveVIP(connection, name, steamID, "Time expired"))
			ReplyToCommand(client, "[VIP-Manager] An error occurred while removing VIP '%s'! Please check the logs.", name);
		else
			ReplyToCommand(client, "[VIP-Manager] VIP '%s' deleted.", name);
	}
	
	CloseHandle(hQuery);
	CloseHandle(connection);
}

public Action:VIP_Check_Cmd(client, args)
{
	VIP_Check(client);
	ReplyToCommand(client, "[VIP-Manager] VIP check finished!");
	return Plugin_Handled;
}

public Action:VIP_Check_Timer(Handle:timer)
{
	VIP_Check(0);
	PrintToServer("[VIP-Manager] VIP check finished!");
	return Plugin_Handled;
}

public OnCVarChanged(Handle:cvar, String:oldVal[], String:newVal[])
{
	SetCheckTimer();
}

public Action:VIP_Add(client, args)
{
	if(args < 2 || args > 3)
	{
		ReplyToCommand(client, "[VIP-Manager] Use vipm_add <\"name\"> <days> [\"SteamID\"]");
		return Plugin_Handled;
	}

	decl String:steamID[64];
	decl String:searchName[255];
	decl String:cName[255];
	decl String:daysBuffer[16];
	new days;

	GetCmdArg(1, searchName, sizeof(searchName));
	GetCmdArg(2, daysBuffer, sizeof(daysBuffer));
	days = StringToInt(daysBuffer);
	if(days < -1)
		days = -1;
	
	if(args == 3)
	{
		strcopy(cName, sizeof(cName), searchName);
		GetCmdArg(3, steamID, sizeof(steamID));
		if(!CheckSteamID(steamID))
		{
			ReplyToCommand(client, "[VIP-Manager] Please use valid SteamID format");
			return Plugin_Handled;
		}
	}
	else
	{
		if(!SearchPlayerByName(searchName, cName, sizeof(cName), steamID, sizeof(steamID)))
		{
			ReplyToCommand(client, "[VIP-Manager] Can't find player '%s'", searchName);
			return Plugin_Handled;
		}
	}

	new Handle:connection = SQL_ConnectToServer();
	if(connection == INVALID_HANDLE)
	{
		ReplyToCommand(client, "[VIP-Manager] There's a problem with the SQL connection! Please check the logs.");
		return Plugin_Handled;
	}
	
	if(!AddVIP(connection, cName, steamID, days))
		ReplyToCommand(client, "[VIP-Manager] An error occurred while adding the VIP! Please check the logs.");
	else
		ReplyToCommand(client, "[VIP-Manager] Added '%s' as VIP for %i days", cName, days);
	
	CloseHandle(connection);
	return Plugin_Handled;
}

public Action:VIP_Remove(client, args)
{
	if(args != 1)
	{
		ReplyToCommand(client, "[VIP-Manager] Use vipm_rm <\"name\">");
		return Plugin_Handled;
	}

	decl String:searchName[255];
	decl String:cName[255];
	decl String:steamID[255];
	
	GetCmdArg(1, searchName, sizeof(searchName));
	
	new Handle:connection = SQL_ConnectToServer();
	if(connection == INVALID_HANDLE)
	{
		ReplyToCommand(client, "[VIP-Manager] There's a problem with the SQL connection! Please check the logs.");
		return Plugin_Handled;
	}
	
	new vipCount = GetVIP(connection, searchName, cName, sizeof(cName), steamID, sizeof(steamID));
	if(vipCount > 1)
	{
		ReplyToCommand(client, "[VIP-Manager] Found more than one VIP with a name like '%s'!", searchName);
		return Plugin_Handled;
	}
	else if(vipCount == 0)
	{
		ReplyToCommand(client, "[VIP-Manager] Can't found VIP with the name like '%s'!", searchName);
		return Plugin_Handled;
	}
	else if(vipCount == -1)
	{
		ReplyToCommand(client, "[VIP-Manager] Unknown error! Please check the logs.");
		return Plugin_Handled;
	}

	decl String:uName[255];
	GetClientName(client, uName, sizeof(uName));
	decl String:reason[512];
	Format(reason, sizeof(reason), "Removed by '%s'", uName);
	
	if(!RemoveVIP(connection, cName, steamID, reason))
		ReplyToCommand(client, "[VIP-Manager] An error occurred while removing VIP '%s'! Please check the logs.", cName);
	else
		ReplyToCommand(client, "[VIP-Manager] VIP '%s' deleted.", cName);
	
	CloseHandle(connection);
	return Plugin_Handled;
}

public Action:VIP_Change_Time(client, args)
{
	if(args != 3)
	{
		ReplyToCommand(client, "[VIP-Manager] Use vipm_time <set|add|sub> <\"name\"> <days>");
		return Plugin_Handled;
	}
	
	decl String:searchName[255];
	decl String:cName[255];
	decl String:steamID[255];
	decl String:cMode[16];
	decl String:daysBuffer[16];
	new newDays;
	new oldDays;

	GetCmdArg(1, cMode, sizeof(cMode));
	GetCmdArg(2, searchName, sizeof(searchName));
	GetCmdArg(3, daysBuffer, sizeof(daysBuffer));
	newDays = StringToInt(daysBuffer);
	
	new Handle:connection = SQL_ConnectToServer();
	if(connection == INVALID_HANDLE)
	{
		ReplyToCommand(client, "[VIP-Manager] There's a problem with the SQL connection! Please check the logs.");
		return Plugin_Handled;
	}

	new vipCount = GetVIP(connection, searchName, cName, sizeof(cName), steamID, sizeof(steamID));
	if(vipCount > 1)
	{
		ReplyToCommand(client, "[VIP-Manager] Found more than one VIP with a name like '%s'!", searchName);
		return Plugin_Handled;
	}
	else if(vipCount == 0)
	{
		ReplyToCommand(client, "[VIP-Manager] Can't found VIP with the name like '%s'!", searchName);
		return Plugin_Handled;
	}
	
	oldDays = GetVIPTime(connection, steamID);
	if(oldDays == -2)
	{
		ReplyToCommand(client, "[VIP-Manager] An error occurred while getting time from VIP! Please check the logs.");
		return Plugin_Handled;
	}

	if(StrEqual(cMode, "set", false))
	{
		if(newDays < -1)
			newDays = -1;
	}
	else if(StrEqual(cMode, "add", false))
	{
		if(newDays < 0)
		{
			ReplyToCommand(client, "[VIP-Manager] Can't add negative days! Use mode 'sub' instead.");
			return Plugin_Handled;
		}
		newDays += oldDays;
	}
	else if(StrEqual(cMode, "sub", false))
	{
		if(newDays < 0)
		{
			ReplyToCommand(client, "[VIP-Manager] Can't subtract negative days! Use mode 'add' instead.");
			return Plugin_Handled;
		}
		newDays = oldDays - newDays;
		if(newDays < -1)
			newDays = -1;
	}
	else
	{
		ReplyToCommand(client, "[VIP-Manager] Unknown mode '%s'. Please use 'set', 'add' or 'sub'", cMode);
		return Plugin_Handled;
	}
	
	if(!SetVIPTime(connection, cName, steamID, oldDays, newDays))
		ReplyToCommand(client, "[VIP-Manager] An error occurred while changing time from VIP! Please check the logs.");
	else
		ReplyToCommand(client, "Changed time of '%s' from %i to %i days", cName, oldDays, newDays);
	
	CloseHandle(connection);
	return Plugin_Handled;
}

ExecuteCustomQueries(const String:queryFilePath[], Handle:connection, const String:steamID[], const String:name[], days)
{
	if(!FileExists(queryFilePath))
	{
		LogMessageToFile("[VIP-Manager] Can't find custom-queries file '%s'", queryFilePath);
		return;
	}

	new Handle:queryFile = OpenFile(queryFilePath, "r");
	if(queryFile == INVALID_HANDLE)
	{
		LogMessageToFile("[VIP-Manager] Can't open file '%s'. Please check if file has set read permission.", queryFilePath);
		return;
	}
	
	decl String:query[1024];
	while(!IsEndOfFile(queryFile))
	{
		ReadFileLine(queryFile, query, sizeof(query));
		if(IsStringEmpty(query))
			continue;

		FormatQuery(query, sizeof(query), steamID, name, days);
		if(SQL_SendFastQuery(connection, query))
			LogMessageToFile("[VIP-Manager] Executed custom query: %s", query);
	}

	CloseHandle(queryFile);
}

FormatQuery(String:query[], maxlenght, const String:steamID[], const String:name[], days)
{
	TrimString(query);

	ReplaceString(query, maxlenght, "{steamid}", steamID, false);
	ReplaceString(query, maxlenght, "{name}", name, false);
	
	decl String:strDays[16];
	IntToString(days, strDays, sizeof(strDays));
	ReplaceString(query, maxlenght, "{time}", strDays, false);
}

SetCheckTimer()
{
	if(CheckTimer != INVALID_HANDLE)
	{
		KillTimer(CheckTimer);
		CheckTimer = INVALID_HANDLE;
	}

	if(!GetConVarBool(VIP_Check_Activated))
	{
		PrintToServer("[VIP-Manager] Auto check disabled.");
		return;
	}
	
	CheckTimer = CreateTimer(GetConVarFloat(VIP_Check_Time) * 60.0, VIP_Check_Timer, INVALID_HANDLE, TIMER_REPEAT);
	PrintToServer("[VIP-Manager] Will check for expired VIPs every %i minute(s).", GetConVarInt(VIP_Check_Time));
}

bool:IsStringEmpty(const String:str[])
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

bool:SearchPlayerByName(const String:sName[], String:cName[], nameLength, String:steamID[], IdLength)
{
	for(new i = 1; i <= MaxClients; i++)
	{
		if(!IsClientConnected(i))
			continue;
		
		GetClientName(i, cName, nameLength);
		if(StrContains(cName, sName, false) >= 0)
			continue;
		
		GetClientAuthString(i, steamID, IdLength);
		return true;
	}
	
	return false;
}

bool:AddVIP(Handle:connection, const String:name[], const String:steamID[], days)
{
	decl String:query[255];
	Format(query, sizeof(query), "INSERT INTO sm_admins (authtype, identity, flags, name, days) VALUES ('steam', '%s', 'a', '%s', %i)", steamID, name, days);
	
	if(!SQL_SendFastQuery(connection, query))
		return false;
	
	ExecuteCustomQueries("cfg/sourcemod/VIP-Manager-OnAdd.cfg", connection, steamID, name, days);
	LogMessageToFile("[VIP-Manager] Added VIP '%s' (SteamID: %s) for %i days", name, steamID, days);
	
	return true;
}

bool:RemoveVIP(Handle:connection, const String:name[], const String:steamID[], const String:reason[])
{
	decl String:query[255];
	Format(query, sizeof(query), "DELETE FROM sm_admins WHERE identity = '%s' AND flags = 'a'", steamID);
	
	if(!SQL_SendFastQuery(connection, query))
		return false;
	
	ExecuteCustomQueries("cfg/sourcemod/VIP-Manager-OnRemove.cfg", connection, steamID, name, 0);
	LogMessageToFile("[VIP-Manager] Deleted VIP '%s' (SteamID: %s). Reason: %s!", name, steamID, reason);
	
	return true;
}

GetVIP(Handle:connection, const String:searchName[], String:cName[], nameLength, String:steamID[], IdLength)
{
	decl String:query[255];
	Format(query, sizeof(query), "SELECT name, identity FROM sm_admins WHERE name LIKE '%s%s%s' AND flags = 'a'", '%', searchName, '%');
	
	new Handle:hQuery = SQL_SendQuery(connection, query);
	if(hQuery == INVALID_HANDLE)
		return -1;
	
	new rowCount = SQL_GetRowCount(hQuery);
	if(rowCount != 1)
		return rowCount;
	
	if(!SQL_FetchRow(hQuery))
	{
		decl String:error[255];
		SQL_GetError(connection, error, sizeof(error));
		LogMessageToFile("[VIP-Manager] An error occurred while fetching sql row! Error: %s", error);
	}
	
	SQL_FetchString(hQuery, 0, cName, nameLength);
	SQL_FetchString(hQuery, 1, steamID, IdLength);
	
	CloseHandle(hQuery);
	return 1;
}

GetVIPTime(Handle:connection, const String:steamID[])
{
	decl String:query[255];
	Format(query, sizeof(query), "SELECT days FROM sm_admins WHERE identity = '%s'", steamID);
	
	new Handle:hQuery = SQL_SendQuery(connection, query);
	if(hQuery == INVALID_HANDLE)
		return -2;
	
	if(!SQL_FetchRow(hQuery))
	{
		decl String:error[255];
		SQL_GetError(connection, error, sizeof(error));
		LogMessageToFile("[VIP-Manager] An error occurred while fetching sql row! Error: %s", error);
		return -2;
	}
	new days = SQL_FetchInt(hQuery, 0);
	
	CloseHandle(hQuery);
	return days;
}

bool:SetVIPTime(Handle:connection, const String:name[], const String:steamID[], oldDays, newDays)
{
	decl String:query[255];
	Format(query, sizeof(query), "UPDATE sm_admins SET days = %i WHERE identity = '%s'", newDays, steamID);
	
	if(!SQL_SendFastQuery(connection, query))
		return false;
	
	LogMessageToFile("[VIP-Manager] Changed time for VIP '%s' (SteamID: %s) from %i to %i!", name, steamID, oldDays, newDays);
	return true;
}

Handle:SQL_ConnectToServer()
{
	if(!SQL_CheckConfig("vip-manager"))
	{
		LogMessageToFile("[VIP-Manager] Missing SQL configuration! Please check your databases.cfg");
		return INVALID_HANDLE;
	}
	
	decl String:error[255];
	new Handle:connection = SQL_Connect("vip-manager", true, error, sizeof(error));

	if(connection == INVALID_HANDLE)
	{
		LogMessageToFile("[VIP-Manager] Couldn't connect to SQL server! Error: %s", error);
		return INVALID_HANDLE;
	}
	
	return connection;
}

Handle:SQL_SendQuery(Handle:connection, const String:query[])
{
	if(connection == INVALID_HANDLE)
		return INVALID_HANDLE;
	
	new Handle:hQuery = SQL_Query(connection, query);
	if(hQuery == INVALID_HANDLE)
	{
		decl String:error[255];
		SQL_GetError(connection, error, sizeof(error));
		LogMessageToFile("[VIP-Manager] Query Error for query (%s)! Error: %s", query, error);
		return INVALID_HANDLE;
	}
	
	return hQuery;
}

bool:SQL_SendFastQuery(Handle:connection, const String:query[])
{
	if(connection == INVALID_HANDLE)
		return false;
	
	if(!SQL_FastQuery(connection, query))
	{
		decl String:error[255];
		SQL_GetError(connection, error, sizeof(error));
		LogMessageToFile("[VIP-Manager] FastQuery Error for query (%s)! Error: %s", query, error);
		return false;
	}
	
	return true;
}

LogMessageToFile(const String:msg[], any:...)
{
	if(IsStringEmpty(msg) || IsStringEmpty(logFilePath) || !GetConVarBool(VIP_Log))
		return;
	
	new String:message[512];
	VFormat(message, sizeof(message), msg, 2);
	
	LogToFileEx(logFilePath, message);
}
