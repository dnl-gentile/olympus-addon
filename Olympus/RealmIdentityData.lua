local _, ns = ...

-- Forever native realm IDs observed before build 71037 stopped returning realm names.
-- Each pair came from a client's own realm name and matching native/Player GUID ID.
-- These identify realms only. Signed lists still establish every player's authority.
ns.FOREVER_REALMS_BY_ID = {
	[6794] = "CAMWOWUS1Realm1PvE",
	[6796] = "CAMWOWUS2Realm1PvE",
	-- Own native name/id/GUID agree in issue #120 (Forever build 70959, project 18).
	[6797] = "CAMWOWAU1Realm1PvE",
	[6921] = "CAMWOWUS1Realm3PvE",
	[6924] = "CAMWOWUS1Realm6PvP",
	[6925] = "CAMWOWUS1Realm7PvE",
	[6931] = "CAMWOWUS2Realm5PvE",
	[6933] = "CAMWOWUS2Realm7PvE",
}
