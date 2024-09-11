-- Create the addon table
local GuildNoteUpdater = CreateFrame("Frame")
GuildNoteUpdater.hasUpdated = false  -- Flag to prevent double updates
GuildNoteUpdater.previousItemLevel = nil  -- Store the previous item level
GuildNoteUpdater.previousNote = ""  -- Store the previous note to avoid redundant updates

-- Profession abbreviations
local professionAbbreviations = {
    Alchemy = "Alch", Blacksmithing = "BS", Enchanting = "Enc", Engineering = "Eng",
    Herbalism = "Herb", Inscription = "Ins", Jewelcrafting = "JC", Leatherworking = "LW",
    Mining = "Min", Skinning = "Skn", Tailoring = "Tail", None = "None"
}

-- Function to get abbreviated profession names
function GuildNoteUpdater:GetProfessionAbbreviation(profession)
    return professionAbbreviations[profession] or "None"
end

-- Function to initialize the addon settings
function GuildNoteUpdater:InitializeSettings()
    if not GuildNoteUpdaterSettings then
        -- Set default settings for first-time use
        GuildNoteUpdaterSettings = {
            enabledCharacters = {},
            specUpdateMode = {},
            selectedSpec = {},
            itemLevelType = {},
            mainOrAlt = {},
            enableProfessions = {}
        }

        GuildNoteUpdaterSettings.enabledCharacters[UnitName("player")] = true
        GuildNoteUpdaterSettings.specUpdateMode[UnitName("player")] = "Automatically"
        GuildNoteUpdaterSettings.selectedSpec[UnitName("player")] = nil
        GuildNoteUpdaterSettings.itemLevelType[UnitName("player")] = "Overall"
        GuildNoteUpdaterSettings.mainOrAlt[UnitName("player")] = nil
        GuildNoteUpdaterSettings.enableProfessions[UnitName("player")] = true
    end

    local characterName = UnitName("player")

    -- Set default values if they are nil
    GuildNoteUpdaterSettings.enabledCharacters[characterName] = GuildNoteUpdaterSettings.enabledCharacters[characterName] or true
    GuildNoteUpdaterSettings.specUpdateMode[characterName] = GuildNoteUpdaterSettings.specUpdateMode[characterName] or "Automatically"
    GuildNoteUpdaterSettings.selectedSpec[characterName] = GuildNoteUpdaterSettings.selectedSpec[characterName] or nil
    GuildNoteUpdaterSettings.itemLevelType[characterName] = GuildNoteUpdaterSettings.itemLevelType[characterName] or "Overall"
    GuildNoteUpdaterSettings.mainOrAlt[characterName] = GuildNoteUpdaterSettings.mainOrAlt[characterName] or nil
    GuildNoteUpdaterSettings.enableProfessions[characterName] = GuildNoteUpdaterSettings.enableProfessions[characterName] or true  -- Default to true if nil

    self.enabledCharacters = GuildNoteUpdaterSettings.enabledCharacters
    self.specUpdateMode = GuildNoteUpdaterSettings.specUpdateMode
    self.selectedSpec = GuildNoteUpdaterSettings.selectedSpec
    self.itemLevelType = GuildNoteUpdaterSettings.itemLevelType
    self.mainOrAlt = GuildNoteUpdaterSettings.mainOrAlt
    self.enableProfessions = GuildNoteUpdaterSettings.enableProfessions

    self:CreateUI() -- Now create the UI after loading saved settings
end

-- Event handling
function GuildNoteUpdater:OnEvent(event, arg1)
    if event == "ADDON_LOADED" and arg1 == "GuildNoteUpdater" then
        self:InitializeSettings()
        self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
    elseif event == "PLAYER_ENTERING_WORLD" then
        if IsInGuild() and not self.hasUpdated then
            self:RegisterEvent("GUILD_ROSTER_UPDATE")
            C_GuildInfo.GuildRoster()  -- Request a guild roster update
            -- Adding a slight delay to ensure guild roster loads
            C_Timer.After(2, function()
                if IsInGuild() then
                    self:UpdateGuildNote()
                end
            end)
        end
    elseif event == "GUILD_ROSTER_UPDATE" then
        if not self.hasUpdated then
            self.hasUpdated = true
            self:UnregisterEvent("GUILD_ROSTER_UPDATE")
            -- Delay the note update to ensure the guild roster is fully loaded
            C_Timer.After(1, function()
                if IsInGuild() and GetNumGuildMembers() > 0 then
                    self:UpdateGuildNote()
                end
            end)
        end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        -- Delay the guild note update by 1 second to ensure the item level is refreshed
        C_Timer.After(1, function()
            if IsInGuild() then
                self:UpdateGuildNote(true)  -- true indicates that we want to check for item level changes
            end
        end)
    end
end

-- Create a slash command to toggle the UI
SLASH_GUILDNOTEUPDATER1 = "/guildupdate"
SlashCmdList["GUILDNOTEUPDATER"] = function()
    if GuildNoteUpdaterUI:IsShown() then
        GuildNoteUpdaterUI:Hide()
    else
        GuildNoteUpdaterUI:Show()
    end
end

-- Event registration
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(self, event, arg1, ...)
    GuildNoteUpdater:OnEvent(event, arg1, ...)
end)

-- Update the guild note with item level, spec, professions, and main/alt status
function GuildNoteUpdater:UpdateGuildNote(checkForChanges)
    local characterName = UnitName("player")

    if not self.enabledCharacters[characterName] then
        print("GuildNoteUpdater: Guild Note auto update disabled for this character.")
        print("GuildNoteUpdater: Run /guildupdate for settings")
        return
    end

    -- Get both overall and equipped item levels
    local overallItemLevel, equippedItemLevel = GetAverageItemLevel()

    -- Determine whether to use overall or equipped item level
    local itemLevelType = self.itemLevelType[characterName] or "Overall"
    local itemLevel = (itemLevelType == "Equipped") and equippedItemLevel or overallItemLevel

    -- Get the current spec
    local spec = self:GetSpec(characterName)
    if spec == "Select Spec" then
        spec = nil  -- Omit if spec isn't selected
    end

    -- Get the main/alt status
    local mainOrAlt = self.mainOrAlt[characterName]
    if mainOrAlt == "Select Option" then
        mainOrAlt = nil  -- Omit if main/alt isn't selected
    end

    -- Get professions if enabled
    local profession1, profession2 = "None", "None"
    if self.enableProfessions[characterName] then
        local prof1, prof2 = GetProfessions()  -- Returns profession indices or nil if no professions
        profession1 = self:GetProfessionAbbreviation(prof1 and select(1, GetProfessionInfo(prof1)) or "None")
        profession2 = self:GetProfessionAbbreviation(prof2 and select(1, GetProfessionInfo(prof2)) or "None")
    end

    -- Build the new guild note text
    local noteParts = { math.floor(itemLevel) }
    
    if spec then table.insert(noteParts, spec) end
    if self.enableProfessions[characterName] then
        table.insert(noteParts, profession1)
        table.insert(noteParts, profession2)
    end
    if mainOrAlt then table.insert(noteParts, mainOrAlt) end

    local newNote = table.concat(noteParts, "-")

    -- Ensure the new note fits the 31-character limit
    if #newNote > 31 then
        -- Truncate professions and spec names as needed
        profession1 = string.sub(profession1, 1, 2)
        profession2 = string.sub(profession2, 1, 2)
        spec = string.sub(spec, 1, 5)
        newNote = table.concat({ math.floor(itemLevel), spec, profession1, profession2, mainOrAlt or "" }, "-")
    end

    -- Get the player's guild index
    local guildIndex = self:GetGuildIndexForPlayer()

    if guildIndex then
        local currentNote = select(8, GetGuildRosterInfo(guildIndex))  -- Get the current guild note

        -- If checking for changes, skip if both item level and spec are unchanged
        if checkForChanges and currentNote == newNote then
            return
        end

        -- Only update the note if the note is different
        if self.previousNote ~= newNote then
            print("GuildNoteUpdater: Updating guild note to:", newNote)
            GuildRosterSetPublicNote(guildIndex, newNote)
            -- Store the current item level and note to track future changes
            self.previousItemLevel = math.floor(itemLevel)
            self.previousNote = newNote
        end
    else
        print("GuildNoteUpdater: Unable to find guild index for player.")
    end
end

-- Get the player's guild index
function GuildNoteUpdater:GetGuildIndexForPlayer()
    local playerName = UnitName("player")
    for i = 1, GetNumGuildMembers() do
        local name = GetGuildRosterInfo(i)
        if name and name:find(playerName) then
            return i
        end
    end
    return nil
end

-- Get the current specialization
function GuildNoteUpdater:GetSpec(characterName)
    local specIndex = GetSpecialization()
    if self.specUpdateMode[characterName] == "Manually" then
        -- Automatically select the current spec if none has been selected yet
        if not self.selectedSpec[characterName] then
            self.selectedSpec[characterName] = select(2, GetSpecializationInfo(specIndex)) or "Select Spec"
        end
        return self.selectedSpec[characterName]
    else
        return select(2, GetSpecializationInfo(specIndex)) or nil
    end
end

-- Create the UI for enabling/disabling the addon and managing spec options
function GuildNoteUpdater:CreateUI()
    local frame = CreateFrame("Frame", "GuildNoteUpdaterUI", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(500, 300)  -- Adjusted height to fit additional options
    frame:SetPoint("CENTER")
    frame:Hide()

    -- Title text
    frame.title = frame:CreateFontString(nil, "OVERLAY")
    frame.title:SetFontObject("GameFontHighlight")
    frame.title:SetPoint("CENTER", frame.TitleBg, "CENTER", 0, 0)
    frame.title:SetText("Guild Note Updater")

    -- Create the enable/disable checkbox
    local enableButton = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    enableButton:SetPoint("TOPLEFT", 20, -40)
    enableButton.text:SetFontObject("GameFontNormal")
    enableButton.text:SetText("Enable for this character")

    enableButton:SetChecked(self.enabledCharacters[UnitName("player")] or false)
    enableButton:SetScript("OnClick", function(self)
        GuildNoteUpdater.enabledCharacters[UnitName("player")] = self:GetChecked()
        GuildNoteUpdaterSettings.enabledCharacters = GuildNoteUpdater.enabledCharacters  -- Save settings
        GuildNoteUpdater:UpdateGuildNote()
    end)

    -- Create the "Enable Professions" checkbox
    local enableProfessionsButton = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    enableProfessionsButton:SetPoint("TOPLEFT", 20, -70)
    enableProfessionsButton.text:SetFontObject("GameFontNormal")
    enableProfessionsButton.text:SetText("Enable professions")

    enableProfessionsButton:SetChecked(self.enableProfessions[UnitName("player")] or false)
    enableProfessionsButton:SetScript("OnClick", function(self)
        GuildNoteUpdater.enableProfessions[UnitName("player")] = self:GetChecked()
        GuildNoteUpdaterSettings.enableProfessions = GuildNoteUpdater.enableProfessions  -- Save settings
        GuildNoteUpdater:UpdateGuildNote()
    end)

    -- Add a label for "Update spec"
    local specUpdateLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    specUpdateLabel:SetPoint("TOPLEFT", 27, -107)
    specUpdateLabel:SetText("Update spec")

    -- Create the dropdown for selecting "Automatically" or "Manually"
    local specUpdateDropdown = CreateFrame("Frame", "GuildNoteUpdaterSpecUpdateDropdown", frame, "UIDropDownMenuTemplate")
    specUpdateDropdown:SetPoint("LEFT", specUpdateLabel, "RIGHT", 30, 0)

    -- Create the dropdown menu for manual spec selection
    local specDropdown = CreateFrame("Frame", "GuildNoteUpdaterSpecDropdown", frame, "UIDropDownMenuTemplate")
    specDropdown:SetPoint("TOPLEFT", specUpdateDropdown, "BOTTOMLEFT", 0, -5)

    -- Add extra space between spec dropdown and item level type
    local itemLevelSpacer = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemLevelSpacer:SetPoint("TOPLEFT", specDropdown, "BOTTOMLEFT", 0, -10)

    -- Add a label for "Main or Alt"
    local mainAltLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mainAltLabel:SetPoint("TOPLEFT", 27, -180)
    mainAltLabel:SetText("Main or Alt")

    -- Create dropdown for selecting main/alt status
    local mainAltDropdown = CreateFrame("Frame", "GuildNoteUpdaterMainAltDropdown", frame, "UIDropDownMenuTemplate")
    mainAltDropdown:SetPoint("LEFT", mainAltLabel, "RIGHT", 40, 0)

    -- Initialize and setup all dropdowns and options
    local function InitializeSpecUpdateDropdown(self, level)
        local info = UIDropDownMenu_CreateInfo()
        info.text = "Automatically"
        info.value = "Automatically"
        info.func = function(self)
            GuildNoteUpdater.specUpdateMode[UnitName("player")] = self.value
            UIDropDownMenu_SetText(specUpdateDropdown, self.value)
            GuildNoteUpdaterSettings.specUpdateMode = GuildNoteUpdater.specUpdateMode
            GuildNoteUpdater:UpdateGuildNote()
        end
        info.checked = (GuildNoteUpdater.specUpdateMode[UnitName("player")] == "Automatically")
        UIDropDownMenu_AddButton(info, level)

        info.text = "Manually"
        info.value = "Manually"
        info.func = function(self)
            GuildNoteUpdater.specUpdateMode[UnitName("player")] = self.value
            UIDropDownMenu_SetText(specUpdateDropdown, self.value)
            GuildNoteUpdaterSettings.specUpdateMode = GuildNoteUpdater.specUpdateMode
            UIDropDownMenu_EnableDropDown(specDropdown)
            GuildNoteUpdater:UpdateGuildNote()
        end
        info.checked = (GuildNoteUpdater.specUpdateMode[UnitName("player")] == "Manually")
        UIDropDownMenu_AddButton(info, level)
    end

    UIDropDownMenu_Initialize(specUpdateDropdown, InitializeSpecUpdateDropdown)
    UIDropDownMenu_SetWidth(specUpdateDropdown, 120)
    UIDropDownMenu_SetText(specUpdateDropdown, self.specUpdateMode[UnitName("player")] or "Automatically")

    local function InitializeSpecDropdown(self, level)
        local info = UIDropDownMenu_CreateInfo()
        local numSpecs = GetNumSpecializations()
        info.text = "Select Spec"
        info.value = "Select Spec"
        info.func = function(self)
            GuildNoteUpdater.selectedSpec[UnitName("player")] = self.value
            UIDropDownMenu_SetText(specDropdown, self.value)
            GuildNoteUpdaterSettings.selectedSpec = GuildNoteUpdater.selectedSpec
            GuildNoteUpdater:UpdateGuildNote()
        end
        info.checked = (GuildNoteUpdater.selectedSpec[UnitName("player")] == "Select Spec")
        UIDropDownMenu_AddButton(info, level)

        for i = 1, numSpecs do
            local specID, specName = GetSpecializationInfo(i)
            info.text = specName
            info.value = specName
            info.func = function(self)
                GuildNoteUpdater.selectedSpec[UnitName("player")] = self.value
                UIDropDownMenu_SetText(specDropdown, self.value)
                GuildNoteUpdaterSettings.selectedSpec = GuildNoteUpdater.selectedSpec
                GuildNoteUpdater:UpdateGuildNote()
            end
            info.checked = (specName == GuildNoteUpdater.selectedSpec[UnitName("player")])
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(specDropdown, InitializeSpecDropdown)
    UIDropDownMenu_SetWidth(specDropdown, 120)
    UIDropDownMenu_SetText(specDropdown, self.selectedSpec[UnitName("player")] or "Select Spec")

    -- Disable the spec dropdown if "Automatically" is selected
    if self.specUpdateMode[UnitName("player")] == "Automatically" then
        UIDropDownMenu_DisableDropDown(specDropdown)
    end

    -- Create dropdown for main/alt status
    local function InitializeMainAltDropdown(self, level)
        local info = UIDropDownMenu_CreateInfo()
        info.text = "This is my Main"
        info.value = "Main"
        info.func = function(self)
            GuildNoteUpdater.mainOrAlt[UnitName("player")] = self.value
            UIDropDownMenu_SetText(mainAltDropdown, self.value)
            GuildNoteUpdaterSettings.mainOrAlt = GuildNoteUpdater.mainOrAlt
            GuildNoteUpdater:UpdateGuildNote()
        end
        info.checked = (GuildNoteUpdater.mainOrAlt[UnitName("player")] == "Main")
        UIDropDownMenu_AddButton(info, level)

        info.text = "This is my Alt"
        info.value = "Alt"
        info.func = function(self)
            GuildNoteUpdater.mainOrAlt[UnitName("player")] = self.value
            UIDropDownMenu_SetText(mainAltDropdown, self.value)
            GuildNoteUpdaterSettings.mainOrAlt = GuildNoteUpdater.mainOrAlt
            GuildNoteUpdater:UpdateGuildNote()
        end
        info.checked = (GuildNoteUpdater.mainOrAlt[UnitName("player")] == "Alt")
        UIDropDownMenu_AddButton(info, level)
    end

    UIDropDownMenu_Initialize(mainAltDropdown, InitializeMainAltDropdown)
    UIDropDownMenu_SetWidth(mainAltDropdown, 120)
    UIDropDownMenu_SetText(mainAltDropdown, self.mainOrAlt[UnitName("player")] or "Select Option")

    -- Create a slash command to toggle the UI
    SLASH_GUILDNOTEUPDATER1 = "/guildupdate"
    SlashCmdList["GUILDNOTEUPDATER"] = function()
        if frame:IsShown() then
            frame:Hide()
        else
            frame:Show()
        end
    end
end