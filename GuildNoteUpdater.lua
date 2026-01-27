GuildNoteUpdater = CreateFrame("Frame")
GuildNoteUpdater.hasUpdated = false
GuildNoteUpdater.previousItemLevel = nil
GuildNoteUpdater.previousNote = ""
GuildNoteUpdater.debugEnabled = false

local professionAbbreviations = {
    Alchemy = "Alch", Blacksmithing = "BS", Enchanting = "Enc", Engineering = "Eng",
    Herbalism = "Herb", Inscription = "Ins", Jewelcrafting = "JC", Leatherworking = "LW",
    Mining = "Min", Skinning = "Skn", Tailoring = "Tail"
}

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

-- Builds and sets the guild note from current character data
function GuildNoteUpdater:UpdateGuildNote(checkForChanges)
    local characterKey = self:GetCharacterKey()

    if not self.enabledCharacters[characterKey] then
        self:DebugPrint("Guild Note auto update disabled for " .. characterKey)
        return
    end

    local overallItemLevel, equippedItemLevel = GetAverageItemLevel()
    local itemLevelType = self.itemLevelType[characterKey] or "Overall"
    local itemLevel = (itemLevelType == "Equipped") and equippedItemLevel or overallItemLevel
    local flooredItemLevel = math.floor(itemLevel)

    local spec = self:GetSpec(characterKey)

    local mainOrAlt = self.mainOrAlt[characterKey]
    if mainOrAlt == "Select Option" or mainOrAlt == "<None>" then
        mainOrAlt = nil
    end

    local profession1, profession2 = nil, nil
    if self.enableProfessions[characterKey] then
        local prof1, prof2 = GetProfessions()
        if prof1 then profession1 = self:GetProfessionAbbreviation(select(1, GetProfessionInfo(prof1))) end
        if prof2 then profession2 = self:GetProfessionAbbreviation(select(1, GetProfessionInfo(prof2))) end
        self:DebugPrint("Professions: " .. (profession1 or "none") .. ", " .. (profession2 or "none"))
    end

    local notePrefix = self.notePrefix[characterKey]
    if notePrefix then
        notePrefix = strtrim(notePrefix)
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

    local newNote = strtrim(table.concat(noteParts, " "))

    -- Truncate to fit 31-char guild note limit
    if #newNote > 31 then
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
        newNote = strtrim(table.concat(noteParts, " "))
        
        while #newNote > 31 and #noteParts > 1 do
            table.remove(noteParts)
            newNote = strtrim(table.concat(noteParts, " "))
        end
    end

    local guildIndex = self:GetGuildIndexForPlayer()
    if guildIndex then
        if self.previousNote ~= newNote then
            self:DebugPrint("Updating guild note to: " .. newNote)
            GuildRosterSetPublicNote(guildIndex, newNote)
            self.previousItemLevel = flooredItemLevel
            self.previousNote = newNote
        else
            self:DebugPrint("Note unchanged, skipping update")
        end
    else
        self:DebugPrint("Unable to find guild index for player.")
    end
end

-- Creates the settings UI frame with all controls and dropdowns
function GuildNoteUpdater:CreateUI()
    local frame = CreateFrame("Frame", "GuildNoteUpdaterUI", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(500, 297)
    frame:SetPoint("CENTER")
    frame:Hide()
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame.title = frame:CreateFontString(nil, "OVERLAY")
    frame.title:SetFontObject("GameFontHighlight")
    frame.title:SetPoint("CENTER", frame.TitleBg, "CENTER", 0, 0)
    frame.title:SetText("Guild Note Updater")

    local characterKey = self:GetCharacterKey()

    local enableButton = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    enableButton:SetPoint("TOPLEFT", 20, -30)
    enableButton.text:SetFontObject("GameFontNormal")
    enableButton.text:SetText("Enable for this character")
    enableButton:SetChecked(self.enabledCharacters[characterKey] or false)
    enableButton:SetScript("OnClick", function(btn)
        local key = GuildNoteUpdater:GetCharacterKey()
        GuildNoteUpdater.enabledCharacters[key] = btn:GetChecked()
        GuildNoteUpdaterSettings.enabledCharacters = GuildNoteUpdater.enabledCharacters
        GuildNoteUpdater:UpdateGuildNote()
    end)

    local enableProfessionsButton = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    enableProfessionsButton:SetPoint("TOPLEFT", 20, -70)
    enableProfessionsButton.text:SetFontObject("GameFontNormal")
    enableProfessionsButton.text:SetText("Enable professions")
    enableProfessionsButton:SetChecked(self.enableProfessions[characterKey] == true)
    enableProfessionsButton:SetScript("OnClick", function(btn)
        local key = GuildNoteUpdater:GetCharacterKey()
        local isChecked = btn:GetChecked()
        GuildNoteUpdater.enableProfessions[key] = isChecked
        GuildNoteUpdaterSettings.enableProfessions[key] = isChecked
        GuildNoteUpdater:UpdateGuildNote()
    end)

    local enableDebugButton = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    enableDebugButton:SetPoint("TOPRIGHT", -140, -30)
    enableDebugButton.text:SetFontObject("GameFontNormal")
    enableDebugButton.text:SetText("Enable Debug")
    enableDebugButton:SetChecked(self.debugEnabled)
    enableDebugButton:SetScript("OnClick", function(btn)
        GuildNoteUpdater.debugEnabled = btn:GetChecked()
        print("Debug mode is now " .. (GuildNoteUpdater.debugEnabled and "enabled" or "disabled"))
        GuildNoteUpdaterSettings.debugEnabled = GuildNoteUpdater.debugEnabled
    end)

    local specUpdateLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    specUpdateLabel:SetPoint("TOPLEFT", 27, -107)
    specUpdateLabel:SetText("Update spec")

    local specUpdateDropdown = CreateFrame("Frame", "GuildNoteUpdaterSpecUpdateDropdown", frame, "UIDropDownMenuTemplate")
    specUpdateDropdown:SetPoint("LEFT", specUpdateLabel, "RIGHT", 30, 0)

    local function OnSpecUpdateSelect(btn)
        local key = GuildNoteUpdater:GetCharacterKey()
        GuildNoteUpdater.specUpdateMode[key] = btn.value
        UIDropDownMenu_SetText(specUpdateDropdown, btn.value)
        GuildNoteUpdaterSettings.specUpdateMode = GuildNoteUpdater.specUpdateMode
        if btn.value == "Manually" then
            UIDropDownMenu_EnableDropDown(GuildNoteUpdaterSpecDropdown)
        else
            UIDropDownMenu_DisableDropDown(GuildNoteUpdaterSpecDropdown)
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

    local specDropdown = CreateFrame("Frame", "GuildNoteUpdaterSpecDropdown", frame, "UIDropDownMenuTemplate")
    specDropdown:SetPoint("TOPLEFT", specUpdateDropdown, "BOTTOMLEFT", 0, -5)

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
    itemLevelTypeLabel:SetPoint("TOPLEFT", 27, -183)
    itemLevelTypeLabel:SetText("Item Level Type")

    local itemLevelDropdown = CreateFrame("Frame", "GuildNoteUpdaterItemLevelDropdown", frame, "UIDropDownMenuTemplate")
    itemLevelDropdown:SetPoint("LEFT", itemLevelTypeLabel, "RIGHT", 10, 0)

    local function OnItemLevelSelect(btn)
        local key = GuildNoteUpdater:GetCharacterKey()
        GuildNoteUpdater.itemLevelType[key] = btn.value
        UIDropDownMenu_SetText(itemLevelDropdown, btn.value)
        GuildNoteUpdaterSettings.itemLevelType = GuildNoteUpdater.itemLevelType
        GuildNoteUpdater:UpdateGuildNote(true)
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
    mainAltLabel:SetPoint("TOPLEFT", 27, -220)
    mainAltLabel:SetText("Main or Alt")

    local mainAltDropdown = CreateFrame("Frame", "GuildNoteUpdaterMainAltDropdown", frame, "UIDropDownMenuTemplate")
    mainAltDropdown:SetPoint("LEFT", mainAltLabel, "RIGHT", 38, 0)

    local function OnMainAltSelect(btn)
        local key = GuildNoteUpdater:GetCharacterKey()
        GuildNoteUpdater.mainOrAlt[key] = btn.value
        UIDropDownMenu_SetText(mainAltDropdown, btn.value)
        GuildNoteUpdaterSettings.mainOrAlt = GuildNoteUpdater.mainOrAlt
        GuildNoteUpdater:UpdateGuildNote(true)
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
    notePrefixLabel:SetPoint("TOPLEFT", 27, -257)
    notePrefixLabel:SetText("Note Prefix")

    local notePrefixText = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    notePrefixText:SetSize(130, 20)
    notePrefixText:SetPoint("LEFT", notePrefixLabel, "RIGHT", 62, 0)
    notePrefixText:SetAutoFocus(false)
    notePrefixText:SetMaxLetters(12)
    notePrefixText:SetText(self.notePrefix[characterKey] and strtrim(self.notePrefix[characterKey]) or "")
    notePrefixText:SetScript("OnEnterPressed", function(editBox)
        local key = GuildNoteUpdater:GetCharacterKey()
        GuildNoteUpdater.notePrefix[key] = strtrim(editBox:GetText())
        GuildNoteUpdaterSettings.notePrefix = GuildNoteUpdater.notePrefix
        GuildNoteUpdater:UpdateGuildNote(true)
        editBox:ClearFocus()
    end)
    notePrefixText:SetScript("OnEscapePressed", function(editBox) editBox:ClearFocus() end)

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
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
        self:DebugPrint("Detected " .. event)
        C_Timer.After(1, function()
            if IsInGuild() then GuildNoteUpdater:UpdateGuildNote(true) end
        end)
    end
end

-- Loads saved settings from SavedVariables and sets defaults for new characters
function GuildNoteUpdater:InitializeSettings()
    if not GuildNoteUpdaterSettings then
        GuildNoteUpdaterSettings = {
            enabledCharacters = {}, specUpdateMode = {}, selectedSpec = {},
            itemLevelType = {}, mainOrAlt = {}, enableProfessions = {},
            debugEnabled = false, notePrefix = {}
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

    local characterKey = self:GetCharacterKey()
    if self.enableProfessions[characterKey] == nil then self.enableProfessions[characterKey] = true end
    if self.specUpdateMode[characterKey] == nil then self.specUpdateMode[characterKey] = "Automatically" end

    self:CreateUI()
end

GuildNoteUpdater:RegisterEvent("ADDON_LOADED")
GuildNoteUpdater:RegisterEvent("PLAYER_ENTERING_WORLD")
GuildNoteUpdater:RegisterEvent("GUILD_ROSTER_UPDATE")
GuildNoteUpdater:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
GuildNoteUpdater:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
GuildNoteUpdater:SetScript("OnEvent", GuildNoteUpdater.OnEvent)