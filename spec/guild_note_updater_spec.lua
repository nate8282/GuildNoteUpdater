-- GuildNoteUpdater busted test suite
-- Run with: busted --verbose

dofile("GuildNoteUpdater.lua")

describe("GuildNoteUpdater", function()
    local charKey

    setup(function()
        _G.UISpecialFrames = {}
        _G.GuildNoteUpdaterSettings = nil
        GuildNoteUpdater:InitializeSettings()
        charKey = GuildNoteUpdater:GetCharacterKey()
    end)

    -- === GetCharacterKey ===
    describe("GetCharacterKey", function()
        after_each(function()
            MockData.player.realm = "Sargeras"
        end)

        it("returns Name-Realm format", function()
            assert.are.equal("Kaelen-Sargeras", GuildNoteUpdater:GetCharacterKey())
        end)

        it("removes spaces from realm name", function()
            MockData.player.realm = "Twisting Nether"
            assert.are.equal("Kaelen-TwistingNether", GuildNoteUpdater:GetCharacterKey())
        end)
    end)

    -- === GetGuildIndexForPlayer ===
    describe("GetGuildIndexForPlayer", function()
        it("finds correct player index", function()
            assert.are.equal(1, GuildNoteUpdater:GetGuildIndexForPlayer())
        end)

        it("does not match different realm", function()
            assert.are_not.equal(2, GuildNoteUpdater:GetGuildIndexForPlayer())
        end)
    end)

    -- === GetProfessionAbbreviation ===
    describe("GetProfessionAbbreviation", function()
        it("abbreviates Leatherworking to LW", function()
            assert.are.equal("LW", GuildNoteUpdater:GetProfessionAbbreviation("Leatherworking"))
        end)

        it("abbreviates Skinning to Skn", function()
            assert.are.equal("Skn", GuildNoteUpdater:GetProfessionAbbreviation("Skinning"))
        end)

        it("returns nil for nil input", function()
            assert.is_nil(GuildNoteUpdater:GetProfessionAbbreviation(nil))
        end)

        it("returns nil for unknown professions", function()
            assert.is_nil(GuildNoteUpdater:GetProfessionAbbreviation("Fishing"))
        end)
    end)

    -- === GetSpec ===
    describe("GetSpec", function()
        after_each(function()
            GuildNoteUpdater.specUpdateMode[charKey] = "Automatically"
            MockData.spec.index = 2
        end)

        it("returns current spec in auto mode", function()
            GuildNoteUpdater.specUpdateMode[charKey] = "Automatically"
            assert.are.equal("Feral", GuildNoteUpdater:GetSpec(charKey))
        end)

        it("returns selected spec in manual mode", function()
            GuildNoteUpdater.specUpdateMode[charKey] = "Manually"
            GuildNoteUpdater.selectedSpec[charKey] = "Guardian"
            assert.are.equal("Guardian", GuildNoteUpdater:GetSpec(charKey))
        end)

        it("returns nil when GetSpecialization returns nil", function()
            MockData.spec.index = nil
            assert.is_nil(GuildNoteUpdater:GetSpec(charKey))
        end)
    end)

    -- === BuildNoteString ===
    describe("BuildNoteString", function()
        before_each(function()
            GuildNoteUpdater.enabledCharacters[charKey] = true
            GuildNoteUpdater.enableProfessions[charKey] = true
            GuildNoteUpdater.mainOrAlt[charKey] = "Main"
            GuildNoteUpdater.notePrefix[charKey] = nil
            GuildNoteUpdater.itemLevelType[charKey] = "Overall"
            GuildNoteUpdater.specUpdateMode[charKey] = "Automatically"
            GuildNoteUpdater.enableSpec[charKey] = true
            MockData.itemLevel = { overall = 489.5, equipped = 485.2 }
            MockData.spec.index = 2
        end)

        it("returns a full note string with all fields", function()
            local note = GuildNoteUpdater:BuildNoteString(charKey)
            assert.are.equal("489 Feral LW Skn Main", note)
        end)

        it("returns nil when character is disabled", function()
            GuildNoteUpdater.enabledCharacters[charKey] = false
            assert.is_nil(GuildNoteUpdater:BuildNoteString(charKey))
        end)

        it("returns nil when ilvl is 0", function()
            MockData.itemLevel = { overall = 0.0, equipped = 0.0 }
            assert.is_nil(GuildNoteUpdater:BuildNoteString(charKey))
        end)

        it("returns nil when ilvl floors to 0", function()
            MockData.itemLevel = { overall = 0.9, equipped = 0.3 }
            assert.is_nil(GuildNoteUpdater:BuildNoteString(charKey))
        end)

        it("uses equipped ilvl when configured", function()
            GuildNoteUpdater.itemLevelType[charKey] = "Equipped"
            local note = GuildNoteUpdater:BuildNoteString(charKey)
            assert.is_truthy(note:find("485"))
        end)

        it("includes prefix with hyphen separator", function()
            GuildNoteUpdater.notePrefix[charKey] = "Tank"
            local note = GuildNoteUpdater:BuildNoteString(charKey)
            assert.is_truthy(note:find("Tank -"))
        end)

        it("excludes professions when disabled", function()
            GuildNoteUpdater.enableProfessions[charKey] = false
            local note = GuildNoteUpdater:BuildNoteString(charKey)
            assert.is_falsy(note:find("LW"))
            assert.is_falsy(note:find("Skn"))
        end)

        it("excludes Main/Alt when set to None", function()
            GuildNoteUpdater.mainOrAlt[charKey] = "<None>"
            local note = GuildNoteUpdater:BuildNoteString(charKey)
            assert.is_falsy(note:find("Main"))
            assert.is_falsy(note:find("Alt"))
        end)

        it("omits spec when enableSpec is false", function()
            GuildNoteUpdater.enableSpec[charKey] = false
            local note = GuildNoteUpdater:BuildNoteString(charKey)
            assert.is_falsy(note:find("Feral"))
            assert.is_truthy(note:find("489"))
        end)

        it("includes spec by default when enableSpec is nil", function()
            GuildNoteUpdater.enableSpec[charKey] = nil
            local note = GuildNoteUpdater:BuildNoteString(charKey)
            assert.is_truthy(note:find("Feral"))
        end)

        it("truncates to 31 characters or fewer", function()
            GuildNoteUpdater.notePrefix[charKey] = "RaidLeaderLongName"
            local note = GuildNoteUpdater:BuildNoteString(charKey)
            assert.is_truthy(#note <= 31)
        end)

        it("empty prefix produces no hyphen", function()
            GuildNoteUpdater.notePrefix[charKey] = ""
            local note = GuildNoteUpdater:BuildNoteString(charKey)
            assert.is_falsy(note:find("%-"))
        end)

        it("nil prefix does not crash", function()
            GuildNoteUpdater.notePrefix[charKey] = nil
            assert.has_no.errors(function()
                GuildNoteUpdater:BuildNoteString(charKey)
            end)
        end)
    end)

    -- === UpdateGuildNote ===
    describe("UpdateGuildNote", function()
        before_each(function()
            GuildNoteUpdater.previousNote = ""
            MockData.updatedNotes = {}
            MockData.inCombat = false
            GuildNoteUpdater.pendingCombatUpdate = false
            GuildNoteUpdater.enabledCharacters[charKey] = true
            GuildNoteUpdater.enableProfessions[charKey] = true
            GuildNoteUpdater.mainOrAlt[charKey] = "Main"
            GuildNoteUpdater.notePrefix[charKey] = nil
            GuildNoteUpdater.itemLevelType[charKey] = "Overall"
            GuildNoteUpdater.specUpdateMode[charKey] = "Automatically"
            GuildNoteUpdater.enableSpec[charKey] = true
            MockData.itemLevel = { overall = 489.5, equipped = 485.2 }
            MockData.spec.index = 2
        end)

        it("updates guild note when enabled", function()
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_not_nil(MockData.updatedNotes[1])
        end)

        it("contains item level (489)", function()
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_truthy(MockData.updatedNotes[1]:find("489"))
        end)

        it("contains spec name", function()
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_truthy(MockData.updatedNotes[1]:find("Feral"))
        end)

        it("contains profession abbreviation", function()
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_truthy(MockData.updatedNotes[1]:find("LW"))
        end)

        it("contains Main status", function()
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_truthy(MockData.updatedNotes[1]:find("Main"))
        end)

        it("uses equipped item level when configured", function()
            GuildNoteUpdater.itemLevelType[charKey] = "Equipped"
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_truthy(MockData.updatedNotes[1]:find("485"))
        end)

        it("includes prefix with hyphen separator", function()
            GuildNoteUpdater.notePrefix[charKey] = "Tank"
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_truthy(MockData.updatedNotes[1]:find("Tank -"))
        end)

        it("does not update when character is disabled", function()
            GuildNoteUpdater.enabledCharacters[charKey] = false
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_nil(MockData.updatedNotes[1])
        end)

        it("excludes professions when disabled", function()
            GuildNoteUpdater.enableProfessions[charKey] = false
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_falsy(MockData.updatedNotes[1] and MockData.updatedNotes[1]:find("LW"))
        end)

        it("excludes Main/Alt when set to <None>", function()
            GuildNoteUpdater.mainOrAlt[charKey] = "<None>"
            GuildNoteUpdater:UpdateGuildNote()
            local note = MockData.updatedNotes[1]
            assert.is_falsy(note and (note:find("Main") or note:find("Alt")))
        end)

        it("skips API call when note is unchanged", function()
            GuildNoteUpdater:UpdateGuildNote()
            MockData.updatedNotes = {}
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_nil(MockData.updatedNotes[1])
        end)

        it("does not update when ilvl is 0", function()
            MockData.itemLevel = { overall = 0.0, equipped = 0.0 }
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_nil(MockData.updatedNotes[1])
        end)

        it("does not have previousItemLevel field", function()
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_nil(rawget(GuildNoteUpdater, "previousItemLevel"))
        end)

        it("does not write note during combat lockdown", function()
            MockData.inCombat = true
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_nil(MockData.updatedNotes[1])
        end)

        it("sets pendingCombatUpdate flag when in combat", function()
            MockData.inCombat = true
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_true(GuildNoteUpdater.pendingCombatUpdate)
        end)

        it("writes note normally when not in combat", function()
            MockData.inCombat = false
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_not_nil(MockData.updatedNotes[1])
        end)
    end)

    -- === Truncation ===
    describe("truncation", function()
        before_each(function()
            GuildNoteUpdater.previousNote = ""
            MockData.updatedNotes = {}
            MockData.inCombat = false
            GuildNoteUpdater.enabledCharacters[charKey] = true
            GuildNoteUpdater.enableProfessions[charKey] = true
            GuildNoteUpdater.mainOrAlt[charKey] = "Main"
            GuildNoteUpdater.itemLevelType[charKey] = "Overall"
            GuildNoteUpdater.specUpdateMode[charKey] = "Automatically"
            GuildNoteUpdater.enableSpec[charKey] = true
            MockData.itemLevel = { overall = 489.5, equipped = 485.2 }
            MockData.spec.index = 2
        end)

        it("enforces 31 character limit", function()
            GuildNoteUpdater.notePrefix[charKey] = "RaidLeader"
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_truthy(#MockData.updatedNotes[1] <= 31)
        end)
    end)

    -- === Nil Safety ===
    describe("nil safety", function()
        before_each(function()
            GuildNoteUpdater.previousNote = ""
            MockData.updatedNotes = {}
            GuildNoteUpdater.enabledCharacters[charKey] = true
            GuildNoteUpdater.enableProfessions[charKey] = true
            GuildNoteUpdater.mainOrAlt[charKey] = "Main"
            GuildNoteUpdater.itemLevelType[charKey] = "Overall"
            GuildNoteUpdater.enableSpec[charKey] = true
            MockData.itemLevel = { overall = 489.5, equipped = 485.2 }
            MockData.spec.index = 2
        end)

        it("empty prefix produces no hyphen", function()
            GuildNoteUpdater.notePrefix[charKey] = ""
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_falsy(MockData.updatedNotes[1] and MockData.updatedNotes[1]:find("%-"))
        end)

        it("nil prefix does not crash", function()
            GuildNoteUpdater.notePrefix[charKey] = nil
            assert.has_no.errors(function()
                GuildNoteUpdater:UpdateGuildNote()
            end)
            assert.is_not_nil(MockData.updatedNotes[1])
        end)
    end)

    -- === Cross-Realm Keys ===
    describe("cross-realm isolation", function()
        it("treats same name on different realms as different characters", function()
            GuildNoteUpdater.mainOrAlt["Kaelen-Sargeras"] = "Main"
            GuildNoteUpdater.mainOrAlt["Kaelen-Proudmoore"] = "Alt"
            assert.are_not.equal(
                GuildNoteUpdater.mainOrAlt["Kaelen-Sargeras"],
                GuildNoteUpdater.mainOrAlt["Kaelen-Proudmoore"]
            )
        end)
    end)

    -- === ParseGuildNote (FEAT-002) ===
    describe("ParseGuildNote", function()
        it("parses a full note with all fields", function()
            local result = GuildNoteUpdater:ParseGuildNote("489 Feral LW Skn Main")
            assert.are.equal("489", result.ilvl)
            assert.are.equal("Feral", result.spec)
            assert.are.equal("Main", result.mainAlt)
            assert.is_truthy(result.professions)
            assert.are.equal(2, #result.professions)
        end)

        it("parses a note with prefix", function()
            local result = GuildNoteUpdater:ParseGuildNote("Tank - 489 Feral LW Main")
            assert.are.equal("Tank", result.prefix)
            assert.are.equal("489", result.ilvl)
            assert.are.equal("Feral", result.spec)
            assert.are.equal("Main", result.mainAlt)
        end)

        it("parses a minimal note with only ilvl", function()
            local result = GuildNoteUpdater:ParseGuildNote("489")
            assert.are.equal("489", result.ilvl)
            assert.is_nil(result.spec)
            assert.is_nil(result.mainAlt)
        end)

        it("returns nil for empty string", function()
            assert.is_nil(GuildNoteUpdater:ParseGuildNote(""))
        end)

        it("returns nil for nil input", function()
            assert.is_nil(GuildNoteUpdater:ParseGuildNote(nil))
        end)

        it("returns nil for non-addon note with no ilvl", function()
            assert.is_nil(GuildNoteUpdater:ParseGuildNote("Officer rank five"))
        end)

        it("parses truncated notes", function()
            local result = GuildNoteUpdater:ParseGuildNote("Tank - 489 Fera LW Sk M")
            assert.are.equal("Tank", result.prefix)
            assert.are.equal("489", result.ilvl)
            assert.are.equal("Fera", result.spec)
            assert.are.equal("Main", result.mainAlt)
        end)

        it("handles note with no professions", function()
            local result = GuildNoteUpdater:ParseGuildNote("489 Feral Main")
            assert.are.equal("489", result.ilvl)
            assert.are.equal("Feral", result.spec)
            assert.are.equal("Main", result.mainAlt)
            assert.is_nil(result.professions)
        end)

        it("parses Alt status correctly", function()
            local result = GuildNoteUpdater:ParseGuildNote("489 Feral LW Skn Alt")
            assert.are.equal("Alt", result.mainAlt)
        end)

        it("resolves profession abbreviations to full names", function()
            local result = GuildNoteUpdater:ParseGuildNote("489 Feral LW Skn Main")
            assert.is_truthy(result.professions)
            -- Check that known abbreviations resolve to full names
            local hasLW = false
            local hasSkinning = false
            for _, prof in ipairs(result.professions) do
                if prof == "Leatherworking" then hasLW = true end
                if prof == "Skinning" then hasSkinning = true end
            end
            assert.is_truthy(hasLW)
            assert.is_truthy(hasSkinning)
        end)
    end)

    -- === ESC-to-close (BUG-005) ===
    describe("ESC-to-close", function()
        it("adds frame name to UISpecialFrames", function()
            local found = false
            for _, name in ipairs(_G.UISpecialFrames) do
                if name == "GuildNoteUpdaterUI" then
                    found = true
                    break
                end
            end
            assert.is_truthy(found)
        end)
    end)

    -- === File-scope event registration (BUG-006) ===
    describe("event registration", function()
        it("registers ADDON_LOADED at file scope", function()
            assert.is_truthy(MockData.registeredEvents["ADDON_LOADED"])
        end)

        it("registers PLAYER_ENTERING_WORLD at file scope", function()
            assert.is_truthy(MockData.registeredEvents["PLAYER_ENTERING_WORLD"])
        end)

        it("registers PLAYER_EQUIPMENT_CHANGED after ADDON_LOADED", function()
            GuildNoteUpdater:OnEvent("ADDON_LOADED", "GuildNoteUpdater")
            assert.is_truthy(MockData.registeredEvents["PLAYER_EQUIPMENT_CHANGED"])
        end)
    end)

    -- === Spec toggle (FEAT-005) ===
    describe("spec toggle", function()
        before_each(function()
            GuildNoteUpdater.previousNote = ""
            MockData.updatedNotes = {}
            GuildNoteUpdater.enabledCharacters[charKey] = true
            GuildNoteUpdater.enableProfessions[charKey] = true
            GuildNoteUpdater.mainOrAlt[charKey] = "Main"
            GuildNoteUpdater.notePrefix[charKey] = nil
            GuildNoteUpdater.itemLevelType[charKey] = "Overall"
            MockData.itemLevel = { overall = 489.5, equipped = 485.2 }
            MockData.spec.index = 2
        end)

        it("includes spec when enableSpec is true", function()
            GuildNoteUpdater.enableSpec[charKey] = true
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_truthy(MockData.updatedNotes[1]:find("Feral"))
        end)

        it("excludes spec when enableSpec is false", function()
            GuildNoteUpdater.enableSpec[charKey] = false
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_falsy(MockData.updatedNotes[1]:find("Feral"))
        end)

        it("still includes ilvl when spec is disabled", function()
            GuildNoteUpdater.enableSpec[charKey] = false
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_truthy(MockData.updatedNotes[1]:find("489"))
        end)

        it("still includes professions when spec is disabled", function()
            GuildNoteUpdater.enableSpec[charKey] = false
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_truthy(MockData.updatedNotes[1]:find("LW"))
        end)
    end)

    -- === ilvl 0 guard (BUG-002) ===
    describe("ilvl 0 guard", function()
        before_each(function()
            GuildNoteUpdater.previousNote = ""
            MockData.updatedNotes = {}
            GuildNoteUpdater.enabledCharacters[charKey] = true
            GuildNoteUpdater.enableProfessions[charKey] = true
            GuildNoteUpdater.mainOrAlt[charKey] = "Main"
            GuildNoteUpdater.enableSpec[charKey] = true
        end)

        after_each(function()
            MockData.itemLevel = { overall = 489.5, equipped = 485.2 }
        end)

        it("does not update when ilvl is 0", function()
            MockData.itemLevel = { overall = 0.0, equipped = 0.0 }
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_nil(MockData.updatedNotes[1])
        end)

        it("does not update when ilvl floors to 0", function()
            MockData.itemLevel = { overall = 0.9, equipped = 0.3 }
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_nil(MockData.updatedNotes[1])
        end)

        it("updates normally when ilvl is 1 or above", function()
            MockData.itemLevel = { overall = 1.0, equipped = 1.0 }
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_not_nil(MockData.updatedNotes[1])
            assert.is_truthy(MockData.updatedNotes[1]:find("1"))
        end)
    end)

    -- === Dead code removal (BUG-003) ===
    describe("dead code removal", function()
        it("does not have previousItemLevel field after initialization", function()
            assert.is_nil(rawget(GuildNoteUpdater, "previousItemLevel"))
        end)

        it("UpdateGuildNote works with no arguments", function()
            GuildNoteUpdater.previousNote = ""
            MockData.updatedNotes = {}
            GuildNoteUpdater.enabledCharacters[charKey] = true
            GuildNoteUpdater.enableSpec[charKey] = true
            MockData.itemLevel = { overall = 489.5, equipped = 485.2 }
            MockData.spec.index = 2
            assert.has_no.errors(function()
                GuildNoteUpdater:UpdateGuildNote()
            end)
            assert.is_not_nil(MockData.updatedNotes[1])
        end)
    end)

    -- === Settings initialization ===
    -- Note: Use _G for global assignments to avoid busted environment shadowing
    describe("InitializeSettings", function()
        it("creates default settings when none exist", function()
            _G.GuildNoteUpdaterSettings = nil
            GuildNoteUpdater:InitializeSettings()
            assert.is_not_nil(_G.GuildNoteUpdaterSettings)
            assert.is_table(_G.GuildNoteUpdaterSettings.enabledCharacters)
            assert.is_table(_G.GuildNoteUpdaterSettings.enableSpec)
        end)

        it("preserves existing settings on reload", function()
            _G.GuildNoteUpdaterSettings = {
                enabledCharacters = { ["Test-Realm"] = true },
                specUpdateMode = {}, selectedSpec = {},
                itemLevelType = {}, mainOrAlt = {},
                enableProfessions = {}, debugEnabled = false,
                notePrefix = {},
                enableSpec = {}, enableTooltipParsing = true,
                showUpdateNotification = true,
            }
            GuildNoteUpdater:InitializeSettings()
            assert.is_true(_G.GuildNoteUpdaterSettings.enabledCharacters["Test-Realm"])
        end)

        it("defaults enableTooltipParsing to true", function()
            _G.GuildNoteUpdaterSettings = nil
            GuildNoteUpdater:InitializeSettings()
            assert.is_true(GuildNoteUpdater.enableTooltipParsing)
        end)

        it("defaults showUpdateNotification to true", function()
            _G.GuildNoteUpdaterSettings = nil
            GuildNoteUpdater:InitializeSettings()
            assert.is_true(GuildNoteUpdater.showUpdateNotification)
        end)

        it("preserves saved showUpdateNotification = false", function()
            _G.GuildNoteUpdaterSettings = { showUpdateNotification = false }
            GuildNoteUpdater:InitializeSettings()
            assert.is_false(GuildNoteUpdater.showUpdateNotification)
        end)

        it("defaults enableProfessions to true for new characters", function()
            _G.GuildNoteUpdaterSettings = nil
            GuildNoteUpdater:InitializeSettings()
            local key = GuildNoteUpdater:GetCharacterKey()
            assert.is_true(GuildNoteUpdater.enableProfessions[key])
        end)

        it("defaults enableItemLevel to empty table (nil key = true via ~= false)", function()
            _G.GuildNoteUpdaterSettings = nil
            GuildNoteUpdater:InitializeSettings()
            assert.are.equal("table", type(GuildNoteUpdater.enableItemLevel))
        end)

        it("defaults enableMainAlt to empty table (nil key = true via ~= false)", function()
            _G.GuildNoteUpdaterSettings = nil
            GuildNoteUpdater:InitializeSettings()
            assert.are.equal("table", type(GuildNoteUpdater.enableMainAlt))
        end)

        it("defaults noteLocked to empty table", function()
            _G.GuildNoteUpdaterSettings = nil
            GuildNoteUpdater:InitializeSettings()
            assert.are.equal("table", type(GuildNoteUpdater.noteLocked))
        end)
    end)

    -- === ShowUpdateConfirmation (FEAT-003) ===
    describe("ShowUpdateConfirmation", function()
        it("does not crash with a normal note", function()
            assert.has_no.errors(function()
                GuildNoteUpdater:ShowUpdateConfirmation("489 Feral LW Skn Main")
            end)
        end)

        it("does not crash with a short note", function()
            assert.has_no.errors(function()
                GuildNoteUpdater:ShowUpdateConfirmation("489")
            end)
        end)

        it("does not crash with a max-length note", function()
            assert.has_no.errors(function()
                GuildNoteUpdater:ShowUpdateConfirmation("1234567890123456789012345678901")
            end)
        end)

        it("prints when showUpdateNotification is true", function()
            GuildNoteUpdater.showUpdateNotification = true
            local s = spy.on(_G, "print")
            GuildNoteUpdater:ShowUpdateConfirmation("489 Feral Main")
            assert.spy(s).was_called()
            s:revert()
        end)

        it("suppresses print when showUpdateNotification is false", function()
            GuildNoteUpdater.showUpdateNotification = false
            local s = spy.on(_G, "print")
            GuildNoteUpdater:ShowUpdateConfirmation("489 Feral Main")
            assert.spy(s).was_not_called()
            s:revert()
            GuildNoteUpdater.showUpdateNotification = true
        end)
    end)

    -- === Field visibility toggles (#28) ===
    describe("field visibility toggles", function()
        before_each(function()
            GuildNoteUpdater.enabledCharacters[charKey] = true
            GuildNoteUpdater.enableItemLevel[charKey] = nil   -- nil = true via ~= false
            GuildNoteUpdater.enableMainAlt[charKey] = nil     -- nil = true via ~= false
            GuildNoteUpdater.enableSpec[charKey] = true
            GuildNoteUpdater.enableProfessions[charKey] = false
            GuildNoteUpdater.mainOrAlt[charKey] = "Main"
            GuildNoteUpdater.notePrefix[charKey] = nil
            GuildNoteUpdater.itemLevelType[charKey] = "Overall"
            GuildNoteUpdater.specUpdateMode[charKey] = "Automatically"
            MockData.itemLevel = { overall = 489.5, equipped = 485.2 }
            MockData.spec.index = 2
        end)

        it("includes item level by default (nil = true)", function()
            local note = GuildNoteUpdater:BuildNoteString(charKey)
            assert.is_truthy(note:find("489"))
        end)

        it("excludes item level when enableItemLevel is false", function()
            GuildNoteUpdater.enableItemLevel[charKey] = false
            local note = GuildNoteUpdater:BuildNoteString(charKey)
            assert.is_falsy(note and note:match("%d%d%d"))
        end)

        it("includes main/alt by default (nil = true)", function()
            local note = GuildNoteUpdater:BuildNoteString(charKey)
            assert.is_truthy(note:find("Main"))
        end)

        it("excludes main/alt when enableMainAlt is false", function()
            GuildNoteUpdater.enableMainAlt[charKey] = false
            local note = GuildNoteUpdater:BuildNoteString(charKey)
            assert.is_falsy(note and note:find("Main"))
        end)

        it("returns nil when all visible fields produce an empty note", function()
            GuildNoteUpdater.enableItemLevel[charKey] = false
            GuildNoteUpdater.enableSpec[charKey] = false
            GuildNoteUpdater.enableMainAlt[charKey] = false
            -- enableProfessions already false, no prefix
            local note = GuildNoteUpdater:BuildNoteString(charKey)
            assert.is_nil(note)
        end)

        it("note without ilvl still includes spec and main/alt", function()
            GuildNoteUpdater.enableItemLevel[charKey] = false
            local note = GuildNoteUpdater:BuildNoteString(charKey)
            assert.is_truthy(note and note:find("Feral"))
            assert.is_truthy(note and note:find("Main"))
        end)

        it("note without main/alt still includes ilvl and spec", function()
            GuildNoteUpdater.enableMainAlt[charKey] = false
            local note = GuildNoteUpdater:BuildNoteString(charKey)
            assert.is_truthy(note and note:find("489"))
            assert.is_truthy(note and note:find("Feral"))
            assert.is_falsy(note and note:find("Main"))
        end)
    end)

    -- === Note lock (#24) ===
    describe("note lock", function()
        before_each(function()
            GuildNoteUpdater.previousNote = ""
            MockData.updatedNotes = {}
            MockData.inCombat = false
            GuildNoteUpdater.pendingCombatUpdate = false
            GuildNoteUpdater.enabledCharacters[charKey] = true
            GuildNoteUpdater.noteLocked[charKey] = false
            GuildNoteUpdater.enableItemLevel[charKey] = nil
            GuildNoteUpdater.enableMainAlt[charKey] = nil
            GuildNoteUpdater.enableSpec[charKey] = true
            GuildNoteUpdater.enableProfessions[charKey] = false
            GuildNoteUpdater.mainOrAlt[charKey] = "Main"
            GuildNoteUpdater.notePrefix[charKey] = nil
            GuildNoteUpdater.itemLevelType[charKey] = "Overall"
            GuildNoteUpdater.specUpdateMode[charKey] = "Automatically"
            MockData.itemLevel = { overall = 489.5, equipped = 485.2 }
            MockData.spec.index = 2
        end)

        it("writes note normally when not locked", function()
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_not_nil(MockData.updatedNotes[1])
        end)

        it("skips note write when note is locked", function()
            GuildNoteUpdater.noteLocked[charKey] = true
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_nil(MockData.updatedNotes[1])
        end)

        it("lock is per-character and does not affect other characters", function()
            GuildNoteUpdater.noteLocked[charKey] = true
            GuildNoteUpdater.noteLocked["OtherChar-Realm"] = false
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_nil(MockData.updatedNotes[1])  -- current char locked
        end)

        it("unlocking allows note to be written again", function()
            GuildNoteUpdater.noteLocked[charKey] = true
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_nil(MockData.updatedNotes[1])
            GuildNoteUpdater.noteLocked[charKey] = false
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_not_nil(MockData.updatedNotes[1])
        end)
    end)

    -- === UpdateNotePreview (FEAT-001) ===
    describe("UpdateNotePreview", function()
        before_each(function()
            GuildNoteUpdater.enabledCharacters[charKey] = true
            GuildNoteUpdater.enableProfessions[charKey] = true
            GuildNoteUpdater.mainOrAlt[charKey] = "Main"
            GuildNoteUpdater.enableSpec[charKey] = true
            MockData.itemLevel = { overall = 489.5, equipped = 485.2 }
            MockData.spec.index = 2
        end)

        it("does not crash when called normally", function()
            assert.has_no.errors(function()
                GuildNoteUpdater:UpdateNotePreview()
            end)
        end)

        it("does not crash when character is disabled", function()
            GuildNoteUpdater.enabledCharacters[charKey] = false
            assert.has_no.errors(function()
                GuildNoteUpdater:UpdateNotePreview()
            end)
        end)
    end)
end)
