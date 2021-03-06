#if defined _vipmanager_included
  #endinput
#endif
#define _vipmanager_included

public SharedPlugin __pl_vipmanager = {
  name = "VIP-Manager",
  file = "VIP-Manager.smx",
#if defined REQUIRE_PLUGIN
  required = 1
#else
  required = 0
#endif
};

/**
  * Called everytime a VIP is added.
  *
  * @param admin          Index of admin, who has added the VIP.
  * @param name           Name of the VIP.
  * @param steamId        SteamId of the VIP.
  * @param minutes        Time the player is VIP.
  *
  */
forward void OnVIPAdded(int admin, char[] name, char[] steamId, int minutes);

/**
  * Called everytime a VIP has been checked.
  *
  * @param client         Client from the VIP.
  * @param expired        Result of the check if a VIP is expired.
  *
  */
forward void OnVIPChecked(int client, bool expired);

/**
  * Called everytime a VIP is loaded into the admin cache.
  *
  * @param client         Client from the VIP.
  *
  */
forward void OnVIPLoaded(int client);

/**
  * Called everytime a VIP is removed.
  *
  * @param admin          Index of admin, who has removed the VIP.
  * @param name           Name of the removed VIP.
  * @param steamId        SteamId of the removed VIP.
  * @param reason         Reason for removing VIP.
  *
  */
forward void OnVIPRemoved(int admin, char[] name, char[] steamId, char[] reason);

/**
  * Called everytime the duration for a VIP has changed.
  *
  * @param admin          Index of admin, who has changed the duration for a VIP.
  * @param name           Name of the VIP.
  * @param steamId        SteamId of the VIP.
  * @param mode           The mode used for the change. Can be 'set', 'add' or 'sub'.
  * @param oldDuration    Old value of the duration.
  * @param duration       New value of the duration.
  *
  */
forward void OnVIPDurationChanged(int admin, char[] name, char[] steamId, char[] mode, int oldDuration, int duration);

/**
  * Check if a client is a VIP.
  *
  * @param client         Index of client to check
  * @return               Result of check
  *
  * On error:             Invalid client index
  *
  */
native bool ClientIsVIP(int client);

/**
  * Add a new VIP.
  *
  * @param name           Name of the VIP
  * @param steamId        SteamId of the VIP
  * @param minutes        Duration in minutes the user becomes a VIP
  * @param admin          Index of admin, who added the VIP
  *
  */
native void AddVIP(const char[] name, const char[] steamId, int minutes, int admin = 0);

#if !defined REQUIRE_PLUGIN
public __pl_vipmanager_SetNTVOptional() {
  MarkNativeAsOptional("ClientIsVIP");
  MarkNativeAsOptional("AddVIP");
}
#endif
