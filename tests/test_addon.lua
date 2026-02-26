-- GuildNoteUpdater Unit Tests
-- Run with: lua5.3 tests/test_addon.lua

print("=== GuildNoteUpdater Test Suite ===\n")

-- Mock data
local mockPlayer = { name = "Kaelen", realm = "Sargeras" }
local mockGuildMembers = {
    { name = "Kaelen-Sargeras", note = "" },
    { name = "Kaelen-Proudmoore", note = "" },
    { name = "Nateicus-Sargeras", note = "" },
    { name = "Dannic-Sargeras", note = "" },
}
local mockItemLevel = { overall = 489.5, equipped = 485.2 }
local mockSpec = { index = 2, name = "Feral" }
local mockProfessions = { [1] = { name = "Leatherworking" }, [2] = { name = "Skinning" } }
local updatedNotes = {}

-- Mock WoW UI Frame metatable
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

-- Global WoW API mocks
function CreateFrame() return mockFrame() end
UIParent = mockFrame()
function UIDropDownMenu_Initialize() end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetText() end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton() end
function UIDropDownMenu_EnableDropDown() end
function UIDropDownMenu_DisableDropDown() end

function UnitName() return mockPlayer.name end
function GetRealmName() return mockPlayer.realm end
function GetNumGuildMembers() return #mockGuildMembers, #mockGuildMembers end
function GetGuildRosterInfo(i) 
    if mockGuildMembers[i] then
        return mockGuildMembers[i].name, "Member", 1, 80, "Druid", "Zone", mockGuildMembers[i].note, "", true, 0, "DRUID", 1000, 1, false, false, 5, "guid"
    end
end
function GuildRosterSetPublicNote(i, note)
    updatedNotes[i] = note
    mockGuildMembers[i].note = note
end
function GetAverageItemLevel() return mockItemLevel.overall, mockItemLevel.equipped, mockItemLevel.equipped end
function GetSpecialization() return mockSpec.index end
function GetSpecializationInfo(i) return i, mockSpec.name, "", 0, "DAMAGER", false, true end
function GetNumSpecializations() return 4 end
function GetProfessions() return 1, 2, nil, nil, nil end
function GetProfessionInfo(i) return mockProfessions[i].name, 0, 100, 100, 0, 0, i, 0, 0, 0, mockProfessions[i].name end
function IsInGuild() return true end
function strsplit(delim, str)
    local pos = str:find(delim)
    if pos then return str:sub(1, pos-1), str:sub(pos+1) end
    return str, nil
end
function strtrim(str) return str and str:match("^%s*(.-)%s*$") or "" end
C_Timer = {
    After = function(d, f) f() end,
    NewTimer = function(_, f) f(); return { Cancel = function() end } end,
}
C_GuildInfo = { GuildRoster = function() end }
SlashCmdList = {}
UISpecialFrames = {}
GameTooltip = mockFrame()
GameTooltip.GetUnit = function() return mockPlayer.name, "target" end
GameTooltip.AddLine = function() end
GameTooltip.AddDoubleLine = function() end
GameTooltip.Show = function() end

-- TooltipDataProcessor mock (Retail 9.0+ tooltip API - replaces OnTooltipSetUnit)
-- See DEPRECATED_APIS.md for migration details
TooltipDataProcessor = {
    AddTooltipPostCall = function() end,
}
Enum = {
    TooltipDataType = { Unit = 0 },
}

-- Load addon
dofile("GuildNoteUpdater.lua")
GuildNoteUpdaterSettings = nil
GuildNoteUpdater:InitializeSettings()

-- Test utilities
local passed, failed = 0, 0
local function test(name, cond)
    if cond then print("✓ " .. name); passed = passed + 1
    else print("✗ " .. name); failed = failed + 1 end
end
local function section(name) print("\n--- " .. name .. " ---") end

-- TESTS
local charKey = GuildNoteUpdater:GetCharacterKey()

section("GetCharacterKey")
test("Returns Name-Realm format", charKey == "Kaelen-Sargeras")
mockPlayer.realm = "Twisting Nether"
test("Removes spaces from realm", GuildNoteUpdater:GetCharacterKey() == "Kaelen-TwistingNether")
mockPlayer.realm = "Sargeras"

section("GetGuildIndexForPlayer")
local idx = GuildNoteUpdater:GetGuildIndexForPlayer()
test("Finds correct player index", idx == 1)
test("Does not match different realm", idx ~= 2)

section("GetProfessionAbbreviation")
test("Leatherworking -> LW", GuildNoteUpdater:GetProfessionAbbreviation("Leatherworking") == "LW")
test("Skinning -> Skn", GuildNoteUpdater:GetProfessionAbbreviation("Skinning") == "Skn")
test("nil returns nil", GuildNoteUpdater:GetProfessionAbbreviation(nil) == nil)
test("Unknown returns nil", GuildNoteUpdater:GetProfessionAbbreviation("Fishing") == nil)

section("GetSpec")
charKey = GuildNoteUpdater:GetCharacterKey()
GuildNoteUpdater.specUpdateMode[charKey] = "Automatically"
test("Auto mode returns current spec", GuildNoteUpdater:GetSpec(charKey) == "Feral")
GuildNoteUpdater.specUpdateMode[charKey] = "Manually"
GuildNoteUpdater.selectedSpec[charKey] = "Guardian"
test("Manual mode returns selected spec", GuildNoteUpdater:GetSpec(charKey) == "Guardian")
GuildNoteUpdater.specUpdateMode[charKey] = "Automatically"

section("UpdateGuildNote - Basic")
GuildNoteUpdater.enabledCharacters[charKey] = true
GuildNoteUpdater.enableProfessions[charKey] = true
GuildNoteUpdater.mainOrAlt[charKey] = "Main"
GuildNoteUpdater.notePrefix[charKey] = nil
GuildNoteUpdater.itemLevelType[charKey] = "Overall"
GuildNoteUpdater.previousNote = ""
updatedNotes = {}
GuildNoteUpdater:UpdateGuildNote()
test("Updates guild note", updatedNotes[1] ~= nil)
test("Contains item level (489)", updatedNotes[1] and updatedNotes[1]:find("489"))
test("Contains spec (Feral)", updatedNotes[1] and updatedNotes[1]:find("Feral"))
test("Contains profession (LW)", updatedNotes[1] and updatedNotes[1]:find("LW"))
test("Contains Main status", updatedNotes[1] and updatedNotes[1]:find("Main"))
print("  Note: " .. (updatedNotes[1] or "nil"))

section("UpdateGuildNote - Equipped iLvl")
GuildNoteUpdater.itemLevelType[charKey] = "Equipped"
GuildNoteUpdater.previousNote = ""
updatedNotes = {}
GuildNoteUpdater:UpdateGuildNote()
test("Uses equipped item level (485)", updatedNotes[1] and updatedNotes[1]:find("485"))
print("  Note: " .. (updatedNotes[1] or "nil"))

section("UpdateGuildNote - Prefix")
GuildNoteUpdater.itemLevelType[charKey] = "Overall"
GuildNoteUpdater.notePrefix[charKey] = "Tank"
GuildNoteUpdater.previousNote = ""
updatedNotes = {}
GuildNoteUpdater:UpdateGuildNote()
test("Includes prefix with hyphen", updatedNotes[1] and updatedNotes[1]:find("Tank -"))
print("  Note: " .. (updatedNotes[1] or "nil"))

section("UpdateGuildNote - Disabled")
GuildNoteUpdater.enabledCharacters[charKey] = false
GuildNoteUpdater.previousNote = ""
updatedNotes = {}
GuildNoteUpdater:UpdateGuildNote()
test("Does not update when disabled", updatedNotes[1] == nil)
GuildNoteUpdater.enabledCharacters[charKey] = true

section("UpdateGuildNote - No Professions")
GuildNoteUpdater.enableProfessions[charKey] = false
GuildNoteUpdater.notePrefix[charKey] = nil
GuildNoteUpdater.previousNote = ""
updatedNotes = {}
GuildNoteUpdater:UpdateGuildNote()
test("Excludes professions when disabled", not (updatedNotes[1] and updatedNotes[1]:find("LW")))
print("  Note: " .. (updatedNotes[1] or "nil"))

section("UpdateGuildNote - No Main/Alt")
GuildNoteUpdater.mainOrAlt[charKey] = "<None>"
GuildNoteUpdater.previousNote = ""
updatedNotes = {}
GuildNoteUpdater:UpdateGuildNote()
test("Excludes Main/Alt when <None>", not (updatedNotes[1] and (updatedNotes[1]:find("Main") or updatedNotes[1]:find("Alt"))))
print("  Note: " .. (updatedNotes[1] or "nil"))

section("Truncation (31 char limit)")
GuildNoteUpdater.enableProfessions[charKey] = true
GuildNoteUpdater.mainOrAlt[charKey] = "Main"
GuildNoteUpdater.notePrefix[charKey] = "RaidLeader"
GuildNoteUpdater.previousNote = ""
updatedNotes = {}
GuildNoteUpdater:UpdateGuildNote()
test("Note is 31 chars or less", updatedNotes[1] and #updatedNotes[1] <= 31)
print("  Note: " .. (updatedNotes[1] or "nil") .. " (" .. (updatedNotes[1] and #updatedNotes[1] or 0) .. " chars)")

section("Nil Safety")
GuildNoteUpdater.notePrefix[charKey] = ""
GuildNoteUpdater.previousNote = ""
updatedNotes = {}
GuildNoteUpdater:UpdateGuildNote()
test("Empty prefix = no hyphen", not (updatedNotes[1] and updatedNotes[1]:find("%-")))

GuildNoteUpdater.notePrefix[charKey] = nil
GuildNoteUpdater.previousNote = ""
updatedNotes = {}
GuildNoteUpdater:UpdateGuildNote()
test("Nil prefix doesn't crash", updatedNotes[1] ~= nil)

section("Cross-Realm Keys")
local key1, key2 = "Kaelen-Sargeras", "Kaelen-Proudmoore"
GuildNoteUpdater.enabledCharacters[key1] = true
GuildNoteUpdater.enabledCharacters[key2] = false
GuildNoteUpdater.mainOrAlt[key1] = "Main"
GuildNoteUpdater.mainOrAlt[key2] = "Alt"
test("Same name, different realm = different settings", GuildNoteUpdater.mainOrAlt[key1] ~= GuildNoteUpdater.mainOrAlt[key2])

section("Skip Unchanged Notes")
GuildNoteUpdater.notePrefix[charKey] = nil
GuildNoteUpdater.mainOrAlt[charKey] = "Main"
GuildNoteUpdater.enableProfessions[charKey] = false
GuildNoteUpdater.previousNote = ""
updatedNotes = {}
GuildNoteUpdater:UpdateGuildNote()
updatedNotes = {}
GuildNoteUpdater:UpdateGuildNote()
test("Skips API call when unchanged", updatedNotes[1] == nil)

-- Summary
print("\n=== Results ===")
print("Passed: " .. passed .. " | Failed: " .. failed)
if failed == 0 then print("\n✓ All tests passed!")
else print("\n✗ " .. failed .. " test(s) failed"); os.exit(1) end
