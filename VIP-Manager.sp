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
	
	// Init Timer
	if(GetConVarBool(VIP_Check_Activated)) CheckTimer = CreateTimer(GetConVarFloat(VIP_Check_Time) * 60.0, Timer_CheckVips, INVALID_HANDLE, TIMER_REPEAT);
}

// Checking for outdated VIPs
public Action:Timer_CheckVips(Handle:timer)
{
	// Create SQL connection
	new String:error[255];
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
		new String:query[255];
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
					new String:name[255];
					new String:steamid[128];
					
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
