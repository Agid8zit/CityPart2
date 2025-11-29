return {
	APPLY_CHANGES = false,
	ENV = "Release", -- "Studio" | "Release"
	RUN_AUDIT_ON_BOOT = false, -- gate the expensive SaveAuditor pass unless explicitly enabled

	PLAYER_DS_BY_ENV = {
		Studio = "PlayerData_PublicTest2",
		Release = "PlayerData_Release1",
	},

	PLAYER_DS_ALL = {
		"PlayerData_PublicTest2",
		"PlayerData_Release1",
	},

	OTHER_DS = {
		"OnboardingAudit_v1",
		"PlayerSesionLock",
		"SavedReceipts",
	},

	MAX_BACKUPS_PER_SLOT = 3,
	MAX_BACKUP_AGE_SECONDS = 14 * 24 * 3600,
	MIN_COMMIT_INTERVAL_SECONDS = 120,
	DEDUPE_BY_HASH = true,

	LIMITS = {
		PER_SAVE_BYTES = 250 * 1024,
		ROADS_B64_MAX = 200 * 1024,
		ZONES_B64_MAX = 200 * 1024,
	},

	INDEX_STORE = "PlayerIndex_v1",
	REPORT_STORE = "AuditReports_v1",

	LIST_PAGE_SIZE = 100,
	GC_BATCH_SIZE = 100,
	YIELD_BETWEEN_DELETES = 0.05,
	YIELD_BETWEEN_PAGES = 0.25,

	MAX_SLOTS_PER_PLAYER = 3,

	HIGH_CHURN_PATHS = {
		["economy/money"] = true,
		["economy/bustickets"] = true,
		["economy/planetickets"] = true,
	},

	STORAGE_BUDGET_WARN_FRACTION = 0.8,
}
