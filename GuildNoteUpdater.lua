GuildNoteUpdater = CreateFrame("Frame")
GuildNoteUpdater.hasUpdated = false
GuildNoteUpdater.previousNote = ""
GuildNoteUpdater.debugEnabled = false
GuildNoteUpdater.pendingUpdateTimer = nil

local DEBOUNCE_DELAY = 2
local MAX_NOTE_LENGTH = 31

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

    local spec = nil
    if self.enableSpec[characterKey] ~= false then
        spec = self:GetSpec(characterKey)
    end

    local mainOrAlt = self.mainOrAlt[characterKey]
    if mainOrAlt == "Select Option" or mainOrAlt == "<None>" then
        mainOrAlt = nil
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

    local noteParts = {}
    if notePrefix then
        table.insert(noteParts, notePrefix)
        table.insert(noteParts, "-")
    end
    table.insert(noteParts, flooredItemLevel)
    if spec then table.insert(noteParts, spec) end
    if self.enableProfessions[characterKey] then
        if profession1 then table.insert(noteParts, profession1) end
        if profession2 then table.insert(noteParts, profession2) end
    end
    if mainOrAlt then table.insert(noteParts, mainOrAlt) end

    local newNote = safeTrim(table.concat(noteParts, " ")) or ""

    -- Truncate to fit 31-char guild note limit
    if #newNote > MAX_NOTE_LENGTH then
        self:DebugPrint("Note too long (" .. #newNote .. " chars), truncating...")
        noteParts = {}
        if notePrefix then
            table.insert(noteParts, string.sub(notePrefix, 1, 4))
            table.insert(noteParts, "-")
        end
        table.insert(noteParts, flooredItemLevel)
        if spec then table.insert(noteParts, string.sub(spec, 1, 4)) end
        if self.enableProfessions[characterKey] then
            if profession1 then table.insert(noteParts, string.sub(profession1, 1, 2)) end
            if profession2 then table.insert(noteParts, string.sub(profession2, 1, 2)) end
        end
        if mainOrAlt then table.insert(noteParts, string.sub(mainOrAlt, 1, 1)) end
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
        previewText:SetText("|cFFAAAAAAPreview:|r " .. note)
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
                        tooltip:Show()
                    end
                    break
                end
            end
        end
    end)
end

-- Creates the settings UI frame with all controls and dropdowns
function GuildNoteUpdater:CreateUI()
    local frame = CreateFrame("Frame", "GuildNoteUpdaterUI", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(500, 376)
    frame:SetPoint("CENTER")
    frame:Hide()
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

    local characterKey = self:GetCharacterKey()

    -- === Left column checkboxes ===

    local enableButton = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    enableButton:SetPoint("TOPLEFT", 20, -32)
    enableButton.text:SetFontObject("GameFontNormal")
    enableButton.text:SetText("Enable for this character")
    enableButton:SetChecked(self.enabledCharacters[characterKey] or false)
    enableButton:SetScript("OnClick", function(btn)
        local key = GuildNoteUpdater:GetCharacterKey()
        GuildNoteUpdater.enabledCharacters[key] = btn:GetChecked()
        GuildNoteUpdaterSettings.enabledCharacters = GuildNoteUpdater.enabledCharacters
        GuildNoteUpdater:UpdateGuildNote()
    end)

    local enableSpecButton = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    enableSpecButton:SetPoint("TOPLEFT", 20, -58)
    enableSpecButton.text:SetFontObject("GameFontNormal")
    enableSpecButton.text:SetText("Show spec")
    enableSpecButton:SetChecked(self.enableSpec[characterKey] ~= false)
    enableSpecButton:SetScript("OnClick", function(btn)
        local key = GuildNoteUpdater:GetCharacterKey()
        GuildNoteUpdater.enableSpec[key] = btn:GetChecked()
        GuildNoteUpdaterSettings.enableSpec = GuildNoteUpdater.enableSpec
        GuildNoteUpdater:UpdateGuildNote()
    end)

    local enableProfessionsButton = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    enableProfessionsButton:SetPoint("TOPLEFT", 20, -84)
    enableProfessionsButton.text:SetFontObject("GameFontNormal")
    enableProfessionsButton.text:SetText("Show professions")
    enableProfessionsButton:SetChecked(self.enableProfessions[characterKey] == true)
    enableProfessionsButton:SetScript("OnClick", function(btn)
        local key = GuildNoteUpdater:GetCharacterKey()
        local isChecked = btn:GetChecked()
        GuildNoteUpdater.enableProfessions[key] = isChecked
        GuildNoteUpdaterSettings.enableProfessions[key] = isChecked
        GuildNoteUpdater:UpdateGuildNote()
    end)

    -- === Right column checkboxes ===

    local enableDebugButton = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    enableDebugButton:SetPoint("TOPRIGHT", -140, -32)
    enableDebugButton.text:SetFontObject("GameFontNormal")
    enableDebugButton.text:SetText("Enable Debug")
    enableDebugButton:SetChecked(self.debugEnabled)
    enableDebugButton:SetScript("OnClick", function(btn)
        GuildNoteUpdater.debugEnabled = btn:GetChecked()
        print("Debug mode is now " .. (GuildNoteUpdater.debugEnabled and "enabled" or "disabled"))
        GuildNoteUpdaterSettings.debugEnabled = GuildNoteUpdater.debugEnabled
    end)

    local enableTooltipButton = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    enableTooltipButton:SetPoint("TOPRIGHT", -140, -58)
    enableTooltipButton.text:SetFontObject("GameFontNormal")
    enableTooltipButton.text:SetText("Parse tooltip notes")
    enableTooltipButton:SetChecked(self.enableTooltipParsing ~= false)
    enableTooltipButton:SetScript("OnClick", function(btn)
        GuildNoteUpdater.enableTooltipParsing = btn:GetChecked()
        GuildNoteUpdaterSettings.enableTooltipParsing = GuildNoteUpdater.enableTooltipParsing
    end)

    local showNotificationButton = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    showNotificationButton:SetPoint("TOPRIGHT", -140, -84)
    showNotificationButton.text:SetFontObject("GameFontNormal")
    showNotificationButton.text:SetText("Update notification")
    showNotificationButton:SetChecked(self.showUpdateNotification ~= false)
    showNotificationButton:SetScript("OnClick", function(btn)
        GuildNoteUpdater.showUpdateNotification = btn:GetChecked()
        GuildNoteUpdaterSettings.showUpdateNotification = GuildNoteUpdater.showUpdateNotification
    end)

    -- === Dropdowns section ===

    local specUpdateLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    specUpdateLabel:SetPoint("TOPLEFT", 27, -130)
    specUpdateLabel:SetText("Update spec")

    local specUpdateDropdown = CreateFrame("Frame", "GuildNoteUpdaterSpecUpdateDropdown", frame, "UIDropDownMenuTemplate")
    specUpdateDropdown:SetPoint("LEFT", specUpdateLabel, "RIGHT", 30, 0)

    local specDropdown = CreateFrame("Frame", "GuildNoteUpdaterSpecDropdown", frame, "UIDropDownMenuTemplate")
    specDropdown:SetPoint("TOPLEFT", specUpdateDropdown, "BOTTOMLEFT", 0, -5)

    local function OnSpecUpdateSelect(btn)
        local key = GuildNoteUpdater:GetCharacterKey()
        GuildNoteUpdater.specUpdateMode[key] = btn.value
        UIDropDownMenu_SetText(specUpdateDropdown, btn.value)
        GuildNoteUpdaterSettings.specUpdateMode = GuildNoteUpdater.specUpdateMode
        if btn.value == "Manually" then
            UIDropDownMenu_EnableDropDown(specDropdown)
        else
            UIDropDownMenu_DisableDropDown(specDropdown)
        end
        GuildNoteUpdater:UpdateGuildNote()
    end

    local function InitializeSpecUpdateDropdown(dropdown, level)
        local key = GuildNoteUpdater:GetCharacterKey()
        local info = UIDropDownMenu_CreateInfo()
        info.text, info.value, info.func = "Automatically", "Automatically", OnSpecUpdateSelect
        info.checked = (GuildNoteUpdater.specUpdateMode[key] == "Automatically")
        UIDropDownMenu_AddButton(info, level)
        info.text, info.value = "Manually", "Manually"
        info.checked = (GuildNoteUpdater.specUpdateMode[key] == "Manually")
        UIDropDownMenu_AddButton(info, level)
    end

    UIDropDownMenu_Initialize(specUpdateDropdown, InitializeSpecUpdateDropdown)
    UIDropDownMenu_SetWidth(specUpdateDropdown, 120)
    UIDropDownMenu_SetText(specUpdateDropdown, self.specUpdateMode[characterKey] or "Automatically")

    local function OnSpecSelect(btn)
        local key = GuildNoteUpdater:GetCharacterKey()
        GuildNoteUpdater.selectedSpec[key] = btn.value
        UIDropDownMenu_SetText(specDropdown, btn.value)
        GuildNoteUpdaterSettings.selectedSpec = GuildNoteUpdater.selectedSpec
        GuildNoteUpdater:UpdateGuildNote()
    end

    local function InitializeSpecDropdown(dropdown, level)
        local key = GuildNoteUpdater:GetCharacterKey()
        local info = UIDropDownMenu_CreateInfo()
        info.text, info.value, info.func = "Select Spec", "Select Spec", OnSpecSelect
        info.checked = (GuildNoteUpdater.selectedSpec[key] == "Select Spec")
        UIDropDownMenu_AddButton(info, level)
        for i = 1, GetNumSpecializations() do
            local _, specName = GetSpecializationInfo(i)
            info.text, info.value = specName, specName
            info.checked = (specName == GuildNoteUpdater.selectedSpec[key])
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(specDropdown, InitializeSpecDropdown)
    UIDropDownMenu_SetWidth(specDropdown, 120)
    UIDropDownMenu_SetText(specDropdown, self.selectedSpec[characterKey] or "Select Spec")
    if self.specUpdateMode[characterKey] == "Automatically" or not self.specUpdateMode[characterKey] then
        UIDropDownMenu_DisableDropDown(specDropdown)
    end

    local itemLevelTypeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemLevelTypeLabel:SetPoint("TOPLEFT", 27, -200)
    itemLevelTypeLabel:SetText("Item Level Type")

    local itemLevelDropdown = CreateFrame("Frame", "GuildNoteUpdaterItemLevelDropdown", frame, "UIDropDownMenuTemplate")
    itemLevelDropdown:SetPoint("LEFT", itemLevelTypeLabel, "RIGHT", 10, 0)

    local function OnItemLevelSelect(btn)
        local key = GuildNoteUpdater:GetCharacterKey()
        GuildNoteUpdater.itemLevelType[key] = btn.value
        UIDropDownMenu_SetText(itemLevelDropdown, btn.value)
        GuildNoteUpdaterSettings.itemLevelType = GuildNoteUpdater.itemLevelType
        GuildNoteUpdater:UpdateGuildNote()
    end

    local function InitializeItemLevelDropdown(dropdown, level)
        local key = GuildNoteUpdater:GetCharacterKey()
        local info = UIDropDownMenu_CreateInfo()
        info.text, info.value, info.func = "Overall", "Overall", OnItemLevelSelect
        info.checked = (GuildNoteUpdater.itemLevelType[key] == "Overall")
        UIDropDownMenu_AddButton(info, level)
        info.text, info.value = "Equipped", "Equipped"
        info.checked = (GuildNoteUpdater.itemLevelType[key] == "Equipped")
        UIDropDownMenu_AddButton(info, level)
    end

    UIDropDownMenu_Initialize(itemLevelDropdown, InitializeItemLevelDropdown)
    UIDropDownMenu_SetWidth(itemLevelDropdown, 120)
    UIDropDownMenu_SetText(itemLevelDropdown, self.itemLevelType[characterKey] or "Overall")

    local mainAltLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mainAltLabel:SetPoint("TOPLEFT", 27, -237)
    mainAltLabel:SetText("Main or Alt")

    local mainAltDropdown = CreateFrame("Frame", "GuildNoteUpdaterMainAltDropdown", frame, "UIDropDownMenuTemplate")
    mainAltDropdown:SetPoint("LEFT", mainAltLabel, "RIGHT", 38, 0)

    local function OnMainAltSelect(btn)
        local key = GuildNoteUpdater:GetCharacterKey()
        GuildNoteUpdater.mainOrAlt[key] = btn.value
        UIDropDownMenu_SetText(mainAltDropdown, btn.value)
        GuildNoteUpdaterSettings.mainOrAlt = GuildNoteUpdater.mainOrAlt
        GuildNoteUpdater:UpdateGuildNote()
    end

    local function InitializeMainAltDropdown(dropdown, level)
        local key = GuildNoteUpdater:GetCharacterKey()
        local info = UIDropDownMenu_CreateInfo()
        for _, opt in ipairs({"<None>", "Main", "Alt"}) do
            info.text, info.value, info.func = opt, opt, OnMainAltSelect
            info.checked = (GuildNoteUpdater.mainOrAlt[key] == opt)
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(mainAltDropdown, InitializeMainAltDropdown)
    UIDropDownMenu_SetWidth(mainAltDropdown, 120)
    UIDropDownMenu_SetText(mainAltDropdown, self.mainOrAlt[characterKey] or "<None>")

    local notePrefixLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    notePrefixLabel:SetPoint("TOPLEFT", 27, -274)
    notePrefixLabel:SetText("Note Prefix")

    local notePrefixText = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    notePrefixText:SetSize(130, 20)
    notePrefixText:SetPoint("LEFT", notePrefixLabel, "RIGHT", 62, 0)
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

    -- === Note Preview (FEAT-001) ===

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 15, -305)
    divider:SetPoint("TOPRIGHT", -15, -305)
    divider:SetColorTexture(0.5, 0.5, 0.5, 0.5)

    previewText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    previewText:SetPoint("TOPLEFT", 27, -318)
    previewText:SetPoint("RIGHT", frame, "RIGHT", -70, 0)
    previewText:SetJustifyH("LEFT")

    charCountText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    charCountText:SetPoint("TOPRIGHT", -20, -318)
    charCountText:SetJustifyH("RIGHT")

    self:UpdateNotePreview()

    -- === Slash Commands ===

    SLASH_GUILDNOTEUPDATER1 = "/gnu"
    SLASH_GUILDUPDATE1 = "/guildupdate"
    local function ToggleUI()
        if frame:IsShown() then frame:Hide() else frame:Show() end
    end
    SlashCmdList["GUILDNOTEUPDATER"] = ToggleUI
    SlashCmdList["GUILDUPDATE"] = ToggleUI
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
                    GuildNoteUpdater:UpdateGuildNote()
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
            showUpdateNotification = true
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

    local characterKey = self:GetCharacterKey()
    if self.enableProfessions[characterKey] == nil then self.enableProfessions[characterKey] = true end
    if self.specUpdateMode[characterKey] == nil then self.specUpdateMode[characterKey] = "Automatically" end

    self:CreateUI()
    self:SetupTooltipHook()
end

-- BUG-006: Only register bootstrap events at file scope
GuildNoteUpdater:RegisterEvent("ADDON_LOADED")
GuildNoteUpdater:RegisterEvent("PLAYER_ENTERING_WORLD")
GuildNoteUpdater:SetScript("OnEvent", GuildNoteUpdater.OnEvent)
