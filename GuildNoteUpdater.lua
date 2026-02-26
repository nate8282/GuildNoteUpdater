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
            print(string.format("  %s%s|r â€” %d%s", nameColor, m.name, m.ilvl, detail))
        end
    end)
end

-- Creates the settings UI frame with scroll frame, three grouped sections, and pinned preview bar
function GuildNoteUpdater:CreateUI()
    local CONTENT_WIDTH = 452
    local LABEL_X = 14
    local INDENT_X = 34
    local SECTION_COLOR = "|cFFFFD100"

    local frame = CreateFrame("Frame", "GuildNoteUpdaterUI", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(520, 420)
    frame:SetPoint("CENTER")
    frame:Hide()
    self.settingsFrame = frame
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    -- ESC-to-close support (BUG-005)
    table.insert(UISpecialFrames, "GuildNoteUpdaterUI")

    frame.title = frame:CreateFontString(nil, "OVERLAY")
    frame.title:SetFontObject("GameFontHighlight")
    frame.title:SetPoint("CENTER", frame.TitleBg, "CENTER", 0, 0)
    frame.title:SetText("Guild Note Updater")

    local version = C_AddOns.GetAddOnMetadata("GuildNoteUpdater", "Version") or ""
    frame.version = frame:CreateFontString(nil, "OVERLAY")
    frame.version:SetFontObject("GameFontNormalSmall")
    frame.version:SetPoint("RIGHT", frame.TitleBg, "RIGHT", -8, 0)
    frame.version:SetText("|cFFAAAAAA v" .. version .. "|r")

    local characterKey = self:GetCharacterKey()

    -- === Scroll Frame ===

    local scrollFrame = CreateFrame("ScrollFrame", "GuildNoteUpdaterScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 100)

    local scrollChild = CreateFrame("Frame", "GuildNoteUpdaterScrollChild", scrollFrame)
    scrollChild:SetWidth(CONTENT_WIDTH)
    scrollFrame:SetScrollChild(scrollChild)

    -- layoutY tracks vertical position in scroll child (always negative, moves down)
    local layoutY = -8

    -- Forward declarations for dropdown cross-references
    local specUpdateDropdown, specDropdown
    local itemLevelDropdown, mainAltDropdown, noteFormatDropdown, updateTriggerDropdown

    -- Helper: add a section header and advance layoutY
    local function SectionHeader(text)
        layoutY = layoutY - 6
        local fs = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", LABEL_X, layoutY)
        fs:SetText(SECTION_COLOR .. "â”€â”€ " .. text .. " â”€â”€|r")
        layoutY = layoutY - 20
        return fs
    end

    -- Helper: add a labelled checkbox and advance layoutY
    local function AddCheckbox(labelText, isChecked, onClick)
        local cb = CreateFrame("CheckButton", nil, scrollChild, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", LABEL_X - 2, layoutY + 2)
        cb.text:SetFontObject("GameFontNormal")
        cb.text:SetText(labelText)
        cb:SetChecked(isChecked)
        cb:SetScript("OnClick", onClick)
        layoutY = layoutY - 26
        return cb
    end

    -- Helper: add a label+dropdown row and advance layoutY
    -- indented=true shifts the row right to show visual subordination
    local function AddDropdown(ddName, labelText, initFn, width, currentText, indented)
        local x = indented and INDENT_X or LABEL_X
        local lbl = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", x, layoutY - 5)
        lbl:SetText(labelText)
        local dd = CreateFrame("Frame", ddName, scrollChild, "UIDropDownMenuTemplate")
        dd:SetPoint("TOPLEFT", x + 100, layoutY + 8)
        UIDropDownMenu_Initialize(dd, initFn)
        UIDropDownMenu_SetWidth(dd, width or 130)
        UIDropDownMenu_SetText(dd, currentText)
        layoutY = layoutY - 36
        return dd
    end

    -- =============================================
    -- SECTION: Note Content
    -- =============================================
    SectionHeader("Note Content")

    itemLevelDropdown = AddDropdown(
        "GuildNoteUpdaterItemLevelDropdown",
        "Item Level Type",
        function(dd, level)
            local key = GuildNoteUpdater:GetCharacterKey()
            local info = UIDropDownMenu_CreateInfo()
            for _, opt in ipairs({"Overall", "Equipped"}) do
                info.text, info.value = opt, opt
                info.func = function(btn)
                    local k = GuildNoteUpdater:GetCharacterKey()
                    GuildNoteUpdater.itemLevelType[k] = btn.value
                    UIDropDownMenu_SetText(itemLevelDropdown, btn.value)
                    GuildNoteUpdaterSettings.itemLevelType = GuildNoteUpdater.itemLevelType
                    GuildNoteUpdater:UpdateGuildNote()
                end
                info.checked = (GuildNoteUpdater.itemLevelType[key] == opt)
                UIDropDownMenu_AddButton(info, level)
            end
        end,
        130, self.itemLevelType[characterKey] or "Overall"
    )

    AddCheckbox("Show item level", self.enableItemLevel[characterKey] ~= false, function(btn)
        local key = GuildNoteUpdater:GetCharacterKey()
        GuildNoteUpdater.enableItemLevel[key] = btn:GetChecked()
        GuildNoteUpdaterSettings.enableItemLevel = GuildNoteUpdater.enableItemLevel
        GuildNoteUpdater:UpdateGuildNote()
    end)

    AddCheckbox("Show spec", self.enableSpec[characterKey] ~= false, function(btn)
        local key = GuildNoteUpdater:GetCharacterKey()
        GuildNoteUpdater.enableSpec[key] = btn:GetChecked()
        GuildNoteUpdaterSettings.enableSpec = GuildNoteUpdater.enableSpec
        GuildNoteUpdater:UpdateGuildNote()
    end)

    -- Update spec and Spec selector are subordinate (indented) under Show spec
    specUpdateDropdown = AddDropdown(
        "GuildNoteUpdaterSpecUpdateDropdown",
        "Update spec",
        function(dd, level)
            local key = GuildNoteUpdater:GetCharacterKey()
            local info = UIDropDownMenu_CreateInfo()
            for _, opt in ipairs({"Automatically", "Manually"}) do
                info.text, info.value = opt, opt
                info.func = function(btn)
                    local k = GuildNoteUpdater:GetCharacterKey()
                    GuildNoteUpdater.specUpdateMode[k] = btn.value
                    UIDropDownMenu_SetText(specUpdateDropdown, btn.value)
                    GuildNoteUpdaterSettings.specUpdateMode = GuildNoteUpdater.specUpdateMode
                    if btn.value == "Manually" then
                        UIDropDownMenu_EnableDropDown(specDropdown)
                    else
                        UIDropDownMenu_DisableDropDown(specDropdown)
                    end
                    GuildNoteUpdater:UpdateGuildNote()
                end
                info.checked = (GuildNoteUpdater.specUpdateMode[key] == opt)
                UIDropDownMenu_AddButton(info, level)
            end
        end,
        130, self.specUpdateMode[characterKey] or "Automatically",
        true  -- indented
    )

    specDropdown = AddDropdown(
        "GuildNoteUpdaterSpecDropdown",
        "Spec",
        function(dd, level)
            local key = GuildNoteUpdater:GetCharacterKey()
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.value = "Select Spec", "Select Spec"
            info.func = function(btn)
                local k = GuildNoteUpdater:GetCharacterKey()
                GuildNoteUpdater.selectedSpec[k] = btn.value
                UIDropDownMenu_SetText(specDropdown, btn.value)
                GuildNoteUpdaterSettings.selectedSpec = GuildNoteUpdater.selectedSpec
                GuildNoteUpdater:UpdateGuildNote()
            end
            info.checked = (GuildNoteUpdater.selectedSpec[key] == "Select Spec")
            UIDropDownMenu_AddButton(info, level)
            for i = 1, GetNumSpecializations() do
                local _, specName = GetSpecializationInfo(i)
                info.text, info.value = specName, specName
                info.checked = (specName == GuildNoteUpdater.selectedSpec[key])
                UIDropDownMenu_AddButton(info, level)
            end
        end,
        130, self.selectedSpec[characterKey] or "Select Spec",
        true  -- indented
    )

    if self.specUpdateMode[characterKey] == "Automatically" or not self.specUpdateMode[characterKey] then
        UIDropDownMenu_DisableDropDown(specDropdown)
    end

    AddCheckbox("Show professions", self.enableProfessions[characterKey] == true, function(btn)
        local key = GuildNoteUpdater:GetCharacterKey()
        local isChecked = btn:GetChecked()
        GuildNoteUpdater.enableProfessions[key] = isChecked
        GuildNoteUpdaterSettings.enableProfessions[key] = isChecked
        GuildNoteUpdater:UpdateGuildNote()
    end)

    AddCheckbox("Show main/alt status", self.enableMainAlt[characterKey] ~= false, function(btn)
        local key = GuildNoteUpdater:GetCharacterKey()
        GuildNoteUpdater.enableMainAlt[key] = btn:GetChecked()
        GuildNoteUpdaterSettings.enableMainAlt = GuildNoteUpdater.enableMainAlt
        GuildNoteUpdater:UpdateGuildNote()
    end)

    -- Main or Alt selector is subordinate (indented) under Show main/alt
    mainAltDropdown = AddDropdown(
        "GuildNoteUpdaterMainAltDropdown",
        "Main or Alt",
        function(dd, level)
            local key = GuildNoteUpdater:GetCharacterKey()
            local info = UIDropDownMenu_CreateInfo()
            for _, opt in ipairs({"<None>", "Main", "Alt"}) do
                info.text, info.value = opt, opt
                info.func = function(btn)
                    local k = GuildNoteUpdater:GetCharacterKey()
                    GuildNoteUpdater.mainOrAlt[k] = btn.value
                    UIDropDownMenu_SetText(mainAltDropdown, btn.value)
                    GuildNoteUpdaterSettings.mainOrAlt = GuildNoteUpdater.mainOrAlt
                    GuildNoteUpdater:UpdateGuildNote()
                end
                info.checked = (GuildNoteUpdater.mainOrAlt[key] == opt)
                UIDropDownMenu_AddButton(info, level)
            end
        end,
        130, self.mainOrAlt[characterKey] or "<None>",
        true  -- indented
    )

    noteFormatDropdown = AddDropdown(
        "GuildNoteUpdaterNoteFormatDropdown",
        "Note Format",
        function(dd, level)
            local info = UIDropDownMenu_CreateInfo()
            for _, opt in ipairs({"Standard", "Compact", "Professions First"}) do
                info.text, info.value = opt, opt
                info.func = function(btn)
                    GuildNoteUpdater.noteFormat = btn.value
                    UIDropDownMenu_SetText(noteFormatDropdown, btn.value)
                    GuildNoteUpdaterSettings.noteFormat = btn.value
                    GuildNoteUpdater:UpdateGuildNote()
                end
                info.checked = (GuildNoteUpdater.noteFormat == opt)
                UIDropDownMenu_AddButton(info, level)
            end
        end,
        140, self.noteFormat or "Standard"
    )

    -- Note Prefix editbox + (?) hint tooltip
    layoutY = layoutY - 4
    local notePrefixLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    notePrefixLabel:SetPoint("TOPLEFT", LABEL_X, layoutY - 5)
    notePrefixLabel:SetText("Note Prefix")

    local notePrefixText = CreateFrame("EditBox", nil, scrollChild, "InputBoxTemplate")
    notePrefixText:SetSize(130, 20)
    notePrefixText:SetPoint("TOPLEFT", LABEL_X + 104, layoutY)
    notePrefixText:SetAutoFocus(false)
    notePrefixText:SetMaxLetters(12)
    local prefixValue = self.notePrefix[characterKey]
    notePrefixText:SetText(prefixValue and safeTrim(prefixValue) or "")

    -- BUG-004: Save prefix on Enter and on focus lost
    local function SaveNotePrefix(editBox)
        local key = GuildNoteUpdater:GetCharacterKey()
        GuildNoteUpdater.notePrefix[key] = safeTrim(editBox:GetText()) or ""
        GuildNoteUpdaterSettings.notePrefix = GuildNoteUpdater.notePrefix
        GuildNoteUpdater:UpdateGuildNote()
        editBox:ClearFocus()
    end
    notePrefixText:SetScript("OnEnterPressed", SaveNotePrefix)
    notePrefixText:SetScript("OnEditFocusLost", SaveNotePrefix)
    notePrefixText:SetScript("OnEscapePressed", function(editBox) editBox:ClearFocus() end)

    -- (?) hover hint explaining Note Prefix
    local hintFrame = CreateFrame("Frame", nil, scrollChild)
    hintFrame:SetSize(20, 20)
    hintFrame:SetPoint("LEFT", notePrefixText, "RIGHT", 4, 0)
    local hintFS = hintFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hintFS:SetAllPoints()
    hintFS:SetText("|cFFAAAAFF(?)|r")
    hintFrame:EnableMouse(true)
    hintFrame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Note Prefix", 1, 0.82, 0)
        GameTooltip:AddLine("Text prepended to every note, followed by ' - '.\nExample: 'R' produces 'R - 489 Feral LW Main'", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    hintFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

    layoutY = layoutY - 30

    -- =============================================
    -- SECTION: General
    -- =============================================
    layoutY = layoutY - 10
    SectionHeader("General")

    AddCheckbox("Enable for this character", self.enabledCharacters[characterKey] or false, function(btn)
        local key = GuildNoteUpdater:GetCharacterKey()
        GuildNoteUpdater.enabledCharacters[key] = btn:GetChecked()
        GuildNoteUpdaterSettings.enabledCharacters = GuildNoteUpdater.enabledCharacters
        GuildNoteUpdater:UpdateGuildNote()
    end)

    AddCheckbox("Lock note (prevent auto-updates)", self.noteLocked[characterKey] == true, function(btn)
        local key = GuildNoteUpdater:GetCharacterKey()
        GuildNoteUpdater.noteLocked[key] = btn:GetChecked()
        GuildNoteUpdaterSettings.noteLocked = GuildNoteUpdater.noteLocked
    end)

    local mbSettings = GuildNoteUpdaterSettings.minimapButton
    AddCheckbox("Show minimap button", not mbSettings or mbSettings.enabled ~= false, function(btn)
        GuildNoteUpdaterSettings.minimapButton.enabled = btn:GetChecked()
        if GuildNoteUpdater.minimapButton then
            if btn:GetChecked() then
                GuildNoteUpdater.minimapButton:Show()
            else
                GuildNoteUpdater.minimapButton:Hide()
            end
        end
    end)

    updateTriggerDropdown = AddDropdown(
        "GuildNoteUpdaterUpdateTriggerDropdown",
        "Update Trigger",
        function(dd, level)
            local info = UIDropDownMenu_CreateInfo()
            for _, opt in ipairs({"On Events", "On Login Only", "Manual Only"}) do
                info.text, info.value = opt, opt
                info.func = function(btn)
                    GuildNoteUpdater.updateTrigger = btn.value
                    UIDropDownMenu_SetText(updateTriggerDropdown, btn.value)
                    GuildNoteUpdaterSettings.updateTrigger = btn.value
                end
                info.checked = (GuildNoteUpdater.updateTrigger == opt)
                UIDropDownMenu_AddButton(info, level)
            end
        end,
        140, self.updateTrigger or "On Events"
    )

    -- =============================================
    -- SECTION: Advanced
    -- =============================================
    layoutY = layoutY - 10
    SectionHeader("Advanced")

    AddCheckbox("Enable debug output", self.debugEnabled, function(btn)
        GuildNoteUpdater.debugEnabled = btn:GetChecked()
        print("Debug mode is now " .. (GuildNoteUpdater.debugEnabled and "enabled" or "disabled"))
        GuildNoteUpdaterSettings.debugEnabled = GuildNoteUpdater.debugEnabled
    end)

    AddCheckbox("Parse tooltip notes", self.enableTooltipParsing ~= false, function(btn)
        GuildNoteUpdater.enableTooltipParsing = btn:GetChecked()
        GuildNoteUpdaterSettings.enableTooltipParsing = GuildNoteUpdater.enableTooltipParsing
    end)

    AddCheckbox("Show update notification", self.showUpdateNotification ~= false, function(btn)
        GuildNoteUpdater.showUpdateNotification = btn:GetChecked()
        GuildNoteUpdaterSettings.showUpdateNotification = GuildNoteUpdater.showUpdateNotification
    end)

    layoutY = layoutY - 20
    scrollChild:SetHeight(math.abs(layoutY) + 10)

    -- =============================================
    -- PREVIEW BAR (pinned outside scroll frame, always visible)
    -- =============================================
    local previewLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    previewLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 86)
    previewLabel:SetText("|cFFAAAAAAAAPreview|r")

    charCountText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    charCountText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 86)
    charCountText:SetJustifyH("RIGHT")

    -- Dark inset box for the note preview text
    local previewBox = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    previewBox:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 54)
    previewBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 54)
    previewBox:SetHeight(28)
    previewBox:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    previewBox:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    previewBox:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

    previewText = previewBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    previewText:SetPoint("LEFT", previewBox, "LEFT", 8, 0)
    previewText:SetPoint("RIGHT", previewBox, "RIGHT", -8, 0)
    previewText:SetJustifyH("LEFT")

    -- Force Update Now button (right-aligned, outside scroll frame)
    local forceUpdateBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    forceUpdateBtn:SetSize(140, 22)
    forceUpdateBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 24)
    forceUpdateBtn:SetText("Force Update Now")
    forceUpdateBtn:SetScript("OnClick", function()
        GuildNoteUpdater.hasUpdated = false
        GuildNoteUpdater:UpdateGuildNote()
    end)

    self:UpdateNotePreview()

    -- === Slash Commands ===

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

    -- Circular border ring â€” 53x53 at TOPLEFT with no offset matches the
    -- MiniMap-TrackingBorder texture layout used by LibDBIcon-1.0 (standard pattern)
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
