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

// Plugin start
public onPluginStart()
{
	// Init CVars
	VIP_Check_Activated = CreateConVar("vipm_check_activated", "true", "Activating checking for outdated VIPs");
	VIP_Check_Time = CreateConVar("vipm_check_time", "720", "Time duration, in minutes, to check for outdated VIPs");
	
	VIP_Log = CreateConVar("vipm_log", "false", "Activate logging. Logs all added and removed VIPs");
	
	// Use config file
	AutoExecConfig(true, "VIP-Manager");
}
