#include <sourcemod>

#define Version "2.0 Dev"

Database database;

public Plugin myinfo = {
	name = "VIP-Manager",
	author = "Shadow_Man",
	description = "Manage VIPs on your server",
	version = Version,
	url = "http://cf-server.pfweb.eu"
};

public void OnPluginStart()
{
	CreateConVar("sm_vipm_version", Version, FCVAR_PLUGIN | FCVAR_SPONLY);

	ConnectToDatabase();
}

public void CallbackConnect(Database db, char[] error, any configuration)
{
	if(db == null)
		LogError("Can't connect to server using '%s' configuration. Error: %s", configuration, error);

	database = db;
}

void ConnectToDatabase()
{
	if(SQL_CheckConfig("vip-manager"))
		database.Connect(CallbackConnect, "vip-manager", "vip-manager");
	else
		database.Connect(CallbackConnect, "default", "default");
}
