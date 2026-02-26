GuildNoteUpdater = CreateFrame("Frame")
GuildNoteUpdater.hasUpdated = false
GuildNoteUpdater.previousNote = ""
GuildNoteUpdater.debugEnabled = false
GuildNoteUpdater.pendingUpdateTimer = nil

local DEBOUNCE_DELAY = 2
local MAX_NOTE_LENGTH = 31
local BUTTON_OFFSET = 5
local STALE_ILVL_THRESHOLD = 15  -- warn in tooltip if note ilvl is this many levels behind live

local professionAbbreviations = {
    Alchemy = "Alch", Blacksmithing = "BS", Enchanting = "Enc", Engineering = "Eng",
    Herbalism = "Herb", Inscription = "Ins", Jewelcrafting = "JC", Leatherworking = "LW",
    Mining = "Min", Skinning = "Skn", Tailoring = "Tail"
}

-- Reverse lookup for tooltip parsing
local abbreviationToFull = {}
for full, abbrev in pairs(professionAbbreviations) do
    abbreviationToFull[abbrev] = full
end

-- Returns "Name-Realm" to uniquely identify characters across connected realms
function GuildNoteUpdater:GetCharacterKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    if name and realm then
        return name .. "-" .. realm:gsub("%s+", "")
    end
    return name or "Unknown"
end

-- Prints debug messages when debug mode is enabled
function GuildNoteUpdater:DebugPrint(message)
    if self.debugEnabled then
        print("|cFF00FF00GuildNoteUpdater:|r " .. message)
    end
end

-- Converts full profession name to short abbreviation for guild note
function GuildNoteUpdater:GetProfessionAbbreviation(profession)
    if not profession then return nil end
    return professionAbbreviations[profession]
end

-- Gets current spec name, respecting manual/auto setting per character
function GuildNoteUpdater:GetSpec(characterKey)
    local specIndex = GetSpecialization()
    if not specIndex then return nil end

    if self.specUpdateMode[characterKey] == "Manually" then
        if not self.selectedSpec[characterKey] or self.selectedSpec[characterKey] == "Select Spec" then
            self.selectedSpec[characterKey] = select(2, GetSpecializationInfo(specIndex))
        end
        return self.selectedSpec[characterKey]
    end
    return select(2, GetSpecializationInfo(specIndex))
end

-- Finds player's index in guild roster using exact Name-Realm match
function GuildNoteUpdater:GetGuildIndexForPlayer()
    local playerName = UnitName("player")
    local playerRealm = GetRealmName()
    if playerRealm then
        playerRealm = playerRealm:gsub("%s+", "")
    end

    for i = 1, GetNumGuildMembers() do
        local fullName = GetGuildRosterInfo(i)
        if fullName then
            local name, realm = strsplit("-", fullName)
            if not realm then realm = playerRealm end
            if name == playerName and (realm == playerRealm or not playerRealm) then
                return i
            end
        end
    end
    return nil
end

-- Helper to safely trim strings (handles nil)
local function safeTrim(str)
    if not str then return nil end
    if type(str) ~= "string" then return str end
    return str:match("^%s*(.-)%s*$")
end

-- Parses a guild note string into structured data for tooltip display
function GuildNoteUpdater:ParseGuildNote(note)
    if not note or note == "" then return nil end

    local result = {}
    local tokens = {}

    -- Handle prefix (everything before " - ")
    local prefixEnd = note:find(" %- ")
    local parseFrom = note
    if prefixEnd then
        result.prefix = note:sub(1, prefixEnd - 1)
        parseFrom = note:sub(prefixEnd + 3)
    end

    -- Tokenize remaining string
    for token in parseFrom:gmatch("%S+") do
        table.insert(tokens, token)
    end

    -- Extract ilvl (first 3+ digit numeric token)
    for i, token in ipairs(tokens) do
        if token:match("^%d%d%d+$") then
            result.ilvl = token
            table.remove(tokens, i)
            break
        end
    end

    -- Extract Main/Alt (last token if it matches)
    if #tokens > 0 then
        local last = tokens[#tokens]
        if last == "Main" or last == "Alt" or last == "M" or last == "A" then
            result.mainAlt = (last == "M" and "Main") or (last == "A" and "Alt") or last
            table.remove(tokens, #tokens)
        end
    end

    -- Remaining tokens: first is spec/role, rest are professions
    local profs = {}
    for i, token in ipairs(tokens) do
        if i == 1 then
            result.spec = token
        else
            if abbreviationToFull[token] then
                table.insert(profs, abbreviationToFull[token])
            else
                table.insert(profs, token)
            end
        end
    end
    if #profs > 0 then result.professions = profs end

    -- Only return if we found an ilvl (required for addon-generated notes)
    if result.ilvl then
        return result
    end
    return nil
end

-- Builds the guild note string from current character settings
function GuildNoteUpdater:BuildNoteString(characterKey)
    if not self.enabledCharacters[characterKey] then return nil end

    local overallItemLevel, equippedItemLevel = GetAverageItemLevel()
    local itemLevelType = self.itemLevelType[characterKey] or "Overall"
    local itemLevel = (itemLevelType == "Equipped") and equippedItemLevel or overallItemLevel
    local flooredItemLevel = math.floor(itemLevel)

    -- Guard: don't write ilvl 0 (inventory not loaded yet)
    if flooredItemLevel <= 0 then return nil end

    local showItemLevel = self.enableItemLevel[characterKey] ~= false

    local spec = nil
    if self.enableSpec[characterKey] ~= false then
        spec = self:GetSpec(characterKey)
    end

    local mainOrAlt = nil
    if self.enableMainAlt[characterKey] ~= false then
        mainOrAlt = self.mainOrAlt[characterKey]
        if mainOrAlt == "Select Option" or mainOrAlt == "<None>" then
            mainOrAlt = nil
        end
    end

    local profession1, profession2 = nil, nil
    if self.enableProfessions[characterKey] then
        local prof1, prof2 = GetProfessions()
        if prof1 then profession1 = self:GetProfessionAbbreviation(select(1, GetProfessionInfo(prof1))) end
        if prof2 then profession2 = self:GetProfessionAbbreviation(select(1, GetProfessionInfo(prof2))) end
    end

    local notePrefix = self.notePrefix[characterKey]
    if notePrefix then
        notePrefix = safeTrim(notePrefix)
        if notePrefix == "" then notePrefix = nil end
    end

    local noteFormat = self.noteFormat or "Standard"

    -- Compact format: shorten main/alt and spec up front
    local mainAltDisplay = mainOrAlt
    local specDisplay = spec
    if noteFormat == "Compact" then
        if mainAltDisplay == "Main" then mainAltDisplay = "M"
        elseif mainAltDisplay == "Alt" then mainAltDisplay = "A" end
        if specDisplay then specDisplay = string.sub(specDisplay, 1, 4) end
    end

    local noteParts = {}
    if notePrefix then
        table.insert(noteParts, notePrefix)
        table.insert(noteParts, "-")
    end
    if noteFormat == "Professions First" then
        if self.enableProfessions[characterKey] then
            if profession1 then table.insert(noteParts, profession1) end
            if profession2 then table.insert(noteParts, profession2) end
        end
        if showItemLevel then table.insert(noteParts, flooredItemLevel) end
        if specDisplay then table.insert(noteParts, specDisplay) end
        if mainAltDisplay then table.insert(noteParts, mainAltDisplay) end
    else -- Standard and Compact share the same field order
        if showItemLevel then table.insert(noteParts, flooredItemLevel) end
        if specDisplay then table.insert(noteParts, specDisplay) end
        if self.enableProfessions[characterKey] then
            if profession1 then table.insert(noteParts, profession1) end
            if profession2 then table.insert(noteParts, profession2) end
        end
        if mainAltDisplay then table.insert(noteParts, mainAltDisplay) end
    end

    local newNote = safeTrim(table.concat(noteParts, " ")) or ""

    if newNote == "" then return "" end

    -- Truncate to fit 31-char guild note limit
    if #newNote > MAX_NOTE_LENGTH then
        self:DebugPrint("Note too long (" .. #newNote .. " chars), truncating...")
        noteParts = {}
        if notePrefix then
            table.insert(noteParts, string.sub(notePrefix, 1, 4))
            table.insert(noteParts, "-")
        end
        if noteFormat == "Professions First" then
            if self.enableProfessions[characterKey] then
                if profession1 then table.insert(noteParts, string.sub(profession1, 1, 2)) end
                if profession2 then table.insert(noteParts, string.sub(profession2, 1, 2)) end
            end
            if showItemLevel then table.insert(noteParts, flooredItemLevel) end
            if spec then table.insert(noteParts, string.sub(spec, 1, 4)) end
            if mainOrAlt then table.insert(noteParts, string.sub(mainOrAlt, 1, 1)) end
        else -- Standard and Compact
            if showItemLevel then table.insert(noteParts, flooredItemLevel) end
            if spec then table.insert(noteParts, string.sub(spec, 1, 4)) end
            if self.enableProfessions[characterKey] then
                if profession1 then table.insert(noteParts, string.sub(profession1, 1, 2)) end
                if profession2 then table.insert(noteParts, string.sub(profession2, 1, 2)) end
            end
            if mainAltDisplay then table.insert(noteParts, string.sub(mainAltDisplay, 1, 1)) end
        end
        newNote = safeTrim(table.concat(noteParts, " ")) or ""

        while #newNote > MAX_NOTE_LENGTH and #noteParts > 1 do
            table.remove(noteParts)
            newNote = safeTrim(table.concat(noteParts, " ")) or ""
        end
    end

    return newNote
end

-- Module-level preview references (avoids mock frame __index issues in tests)
local previewText = nil
local charCountText = nil

-- Shows visual confirmation when note is updated
function GuildNoteUpdater:ShowUpdateConfirmation(newNote)
    if not self.showUpdateNotification then return end
    local len = #newNote
    local color
    if len <= 24 then
        color = "|cFF00FF00"
    elseif len <= MAX_NOTE_LENGTH then
        color = "|cFFFFFF00"
    else
        color = "|cFFFF0000"
    end
    print("|cFF00FF00GuildNoteUpdater:|r Note updated -> |cFFFFFFFF" .. newNote .. "|r " .. color .. "(" .. len .. "/" .. MAX_NOTE_LENGTH .. ")|r")
end

-- Refreshes the note preview display in the settings UI
function GuildNoteUpdater:UpdateNotePreview()
    if not previewText then return end

    local characterKey = self:GetCharacterKey()

    -- When note is locked, show the actual current guild note for manual editing
    if self.noteLocked and self.noteLocked[characterKey] then
        local note = self.previousNote or ""
        previewText:SetText(note)
        local charCount = #note
        local color
        if charCount <= 24 then color = "|cFF00FF00"
        elseif charCount <= MAX_NOTE_LENGTH then color = "|cFFFFFF00"
        else color = "|cFFFF0000" end
        charCountText:SetText(color .. charCount .. "/" .. MAX_NOTE_LENGTH .. "|r")
        return
    end

    local note = self:BuildNoteString(characterKey)

    if note then
        local charCount = #note
        local color
        if charCount <= 24 then
            color = "|cFF00FF00"
        elseif charCount <= MAX_NOTE_LENGTH then
            color = "|cFFFFFF00"
        else
            color = "|cFFFF0000"
        end
        previewText:SetText(note)
        charCountText:SetText(color .. charCount .. "/" .. MAX_NOTE_LENGTH .. "|r")
    else
        if not self.enabledCharacters[characterKey] then
            previewText:SetText("|cFF888888Disabled for this character|r")
        else
            previewText:SetText("|cFF888888Waiting for data...|r")
        end
        charCountText:SetText("")
    end
end

-- Builds and sets the guild note from current character data
function GuildNoteUpdater:UpdateGuildNote()
    if InCombatLockdown() then
        self:DebugPrint("In combat lockdown, deferring note update")
        self.pendingCombatUpdate = true
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end

    local characterKey = self:GetCharacterKey()

    if self.noteLocked[characterKey] then
        self:DebugPrint("Note is locked, skipping update")
        self:UpdateNotePreview()
        return
    end

    local newNote = self:BuildNoteString(characterKey)

    if not newNote then
        self:DebugPrint("No note to update (disabled or ilvl 0)")
        self:UpdateNotePreview()
        return
    end

    local guildIndex = self:GetGuildIndexForPlayer()
    if guildIndex then
        if self.previousNote ~= newNote then
            self:DebugPrint("Updating guild note to: " .. newNote)
            GuildRosterSetPublicNote(guildIndex, newNote)
            self.previousNote = newNote
            self:ShowUpdateConfirmation(newNote)
        else
            self:DebugPrint("Note unchanged, skipping update")
        end
    else
        self:DebugPrint("Unable to find guild index for player.")
    end

    self:UpdateNotePreview()
end

-- Builds a "Name-RealmNoSpaces" key from a guild roster full name
-- Handles same-realm members (no realm suffix) and cross-realm members
local function buildMemberKey(fullName)
    local name, realm = strsplit("-", fullName)
    if realm then
        return name .. "-" .. realm:gsub("%s+", "")
    end
    return fullName .. "-" .. GetRealmName():gsub("%s+", "")
end

-- Sets up tooltip hook to display parsed guild note data
-- Uses TooltipDataProcessor API (Retail 9.0+) - OnTooltipSetUnit was removed in modern WoW
function GuildNoteUpdater:SetupTooltipHook()
    if not TooltipDataProcessor then return end

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
        if not GuildNoteUpdater.enableTooltipParsing then return end
        if not IsInGuild() then return end

        local unitName = data and data.name
        if not unitName then return end

        for i = 1, GetNumGuildMembers() do
            local fullName, _, _, _, _, _, note = GetGuildRosterInfo(i)
            if fullName and note and note ~= "" then
                local name = strsplit("-", fullName)
                if name == unitName then
                    local parsed = GuildNoteUpdater:ParseGuildNote(note)
                    if parsed and parsed.ilvl then
                        tooltip:AddLine(" ")
                        tooltip:AddLine("|cFF00FF00Guild Note:|r")
                        tooltip:AddDoubleLine("  Item Level", parsed.ilvl, 1, 0.82, 0, 1, 1, 1)
                        if parsed.spec then
                            tooltip:AddDoubleLine("  Spec", parsed.spec, 1, 0.82, 0, 1, 1, 1)
                        end
                        if parsed.professions then
                            tooltip:AddDoubleLine("  Professions", table.concat(parsed.professions, ", "), 1, 0.82, 0, 1, 1, 1)
                        end
                        if parsed.mainAlt then
                            tooltip:AddDoubleLine("  Status", parsed.mainAlt, 1, 0.82, 0, 1, 1, 1)
                        end
                        -- Alt registry: show main character name for alts
                        if parsed.mainAlt == "Alt" then
                            local altKey = buildMemberKey(fullName)
                            local mainName = GuildNoteUpdater.altRegistry and GuildNoteUpdater.altRegistry[altKey]
                            if mainName then
                                tooltip:AddDoubleLine("  Main", mainName, 1, 0.82, 0, 1, 1, 1)
                            end
                        end
                        -- Stale note warning: compare note ilvl to live ilvl for group members
                        if STALE_ILVL_THRESHOLD > 0 then
                            local noteIlvl = tonumber(parsed.ilvl)
                            if noteIlvl then
                                local unitToken = nil
                                for i = 1, 4 do
                                    local token = "party" .. i
                                    if UnitName(token) == unitName then unitToken = token ; break end
                                end
                                if not unitToken then
                                    for i = 1, 40 do
                                        local token = "raid" .. i
                                        if UnitName(token) == unitName then unitToken = token ; break end
                                    end
                                end
                                if unitToken then
                                    local liveIlvl = tonumber(UnitAverageItemLevel(unitToken))
                                    if liveIlvl and (liveIlvl - noteIlvl) >= STALE_ILVL_THRESHOLD then
                                        tooltip:AddLine(string.format(
                                            "|cFFFFFF00Note may be outdated (note: %d, live: %d)|r",
                                            noteIlvl, math.floor(liveIlvl)))
                                    end
                                end
                            end
                        end
                        tooltip:Show()
                    end
                    break
                end
            end
        end
    end)
end

-- Prints a per-member guild roster to chat (/gnu roster)
local function PrintRosterSummary(mainsOnly)
    if not IsInGuild() then
        print("|cFFFF0000GuildNoteUpdater:|r You are not in a guild.")
        return
    end
    C_GuildInfo.GuildRoster()
    C_Timer.After(0.5, function()
        local totalMembers = 0
        local mainCount, altCount = 0, 0
        local members = {}

        for i = 1, GetNumGuildMembers() do
            local fullName, _, _, _, _, _, note, _, _, _, class = GetGuildRosterInfo(i)
            if fullName then
                totalMembers = totalMembers + 1
                local parsed = GuildNoteUpdater:ParseGuildNote(note)
                if parsed then
                    local name = strsplit("-", fullName) or fullName
                    local isMain = parsed.mainAlt == "Main"
                    if isMain then mainCount = mainCount + 1 end
                    if parsed.mainAlt == "Alt" then altCount = altCount + 1 end
                    table.insert(members, {
                        name = name,
                        ilvl = tonumber(parsed.ilvl) or 0,
                        spec = parsed.spec,
                        profs = parsed.professions,
                        mainAlt = parsed.mainAlt,
                        class = class,
                    })
                end
            end
        end

        -- Filter to mains only if requested
        if mainsOnly then
            local filtered = {}
            for _, m in ipairs(members) do
                if m.mainAlt == "Main" then table.insert(filtered, m) end
            end
            members = filtered
        end

        if #members == 0 then
            print("|cFF00FF00[GNU] Roster:|r No recognized GNU notes found.")
            return
        end

        -- Sort by ilvl descending
        table.sort(members, function(a, b) return a.ilvl > b.ilvl end)

        -- Compute avg from filtered list
        local ilvlSum, ilvlCount = 0, 0
        for _, m in ipairs(members) do
            if m.ilvl > 0 then ilvlSum = ilvlSum + m.ilvl ; ilvlCount = ilvlCount + 1 end
        end
        local avgStr = ilvlCount > 0 and tostring(math.floor(ilvlSum / ilvlCount)) or "N/A"

        local header = mainsOnly and "Mains Only" or "All"
        print(string.format("|cFF00FF00===  GNU Roster: %s  ===|r", header))
        print(string.format("|cFFFFD100  %d/%d w/notes  |  avg %s ilvl  |  %d Mains  |  %d Alts|r",
            #members, totalMembers, avgStr, mainCount, altCount))

        for _, m in ipairs(members) do
            local parts = {}
            if m.spec then table.insert(parts, m.spec) end
            if m.profs then table.insert(parts, table.concat(m.profs, "/")) end
            if m.mainAlt then table.insert(parts, m.mainAlt) end
            local detail = #parts > 0 and ("  " .. table.concat(parts, " | ")) or ""
            local nameColor = "|cFFFFFFFF"
            if m.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[m.class] then
                local c = RAID_CLASS_COLORS[m.class]
                nameColor = string.format("|cFF%02X%02X%02X", math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255))
            end
            print(string.format("  %s%s|r - %d%s", nameColor, m.name, m.ilvl, detail))
        end
    end)
end

-- Creates the settings UI with sidebar navigation and themed panel
function GuildNoteUpdater:CreateUI()
    local characterKey = self:GetCharacterKey()

    -- Solid 1px-border backdrop used throughout
    local solidBD = {
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    }

    -- Forward declarations for cross-references between General page and preview bar
    local lockCB         = nil  -- General page "Lock note" checkbox
    local lockPreviewBtn = nil  -- Preview bar lock toggle button

    -- =========================================================
    -- MAIN FRAME
    -- =========================================================
    local frame = CreateFrame("Frame", "GuildNoteUpdaterUI", UIParent, "BackdropTemplate")
    frame:SetSize(500, 420)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    self.settingsFrame = frame
    table.insert(UISpecialFrames, "GuildNoteUpdaterUI")

    frame:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.067, 0.067, 0.125, 0.97)
    frame:SetBackdropBorderColor(0.145, 0.145, 0.251, 1.0)

    -- =========================================================
    -- TITLE BAR
    -- =========================================================
    local titleBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    titleBar:SetPoint("TOPLEFT",  frame, "TOPLEFT",  4, -4)
    titleBar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
    titleBar:SetHeight(34)
    titleBar:SetBackdrop(solidBD)
    titleBar:SetBackdropColor(0.102, 0.102, 0.188, 1.0)
    titleBar:SetBackdropBorderColor(0, 0, 0, 0)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function() frame:StopMovingOrSizing() end)

    -- Title bar bottom divider
    local titleDivider = frame:CreateTexture(nil, "BORDER")
    titleDivider:SetPoint("TOPLEFT",  titleBar, "BOTTOMLEFT",  0, 0)
    titleDivider:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
    titleDivider:SetHeight(1)
    titleDivider:SetColorTexture(0.102, 0.102, 0.188, 1.0)

    -- Icon box: uses the addon's icon texture
    local iconBox = CreateFrame("Frame", nil, titleBar, "BackdropTemplate")
    iconBox:SetSize(18, 18)
    iconBox:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
    iconBox:SetBackdrop(solidBD)
    iconBox:SetBackdropColor(0.65, 0.52, 0.0, 1.0)
    iconBox:SetBackdropBorderColor(0.40, 0.32, 0.0, 1.0)
    local iconTex = iconBox:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints(iconBox)
    iconTex:SetTexture("Interface\\AddOns\\GuildNoteUpdater\\Icon")

    -- Title text
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", iconBox, "RIGHT", 8, 0)
    titleText:SetText("Guild Note Updater")
    titleText:SetTextColor(0.91, 0.91, 0.94)

    -- Version text
    local version = C_AddOns.GetAddOnMetadata("GuildNoteUpdater", "Version") or ""
    local versionText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    versionText:SetPoint("RIGHT", titleBar, "RIGHT", -32, 0)
    versionText:SetText("v" .. version)
    versionText:SetTextColor(0.267, 0.267, 0.353)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("RIGHT", titleBar, "RIGHT", -8, 0)
    closeBtn:SetBackdrop(solidBD)
    closeBtn:SetBackdropColor(0.35, 0.08, 0.08, 1.0)
    closeBtn:SetBackdropBorderColor(0.48, 0.16, 0.16, 1.0)
    local closeTxt = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    closeTxt:SetPoint("CENTER")
    closeTxt:SetText("|cFFCC4444x|r")
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    closeBtn:SetScript("OnEnter", function()
        closeBtn:SetBackdropColor(0.55, 0.12, 0.12, 1.0)
        closeBtn:SetBackdropBorderColor(0.70, 0.20, 0.20, 1.0)
        closeTxt:SetText("|cFFFF6060x|r")
    end)
    closeBtn:SetScript("OnLeave", function()
        closeBtn:SetBackdropColor(0.35, 0.08, 0.08, 1.0)
        closeBtn:SetBackdropBorderColor(0.48, 0.16, 0.16, 1.0)
        closeTxt:SetText("|cFFCC4444x|r")
    end)

    -- =========================================================
    -- SIDEBAR
    -- =========================================================
    local SIDEBAR_W  = 138
    local PREVIEW_H  = 62   -- increased for two-row layout
    local TITLE_H    = 39   -- titleBar 34 + divider 1 + 4px gap

    local sidebar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT",    frame, "TOPLEFT",    4, -(TITLE_H + 4))
    sidebar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 4, PREVIEW_H + 4)
    sidebar:SetWidth(SIDEBAR_W)
    sidebar:SetBackdrop(solidBD)
    sidebar:SetBackdropColor(0.051, 0.051, 0.110, 1.0)
    sidebar:SetBackdropBorderColor(0, 0, 0, 0)

    -- Sidebar right divider
    local sidebarDiv = frame:CreateTexture(nil, "BORDER")
    sidebarDiv:SetPoint("TOPLEFT",    sidebar, "TOPRIGHT",    0, 0)
    sidebarDiv:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 0, 0)
    sidebarDiv:SetWidth(1)
    sidebarDiv:SetColorTexture(0.102, 0.102, 0.188, 1.0)

    -- =========================================================
    -- CONTENT AREA
    -- =========================================================
    local contentArea = CreateFrame("Frame", nil, frame)
    contentArea:SetPoint("TOPLEFT",    sidebar, "TOPRIGHT",    1,  0)
    contentArea:SetPoint("BOTTOMRIGHT", frame,  "BOTTOMRIGHT", -4, PREVIEW_H + 4)

    -- =========================================================
    -- NAV ITEMS  (builds sidebar buttons and page frames)
    -- =========================================================
    local pages      = {}
    local navBgs     = {}
    local navDots    = {}
    local navLabels  = {}
    local activeNav  = nil

    local function ActivateNav(name)
        for n, pg in pairs(pages) do
            pg:SetShown(n == name)
        end
        activeNav = name
        for n, bg in pairs(navBgs) do
            if n == name then
                bg:SetBackdropColor(1.0, 0.820, 0.0, 0.07)
                bg:SetBackdropBorderColor(1.0, 0.820, 0.0, 0.15)
                navDots[n]:SetColorTexture(1.0, 0.820, 0.0, 1.0)
                navLabels[n]:SetTextColor(1.0, 0.820, 0.0)
            else
                bg:SetBackdropColor(0, 0, 0, 0)
                bg:SetBackdropBorderColor(0, 0, 0, 0)
                navDots[n]:SetColorTexture(0.165, 0.165, 0.267, 1.0)
                navLabels[n]:SetTextColor(0.353, 0.353, 0.478)
            end
        end
    end

    local navY = -8
    local function MakeNavItem(navName)
        local btn = CreateFrame("Button", nil, sidebar, "BackdropTemplate")
        btn:SetPoint("TOPLEFT",  sidebar, "TOPLEFT",  6, navY)
        btn:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -6, navY)
        btn:SetHeight(28)
        btn:SetBackdrop(solidBD)
        btn:SetBackdropColor(0, 0, 0, 0)
        btn:SetBackdropBorderColor(0, 0, 0, 0)

        local dot = btn:CreateTexture(nil, "ARTWORK")
        dot:SetSize(5, 5)
        dot:SetPoint("LEFT", btn, "LEFT", 9, 0)
        dot:SetColorTexture(0.165, 0.165, 0.267, 1.0)
        navDots[navName] = dot

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT", dot, "RIGHT", 9, 0)
        lbl:SetText(navName)
        lbl:SetTextColor(0.353, 0.353, 0.478)
        navLabels[navName] = lbl

        navBgs[navName] = btn
        btn:SetScript("OnClick",  function() ActivateNav(navName) end)
        btn:SetScript("OnEnter",  function()
            if activeNav ~= navName then lbl:SetTextColor(0.565, 0.565, 0.690) end
        end)
        btn:SetScript("OnLeave",  function()
            if activeNav ~= navName then lbl:SetTextColor(0.353, 0.353, 0.478) end
        end)

        -- Create matching page frame
        local pg = CreateFrame("Frame", nil, contentArea)
        pg:SetAllPoints(contentArea)
        pg:Hide()
        pages[navName] = pg

        navY = navY - 30
        return pg
    end

    local pageNC = MakeNavItem("Note Content")
    local pageG  = MakeNavItem("General")

    -- Thin divider between General and Advanced
    local navDiv = sidebar:CreateTexture(nil, "BORDER")
    navDiv:SetPoint("TOPLEFT",  sidebar, "TOPLEFT",  10, navY - 4)
    navDiv:SetPoint("TOPRIGHT", sidebar, "TOPRIGHT", -10, navY - 4)
    navDiv:SetHeight(1)
    navDiv:SetColorTexture(0.094, 0.094, 0.188, 1.0)
    navY = navY - 14

    local pageA = MakeNavItem("Advanced")

    -- =========================================================
    -- SHARED CONTROL HELPERS
    -- =========================================================

    -- Custom checkbox: small dark box with gold checkmark, styled label
    local function MakeCB(parent, py, labelText, isChecked, onClick)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, py)
        btn:SetSize(300, 20)

        local box = CreateFrame("Frame", nil, btn, "BackdropTemplate")
        box:SetSize(13, 13)
        box:SetPoint("LEFT", btn, "LEFT", 0, 0)
        box:SetBackdrop(solidBD)

        local function StyleBox(checked)
            if checked then
                box:SetBackdropColor(1.0, 0.820, 0.0, 0.10)
                box:SetBackdropBorderColor(1.0, 0.820, 0.0, 0.50)
            else
                box:SetBackdropColor(0.039, 0.039, 0.094, 1.0)
                box:SetBackdropBorderColor(0.165, 0.165, 0.267, 1.0)
            end
        end
        StyleBox(isChecked)

        local chk = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        chk:SetPoint("CENTER")
        chk:SetText("|cFFFFD100v|r")
        chk:SetShown(isChecked)

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("LEFT", box, "RIGHT", 8, 0)
        lbl:SetText(labelText)
        lbl:SetTextColor(
            isChecked and 0.690 or 0.353,
            isChecked and 0.690 or 0.353,
            isChecked and 0.800 or 0.478)

        btn:SetScript("OnClick", function()
            local val = not chk:IsShown()
            chk:SetShown(val)
            StyleBox(val)
            lbl:SetTextColor(val and 0.690 or 0.353, val and 0.690 or 0.353, val and 0.800 or 0.478)
            onClick(val)
        end)
        btn.SetChecked = function(_, val)
            chk:SetShown(val)
            StyleBox(val)
            lbl:SetTextColor(val and 0.690 or 0.353, val and 0.690 or 0.353, val and 0.800 or 0.478)
        end
        btn.GetChecked = function() return chk:IsShown() end
        return btn
    end

    -- Small dim label
    local function MakeLbl(parent, x, py, text)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, py)
        fs:SetText(text)
        fs:SetTextColor(0.353, 0.353, 0.478)
        return fs
    end

    -- Section title with underline divider
    local function MakeSection(parent, py, text)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT",  parent, "TOPLEFT",  12, py)
        fs:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, py)
        fs:SetText("|cFFFFD100" .. string.upper(text) .. "|r")
        local div = parent:CreateTexture(nil, "BORDER")
        div:SetPoint("TOPLEFT",  parent, "TOPLEFT",  12, py - 14)
        div:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, py - 14)
        div:SetHeight(1)
        div:SetColorTexture(0.102, 0.102, 0.188, 1.0)
    end

    -- =========================================================
    -- CUSTOM DROPDOWN FACTORY
    -- =========================================================

    -- Shared dismisser: catches outside clicks to close any open dropdown list
    local ddDismisser = CreateFrame("Frame", nil, UIParent)
    ddDismisser:SetAllPoints(UIParent)
    ddDismisser:SetFrameStrata("TOOLTIP")
    ddDismisser:SetFrameLevel(499)
    ddDismisser:EnableMouse(true)
    ddDismisser:Hide()

    local openDDList = nil
    local function CloseDDList()
        if openDDList then openDDList:Hide(); openDDList = nil end
        ddDismisser:Hide()
    end
    ddDismisser:SetScript("OnMouseDown", CloseDDList)
    frame:SetScript("OnHide", CloseDDList)

    local specDD  -- forward declaration: referenced in specUpdateDD's onChange before specDD is created

    -- Custom dropdown factory
    -- parent     : parent frame
    -- x, py      : TOPLEFT offset from parent (py is negative = downward)
    -- initLabel  : initial display text
    -- getOptions : function() → { {label, value}, ... }  called fresh each open
    -- width      : pixel width of the widget
    -- onChange   : function(value)  called when user picks an item
    local function MakeDropdown(parent, x, py, initLabel, getOptions, width, onChange)
        local w = width or 110

        local container = CreateFrame("Button", nil, parent, "BackdropTemplate")
        container:SetPoint("TOPLEFT", parent, "TOPLEFT", x, py)
        container:SetSize(w, 22)
        container:SetBackdrop(solidBD)
        container:SetBackdropColor(0.039, 0.039, 0.094, 1.0)
        container:SetBackdropBorderColor(0.165, 0.165, 0.267, 1.0)

        local valText = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        valText:SetPoint("LEFT",  container, "LEFT",  7, 0)
        valText:SetPoint("RIGHT", container, "RIGHT", -16, 0)
        valText:SetJustifyH("LEFT")
        valText:SetText(initLabel)
        valText:SetTextColor(0.690, 0.690, 0.800)

        local arrowText = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        arrowText:SetPoint("RIGHT", container, "RIGHT", -5, 0)
        arrowText:SetText("|cFF44445Av|r")

        -- Popup list (parented to UIParent so it always floats above everything)
        local list = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        list:SetFrameStrata("TOOLTIP")
        list:SetFrameLevel(500)
        list:SetBackdrop(solidBD)
        list:SetBackdropColor(0.027, 0.027, 0.063, 0.98)
        list:SetBackdropBorderColor(0.165, 0.165, 0.267, 1.0)
        list:Hide()

        local selectedValue = initLabel
        local itemPool = {}
        local ITEM_H = 22
        local PAD_V  = 4

        local function PopulateList()
            for _, btn in ipairs(itemPool) do btn:Hide() end
            local opts = getOptions()

            while #itemPool < #opts do
                local btn = CreateFrame("Button", nil, list, "BackdropTemplate")
                btn:SetHeight(ITEM_H)
                btn:SetBackdrop(solidBD)
                btn:SetBackdropColor(0, 0, 0, 0)
                btn:SetBackdropBorderColor(0, 0, 0, 0)
                local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                fs:SetPoint("LEFT",  btn, "LEFT",  8, 0)
                fs:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
                fs:SetJustifyH("LEFT")
                btn._fs = fs
                btn:SetScript("OnEnter", function(self)
                    self:SetBackdropColor(1.0, 0.820, 0.0, 0.10)
                    self:SetBackdropBorderColor(0, 0, 0, 0)
                end)
                btn:SetScript("OnLeave", function(self)
                    self:SetBackdropColor(0, 0, 0, 0)
                    self:SetBackdropBorderColor(0, 0, 0, 0)
                end)
                table.insert(itemPool, btn)
            end

            for i, opt in ipairs(opts) do
                local btn = itemPool[i]
                btn:SetPoint("TOPLEFT",  list, "TOPLEFT",  1, -(PAD_V + (i - 1) * ITEM_H))
                btn:SetPoint("TOPRIGHT", list, "TOPRIGHT", -1, -(PAD_V + (i - 1) * ITEM_H))
                btn:SetHeight(ITEM_H)
                btn:SetBackdropColor(0, 0, 0, 0)
                btn:SetBackdropBorderColor(0, 0, 0, 0)
                btn._fs:SetText(opt.label)
                if opt.value == selectedValue then
                    btn._fs:SetTextColor(1.0, 0.820, 0.0)
                else
                    btn._fs:SetTextColor(0.690, 0.690, 0.800)
                end
                btn:SetScript("OnClick", function()
                    selectedValue = opt.value
                    valText:SetText(opt.label)
                    CloseDDList()
                    if onChange then onChange(opt.value) end
                end)
                btn:Show()
            end
            list:SetWidth(w)
            list:SetHeight(PAD_V * 2 + #opts * ITEM_H)
        end

        container:SetScript("OnClick", function()
            if not container._enabled then return end
            if openDDList == list then CloseDDList(); return end
            CloseDDList()
            PopulateList()
            list:ClearAllPoints()
            list:SetPoint("TOPLEFT", container, "BOTTOMLEFT", 0, -2)
            list:Show()
            openDDList = list
            ddDismisser:Show()
        end)

        container:SetScript("OnEnter", function()
            if container._enabled then
                container:SetBackdropBorderColor(0.265, 0.265, 0.400, 1.0)
            end
        end)
        container:SetScript("OnLeave", function()
            if container._enabled then
                container:SetBackdropBorderColor(0.165, 0.165, 0.267, 1.0)
            end
        end)

        container._enabled = true
        function container:Enable()
            self._enabled = true
            valText:SetTextColor(0.690, 0.690, 0.800)
            arrowText:SetText("|cFF44445Av|r")
            self:SetBackdropColor(0.039, 0.039, 0.094, 1.0)
            self:SetBackdropBorderColor(0.165, 0.165, 0.267, 1.0)
        end
        function container:Disable()
            self._enabled = false
            valText:SetTextColor(0.200, 0.200, 0.300)
            arrowText:SetText("|cFF1A1A2Av|r")
            self:SetBackdropColor(0.025, 0.025, 0.060, 1.0)
            self:SetBackdropBorderColor(0.100, 0.100, 0.160, 1.0)
            if openDDList == list then CloseDDList() end
        end
        function container:GetValue() return selectedValue end
        function container:SetValue(v, lbl)
            selectedValue = v
            valText:SetText(lbl or v)
        end

        return container
    end

    -- =========================================================
    -- SHARED LOCK STATE HANDLER
    -- Updates both the General page checkbox and the preview bar lock button
    -- =========================================================
    local function UpdateLockState(val)
        local key = GuildNoteUpdater:GetCharacterKey()
        GuildNoteUpdater.noteLocked[key] = val
        GuildNoteUpdaterSettings.noteLocked = GuildNoteUpdater.noteLocked

        -- Sync the General page checkbox
        if lockCB then lockCB:SetChecked(val) end

        -- Update preview EditBox editability
        if previewText then
            if val then
                previewText:SetEnabled(true)
                previewText:SetTextColor(1.0, 0.820, 0.0)
                -- Show the actual current note for manual editing
                previewText:SetText(GuildNoteUpdater.previousNote or "")
            else
                previewText:SetEnabled(false)
                previewText:SetTextColor(1.0, 0.820, 0.0)
                GuildNoteUpdater:UpdateNotePreview()
            end
        end

        -- Update lock button visual
        if lockPreviewBtn then
            if val then
                lockPreviewBtn:SetBackdropColor(1.0, 0.820, 0.0, 0.15)
                lockPreviewBtn:SetBackdropBorderColor(1.0, 0.820, 0.0, 0.60)
            else
                lockPreviewBtn:SetBackdropColor(0.039, 0.039, 0.094, 1.0)
                lockPreviewBtn:SetBackdropBorderColor(0.165, 0.165, 0.267, 1.0)
            end
        end
    end

    -- =========================================================
    -- PAGE: Note Content
    -- =========================================================
    local ncY = -8
    MakeSection(pageNC, ncY, "Note Content")
    ncY = ncY - 26

    -- ── Show item level  [checkbox]  [Overall/Equipped dropdown — right-aligned] ──
    MakeCB(pageNC, ncY, "Show item level",
        self.enableItemLevel[characterKey] ~= false,
        function(val)
            local key = GuildNoteUpdater:GetCharacterKey()
            GuildNoteUpdater.enableItemLevel[key] = val
            GuildNoteUpdaterSettings.enableItemLevel = GuildNoteUpdater.enableItemLevel
            GuildNoteUpdater:UpdateGuildNote()
        end)

    -- Dropdown right-side column (x=175) — consistent across all rows with paired dropdowns
    MakeDropdown(pageNC, 175, ncY,
        self.itemLevelType[characterKey] or "Overall",
        function()
            local opts = {}
            for _, opt in ipairs({"Overall", "Equipped"}) do
                table.insert(opts, {label = opt, value = opt})
            end
            return opts
        end,
        105,
        function(val)
            local k = GuildNoteUpdater:GetCharacterKey()
            GuildNoteUpdater.itemLevelType[k] = val
            GuildNoteUpdaterSettings.itemLevelType = GuildNoteUpdater.itemLevelType
            GuildNoteUpdater:UpdateGuildNote()
        end)
    ncY = ncY - 26

    -- ── Show spec  [checkbox] ──
    MakeCB(pageNC, ncY, "Show spec",
        self.enableSpec[characterKey] ~= false,
        function(val)
            local key = GuildNoteUpdater:GetCharacterKey()
            GuildNoteUpdater.enableSpec[key] = val
            GuildNoteUpdaterSettings.enableSpec = GuildNoteUpdater.enableSpec
            GuildNoteUpdater:UpdateGuildNote()
        end)
    ncY = ncY - 26

    -- Thin left bar to visually group the spec sub-options under "Show spec"
    local specSubBar = pageNC:CreateTexture(nil, "BORDER")
    specSubBar:SetWidth(1)
    specSubBar:SetPoint("TOPLEFT", pageNC, "TOPLEFT", 22, ncY + 2)
    specSubBar:SetHeight(54)   -- spans both sub-rows (26 + 28)
    specSubBar:SetColorTexture(0.165, 0.165, 0.267, 1.0)

    -- Sub-row A: Update mode (Automatically / Manually)
    MakeLbl(pageNC, 30, ncY - 3, "Update")
    MakeDropdown(pageNC, 76, ncY,
        self.specUpdateMode[characterKey] or "Automatically",
        function()
            local opts = {}
            for _, opt in ipairs({"Automatically", "Manually"}) do
                table.insert(opts, {label = opt, value = opt})
            end
            return opts
        end,
        120,
        function(val)
            local k = GuildNoteUpdater:GetCharacterKey()
            GuildNoteUpdater.specUpdateMode[k] = val
            GuildNoteUpdaterSettings.specUpdateMode = GuildNoteUpdater.specUpdateMode
            if val == "Manually" then specDD:Enable() else specDD:Disable() end
            GuildNoteUpdater:UpdateGuildNote()
        end)
    ncY = ncY - 26

    -- Sub-row B: Spec selector (disabled when mode is Automatically)
    MakeLbl(pageNC, 30, ncY - 3, "Spec")
    specDD = MakeDropdown(pageNC, 76, ncY,
        self.selectedSpec[characterKey] or "Select Spec",
        function()
            local opts = {{label = "Select Spec", value = "Select Spec"}}
            for i = 1, GetNumSpecializations() do
                local _, specName = GetSpecializationInfo(i)
                if specName then
                    table.insert(opts, {label = specName, value = specName})
                end
            end
            return opts
        end,
        135,
        function(val)
            local k = GuildNoteUpdater:GetCharacterKey()
            GuildNoteUpdater.selectedSpec[k] = val
            GuildNoteUpdaterSettings.selectedSpec = GuildNoteUpdater.selectedSpec
            GuildNoteUpdater:UpdateGuildNote()
        end)

    if self.specUpdateMode[characterKey] == "Automatically" or not self.specUpdateMode[characterKey] then
        specDD:Disable()
    end
    ncY = ncY - 28

    -- ── Show professions  [checkbox] ──
    MakeCB(pageNC, ncY, "Show professions",
        self.enableProfessions[characterKey] == true,
        function(val)
            local key = GuildNoteUpdater:GetCharacterKey()
            GuildNoteUpdater.enableProfessions[key] = val
            GuildNoteUpdaterSettings.enableProfessions[key] = val
            GuildNoteUpdater:UpdateGuildNote()
        end)
    ncY = ncY - 26

    -- ── Show main / alt  [checkbox]  [None/Main/Alt dropdown — right-aligned] ──
    MakeCB(pageNC, ncY, "Show main / alt",
        self.enableMainAlt[characterKey] ~= false,
        function(val)
            local key = GuildNoteUpdater:GetCharacterKey()
            GuildNoteUpdater.enableMainAlt[key] = val
            GuildNoteUpdaterSettings.enableMainAlt = GuildNoteUpdater.enableMainAlt
            GuildNoteUpdater:UpdateGuildNote()
        end)

    MakeDropdown(pageNC, 175, ncY,
        self.mainOrAlt[characterKey] or "<None>",
        function()
            local opts = {}
            for _, opt in ipairs({"<None>", "Main", "Alt"}) do
                table.insert(opts, {label = opt, value = opt})
            end
            return opts
        end,
        90,
        function(val)
            local k = GuildNoteUpdater:GetCharacterKey()
            GuildNoteUpdater.mainOrAlt[k] = val
            GuildNoteUpdaterSettings.mainOrAlt = GuildNoteUpdater.mainOrAlt
            GuildNoteUpdater:UpdateGuildNote()
        end)
    ncY = ncY - 30

    -- ── Note format  [label + dropdown] ──
    MakeLbl(pageNC, 12, ncY - 3, "Format")
    MakeDropdown(pageNC, 60, ncY,
        self.noteFormat or "Standard",
        function()
            local opts = {}
            for _, opt in ipairs({"Standard", "Compact", "Professions First"}) do
                table.insert(opts, {label = opt, value = opt})
            end
            return opts
        end,
        148,
        function(val)
            GuildNoteUpdater.noteFormat = val
            GuildNoteUpdaterSettings.noteFormat = val
            GuildNoteUpdater:UpdateGuildNote()
        end)
    ncY = ncY - 30

    -- ── Note prefix  [label + editbox] ──
    MakeLbl(pageNC, 12, ncY - 3, "Prefix")
    local notePrefixText = CreateFrame("EditBox", nil, pageNC, "InputBoxTemplate")
    notePrefixText:SetSize(120, 20)
    notePrefixText:SetPoint("TOPLEFT", pageNC, "TOPLEFT", 58, ncY)
    notePrefixText:SetAutoFocus(false)
    notePrefixText:SetMaxLetters(12)
    local prefixValue = self.notePrefix[characterKey]
    notePrefixText:SetText(prefixValue and safeTrim(prefixValue) or "")
    local function SaveNotePrefix(editBox)
        local key = GuildNoteUpdater:GetCharacterKey()
        GuildNoteUpdater.notePrefix[key] = safeTrim(editBox:GetText()) or ""
        GuildNoteUpdaterSettings.notePrefix = GuildNoteUpdater.notePrefix
        GuildNoteUpdater:UpdateGuildNote()
        editBox:ClearFocus()
    end
    notePrefixText:SetScript("OnEnterPressed", SaveNotePrefix)
    notePrefixText:SetScript("OnEditFocusLost", SaveNotePrefix)
    notePrefixText:SetScript("OnEscapePressed", function(e) e:ClearFocus() end)

    local hintFrame = CreateFrame("Frame", nil, pageNC)
    hintFrame:SetSize(20, 20)
    hintFrame:SetPoint("LEFT", notePrefixText, "RIGHT", 4, 0)
    local hintFS = hintFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hintFS:SetAllPoints()
    hintFS:SetText("|cFF4A6A8A(?)|r")
    hintFrame:EnableMouse(true)
    hintFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Note Prefix", 1, 0.82, 0)
        GameTooltip:AddLine("Text prepended to every note, followed by ' - '.\nExample: 'R' produces 'R - 489 Feral LW Main'", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    hintFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- =========================================================
    -- PAGE: General
    -- =========================================================
    local gY = -8
    MakeSection(pageG, gY, "General")
    gY = gY - 26

    MakeCB(pageG, gY, "Enable for this character",
        self.enabledCharacters[characterKey] or false,
        function(val)
            local key = GuildNoteUpdater:GetCharacterKey()
            GuildNoteUpdater.enabledCharacters[key] = val
            GuildNoteUpdaterSettings.enabledCharacters = GuildNoteUpdater.enabledCharacters
            GuildNoteUpdater:UpdateGuildNote()
        end)
    gY = gY - 26

    lockCB = MakeCB(pageG, gY, "Lock note (prevent auto-updates)",
        self.noteLocked[characterKey] == true,
        function(val)
            UpdateLockState(val)
        end)
    gY = gY - 26

    local mbSettings = GuildNoteUpdaterSettings.minimapButton
    MakeCB(pageG, gY, "Show minimap button",
        not mbSettings or mbSettings.enabled ~= false,
        function(val)
            GuildNoteUpdaterSettings.minimapButton.enabled = val
            if GuildNoteUpdater.minimapButton then
                if val then GuildNoteUpdater.minimapButton:Show()
                else GuildNoteUpdater.minimapButton:Hide() end
            end
        end)
    gY = gY - 30

    MakeLbl(pageG, 12, gY - 4, "Update trigger")
    MakeDropdown(pageG, 100, gY,
        self.updateTrigger or "On Events",
        function()
            local opts = {}
            for _, opt in ipairs({"On Events", "On Login Only", "Manual Only"}) do
                table.insert(opts, {label = opt, value = opt})
            end
            return opts
        end,
        110,
        function(val)
            GuildNoteUpdater.updateTrigger = val
            GuildNoteUpdaterSettings.updateTrigger = val
        end)
    gY = gY - 30

    MakeCB(pageG, gY, "Show update notification",
        self.showUpdateNotification ~= false,
        function(val)
            GuildNoteUpdater.showUpdateNotification = val
            GuildNoteUpdaterSettings.showUpdateNotification = val
        end)

    -- =========================================================
    -- PAGE: Advanced
    -- =========================================================
    local aY = -8
    MakeSection(pageA, aY, "Advanced")
    aY = aY - 26

    MakeCB(pageA, aY, "Enable debug output",
        self.debugEnabled,
        function(val)
            GuildNoteUpdater.debugEnabled = val
            print("Debug mode is now " .. (val and "enabled" or "disabled"))
            GuildNoteUpdaterSettings.debugEnabled = val
        end)
    aY = aY - 26

    MakeCB(pageA, aY, "Parse tooltip notes",
        self.enableTooltipParsing ~= false,
        function(val)
            GuildNoteUpdater.enableTooltipParsing = val
            GuildNoteUpdaterSettings.enableTooltipParsing = val
        end)

    -- =========================================================
    -- ACTIVATE DEFAULT PAGE
    -- =========================================================
    ActivateNav("Note Content")

    -- =========================================================
    -- PREVIEW BAR  (pinned at bottom, two-row layout)
    -- Row 1 (top):    "NOTE PREVIEW" label
    -- Row 2 (bottom): [editable note text] [lock btn] [charcount] [Force Update]
    -- =========================================================
    local previewBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    previewBar:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  4, 4)
    previewBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
    previewBar:SetHeight(PREVIEW_H)
    previewBar:SetBackdrop(solidBD)
    previewBar:SetBackdropColor(0.039, 0.039, 0.090, 1.0)
    previewBar:SetBackdropBorderColor(0, 0, 0, 0)

    local previewTopLine = frame:CreateTexture(nil, "BORDER")
    previewTopLine:SetPoint("TOPLEFT",  previewBar, "TOPLEFT",  0, 0)
    previewTopLine:SetPoint("TOPRIGHT", previewBar, "TOPRIGHT", 0, 0)
    previewTopLine:SetHeight(1)
    previewTopLine:SetColorTexture(0.102, 0.102, 0.188, 1.0)

    -- Row 1: "NOTE PREVIEW" label (top-left)
    local previewLbl = previewBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    previewLbl:SetPoint("TOPLEFT", previewBar, "TOPLEFT", 10, -7)
    previewLbl:SetText("|cFF3A3A5ANOTE PREVIEW|r")

    -- Force Update button  (bottom-right, anchored first so others can left-anchor off it)
    local forceBtn = CreateFrame("Button", nil, previewBar, "BackdropTemplate")
    forceBtn:SetSize(108, 24)
    forceBtn:SetPoint("BOTTOMRIGHT", previewBar, "BOTTOMRIGHT", -6, 6)
    forceBtn:SetBackdrop(solidBD)
    forceBtn:SetBackdropColor(0.165, 0.140, 0.0, 1.0)
    forceBtn:SetBackdropBorderColor(1.0, 0.820, 0.0, 0.25)
    local fTxt = forceBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fTxt:SetPoint("CENTER")
    fTxt:SetText("Force Update")
    fTxt:SetTextColor(0.784, 0.651, 0.0)
    forceBtn:SetScript("OnClick", function()
        GuildNoteUpdater.hasUpdated = false
        GuildNoteUpdater:UpdateGuildNote()
    end)
    forceBtn:SetScript("OnEnter", function()
        forceBtn:SetBackdropColor(0.227, 0.188, 0.0, 1.0)
        forceBtn:SetBackdropBorderColor(1.0, 0.820, 0.0, 0.5)
        fTxt:SetTextColor(1.0, 0.820, 0.0)
    end)
    forceBtn:SetScript("OnLeave", function()
        forceBtn:SetBackdropColor(0.165, 0.140, 0.0, 1.0)
        forceBtn:SetBackdropBorderColor(1.0, 0.820, 0.0, 0.25)
        fTxt:SetTextColor(0.784, 0.651, 0.0)
    end)

    -- Char count  (to the left of Force Update, same row)
    charCountText = previewBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    charCountText:SetPoint("RIGHT", forceBtn, "LEFT", -8, 0)
    charCountText:SetJustifyH("RIGHT")
    charCountText:SetWidth(46)

    -- Lock button  (to the left of char count)
    lockPreviewBtn = CreateFrame("Button", nil, previewBar, "BackdropTemplate")
    lockPreviewBtn:SetSize(24, 24)
    lockPreviewBtn:SetPoint("RIGHT", charCountText, "LEFT", -6, 0)
    lockPreviewBtn:SetBackdrop(solidBD)
    lockPreviewBtn:SetBackdropColor(0.039, 0.039, 0.094, 1.0)
    lockPreviewBtn:SetBackdropBorderColor(0.165, 0.165, 0.267, 1.0)
    local lockTex = lockPreviewBtn:CreateTexture(nil, "ARTWORK")
    lockTex:SetSize(14, 14)
    lockTex:SetPoint("CENTER")
    lockTex:SetTexture("Interface\\PaperDollInfoFrame\\GearSetLock")
    lockPreviewBtn:SetScript("OnClick", function()
        local key = GuildNoteUpdater:GetCharacterKey()
        local newVal = not (GuildNoteUpdater.noteLocked and GuildNoteUpdater.noteLocked[key])
        UpdateLockState(newVal)
    end)
    lockPreviewBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(lockPreviewBtn, "ANCHOR_TOP")
        GameTooltip:SetText("Lock Note", 1, 0.82, 0)
        GameTooltip:AddLine("Prevents auto-updates from overwriting your note.\nWhen locked, you can type directly in the preview box.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    lockPreviewBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Apply initial lock button visual state
    if self.noteLocked[characterKey] then
        lockPreviewBtn:SetBackdropColor(1.0, 0.820, 0.0, 0.15)
        lockPreviewBtn:SetBackdropBorderColor(1.0, 0.820, 0.0, 0.60)
    end

    -- Preview box  (from left edge to just left of the lock button)
    local previewBox = CreateFrame("Frame", nil, previewBar, "BackdropTemplate")
    previewBox:SetPoint("BOTTOMLEFT",  previewBar, "BOTTOMLEFT", 8, 6)
    previewBox:SetPoint("BOTTOMRIGHT", lockPreviewBtn, "BOTTOMLEFT", -6, 0)
    previewBox:SetHeight(24)
    previewBox:SetBackdrop(solidBD)
    previewBox:SetBackdropColor(0.027, 0.027, 0.063, 1.0)
    previewBox:SetBackdropBorderColor(0.102, 0.102, 0.188, 1.0)

    -- EditBox inside preview box (disabled/read-only by default, enabled when note is locked)
    local previewEB = CreateFrame("EditBox", nil, previewBox)
    previewEB:SetPoint("LEFT",  previewBox, "LEFT",  6, 0)
    previewEB:SetPoint("RIGHT", previewBox, "RIGHT", -6, 0)
    previewEB:SetHeight(20)
    previewEB:SetAutoFocus(false)
    previewEB:SetEnabled(false)
    previewEB:SetFontObject("GameFontNormalSmall")
    previewEB:SetTextColor(1.0, 0.820, 0.0)
    previewEB:SetTextInsets(0, 0, 0, 0)
    previewEB:SetMaxLetters(MAX_NOTE_LENGTH)

    local function SaveLockedNote(eb)
        local key = GuildNoteUpdater:GetCharacterKey()
        if not GuildNoteUpdater.noteLocked or not GuildNoteUpdater.noteLocked[key] then
            eb:ClearFocus()
            return
        end
        local newNote = eb:GetText()
        if #newNote > MAX_NOTE_LENGTH then
            newNote = string.sub(newNote, 1, MAX_NOTE_LENGTH)
            eb:SetText(newNote)
        end
        local guildIndex = GuildNoteUpdater:GetGuildIndexForPlayer()
        if guildIndex and newNote ~= "" then
            GuildRosterSetPublicNote(guildIndex, newNote)
            GuildNoteUpdater.previousNote = newNote
        end
        GuildNoteUpdater:UpdateNotePreview()
        eb:ClearFocus()
    end
    previewEB:SetScript("OnEnterPressed", SaveLockedNote)
    previewEB:SetScript("OnEditFocusLost", SaveLockedNote)
    previewEB:SetScript("OnEscapePressed", function(eb)
        eb:SetText(GuildNoteUpdater.previousNote or "")
        eb:ClearFocus()
    end)

    -- Apply initial locked state to EditBox
    if self.noteLocked[characterKey] then
        previewEB:SetEnabled(true)
        previewEB:SetText(self.previousNote or "")
    end

    -- Point the module-level reference at the EditBox so UpdateNotePreview works
    previewText = previewEB

    self:UpdateNotePreview()

    -- =========================================================
    -- SLASH COMMANDS
    -- =========================================================
    SLASH_GUILDNOTEUPDATER1 = "/gnu"
    SLASH_GUILDUPDATE1 = "/guildupdate"
    local function ToggleUI()
        if frame:IsShown() then frame:Hide() else frame:Show() end
    end
    SlashCmdList["GUILDNOTEUPDATER"] = function(msg)
        local setmainArg = msg:match("^setmain%s+(.+)$")
        if msg == "update" then
            GuildNoteUpdater:UpdateGuildNote()
        elseif msg == "roster mains" then
            PrintRosterSummary(true)
        elseif msg == "roster" then
            PrintRosterSummary(false)
        elseif setmainArg then
            local mainName = strtrim(setmainArg)
            local key = GuildNoteUpdater:GetCharacterKey()
            if not GuildNoteUpdaterSettings.altRegistry then GuildNoteUpdaterSettings.altRegistry = {} end
            GuildNoteUpdaterSettings.altRegistry[key] = mainName
            GuildNoteUpdater.altRegistry = GuildNoteUpdaterSettings.altRegistry
            print(string.format("|cFF00FF00GuildNoteUpdater:|r %s linked to main: %s", key, mainName))
        elseif msg == "setmain" then
            print("|cFF00FF00GuildNoteUpdater:|r Usage: /gnu setmain <MainName>")
        elseif msg == "alts clear" then
            GuildNoteUpdaterSettings.altRegistry = {}
            GuildNoteUpdater.altRegistry = {}
            print("|cFF00FF00GuildNoteUpdater:|r Alt registry cleared.")
        elseif msg == "alts" then
            local registry = GuildNoteUpdater.altRegistry
            if not registry or not next(registry) then
                print("|cFF00FF00GuildNoteUpdater:|r Alt registry is empty.")
            else
                print("|cFF00FF00GuildNoteUpdater:|r Alt registry:")
                for alt, main in pairs(registry) do
                    print(string.format("  %s -> %s", alt, main))
                end
            end
        else
            ToggleUI()
        end
    end
    SlashCmdList["GUILDUPDATE"] = ToggleUI
end

-- Positions the minimap button at the given angle around the minimap edge
local function UpdateMinimapButtonPosition(angle)
    local rad = math.rad(angle)
    local radius = (Minimap:GetWidth() / 2) + BUTTON_OFFSET
    local x = math.cos(rad) * radius
    local y = math.sin(rad) * radius
    GuildNoteUpdater.minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Creates the minimap button for quick access to the settings panel
function GuildNoteUpdater:CreateMinimapButton()
    local mb = GuildNoteUpdaterSettings.minimapButton
    local button = CreateFrame("Button", "GuildNoteUpdaterMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForDrag("LeftButton")

    -- Icon sized to fill the inner circle of the border ring
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(21, 21)
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 5, -5)
    icon:SetTexture("Interface\\AddOns\\GuildNoteUpdater\\Icon")

    -- Circular mask to clip the icon into a circle
    local mask = button:CreateMaskTexture()
    mask:SetSize(21, 21)
    mask:SetPoint("TOPLEFT", button, "TOPLEFT", 5, -5)
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    icon:AddMaskTexture(mask)

    -- Circular border ring
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    -- Hover glow (ADD blend mode brightens instead of darkening)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")

    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "LeftButton" and not self._dragging then
            if GuildNoteUpdater.settingsFrame:IsShown() then
                GuildNoteUpdater.settingsFrame:Hide()
            else
                GuildNoteUpdater.settingsFrame:Show()
            end
        end
    end)

    button:SetScript("OnDragStart", function(self)
        self._dragging = true
    end)
    button:SetScript("OnDragStop", function(self)
        self._dragging = false
    end)
    button:SetScript("OnUpdate", function(self)
        if not self._dragging then return end
        local cx, cy = Minimap:GetCenter()
        local mx, my = GetCursorPosition()
        local scale = UIParent:GetScale()
        mx, my = mx / scale, my / scale
        local angle = math.deg(math.atan2(my - cy, mx - cx))
        GuildNoteUpdaterSettings.minimapButton.angle = angle
        UpdateMinimapButtonPosition(angle)
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("GuildNoteUpdater")
        GameTooltip:AddLine("Left-click to toggle settings", 1, 1, 1)
        GameTooltip:AddLine("Drag to reposition", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    GuildNoteUpdater.minimapButton = button
    UpdateMinimapButtonPosition(mb.angle)
    if not mb.enabled then
        button:Hide()
    end
end

-- Handles all registered addon events
function GuildNoteUpdater:OnEvent(event, arg1)
    if event == "ADDON_LOADED" and arg1 == "GuildNoteUpdater" then
        self:InitializeSettings()
        self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
        self:DebugPrint("Addon loaded for " .. self:GetCharacterKey())
    elseif event == "PLAYER_ENTERING_WORLD" then
        if IsInGuild() and not self.hasUpdated then
            self:RegisterEvent("GUILD_ROSTER_UPDATE")
            C_GuildInfo.GuildRoster()
        end
    elseif event == "GUILD_ROSTER_UPDATE" then
        if not self.hasUpdated then
            self.hasUpdated = true
            self:UnregisterEvent("GUILD_ROSTER_UPDATE")
            C_Timer.After(1, function()
                if IsInGuild() and GetNumGuildMembers() > 0 then
                    if (GuildNoteUpdater.updateTrigger or "On Events") ~= "Manual Only" then
                        GuildNoteUpdater:UpdateGuildNote()
                    end
                end
            end)
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if self.pendingCombatUpdate then
            self.pendingCombatUpdate = false
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            C_Timer.After(DEBOUNCE_DELAY, function()
                if IsInGuild() then GuildNoteUpdater:UpdateGuildNote() end
            end)
        end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
        self:DebugPrint("Detected " .. event)
        local trigger = self.updateTrigger or "On Events"
        if trigger == "Manual Only" or trigger == "On Login Only" then return end
        -- BUG-001: Debounce rapid equipment changes
        if self.pendingUpdateTimer then
            self.pendingUpdateTimer:Cancel()
        end
        self.pendingUpdateTimer = C_Timer.NewTimer(DEBOUNCE_DELAY, function()
            self.pendingUpdateTimer = nil
            if IsInGuild() then GuildNoteUpdater:UpdateGuildNote() end
        end)
    end
end

-- Loads saved settings from SavedVariables and sets defaults for new characters
function GuildNoteUpdater:InitializeSettings()
    if not GuildNoteUpdaterSettings then
        GuildNoteUpdaterSettings = {
            enabledCharacters = {}, specUpdateMode = {}, selectedSpec = {},
            itemLevelType = {}, mainOrAlt = {}, enableProfessions = {},
            debugEnabled = false, notePrefix = {},
            enableSpec = {}, enableTooltipParsing = true,
            showUpdateNotification = true,
            enableItemLevel = {}, enableMainAlt = {}, noteLocked = {},
            updateTrigger = "On Events",
            noteFormat = "Standard",
            altRegistry = {},
            minimapButton = { enabled = true, angle = 225 }
        }
    end

    self.enabledCharacters = GuildNoteUpdaterSettings.enabledCharacters or {}
    self.specUpdateMode = GuildNoteUpdaterSettings.specUpdateMode or {}
    self.selectedSpec = GuildNoteUpdaterSettings.selectedSpec or {}
    self.itemLevelType = GuildNoteUpdaterSettings.itemLevelType or {}
    self.mainOrAlt = GuildNoteUpdaterSettings.mainOrAlt or {}
    self.enableProfessions = GuildNoteUpdaterSettings.enableProfessions or {}
    self.debugEnabled = GuildNoteUpdaterSettings.debugEnabled or false
    self.notePrefix = GuildNoteUpdaterSettings.notePrefix or {}
    self.enableSpec = GuildNoteUpdaterSettings.enableSpec or {}
    self.enableTooltipParsing = GuildNoteUpdaterSettings.enableTooltipParsing ~= false
    self.showUpdateNotification = GuildNoteUpdaterSettings.showUpdateNotification ~= false
    self.enableItemLevel = GuildNoteUpdaterSettings.enableItemLevel or {}
    self.enableMainAlt = GuildNoteUpdaterSettings.enableMainAlt or {}
    self.noteLocked = GuildNoteUpdaterSettings.noteLocked or {}
    self.updateTrigger = GuildNoteUpdaterSettings.updateTrigger or "On Events"
    self.noteFormat = GuildNoteUpdaterSettings.noteFormat or "Standard"
    if not GuildNoteUpdaterSettings.altRegistry then
        GuildNoteUpdaterSettings.altRegistry = {}
    end
    self.altRegistry = GuildNoteUpdaterSettings.altRegistry
    if not GuildNoteUpdaterSettings.minimapButton then
        GuildNoteUpdaterSettings.minimapButton = { enabled = true, angle = 225 }
    end

    local characterKey = self:GetCharacterKey()
    if self.enableProfessions[characterKey] == nil then self.enableProfessions[characterKey] = true end
    if self.specUpdateMode[characterKey] == nil then self.specUpdateMode[characterKey] = "Automatically" end

    self:CreateUI()
    self:CreateMinimapButton()
    self:SetupTooltipHook()
end

-- BUG-006: Only register bootstrap events at file scope
GuildNoteUpdater:RegisterEvent("ADDON_LOADED")
GuildNoteUpdater:RegisterEvent("PLAYER_ENTERING_WORLD")
GuildNoteUpdater:SetScript("OnEvent", GuildNoteUpdater.OnEvent)
