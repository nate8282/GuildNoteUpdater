-- GuildNoteUpdater busted test suite
-- Run with: busted --verbose

dofile("GuildNoteUpdater.lua")

describe("GuildNoteUpdater", function()
    local charKey

    setup(function()
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
end)
