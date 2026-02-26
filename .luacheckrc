std = "lua51"
max_line_length = false

exclude_files = {
    "Libs/**",
    "libs/**",
    ".release/**",
    ".luacheckrc",
}

ignore = {
    "11./SLASH_.*",     -- Slash command globals (SLASH_GUILDNOTEUPDATER1, etc.)
    "11./BINDING_.*",   -- Keybinding globals
    "212",              -- Unused arguments (WoW callbacks have fixed signatures)
}

-- Globals the addon WRITES to
globals = {
    "GuildNoteUpdater",
    "GuildNoteUpdaterSettings",
    "SlashCmdList",
    "UISpecialFrames",
}

-- WoW API functions the addon READS (organized by category)
read_globals = {
    -- Frame system
    "CreateFrame",
    "UIParent",

    -- Dropdown menu API
    "UIDropDownMenu_Initialize",
    "UIDropDownMenu_SetWidth",
    "UIDropDownMenu_SetText",
    "UIDropDownMenu_CreateInfo",
    "UIDropDownMenu_AddButton",
    "UIDropDownMenu_EnableDropDown",
    "UIDropDownMenu_DisableDropDown",

    -- Player info
    "UnitName",
    "GetRealmName",

    -- Guild API
    "GetNumGuildMembers",
    "GetGuildRosterInfo",
    "GuildRosterSetPublicNote",
    "IsInGuild",
    "C_GuildInfo",
    "C_AddOns",

    -- Character info
    "GetAverageItemLevel",
    "GetSpecialization",
    "GetSpecializationInfo",
    "GetNumSpecializations",
    "GetProfessions",
    "GetProfessionInfo",

    -- Tooltip API (9.0+ TooltipDataProcessor replaces OnTooltipSetUnit)
    "GameTooltip",
    "TooltipDataProcessor",
    "Enum",

    -- Combat
    "InCombatLockdown",

    -- Minimap
    "Minimap",
    "GetCursorPosition",

    -- Utility
    "C_Timer",
    "strsplit",
    "strtrim",
}

-- Busted test files mock the entire WoW API as globals
files["spec/**"] = {
    globals = {
        "CreateFrame", "UIParent", "UISpecialFrames",
        "UIDropDownMenu_Initialize", "UIDropDownMenu_SetWidth",
        "UIDropDownMenu_SetText", "UIDropDownMenu_CreateInfo",
        "UIDropDownMenu_AddButton", "UIDropDownMenu_EnableDropDown",
        "UIDropDownMenu_DisableDropDown",
        "UnitName", "GetRealmName",
        "GetNumGuildMembers", "GetGuildRosterInfo", "GuildRosterSetPublicNote",
        "IsInGuild", "GetAverageItemLevel", "GetSpecialization",
        "GetSpecializationInfo", "GetNumSpecializations",
        "GetProfessions", "GetProfessionInfo",
        "strsplit", "strtrim",
        "C_Timer", "C_GuildInfo", "C_AddOns", "SlashCmdList",
        "GuildNoteUpdater", "GuildNoteUpdaterSettings", "MockData",
        "GameTooltip", "TooltipDataProcessor", "Enum",
        "InCombatLockdown",
        "Minimap", "GetCursorPosition",
    },
    ignore = {
        "211",  -- Unused local variable (mock data)
        "212",  -- Unused argument (mock signatures)
        "213",  -- Unused loop variable
    },
    read_globals = {
        "dofile", "setmetatable", "os",
        -- Busted globals
        "describe", "it", "setup", "teardown",
        "before_each", "after_each",
        "assert", "spy", "stub", "mock", "match",
        "insulate", "expose",
    },
}

-- Legacy test files (custom runner)
files["tests/**"] = {
    globals = {
        "CreateFrame", "UIParent", "UISpecialFrames",
        "UIDropDownMenu_Initialize", "UIDropDownMenu_SetWidth",
        "UIDropDownMenu_SetText", "UIDropDownMenu_CreateInfo",
        "UIDropDownMenu_AddButton", "UIDropDownMenu_EnableDropDown",
        "UIDropDownMenu_DisableDropDown",
        "UnitName", "GetRealmName",
        "GetNumGuildMembers", "GetGuildRosterInfo", "GuildRosterSetPublicNote",
        "IsInGuild", "GetAverageItemLevel", "GetSpecialization",
        "GetSpecializationInfo", "GetNumSpecializations",
        "GetProfessions", "GetProfessionInfo",
        "strsplit", "strtrim",
        "C_Timer", "C_GuildInfo", "C_AddOns", "SlashCmdList",
        "GuildNoteUpdater", "GuildNoteUpdaterSettings",
        "GameTooltip", "TooltipDataProcessor", "Enum",
        "InCombatLockdown",
        "Minimap", "GetCursorPosition",
    },
    ignore = { "211", "212", "213", "311" },
    read_globals = { "dofile", "setmetatable", "os" },
}
