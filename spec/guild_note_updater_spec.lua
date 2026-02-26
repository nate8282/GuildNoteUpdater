-- GuildNoteUpdater busted test suite
-- Run with: busted --verbose

dofile("GuildNoteUpdater.lua")

describe("GuildNoteUpdater", function()
    local charKey

    setup(function()
        UISpecialFrames = {}
        GuildNoteUpdaterSettings = nil
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

    -- === GetSpecForNote ===
    describe("GetSpecForNote", function()
        after_each(function()
            GuildNoteUpdater.useRoleAbbreviation[charKey] = false
            MockData.spec.index = 2
        end)

        it("returns spec name when useRoleAbbreviation is false", function()
            GuildNoteUpdater.useRoleAbbreviation[charKey] = false
            assert.are.equal("Feral", GuildNoteUpdater:GetSpecForNote(charKey))
        end)

        it("returns D for DPS spec when useRoleAbbreviation is true", function()
            GuildNoteUpdater.useRoleAbbreviation[charKey] = true
            MockData.spec.index = 2  -- Feral = DAMAGER
            assert.are.equal("D", GuildNoteUpdater:GetSpecForNote(charKey))
        end)

        it("returns T for tank spec when useRoleAbbreviation is true", function()
            GuildNoteUpdater.useRoleAbbreviation[charKey] = true
            MockData.spec.index = 3  -- Guardian = TANK
            assert.are.equal("T", GuildNoteUpdater:GetSpecForNote(charKey))
        end)

        it("returns H for healer spec when useRoleAbbreviation is true", function()
            GuildNoteUpdater.useRoleAbbreviation[charKey] = true
            MockData.spec.index = 4  -- Restoration = HEALER
            assert.are.equal("H", GuildNoteUpdater:GetSpecForNote(charKey))
        end)

        it("returns nil when GetSpecialization returns nil", function()
            MockData.spec.index = nil
            assert.is_nil(GuildNoteUpdater:GetSpecForNote(charKey))
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
            GuildNoteUpdater.useRoleAbbreviation[charKey] = false
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

        it("uses role abbreviation when enabled", function()
            GuildNoteUpdater.useRoleAbbreviation[charKey] = true
            MockData.spec.index = 2  -- DAMAGER
            local note = GuildNoteUpdater:BuildNoteString(charKey)
            assert.is_truthy(note:find(" D ") or note:find(" D$"))
            assert.is_falsy(note:find("Feral"))
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
            GuildNoteUpdater.enabledCharacters[charKey] = true
            GuildNoteUpdater.enableProfessions[charKey] = true
            GuildNoteUpdater.mainOrAlt[charKey] = "Main"
            GuildNoteUpdater.notePrefix[charKey] = nil
            GuildNoteUpdater.itemLevelType[charKey] = "Overall"
            GuildNoteUpdater.specUpdateMode[charKey] = "Automatically"
            GuildNoteUpdater.enableSpec[charKey] = true
            GuildNoteUpdater.useRoleAbbreviation[charKey] = false
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
    end)

    -- === Truncation ===
    describe("truncation", function()
        before_each(function()
            GuildNoteUpdater.previousNote = ""
            MockData.updatedNotes = {}
            GuildNoteUpdater.enabledCharacters[charKey] = true
            GuildNoteUpdater.enableProfessions[charKey] = true
            GuildNoteUpdater.mainOrAlt[charKey] = "Main"
            GuildNoteUpdater.itemLevelType[charKey] = "Overall"
            GuildNoteUpdater.specUpdateMode[charKey] = "Automatically"
            GuildNoteUpdater.enableSpec[charKey] = true
            GuildNoteUpdater.useRoleAbbreviation[charKey] = false
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
            GuildNoteUpdater.useRoleAbbreviation[charKey] = false
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

        it("parses a note with role abbreviation T", function()
            local result = GuildNoteUpdater:ParseGuildNote("489 T LW Main")
            assert.are.equal("489", result.ilvl)
            assert.are.equal("Tank", result.role)
            assert.are.equal("Main", result.mainAlt)
        end)

        it("parses a note with role abbreviation H", function()
            local result = GuildNoteUpdater:ParseGuildNote("512 H Alch Herb Alt")
            assert.are.equal("512", result.ilvl)
            assert.are.equal("Healer", result.role)
            assert.are.equal("Alt", result.mainAlt)
        end)

        it("parses a note with role abbreviation D", function()
            local result = GuildNoteUpdater:ParseGuildNote("500 D JC Min Main")
            assert.are.equal("500", result.ilvl)
            assert.are.equal("DPS", result.role)
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
            for _, name in ipairs(UISpecialFrames) do
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

    -- === Role abbreviation in BuildNoteString (FEAT-004) ===
    describe("role abbreviation in notes", function()
        before_each(function()
            GuildNoteUpdater.previousNote = ""
            MockData.updatedNotes = {}
            GuildNoteUpdater.enabledCharacters[charKey] = true
            GuildNoteUpdater.enableProfessions[charKey] = false
            GuildNoteUpdater.mainOrAlt[charKey] = "<None>"
            GuildNoteUpdater.notePrefix[charKey] = nil
            GuildNoteUpdater.itemLevelType[charKey] = "Overall"
            GuildNoteUpdater.specUpdateMode[charKey] = "Automatically"
            GuildNoteUpdater.enableSpec[charKey] = true
            MockData.itemLevel = { overall = 489.5, equipped = 485.2 }
        end)

        it("uses full spec name when role abbreviation is off", function()
            GuildNoteUpdater.useRoleAbbreviation[charKey] = false
            MockData.spec.index = 2
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_truthy(MockData.updatedNotes[1]:find("Feral"))
        end)

        it("uses D when role abbreviation is on for DPS spec", function()
            GuildNoteUpdater.useRoleAbbreviation[charKey] = true
            MockData.spec.index = 2  -- Feral = DAMAGER
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_truthy(MockData.updatedNotes[1]:find("D"))
            assert.is_falsy(MockData.updatedNotes[1]:find("Feral"))
        end)

        it("uses T when role abbreviation is on for tank spec", function()
            GuildNoteUpdater.useRoleAbbreviation[charKey] = true
            MockData.spec.index = 3  -- Guardian = TANK
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_truthy(MockData.updatedNotes[1]:find("T"))
        end)

        it("uses H when role abbreviation is on for healer spec", function()
            GuildNoteUpdater.useRoleAbbreviation[charKey] = true
            MockData.spec.index = 4  -- Restoration = HEALER
            GuildNoteUpdater:UpdateGuildNote()
            assert.is_truthy(MockData.updatedNotes[1]:find("H"))
        end)

        it("saves characters compared to full spec name", function()
            GuildNoteUpdater.useRoleAbbreviation[charKey] = false
            MockData.spec.index = 4  -- Restoration
            local fullNote = GuildNoteUpdater:BuildNoteString(charKey)

            GuildNoteUpdater.useRoleAbbreviation[charKey] = true
            local shortNote = GuildNoteUpdater:BuildNoteString(charKey)

            assert.is_truthy(#shortNote < #fullNote)
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
            GuildNoteUpdater.useRoleAbbreviation[charKey] = false
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
            GuildNoteUpdater.useRoleAbbreviation[charKey] = false
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
            GuildNoteUpdater.useRoleAbbreviation[charKey] = false
            MockData.itemLevel = { overall = 489.5, equipped = 485.2 }
            MockData.spec.index = 2
            assert.has_no.errors(function()
                GuildNoteUpdater:UpdateGuildNote()
            end)
            assert.is_not_nil(MockData.updatedNotes[1])
        end)
    end)

    -- === Settings initialization ===
    describe("InitializeSettings", function()
        it("creates default settings when none exist", function()
            GuildNoteUpdaterSettings = nil
            GuildNoteUpdater:InitializeSettings()
            assert.is_not_nil(GuildNoteUpdaterSettings)
            assert.is_table(GuildNoteUpdaterSettings.enabledCharacters)
            assert.is_table(GuildNoteUpdaterSettings.useRoleAbbreviation)
            assert.is_table(GuildNoteUpdaterSettings.enableSpec)
        end)

        it("preserves existing settings on reload", function()
            GuildNoteUpdaterSettings = {
                enabledCharacters = { ["Test-Realm"] = true },
                specUpdateMode = {}, selectedSpec = {},
                itemLevelType = {}, mainOrAlt = {},
                enableProfessions = {}, debugEnabled = false,
                notePrefix = {}, useRoleAbbreviation = {},
                enableSpec = {}, enableTooltipParsing = true,
            }
            GuildNoteUpdater:InitializeSettings()
            local chars = rawget(GuildNoteUpdater, "enabledCharacters")
            assert.is_table(chars)
            assert.is_true(chars["Test-Realm"])
        end)

        it("defaults enableTooltipParsing to true", function()
            GuildNoteUpdaterSettings = nil
            GuildNoteUpdater:InitializeSettings()
            assert.is_true(GuildNoteUpdater.enableTooltipParsing)
        end)

        it("defaults enableProfessions to true for new characters", function()
            GuildNoteUpdaterSettings = nil
            GuildNoteUpdater:InitializeSettings()
            local key = GuildNoteUpdater:GetCharacterKey()
            assert.is_true(GuildNoteUpdater.enableProfessions[key])
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
    end)

    -- === UpdateNotePreview (FEAT-001) ===
    describe("UpdateNotePreview", function()
        before_each(function()
            GuildNoteUpdater.enabledCharacters[charKey] = true
            GuildNoteUpdater.enableProfessions[charKey] = true
            GuildNoteUpdater.mainOrAlt[charKey] = "Main"
            GuildNoteUpdater.enableSpec[charKey] = true
            GuildNoteUpdater.useRoleAbbreviation[charKey] = false
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
