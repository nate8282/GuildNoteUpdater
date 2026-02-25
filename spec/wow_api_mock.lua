-- WoW API mock layer for busted tests
-- Provides mock implementations of WoW API functions used by GuildNoteUpdater

local MockData = {
    player = { name = "Kaelen", realm = "Sargeras" },
    guildMembers = {
        { name = "Kaelen-Sargeras", note = "" },
        { name = "Kaelen-Proudmoore", note = "" },
        { name = "Nateicus-Sargeras", note = "" },
        { name = "Dannic-Sargeras", note = "" },
    },
    itemLevel = { overall = 489.5, equipped = 485.2 },
    spec = { index = 2, name = "Feral" },
    professions = { [1] = { name = "Leatherworking" }, [2] = { name = "Skinning" } },
    updatedNotes = {},
}

-- Frame mock with chainable method stubs
local frameMT = {
    __index = function(t, k)
        return function() return t end
    end
}
local function mockFrame()
    local f = setmetatable({}, frameMT)
    f.text = setmetatable({}, frameMT)
    f.TitleBg = setmetatable({}, frameMT)
    return f
end

-- Core WoW frame/UI globals
function CreateFrame() return mockFrame() end
UIParent = mockFrame()

-- Dropdown menu API stubs
function UIDropDownMenu_Initialize() end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetText() end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton() end
function UIDropDownMenu_EnableDropDown() end
function UIDropDownMenu_DisableDropDown() end

-- Player info
function UnitName() return MockData.player.name end
function GetRealmName() return MockData.player.realm end

-- Guild API
function GetNumGuildMembers() return #MockData.guildMembers, #MockData.guildMembers end
function GetGuildRosterInfo(i)
    local m = MockData.guildMembers[i]
    if m then
        return m.name, "Member", 1, 80, "Druid", "Zone", m.note, "", true, 0, "DRUID", 1000, 1, false, false, 5, "guid"
    end
end
function GuildRosterSetPublicNote(i, note)
    MockData.updatedNotes[i] = note
    if MockData.guildMembers[i] then
        MockData.guildMembers[i].note = note
    end
end
function IsInGuild() return true end

-- Character info
function GetAverageItemLevel() return MockData.itemLevel.overall, MockData.itemLevel.equipped, MockData.itemLevel.equipped end
function GetSpecialization() return MockData.spec.index end
function GetSpecializationInfo(i) return i, MockData.spec.name, "", 0, "DAMAGER", false, true end
function GetNumSpecializations() return 4 end
function GetProfessions() return 1, 2, nil, nil, nil end
function GetProfessionInfo(i) return MockData.professions[i].name, 0, 100, 100, 0, 0, i, 0, 0, 0, MockData.professions[i].name end

-- WoW utility functions
function strsplit(delim, str)
    local pos = str:find(delim)
    if pos then return str:sub(1, pos - 1), str:sub(pos + 1) end
    return str, nil
end
function strtrim(str) return str and str:match("^%s*(.-)%s*$") or "" end

-- System stubs
C_Timer = { After = function(_, f) f() end }
C_GuildInfo = { GuildRoster = function() end }
SlashCmdList = {}

-- Expose MockData globally so tests can modify it
_G.MockData = MockData

return MockData
