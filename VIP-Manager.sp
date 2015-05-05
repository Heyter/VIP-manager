#include <sourcemod>
#include <VIP-Manager>

#define Version "2.0 Dev"

Database connection;

Handle onAddVIPForward;
Handle onRemoveVIPForward;
Handle onDurationChangedForward;

public Plugin myinfo = {
	name = "VIP-Manager",
	author = "Shadow_Man",
	description = "Manage VIPs on your server",
	version = Version,
	url = "http://cf-server.pfweb.eu"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, err_max)
{
	RegPluginLibrary("VIP-Manager");

	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("sm_vipm_version", Version, "Version of VIP-Manager", FCVAR_PLUGIN | FCVAR_SPONLY);

	RegAdminCmd("sm_vipm_add", CmdAddVIP, ADMFLAG_ROOT, "Add a VIP.");
	RegAdminCmd("sm_vipm_rm", CmdRemoveVIP, ADMFLAG_ROOT, "Remove a VIP.");
	RegAdminCmd("sm_vipm_time", CmdChangeVIPTime, ADMFLAG_ROOT, "Change the duration for a VIP.");

	onAddVIPForward = CreateGlobalForward("OnVIPAdded", ET_Ignore, Param_Cell, Param_String, Param_String, Param_Cell);
	onRemoveVIPForward = CreateGlobalForward("OnVIPRemoved", ET_Ignore, Param_Cell, Param_String, Param_String, Param_String);
	onDurationChangedForward = CreateGlobalForward("OnVIPDurationChanged", ET_Ignore, Param_Cell, Param_String, Param_String, Param_String, Param_Cell, Param_Cell);

	ConnectToDatabase();
}

public int OnRebuildAdminCache(AdminCachePart part)
{
	if(part == AdminCache_Admins)
		FetchAvailableVIPs();
}

public Action OnClientPreAdminCheck(int client)
{
	if(connection == null)
		return Plugin_Continue;

	if(GetUserAdmin(client) != INVALID_ADMIN_ID)
		return Plugin_Continue;

	CheckVIP(client);
	FetchVIP(client);
	return Plugin_Handled;
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
		ReplyToCommand(client, "Usage: sm_vipm_add <\"name\"> <minutes>");
		return Plugin_Handled;
	}

	char searchName[64];
	GetCmdArg(1, searchName, sizeof(searchName));

	int vip = FindPlayer(searchName);
	if(vip == -1)
	{
		ReplyToCommand(client, "Can't find client '%s'", searchName);
		return Plugin_Handled;
	}

	char name[64];
	GetClientName(vip, name, sizeof(name));

	char steamId[64];
	GetClientAuthId(vip, AuthId_Engine, steamId, sizeof(steamId));

	char durationString[16];
	GetCmdArg(2, durationString, sizeof(durationString));

	int duration = StringToInt(durationString);
	if(duration < -1)
		duration = -1;

	int len = strlen(name) * 2 + 1;
	char[] escapedName = new char[len];
	connection.Escape(name, escapedName, len);

	len = strlen(steamId) * 2 + 1;
	char[] escapedSteamId = new char[len];
	connection.Escape(steamId, escapedSteamId, len);

	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteCell(vip);
	pack.WriteString(name);
	pack.WriteString(steamId);
	pack.WriteCell(duration);

	char query[512];
	Format(query, sizeof(query), "INSERT INTO vips (steamId, name, duration) VALUES ('%s', '%s', %i);", escapedSteamId, escapedName, duration);
	connection.Query(CallbackAddVIP, query, pack);

	return Plugin_Handled;
}

public Action CmdRemoveVIP(int client, int args)
{
	if(connection == null)
	{
		ReplyToCommand(client, "There is currently no connection to the SQL server");
		return Plugin_Handled;
	}

	if(args < 1)
	{
		ReplyToCommand(client, "Usage: sm_vipm_rm <\"name\">");
		return Plugin_Handled;
	}

	char searchName[64];
	GetCmdArg(1, searchName, sizeof(searchName));

	char query[128];
	Format(query, sizeof(query), "SELECT * FROM vips WHERE name LIKE '%s';", searchName);

	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteString(searchName);

	connection.Query(CallbackPreRemoveVIP, query, pack);
	return Plugin_Handled;
}

public Action CmdChangeVIPTime(int client, int args)
{
	if(args != 3)
	{
		ReplyToCommand(client, "Usage: sm_vipm_time <set|add|sub> <\"name\"> <minutes>");
		return Plugin_Handled;
	}

	char mode[8];
	GetCmdArg(1, mode, sizeof(mode));

	if(!StrEqual(mode, "set", false) && !StrEqual(mode, "add", false) && !StrEqual(mode, "sub", false))
	{
		ReplyToCommand(client, "Unknown mode '%s'! Please use 'set', 'add' or 'sub'.", mode);
		return Plugin_Handled;
	}

	char searchName[64];
	GetCmdArg(2, searchName, sizeof(searchName));

	char minutesString[8];
	GetCmdArg(3, minutesString, sizeof(minutesString));

	int minutes = StringToInt(minutesString);
	if(minutes < 0)
		minutes *= -1;

	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteString(searchName);
	pack.WriteString(mode);
	pack.WriteCell(minutes);

	char query[64];
	Format(query, sizeof(query), "SELECT * FROM vips WHERE name LIKE '%s%s%s';", "%", searchName, "%");

	connection.Query(CallbackPreChangeTime, query, pack);
	return Plugin_Handled;
}

public void CallbackConnect(Database db, char[] error, any data)
{
	if(db == null)
		LogError("Can't connect to server. Error: %s", error);

	connection = db;
	CreateTableIfExists();
}

public void CallbackCreateTable(Database db, DBResultSet result, char[] error, any data)
{
	if(result == null)
		LogError("Error while creating table! Error: %s", error);
}

public void CallbackAddVIP(Database db, DBResultSet result, char[] error, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();
	int client = pack.ReadCell();
	int vip = pack.ReadCell();

	if(result == null)
	{
		LogError("Error while adding VIP! Error: %s", error);
		ReplyClient(client, "Can't add VIP! %s", error);
		return;
	}

	char name[64];
	pack.ReadString(name, sizeof(name));

	char steamId[64];
	pack.ReadString(steamId, sizeof(steamId));

	int duration = pack.ReadCell();

	Call_StartForward(onAddVIPForward);
	Call_PushCell(client);
	Call_PushString(name);
	Call_PushString(steamId);
	Call_PushCell(duration);
	Call_Finish();

	if(!AddVipToAdminCache(vip))
		ReplyClient(client, "Added '%s' as a VIP in database, but can't added VIP in admin cache!", name);
	else
		ReplyClient(client, "Successfully added '%s' as a VIP for %i minutes!", name, duration);
}

public void CallbackPreRemoveVIP(Database db, DBResultSet result, char[] error, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();
	int client = pack.ReadCell();

	if(result == null)
	{
		LogError("Error while selecting VIP for removing! Error: %s", error);
		ReplyClient(client, "Can't remove VIP! %s", error);
		return;
	}

	char searchName[64];
	pack.ReadString(searchName, sizeof(searchName));

	if(result.AffectedRows == 0)
	{
		ReplyClient(client, "Can't find a VIP with the name '%s'!", searchName);
		return;
	}
	else if(result.AffectedRows > 1)
	{
		ReplyClient(client, "Found more than one VIP with the name '%s'! Please specify the name more accurately!", searchName);
		return;
	}

	result.FetchRow();

	char steamId[64];
	result.FetchString(0, steamId, sizeof(steamId));

	char name[64];
	result.FetchString(1, name, sizeof(name));

	char adminName[64];
	GetClientName(client, adminName, sizeof(adminName));

	char reason[256];
	Format(reason, sizeof(reason), "Removed by admin '%s'", adminName);

	RemoveVip(client, steamId, name, reason);
}

public void CallbackRemoveVIP(Database db, DBResultSet result, char[] error, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	int client = pack.ReadCell();

	if(result == null)
	{
		LogError("Error while removing VIP! Error: %s", error);
		if(client > 0)
			ReplyClient(client, "Can't remove VIP! %s", error);
		return;
	}

	char steamId[64];
	pack.ReadString(steamId, sizeof(steamId));

	char name[64];
	pack.ReadString(name, sizeof(name));

	char reason[256];
	pack.ReadString(reason, sizeof(reason));

	RemoveVipFromAdminCache(steamId);

	Call_StartForward(onRemoveVIPForward);
	Call_PushCell(client);
	Call_PushString(name);
	Call_PushString(steamId);
	Call_PushString(reason);
	Call_Finish();

	ReplyClient(client, "Removed VIP %s(%s)! Reason: %s", name, steamId, reason);
}

public void CallbackPreChangeTime(Database db, DBResultSet result, char[] error, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();
	int client = pack.ReadCell();

	if(result == null)
	{
		LogError("Error while selecting VIP for time manipulation! Error: %s", error);
		ReplyClient(client, "Can't change time for VIP! %s", error);
		return;
	}

	char searchName[64];
	pack.ReadString(searchName, sizeof(searchName));

	if(result.AffectedRows == 0)
	{
		ReplyClient(client, "Can't find a VIP with the name '%s'!", searchName);
		return;
	}
	else if(result.AffectedRows > 1)
	{
		ReplyClient(client, "Found more than one VIP with the name '%s'! Please specify the name more accurately!", searchName);
		return;
	}

	result.FetchRow();

	char steamId[64];
	result.FetchString(0, steamId, sizeof(steamId));

	char name[64];
	result.FetchString(1, name, sizeof(name));

	int duration = result.FetchInt(3);

	char mode[8];
	pack.ReadString(mode, sizeof(mode));

	int newDuration;
	int minutes = pack.ReadCell();
	if(StrEqual(mode, "set", false))
		newDuration = minutes;
	else if(StrEqual(mode, "add"))
		newDuration = duration + minutes;
	else if(StrEqual(mode, "sub"))
		newDuration = duration - minutes;

	delete pack;
	pack = new DataPack();

	pack.WriteCell(client);
	pack.WriteString(name);
	pack.WriteString(steamId);
	pack.WriteString(mode);
	pack.WriteCell(duration);
	pack.WriteCell(newDuration);

	char query[128];
	Format(query, sizeof(query), "UPDATE vips SET duration = %i WHERE steamId = '%s'", newDuration, steamId);

	connection.Query(CallbackChangeTime, query, pack);
}

public void CallbackChangeTime(Database db, DBResultSet result, char[] error, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();
	int client = pack.ReadCell();

	if(result == null)
	{
		LogError("Error while manipulate VIP time! Error: %s", error);
		ReplyClient(client, "Can't change time for VIP! %s", error);
		return;
	}

	char name[64];
	pack.ReadString(name, sizeof(name));

	char steamId[64];
	pack.ReadString(steamId, sizeof(steamId));

	char mode[8];
	pack.ReadString(mode, sizeof(mode));

	int duration = pack.ReadCell();
	int newDuration = pack.ReadCell();

	Call_StartForward(onDurationChangedForward);
	Call_PushCell(client);
	Call_PushString(name);
	Call_PushString(steamId);
	Call_PushString(mode);
	Call_PushCell(duration);
	Call_PushCell(newDuration);
	Call_Finish();

	ReplyClient(client, "Changed time for VIP '%s' from %i to %i minutes!", name, duration, newDuration);
}

public void CallbackFetchVIP(Database db, DBResultSet result, char[] error, any data)
{
	int client = data;

	if(result == null)
	{
		LogError("Error while fetching VIP! Error: %s", error);
		return;
	}

	if(result.AffectedRows != 1)
		return;

	AddVipToAdminCache(client);
	NotifyPostAdminCheck(client);
}

public void CallbackCheckVIP(Database db, DBResultSet result, char[] error, any data)
{
	if(result == null)
	{
		LogError("Error while checking VIP! Error: %s", error);
		return;
	}

	if(result.AffectedRows != 1)
		return;

	DataPack pack = view_as<DataPack>(data);
	pack.Reset();

	char steamId[64];
	pack.ReadString(steamId, sizeof(steamId));

	char name[64];
	pack.ReadString(name, sizeof(name));

	char reason[256];
	strcopy(reason, sizeof(reason), "Time expired!");

	RemoveVip(0, steamId, name, reason);
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

void FetchVIP(int client)
{
	char steamId[64];
	GetClientAuthId(client, AuthId_Engine, steamId, sizeof(steamId));

	int len = strlen(steamId) * 2 + 1;
	char[] escapedSteamId = new char[len];
	connection.Escape(steamId, escapedSteamId, len);

	char query[128];
	Format(query, sizeof(query), "SELECT duration FROM vips WHERE steamId = '%s';", escapedSteamId);
	connection.Query(CallbackFetchVIP, query, client, DBPrio_High);
}

void FetchAvailableVIPs()
{
	for(int i = 1; i < MaxClients; i++)
	{
		if(IsClientConnected(i) && GetUserAdmin(i) == INVALID_ADMIN_ID)
			FetchVIP(i);
	}
}

void CheckVIP(int client)
{
	if(connection == null)
		return;

	DataPack pack = new DataPack();

	char steamId[64];
	GetClientAuthId(client, AuthId_Engine, steamId, sizeof(steamId));
	pack.WriteString(steamId);

	char name[64];
	GetClientName(client, name, sizeof(name));
	pack.WriteString(name);

	int len = strlen(steamId) * 2 + 1;
	char[] escapedSteamId = new char[len];
	connection.Escape(steamId, escapedSteamId, len);

	char query[196];
	Format(query, sizeof(query), "SELECT joindate, duration FROM vips WHERE steamId = '%s' AND TIMEDIFF(DATE_ADD(joindate, INTERVAL duration MINUTE), NOW()) < 0 AND duration > 0;", escapedSteamId);
	connection.Query(CallbackCheckVIP, query, pack, DBPrio_High);
}

void RemoveVip(int client, char[] steamId, char[] name, char[] reason)
{
	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteString(steamId);
	pack.WriteString(name);
	pack.WriteString(reason);

	int len = strlen(steamId) * 2 + 1;
	char[] escapedSteamId = new char[len];
	connection.Escape(steamId, escapedSteamId, len);

	char query[128];
	Format(query, sizeof(query), "DELETE FROM vips WHERE steamId = '%s';", escapedSteamId);
	connection.Query(CallbackRemoveVIP, query, pack);
}

bool AddVipToAdminCache(int client)
{
	char steamId[64];
	GetClientAuthId(client, AuthId_Engine, steamId, sizeof(steamId));

	AdminId admin = FindAdminByIdentity(AUTHMETHOD_STEAM, steamId);
	if(admin != INVALID_ADMIN_ID)
		RemoveAdmin(admin);

	GroupId group = FindAdmGroup("VIP");
	if(group == INVALID_GROUP_ID)
	{
		PrintToServer("[VIP-Manager] Couldn't found group 'VIP'! Please create a group called 'VIP'.");
		return false;
	}

	admin = CreateAdmin();
	BindAdminIdentity(admin, AUTHMETHOD_STEAM, steamId);

	AdminInheritGroup(admin, group);
	RunAdminCacheChecks(client);
	return true;
}

void RemoveVipFromAdminCache(char[] steamId)
{
	AdminId admin = FindAdminByIdentity(AUTHMETHOD_STEAM, steamId);
	if(admin == INVALID_ADMIN_ID)
		return;

	RemoveAdmin(admin);
}

int FindPlayer(char[] searchTerm)
{
	for(int i = 1; i < MaxClients; i++)
	{
		if(!IsClientConnected(i))
			continue;

		char playerName[64];
		GetClientName(i, playerName, sizeof(playerName));

		if(StrContains(playerName, searchTerm, false) > -1)
			return i;
	}

	return -1;
}

void ReplyClient(int client, const char[] format, any ...)
{
	int len = strlen(format) + 256;
	char[] message = new char[len];
	VFormat(message, len, format, 3);

	if(client == 0)
		PrintToServer(message);
	else
		PrintToChat(client, message);
}
