-- Create the addon table and register as a frame
GuildNoteUpdater = CreateFrame("Frame")  -- Create the frame that will handle events

GuildNoteUpdater.hasUpdated = false  -- Flag to prevent double updates
GuildNoteUpdater.previousItemLevel = nil  -- Store the previous item level
GuildNoteUpdater.previousNote = ""  -- Store the previous note to avoid redundant updates
GuildNoteUpdater.debugEnabled = false  -- Debug flag to control printing

-- Helper function for debug printing
function GuildNoteUpdater:DebugPrint(message)
    if self.debugEnabled then
        print(message)
    end
end
-- Update the guild note with item level, spec, professions, and main/alt status
function GuildNoteUpdater:UpdateGuildNote(checkForChanges)
    local characterName = UnitName("player")

    if not self.enabledCharacters[characterName] then
        self:DebugPrint("GuildNoteUpdater: Guild Note auto update disabled for this character.")
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

    local newNote = table.concat(noteParts, " ")

    -- Ensure the new note fits the 31-character limit
    if #newNote > 31 then
        -- Truncate professions and spec names as needed
        profession1 = string.sub(profession1, 1, 2)
        profession2 = string.sub(profession2, 1, 2)
        spec = string.sub(spec, 1, 5)
        newNote = table.concat({ math.floor(itemLevel), spec, profession1, profession2, mainOrAlt or "" }, " ")
    end

    -- Get the player's guild index
    local guildIndex = self:GetGuildIndexForPlayer()

    if guildIndex then
        local currentNote = select(8, GetGuildRosterInfo(guildIndex))  -- Get the current guild note

        -- Always update the note regardless of changes
        if self.previousNote ~= newNote then
            self:DebugPrint("GuildNoteUpdater: Updating guild note to: " .. newNote)
            GuildRosterSetPublicNote(guildIndex, newNote)
            -- Store the current item level and note to track future changes
            self.previousItemLevel = math.floor(itemLevel)
            self.previousNote = newNote
        end
    else
        self:DebugPrint("GuildNoteUpdater: Unable to find guild index for player.")
    end
end

-- Create the UI for enabling/disabling the addon and managing spec options
function GuildNoteUpdater:CreateUI()
    local frame = CreateFrame("Frame", "GuildNoteUpdaterUI", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(500, 260)  -- Adjust height to accommodate new elements
    frame:SetPoint("CENTER")
    frame:Hide()

    -- Title text
    frame.title = frame:CreateFontString(nil, "OVERLAY")
    frame.title:SetFontObject("GameFontHighlight")
    frame.title:SetPoint("CENTER", frame.TitleBg, "CENTER", 0, 0)
    frame.title:SetText("Guild Note Updater")

    -- Create the enable/disable checkbox
    local enableButton = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    enableButton:SetPoint("TOPLEFT", 20, -30)
    enableButton.text:SetFontObject("GameFontNormal")
    enableButton.text:SetText("Enable for this character")

    enableButton:SetChecked(self.enabledCharacters[UnitName("player")] or false)
    enableButton:SetScript("OnClick", function(self)
        GuildNoteUpdater.enabledCharacters[UnitName("player")] = self:GetChecked()
        GuildNoteUpdaterSettings.enabledCharacters = GuildNoteUpdater.enabledCharacters  -- Save settings
        GuildNoteUpdater:UpdateGuildNote()  -- Immediately update after change
    end)

    -- Create the "Enable Professions" checkbox (only defined once now)
    local enableProfessionsButton = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    enableProfessionsButton:SetPoint("TOPLEFT", 20, -70)
    enableProfessionsButton.text:SetFontObject("GameFontNormal")
    enableProfessionsButton.text:SetText("Enable professions")

    -- Properly initialize the button before setting its script and state
    enableProfessionsButton:SetChecked(self.enableProfessions[UnitName("player")] == true)
    enableProfessionsButton:SetScript("OnClick", function(self)
        local isChecked = self:GetChecked()  -- Get the checkbox state (true or false)
        GuildNoteUpdater.enableProfessions[UnitName("player")] = isChecked  -- Save the boolean value
        GuildNoteUpdaterSettings.enableProfessions[UnitName("player")] = isChecked  -- Ensure the settings are saved as a boolean
        GuildNoteUpdater:UpdateGuildNote()  -- Immediately update after change
    end)
	
-- Add the "Enable Debug" checkbox
	local enableDebugButton = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	enableDebugButton:SetPoint("TOPRIGHT", -140, -30)  -- Position in the upper right corner
	enableDebugButton.text:SetFontObject("GameFontNormal")
	enableDebugButton.text:SetText("Enable Debug")
	enableDebugButton:SetChecked(self.debugEnabled)
	
	enableDebugButton:SetScript("OnClick", function(self)
    GuildNoteUpdater.debugEnabled = self:GetChecked()
    print("Debug mode is now", GuildNoteUpdater.debugEnabled and "enabled" or "disabled")
	-- Save the new debug state to the settings
    GuildNoteUpdaterSettings.debugEnabled = GuildNoteUpdater.debugEnabled
end)

    -- Add a label for "Update spec"
    local specUpdateLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    specUpdateLabel:SetPoint("TOPLEFT", 27, -107)
    specUpdateLabel:SetText("Update spec")

    -- Create the dropdown for selecting "Automatically" or "Manually"
    local specUpdateDropdown = CreateFrame("Frame", "GuildNoteUpdaterSpecUpdateDropdown", frame, "UIDropDownMenuTemplate")
    specUpdateDropdown:SetPoint("LEFT", specUpdateLabel, "RIGHT", 30, 0)

    -- Function for selecting spec update mode (Automatically or Manually)
    local function OnSpecUpdateSelect(self)
        GuildNoteUpdater.specUpdateMode[UnitName("player")] = self.value
        UIDropDownMenu_SetText(specUpdateDropdown, self.value)
        GuildNoteUpdaterSettings.specUpdateMode = GuildNoteUpdater.specUpdateMode

        -- Enable or disable the spec dropdown based on the selection
        if self.value == "Manually" then
            UIDropDownMenu_EnableDropDown(GuildNoteUpdaterSpecDropdown)
            -- Immediately update with the selected spec
            GuildNoteUpdater:UpdateGuildNote()
        else
            UIDropDownMenu_DisableDropDown(GuildNoteUpdaterSpecDropdown)
            GuildNoteUpdater:UpdateGuildNote()  -- Automatically update spec
        end
    end

    -- Initialize the spec update dropdown
    local function InitializeSpecUpdateDropdown(self, level)
        local info = UIDropDownMenu_CreateInfo()
        info.text = "Automatically"
        info.value = "Automatically"
        info.func = OnSpecUpdateSelect
        info.checked = (GuildNoteUpdater.specUpdateMode[UnitName("player")] == "Automatically")
        UIDropDownMenu_AddButton(info, level)

        info.text = "Manually"
        info.value = "Manually"
        info.func = OnSpecUpdateSelect
        info.checked = (GuildNoteUpdater.specUpdateMode[UnitName("player")] == "Manually")
        UIDropDownMenu_AddButton(info, level)
    end

    UIDropDownMenu_Initialize(specUpdateDropdown, InitializeSpecUpdateDropdown)
    UIDropDownMenu_SetWidth(specUpdateDropdown, 120)
    UIDropDownMenu_SetText(specUpdateDropdown, self.specUpdateMode[UnitName("player")] or "Automatically")

    -- Create the dropdown menu for manual spec selection (aligned directly under the "Update spec" dropdown)
    local specDropdown = CreateFrame("Frame", "GuildNoteUpdaterSpecDropdown", frame, "UIDropDownMenuTemplate")
    specDropdown:SetPoint("TOPLEFT", specUpdateDropdown, "BOTTOMLEFT", 0, -5)  -- Adjusted positioning to match alignment

    -- Function for selecting a spec manually
    local function OnSpecSelect(self)
        GuildNoteUpdater.selectedSpec[UnitName("player")] = self.value
        UIDropDownMenu_SetText(specDropdown, self.value)
        GuildNoteUpdaterSettings.selectedSpec = GuildNoteUpdater.selectedSpec
        -- Immediately update the guild note with the selected spec
        GuildNoteUpdater:UpdateGuildNote()
    end

    -- Initialize the spec dropdown
    local function InitializeSpecDropdown(self, level)
        local info = UIDropDownMenu_CreateInfo()
        local numSpecs = GetNumSpecializations()
        info.text = "Select Spec"
        info.value = "Select Spec"
        info.func = OnSpecSelect
        info.checked = (GuildNoteUpdater.selectedSpec[UnitName("player")] == "Select Spec")
        UIDropDownMenu_AddButton(info, level)
        for i = 1, numSpecs do
            local specID, specName = GetSpecializationInfo(i)
            info.text = specName
            info.value = specName
            info.func = OnSpecSelect
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

    -- Add a label for Item Level Type
    local itemLevelTypeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemLevelTypeLabel:SetPoint("TOPLEFT", 27, -183)
    itemLevelTypeLabel:SetText("Item Level Type")

    -- Create the dropdown menu for selecting item level type (Overall or Equipped)
    local itemLevelDropdown = CreateFrame("Frame", "GuildNoteUpdaterItemLevelDropdown", frame, "UIDropDownMenuTemplate")
    itemLevelDropdown:SetPoint("LEFT", itemLevelTypeLabel, "RIGHT", 10, 0)

    -- Function for selecting item level type (Overall or Equipped)
    local function OnItemLevelSelect(self)
        GuildNoteUpdater.itemLevelType[UnitName("player")] = self.value
        UIDropDownMenu_SetText(itemLevelDropdown, self.value)
        GuildNoteUpdaterSettings.itemLevelType = GuildNoteUpdater.itemLevelType
        -- Immediately update the guild note when item level type is changed
        GuildNoteUpdater:UpdateGuildNote(true)
    end

    -- Initialize the item level dropdown
    local function InitializeItemLevelDropdown(self, level)
        local info = UIDropDownMenu_CreateInfo()
        info.text = "Overall"
        info.value = "Overall"
        info.func = OnItemLevelSelect
        info.checked = (GuildNoteUpdater.itemLevelType[UnitName("player")] == "Overall")
        UIDropDownMenu_AddButton(info, level)

        info.text = "Equipped"
        info.value = "Equipped"
        info.func = OnItemLevelSelect
        info.checked = (GuildNoteUpdater.itemLevelType[UnitName("player")] == "Equipped")
        UIDropDownMenu_AddButton(info, level)
    end

    UIDropDownMenu_Initialize(itemLevelDropdown, InitializeItemLevelDropdown)
    UIDropDownMenu_SetWidth(itemLevelDropdown, 120)
    UIDropDownMenu_SetText(itemLevelDropdown, self.itemLevelType[UnitName("player")] or "Overall")

    -- Add a label for "Main or Alt"
    local mainAltLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mainAltLabel:SetPoint("TOPLEFT", 27, -220)
    mainAltLabel:SetText("Main or Alt")

    -- Create dropdown for selecting main/alt status
    local mainAltDropdown = CreateFrame("Frame", "GuildNoteUpdaterMainAltDropdown", frame, "UIDropDownMenuTemplate")
    mainAltDropdown:SetPoint("LEFT", mainAltLabel, "RIGHT", 38, 0)

    -- Function for selecting main/alt status
    local function OnMainAltSelect(self)
        GuildNoteUpdater.mainOrAlt[UnitName("player")] = self.value
        UIDropDownMenu_SetText(mainAltDropdown, self.value)
        GuildNoteUpdaterSettings.mainOrAlt = GuildNoteUpdater.mainOrAlt
        -- Immediately update the guild note when main/alt is changed
        GuildNoteUpdater:UpdateGuildNote(true)
    end

    -- Initialize the main/alt dropdown
    local function InitializeMainAltDropdown(self, level)
        local info = UIDropDownMenu_CreateInfo()
        info.text = "Main"
        info.value = "Main"
        info.func = OnMainAltSelect
        info.checked = (GuildNoteUpdater.mainOrAlt[UnitName("player")] == "Main")
        UIDropDownMenu_AddButton(info, level)

        info.text = "Alt"
        info.value = "Alt"
        info.func = OnMainAltSelect
        info.checked = (GuildNoteUpdater.mainOrAlt[UnitName("player")] == "Alt")
        UIDropDownMenu_AddButton(info, level)
    end

    UIDropDownMenu_Initialize(mainAltDropdown, InitializeMainAltDropdown)
    UIDropDownMenu_SetWidth(mainAltDropdown, 120)
    UIDropDownMenu_SetText(mainAltDropdown, self.mainOrAlt[UnitName("player")] or "Main")

    -- Create a slash command to toggle the UI
    SLASH_GUILDNOTEUPDATER1 = "/gnu"
    SlashCmdList["GUILDNOTEUPDATER"] = function()
        if frame:IsShown() then
            frame:Hide()
        else
            frame:Show()
        end
    end

    -- Restore the /guildupdate command
    SLASH_GUILDUPDATE1 = "/guildupdate"
    SlashCmdList["GUILDUPDATE"] = function()
        if frame:IsShown() then
            frame:Hide()
        else
            frame:Show()
        end
    end
end

-- Update the guild note with item level, spec, professions, and main/alt status
function GuildNoteUpdater:UpdateGuildNote(checkForChanges)
    local characterName = UnitName("player")

    if not self.enabledCharacters[characterName] then
        self:DebugPrint("GuildNoteUpdater: Guild Note auto update disabled for this character.")
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

    -- Add debug output for profession checkbox state
    --self:DebugPrint("GuildNoteUpdater: Enable professions is" .. self.enableProfessions[characterName])

    -- Build the new guild note text
    local noteParts = { math.floor(itemLevel) }

    if spec then table.insert(noteParts, spec) end

    -- Check if professions are enabled and only include them if the checkbox is checked
    if self.enableProfessions[characterName] then
        local prof1, prof2 = GetProfessions()  -- Returns profession indices or nil if no professions
        local profession1 = self:GetProfessionAbbreviation(prof1 and select(1, GetProfessionInfo(prof1)) or nil)
        local profession2 = self:GetProfessionAbbreviation(prof2 and select(1, GetProfessionInfo(prof2)) or nil)

        if profession1 then
            self:DebugPrint("GuildNoteUpdater: Including profession1:" .. profession1)
            table.insert(noteParts, profession1)
        end
        if profession2 then
            self:DebugPrint("GuildNoteUpdater: Including profession2:" .. profession2)
            table.insert(noteParts, profession2)
        end
    else
        self:DebugPrint("GuildNoteUpdater: Professions are disabled for this character.")
    end

    if mainOrAlt then table.insert(noteParts, mainOrAlt) end

    -- Combine all note parts into the final guild note text
    local newNote = table.concat(noteParts, " ")

    -- Ensure the new note fits the 31-character limit
    if #newNote > 31 then
        -- Truncate professions and spec names as needed
        if self.enableProfessions[characterName] then
            profession1 = string.sub(profession1 or "", 1, 2)
            profession2 = string.sub(profession2 or "", 1, 2)
        end
        spec = string.sub(spec or "", 1, 5)
        newNote = table.concat({ math.floor(itemLevel), spec, profession1 or "", profession2 or "", mainOrAlt or "" }, " ")
    end

    -- Get the player's guild index
    local guildIndex = self:GetGuildIndexForPlayer()

    if guildIndex then
        local currentNote = select(8, GetGuildRosterInfo(guildIndex))  -- Get the current guild note

        -- Always update the note if it's different
        if self.previousNote ~= newNote then
			self:DebugPrint("GuildNoteUpdater: Updating guild note to: " .. newNote)
            GuildRosterSetPublicNote(guildIndex, newNote)
            -- Store the current item level and note to track future changes
            self.previousItemLevel = math.floor(itemLevel)
            self.previousNote = newNote
        end
    else
        self:DebugPrint("GuildNoteUpdater: Unable to find guild index for player.")
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

-- Function to get abbreviated profession names
local professionAbbreviations = {
    Alchemy = "Alch", Blacksmithing = "BS", Enchanting = "Enc", Engineering = "Eng",
    Herbalism = "Herb", Inscription = "Ins", Jewelcrafting = "JC", Leatherworking = "LW",
    Mining = "Min", Skinning = "Skn", Tailoring = "Tail", None = "None"
}

function GuildNoteUpdater:GetProfessionAbbreviation(profession)
    return professionAbbreviations[profession] or "None"
end

-- Event handling
function GuildNoteUpdater:OnEvent(event, arg1)
    if event == "ADDON_LOADED" and arg1 == "GuildNoteUpdater" then
        self:InitializeSettings()
        -- Register events for gear changes and spec changes
        self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")  -- Event for spec change
    elseif event == "PLAYER_ENTERING_WORLD" then
        if IsInGuild() and not self.hasUpdated then
            self:RegisterEvent("GUILD_ROSTER_UPDATE")
            C_GuildInfo.GuildRoster()  -- Request a guild roster update
        end
    elseif event == "GUILD_ROSTER_UPDATE" then
        if not self.hasUpdated then
            -- Set the flag to prevent further updates and introduce a brief delay
            self.hasUpdated = true
            self:UnregisterEvent("GUILD_ROSTER_UPDATE")  -- Unregister the event to prevent further triggering
            C_Timer.After(1, function()
                if IsInGuild() and GetNumGuildMembers() > 0 then
                    self:UpdateGuildNote()
                end
            end)
        end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
        -- Delay the guild note update by 1 second to ensure the item level is refreshed
		self:DebugPrint("Detected equipment or spec change!")  -- Debugging print
        C_Timer.After(1, function()
            if IsInGuild() then
                self:UpdateGuildNote(true)  -- true indicates that we want to check for item level or spec changes
            end
        end)
    end
end

-- Initialize settings and create the UI
function GuildNoteUpdater:InitializeSettings()
    if not GuildNoteUpdaterSettings then
        -- Set default settings for first-time use
        GuildNoteUpdaterSettings = {
            enabledCharacters = {},
            specUpdateMode = {},  -- Store whether to update automatically or manually
            selectedSpec = {},
            itemLevelType = {},  -- Store the item level type selection (Overall/Equipped)
            mainOrAlt = {},
            enableProfessions = {},  -- Ensure professions are included in the saved settings
			debugEnabled = false  -- Default to debug mode off
			
        }
    end

    -- Load saved settings or set defaults if not available
    self.enabledCharacters = GuildNoteUpdaterSettings.enabledCharacters or {}
    self.specUpdateMode = GuildNoteUpdaterSettings.specUpdateMode or {}
    self.selectedSpec = GuildNoteUpdaterSettings.selectedSpec or {}
    self.itemLevelType = GuildNoteUpdaterSettings.itemLevelType or {}
    self.mainOrAlt = GuildNoteUpdaterSettings.mainOrAlt or {}
    self.enableProfessions = GuildNoteUpdaterSettings.enableProfessions or {}
	self.debugEnabled = GuildNoteUpdaterSettings.debugEnabled or false  -- Load debug mode state

    -- Set default for the current character if not yet set
    local characterName = UnitName("player")
    if self.enableProfessions[characterName] == nil then
        self.enableProfessions[characterName] = true  -- Default to enabling professions
    end

    self:CreateUI()  -- Now create the UI after loading saved settings
end

-- Event registration
GuildNoteUpdater:RegisterEvent("ADDON_LOADED")
GuildNoteUpdater:RegisterEvent("PLAYER_ENTERING_WORLD")
GuildNoteUpdater:RegisterEvent("GUILD_ROSTER_UPDATE")  -- Register the event to handle guild roster updates
GuildNoteUpdater:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")  -- Register event to detect equipment changes
GuildNoteUpdater:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")  -- Register event to detect spec changes
GuildNoteUpdater:SetScript("OnEvent", GuildNoteUpdater.OnEvent)
