#include <sourcemod>

#define Version "2.0 Dev"

Database connection;

public Plugin myinfo = {
	name = "VIP-Manager",
	author = "Shadow_Man",
	description = "Manage VIPs on your server",
	version = Version,
	url = "http://cf-server.pfweb.eu"
};

public void OnPluginStart()
{
	CreateConVar("sm_vipm_version", Version, "Version of VIP-Manager", FCVAR_PLUGIN | FCVAR_SPONLY);

	RegAdminCmd("sm_vipm_add", CmdAddVIP, ADMFLAG_ROOT, "Add a VIP.");

	ConnectToDatabase();
	CreateTableIfExists();
}

public Action CmdAddVIP(int client, int args)
{
	if(connection == null)
	{
		ReplyToCommand(client, "There is currently no connection to the SQL server");
		return Plugin_Handled;
	}

	if(args < 2)
	{
		ReplyToCommand(client, "Usage: sm_vipm_add <\"name\"|#id> <minutes>");
		return Plugin_Handled;
	}

	char searchName[64];
	GetCmdArg(1, searchName, sizeof(searchName));

	int vip = FindTarget(client, searchName, true);
	if(vip == -1)
	{
		ReplyToCommand(client, "Can't find client '%s'", searchName);
		return Plugin_Handled;
	}

	char vipName[64];
	GetClientName(vip, vipName, sizeof(vipName));

	char vipSteamId[64];
	GetClientAuthId(vip, AuthId_Steam2, vipSteamId, sizeof(vipSteamId));

	char durationString[16];
	GetCmdArg(2, durationString, sizeof(durationString));

	int duration = StringToInt(durationString);
	if(duration < -1)
		duration = -1;

	int len = strlen(vipName) * 2 + 1;
	char[] escapedVipName = new char[len];
	connection.Escape(vipName, escapedVipName, len);

	len = strlen(vipSteamId) * 2 + 1;
	char[] escapedVipSteamId = new char[len];
	connection.Escape(vipSteamId, escapedVipSteamId, len);

	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteString(vipName);
	pack.WriteCell(duration);

	char query[512];
	Format(query, sizeof(query), "INSERT INTO vips (steamId, name, duration) VALUES ('%s', '%s', %i);", escapedVipSteamId, escapedVipName, duration);
	connection.Query(CallbackAddVIP, query, pack);

	return Plugin_Handled;
}

public void CallbackConnect(Database db, char[] error, any data)
{
	if(db == null)
		LogError("Can't connect to server. Error: %s", error);

	connection = db;
}

public void CallbackCreateTable(Database db, DBResultSet result, char[] error, any data)
{
	if(result == null)
		LogError("Error while creating table! Error: %s", error);
}

public void CallbackAddVIP(Database db, DBResultSet result, char[] error, any data)
{
	DataPack pack = view_as<DataPack>(data);
	int client = pack.ReadCell();

	if(result == null)
	{
		LogError("Error while adding VIP! Error: %s", error);
		ReplyToCommand(client, "Can't add VIP! Please check the log.");
		return;
	}

	char vipName[64];
	pack.ReadString(vipName, sizeof(vipName));

	int duration = pack.ReadCell();

	ReplyToCommand(client, "Successfully added '%s' as a VIP for %i minutes!", vipName, duration);
}

void ConnectToDatabase()
{
	if(SQL_CheckConfig("vip-manager"))
		Database.Connect(CallbackConnect, "vip-manager");
	else
		Database.Connect(CallbackConnect, "default");
}

void CreateTableIfExists()
{
	if(connection == null)
		return;

	connection.Query(CallbackCreateTable, "CREATE TABLE IF NOT EXISTS vips (steamId VARCHAR(64) PRIMARY KEY, name VARCHAR(64) NOT NULL, joindate TIMESTAMP DEFAULT NOW(), duration INT(11) NOT NULL);");
}
