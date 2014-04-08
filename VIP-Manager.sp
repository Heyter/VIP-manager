#include <sourcemod>

// Plugin information
#define Author "Shadow_Man"
#define Version "0.1 Dev"

public Plugin:info =
{
	name = "VIP-Manager";
	author = Author;
	description = "VIP-Manager for CTaF-Server";
	version = Version;
	url = "http://cf-server.pfweb.eu";
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
	if(GetConVarBool(VIP_Check_Activated)) CheckTimer = CreateTimer(GetConVarInt(VIP_Check_Time * 60, Timer_CheckVips, INVALID_HANDLE, TIMER_REPEAT);
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
	}
	else
	{
		// TO-Do
		// - Get oudated VIPs and log them
		// - Remove oudated VIPs from server
		
		// Close connection
		CloseHandle(connection);
	}
}
