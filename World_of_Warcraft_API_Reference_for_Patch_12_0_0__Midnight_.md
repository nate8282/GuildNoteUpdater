# World of Warcraft API Reference for Patch 12.0.0 (Midnight)

The **Secret Values system** fundamentally transforms addon development in patch 12.0.0, making combat data inaccessible for computation while preserving UI customization. Released January 20, 2026 as the Midnight pre-patch, this represents the largest API change in WoW's historyâ€”dubbed the "Addon Apocalypse." Combat API functions now return opaque values that addons can display but cannot inspect, compare, or manipulate mathematically. The restrictions apply primarily in instanced content (raids, M+) and during combat, with Blizzard providing native replacement systems for cooldown tracking, boss warnings, and damage meters.

---

## The Secret Values system restricts combat data access

Secret values prevent addons from "knowing" combat information while still allowing display. When tainted (addon) code calls functions like `UnitHealth()`, the return value is marked secret.

**Operations FORBIDDEN on secret values:**
- Arithmetic operations (`health + 100`, `health * 0.5`)
- Comparisons and boolean tests (`health > 5000`, `if health then`)
- Concatenation (`"Health: " .. health`)
- Length operator (`#secretTable`)
- Use as table keys (`table[secretValue] = x`)
- Indexed access (`secretValue["field"]`)
- Function calls (`secretValue()`)

**Operations ALLOWED on secret values:**
- Storage in variables and table values
- Passing to Lua functions
- Passing to whitelisted native APIs (`StatusBar:SetValue(secretHealth)`)
- Using with Curve/Duration objects for display

### Testing functions for secret values
```lua
issecretvalue(value)      -- Returns true if value is secret
canaccesssecrets()        -- Returns false if caller cannot access secrets (tainted)
canaccessvalue(value)     -- Returns true if value is accessible
issecrettable(table)      -- Returns true if table is marked secret
canaccesstable(table)     -- Returns true if table is accessible
dropsecretaccess()        -- Removes secret access from calling function
```

### When secrets apply
Secrets are enforced based on `GetRestrictedActionStatus(restrictionType)`:
- **In combat** with non-player/pet units
- **In instances** (raids, M+, dungeons) â€” creature names, GUIDs, and IDs become secret
- **Never secret**: Player's secondary resources (Holy Power, Stagger, Maelstrom Weapon, Soul Fragments, Skyriding charges)
- **Whitelisted spells**: GCD (spell 61304), Combat Resurrection spells, player's own casts

---

## C_Spell namespace provides spell information

The C_Spell namespace (added 11.0.0) replaces deprecated spell functions. Many returns may be **secret in combat** for non-whitelisted spells.

### Core information functions
```lua
-- GetSpellInfo returns SpellInfo structure
spellInfo = C_Spell.GetSpellInfo(spellIdentifier)
-- spellIdentifier: number (spellID) or string (name, "name(subtext)", or link)

-- SpellInfo structure:
{
    name = "string",           -- Localized spell name
    iconID = number,           -- FileID of current icon
    originalIconID = number,   -- FileID for overridden spells
    castTime = number,         -- Cast time in milliseconds
    minRange = number,         -- Minimum range
    maxRange = number,         -- Maximum range
    spellID = number           -- Spell ID
}

-- Additional info functions:
name = C_Spell.GetSpellName(spellIdentifier)
description = C_Spell.GetSpellDescription(spellIdentifier)
iconID, originalIconID = C_Spell.GetSpellTexture(spellIdentifier)
subtext = C_Spell.GetSpellSubtext(spellIdentifier)
spellLink = C_Spell.GetSpellLink(spellIdentifier [, glyphID])
```

### Cooldown and charge functions (may return secrets)
```lua
-- GetSpellCooldown returns SpellCooldownInfo
spellCooldownInfo = C_Spell.GetSpellCooldown(spellIdentifier)

-- SpellCooldownInfo structure (12.0.0):
{
    startTime = number,    -- GetTime() when cooldown started; 0 if inactive
    duration = number,     -- Cooldown duration in seconds
    isEnabled = boolean,   -- false if spell is active (buff running)
    modRate = number,      -- Haste modifier for cooldown rate
    endTime = number       -- NEW in 12.0.0: Direct end time
}

-- GetSpellCharges returns SpellChargeInfo
chargeInfo = C_Spell.GetSpellCharges(spellIdentifier)

-- SpellChargeInfo structure:
{
    currentCharges = number,
    maxCharges = number,
    cooldownStartTime = number,
    cooldownDuration = number,
    chargeModRate = number
}
```

### Usability and state functions
```lua
isUsable, insufficientPower = C_Spell.IsSpellUsable(spellIdentifier)
-- Returns may be SECRET in combat

isCurrentSpell = C_Spell.IsCurrentSpell(spellIdentifier)
inRange = C_Spell.IsSpellInRange(spellIdentifier [, targetUnit])
-- inRange: true=in range, false=out of range, nil=invalid check
-- May be SECRET for enemy units in combat

-- Power cost information
powerCosts = C_Spell.GetSpellPowerCost(spellIdentifier)
-- Returns array of SpellPowerCostInfo:
{
    type = number,            -- PowerType enum value
    name = string,            -- Localized power name
    cost = number,
    minCost = number,
    requiredAuraID = number,
    costPercent = number,
    costPerSec = number       -- For channeled spells
}
```

---

## C_SpellBook namespace manages spellbook access

```lua
-- Get spell info from spellbook slot
spellBookItemInfo = C_SpellBook.GetSpellBookItemInfo(slotIndex, spellBank)
-- spellBank: Enum.SpellBookSpellBank.Player or Enum.SpellBookSpellBank.Pet

-- SpellBookItemInfo structure:
{
    itemType = Enum.SpellBookItemType,  -- Spell, FutureSpell, Flyout, PetAction
    actionID = number,                   -- Spell ID or Flyout ID
    spellID = number,
    iconID = number,
    name = string,
    subName = string,
    isOffSpec = boolean,
    isPassive = boolean
}

-- Tab/skill line functions
numSkillLines = C_SpellBook.GetNumSpellBookSkillLines()
skillLineInfo = C_SpellBook.GetSpellBookSkillLineInfo(skillLineIndex)

-- SkillLineInfo structure:
{
    name = string,              -- Tab name
    iconID = number,
    itemIndexOffset = number,   -- Items before this tab
    numSpellBookItems = number,
    isGuild = boolean,
    offSpecID = number,         -- 0 if active spec
    shouldHide = boolean,
    specID = number
}

-- Pet spells
numPetSpells, petNameToken = C_SpellBook.HasPetSpells()

-- Other functions
isKnown = C_SpellBook.IsSpellKnown(spellID [, spellBank])
levelLearned = C_SpellBook.GetSpellBookItemLevelLearned(slotIndex, spellBank)
spellIDs = C_SpellBook.GetCurrentLevelSpells(level)
```

---

## C_UnitAuras handles buff and debuff data

The AuraData system (10.0+) replaces deprecated `UnitAura()`. In 12.0.0, aura vectors and AuraInstanceIDs are **no longer secret**, but aura contents remain secret during combat.

### Primary aura functions
```lua
-- By index
aura = C_UnitAuras.GetAuraDataByIndex(unitToken, index [, filter])
aura = C_UnitAuras.GetBuffDataByIndex(unitToken, index [, filter])   -- Alias with "HELPFUL"
aura = C_UnitAuras.GetDebuffDataByIndex(unitToken, index [, filter]) -- Alias with "HARMFUL"

-- By aura instance ID (most efficient for updates)
aura = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)

-- By spell name
aura = C_UnitAuras.GetAuraDataBySpellName(unitToken, spellName [, filter])

-- NEW in 12.0.0: Duration remaining
remaining = GetAuraDurationRemainingByAuraInstanceID(unit, auraInstanceID)
```

### AuraData structure
```lua
{
    name = string,
    icon = number,              -- Texture FileID
    count = number,             -- Stack count
    dispelType = string,        -- "Curse", "Disease", "Magic", "Poison", or nil
    duration = number,
    expirationTime = number,    -- GetTime() format
    source = string,            -- UnitId of caster
    isStealable = boolean,
    nameplateShowPersonal = boolean,
    spellId = number,
    canApplyAura = boolean,
    isBossDebuff = boolean,
    castByPlayer = boolean,
    nameplateShowAll = boolean,
    timeMod = number,
    auraInstanceID = number,    -- No longer secret in 12.0.0
    applications = number
}
```

### Filter options
Combine with `|` or space: `HELPFUL`, `HARMFUL`, `PLAYER`, `RAID`, `CANCELABLE`, `NOT_CANCELABLE`, `INCLUDE_NAME_PLATE_ONLY`

### UNIT_AURA event processing (12.0.0)
```lua
local function OnUnitAura(self, event, unit, info)
    if info.isFullUpdate then
        -- Full refresh needed, iterate all auras
        return
    end
    
    if info.addedAuras then
        for _, aura in pairs(info.addedAuras) do
            -- aura contains full AuraData
        end
    end
    
    if info.updatedAuraInstanceIDs then
        for _, auraInstanceID in pairs(info.updatedAuraInstanceIDs) do
            local aura = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
        end
    end
    
    if info.removedAuraInstanceIDs then
        for _, auraInstanceID in pairs(info.removedAuraInstanceIDs) do
            -- Cleanup tracking
        end
    end
end
```

---

## Unit functions return secret values in combat

### Health and power functions (NEW percentage variants in 12.0.0)
```lua
-- Traditional functions (may return secrets)
health = UnitHealth(unit)
healthMax = UnitHealthMax(unit)     -- NOT secret for player units
power = UnitPower(unit [, powerType [, unmodified]])
powerMax = UnitPowerMax(unit, powerType)  -- NOT secret for player units

-- NEW 12.0.0 percentage functions (return secrets, accept curves)
healthPercent = UnitHealthPercent(unit [, curve])
-- Returns 0-1 percentage, or curve evaluation if curve provided

healthMissing = UnitHealthMissing(unit)
powerPercent = UnitPowerPercent(unit, powerType [, curve])
powerMissing = UnitPowerMissing(unit, powerType)
```

### Cast information functions
```lua
name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castID, 
notInterruptible, spellId = UnitCastingInfo(unit)

name, text, texture, startTimeMS, endTimeMS, isTradeSkill, 
notInterruptible, spellId, isEmpowered, numEmpowerStages = UnitChannelInfo(unit)

-- 12.0.0: Empowered cast data (stages, percentages) no longer secret
-- 12.0.0: New spell sequence ID (never secret) for cast bars
```

### Unit comparison
```lua
isSame = UnitIsUnit(unit1, unit2)
-- 12.0.0: Returns NON-SECRET when comparing: target, focus, mouseover, 
-- softenemy, softinteract, softfriend
```

---

## Combat log events have restricted access in 12.0.0

COMBAT_LOG_EVENT_UNFILTERED remains available but with restrictions during instanced content.

### Accessing combat log data
```lua
local function OnEvent(self, event)
    local timestamp, subevent, hideCaster, sourceGUID, sourceName, 
          sourceFlags, sourceRaidFlags, destGUID, destName, 
          destFlags, destRaidFlags, ... = CombatLogGetCurrentEventInfo()
end
```

### Base payload parameters
| Parameter | Type | Description |
|-----------|------|-------------|
| timestamp | number | Unix time with milliseconds |
| subevent | string | Event type (SPELL_DAMAGE, etc.) |
| hideCaster | boolean | Caster visibility flag |
| sourceGUID/destGUID | string | Unit GUIDs (may be secret in instances) |
| sourceName/destName | string | Unit names (may be secret in instances) |
| sourceFlags/destFlags | number | Unit type/controller/reaction bits |
| sourceRaidFlags/destRaidFlags | number | Raid target icon bits |

### Common subevents (position 12+ parameters vary)
- **SPELL_DAMAGE**: spellId, spellName, spellSchool, amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing
- **SPELL_HEAL**: spellId, spellName, spellSchool, amount, overhealing, absorbed, critical
- **SPELL_AURA_APPLIED/REMOVED**: spellId, spellName, spellSchool, auraType
- **UNIT_DIED**: No additional parameters

### 12.0.0 restrictions
- Combat log restricted to **50 yards** in open world (raids/dungeons unrestricted range)
- Unit names and GUIDs are **secret in instances**
- Combat log chat tab messages converted to unparseable KStrings
- Real-time parsing for decision-making effectively blocked

---

## C_Traits and C_ClassTalents manage the talent system

### C_Traits core functions
```lua
-- Config management
configID = C_ClassTalents.GetActiveConfigID()
configInfo = C_Traits.GetConfigInfo(configID)
treeIDs = configInfo.treeIDs  -- Usually 1 tree per spec

-- Tree and node information
nodeIDs = C_Traits.GetTreeNodes(treeID)
nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
entryInfo = C_Traits.GetEntryInfo(configID, entryID)
defInfo = C_Traits.GetDefinitionInfo(definitionID)

-- Import/Export
importString = C_Traits.GenerateImportString(configID)
importString = C_Traits.GenerateInspectImportString("target")
```

### TraitNodeInfo structure
```lua
{
    ID = number,
    posX = number,
    posY = number,
    type = Enum.TraitNodeType,      -- Single(0), Tiered(1), Selection(2), SubTreeSelection(3)
    maxRanks = number,
    flags = number,
    groupIDs = number[],
    visibleEdges = table[],
    conditionIDs = number[],
    entryIDs = number[],            -- All entry options
    entryIDsWithCommittedRanks = number[],
    canPurchaseRank = boolean,
    canRefundRank = boolean,
    isAvailable = boolean,
    isVisible = boolean,
    activeRank = number,
    currentRank = number,
    subTreeID = number,             -- For hero talent nodes
    subTreeActive = boolean,
    activeEntry = { entryID = number, rank = number }
}
```

### Hero talent functions
```lua
heroSpecID = C_ClassTalents.GetActiveHeroTalentSpec()
subTreeIDs, requiredLevel = C_ClassTalents.GetHeroTalentSpecsForClassSpec([configID [, classSpecID]])
hasUnspent, numPoints = C_ClassTalents.HasUnspentHeroTalentPoints()
```

---

## Action bar APIs provide slot information

```lua
-- Action info
actionType, id, subType = GetActionInfo(slot)
-- actionType: "spell", "item", "macro", "companion", "equipmentset", "flyout"

-- Cooldown info (may return secrets)
start, duration, enable, modRate = GetActionCooldown(slot)

-- State checks
hasAction = HasAction(slot)
inRange = IsActionInRange(slot [, unit])  -- 1=in range, 0=out, nil=N/A
texture = GetActionTexture(slot)
count = GetActionCount(slot)
text = GetActionText(slot)
```

---

## Protected functions require hardware events or secure execution

### Categories of restrictions
| Category | Description |
|----------|-------------|
| PROTECTED | Cannot be called by insecure code ever |
| HW/HWEVENT | Requires hardware event (click/keypress) |
| NOCOMBAT | Blocked from insecure code during combat |
| SECUREFRAME | Cannot modify protected frames in combat |

### Fully protected functions (never callable by addons)
```lua
-- Movement
JumpOrAscendStart(), MoveForwardStart/Stop(), MoveBackwardStart/Stop()
StrafeLeftStart/Stop(), StrafeRightStart/Stop(), TurnLeftStart/Stop()
TurnRightStart/Stop(), ToggleAutoRun(), ToggleRun()

-- Spell casting
CastSpellByName("name"), CastSpellByID(spellID), CastSpell(index, bookType)
UseAction(slot), CastShapeshiftForm(index)

-- Targeting
TargetUnit("unit"), AssistUnit("unit"), AttackTarget()
FocusUnit("unit"), ClearFocus(), TargetNearestEnemy()

-- Actions
ActionButtonDown(id), ActionButtonUp(id)
PetAttack(), FollowUnit("unit")
```

### NOCOMBAT functions (blocked during combat)
```lua
CreateMacro(), EditMacro(), DeleteMacro(), SetMacro()
PickupAction(slot), PickupSpell(), PlaceAction(slot)
SetBinding(), SetBindingClick(), SetBindingSpell()
SaveBindings(), LoadBindings()
```

### Combat lockdown timing
```lua
inLockdown = InCombatLockdown()
-- Begins: After PLAYER_REGEN_DISABLED fires
-- Ends: Before PLAYER_REGEN_ENABLED fires
```

### SecureActionButtonTemplate in 12.0.0
```lua
local btn = CreateFrame("Button", "MyButton", UIParent, "SecureActionButtonTemplate")
btn:SetAttribute("type", "spell")
btn:SetAttribute("spell", "Flash Heal")
btn:SetAttribute("unit", "target")
btn:RegisterForClicks("AnyUp", "AnyDown")

-- Type attributes: action, spell, item, macro, target, focus, assist, pet, cancelaura, stop, click

-- Modifier variants
btn:SetAttribute("shift-type1", "spell")
btn:SetAttribute("ctrl-spell", "Power Word: Shield")

-- 12.0.0 changes:
-- macrotext attribute limited to 255 characters
-- Macros cannot chain to other macros
-- SetAttribute() blocked on protected frames in combat
```

---

## Key events for combat addon development

### Combat state events
```lua
PLAYER_REGEN_DISABLED    -- Entering combat (no payload)
PLAYER_REGEN_ENABLED     -- Leaving combat (no payload)
```

### Spell events
```lua
SPELL_UPDATE_COOLDOWN: spellID, baseSpellID, category, startRecoveryCategory
-- spellID may be nil (update all cooldowns)
-- Cooldown data may be SECRET for non-whitelisted spells

UNIT_SPELLCAST_START: unitTarget, castGUID, spellID
UNIT_SPELLCAST_STOP: unitTarget, castGUID, spellID
UNIT_SPELLCAST_SUCCEEDED: unitTarget, castGUID, spellID
UNIT_SPELLCAST_CHANNEL_START: unitTarget, castGUID, spellID
UNIT_SPELLCAST_CHANNEL_STOP: unitTarget, castGUID, spellID
```

### Unit events
```lua
UNIT_HEALTH: unitTarget
UNIT_POWER_UPDATE: unitTarget, powerType
UNIT_AURA: unitTarget, updateInfo  -- updateInfo contains incremental changes
UNIT_TARGET: unitTarget
PLAYER_TARGET_CHANGED  -- No payload
```

### Encounter events
```lua
ENCOUNTER_START: encounterID, encounterName, difficultyID, groupSize
ENCOUNTER_END: encounterID, encounterName, difficultyID, groupSize, success
-- success: 1 for kill, 0 for wipe
```

### New 12.0.0 events
```lua
PARTY_KILL: attackerGUID, targetGUID
-- Both GUIDs secret when unit identity is restricted
```

---

## C_Timer provides non-blocking timers

```lua
-- Simple one-shot (non-cancelable)
C_Timer.After(seconds, callback)

-- Cancelable one-shot
timerHandle = C_Timer.NewTimer(seconds, callback)
timerHandle:Cancel()
timerHandle:IsCancelled()

-- Repeating ticker
tickerHandle = C_Timer.NewTicker(seconds, callback [, iterations])
-- iterations: nil for infinite

-- Example usage
local myTimer = C_Timer.NewTimer(3, function() print("Done") end)
if not myTimer:IsCancelled() then
    myTimer:Cancel()
end
```

### OnUpdate patterns
```lua
-- Basic throttled OnUpdate
local frame = CreateFrame("Frame")
local elapsed = 0
frame:SetScript("OnUpdate", function(self, delta)
    elapsed = elapsed + delta
    if elapsed > 0.1 then  -- 10 updates/second
        elapsed = 0
        -- Do work
    end
end)
```

---

## C_CurveUtil enables display of secret values

New in 12.0.0, Curve objects allow addons to display secret values without inspecting them.

```lua
-- Create color curve for health bar coloring
local colorCurve = C_CurveUtil.CreateColorCurve()
colorCurve:SetType(Enum.LuaCurveType.Linear)  -- or .Step
colorCurve:AddPoint(0.0, CreateColor(1, 0, 0, 1))  -- Red at 0%
colorCurve:AddPoint(0.5, CreateColor(1, 1, 0, 1))  -- Yellow at 50%
colorCurve:AddPoint(1.0, CreateColor(0, 1, 0, 1))  -- Green at 100%

-- Use with UnitHealthPercent
local color = UnitHealthPercent("target", colorCurve)
statusBar:GetStatusBarTexture():SetVertexColor(color:GetRGB())

-- Boolean-to-color conversion for secret booleans
color = C_CurveUtil.EvaluateColorFromBoolean(secretBool, trueColor, falseColor)
```

---

## C_DurationUtil provides time calculation objects

```lua
-- Create duration object
local duration = C_DurationUtil.CreateDuration()

-- Configure (cannot use secret values from tainted code)
duration:SetTimeSpan(startTime, endTime)
duration:SetTimeFromStart(startTime, durationSecs [, modRate])
duration:SetTimeFromEnd(endTime, durationSecs [, modRate])

-- Evaluate (returns secrets when appropriate)
elapsed = duration:GetElapsedDuration()
remaining = duration:GetRemainingDuration()
progress = duration:EvaluateElapsedProgress()
result = duration:EvaluateRemainingPercent(curve [, modifier])

-- Integration with UI elements
cooldownFrame:SetCooldownFromDurationObject(duration [, clearIfZero])
statusBar:SetTimerDuration(duration [, interpolation])
```

---

## Heal prediction calculator for display

```lua
local calculator = CreateUnitHealPredictionCalculator()
UnitGetDetailedHealPrediction(unit, unitDoingTheHealing, calculator)
-- Calculator populated with heal prediction and absorb data
```

---

## Additional namespaces for 12.0.0

### C_NamePlate
```lua
nameplate = C_NamePlate.GetNamePlateForUnit(unit [, isSecure])
nameplates = C_NamePlate.GetNamePlates([isSecure])
C_NamePlate.SetNamePlateFriendlySize(width, height)
-- Events: NAME_PLATE_UNIT_ADDED, NAME_PLATE_UNIT_REMOVED
```

### C_MythicPlus
```lua
C_MythicPlus.RequestMapInfo()  -- MUST call before other functions
seasonID = C_MythicPlus.GetCurrentSeason()
challengeMapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
weeklyReward, endOfRunReward = C_MythicPlus.GetRewardLevelForDifficultyLevel(level)
affixes = C_MythicPlus.GetCurrentAffixes()
```

### C_Map
```lua
uiMapID = C_Map.GetBestMapForUnit("player")
position = C_Map.GetPlayerMapPosition(uiMapID, unitToken)  -- RESTRICTED
mapInfo = C_Map.GetMapInfo(uiMapID)
continentID, worldPos = C_Map.GetWorldPosFromMapPos(uiMapID, mapPosition)
```

### C_Item and C_Container
```lua
-- Item info
itemName, itemLink, quality, iLevel, ... = C_Item.GetItemInfo(itemInfo)
itemID, itemType, subType, equipLoc, icon = C_Item.GetItemInfoInstant(itemInfo)

-- Container
containerInfo = C_Container.GetContainerItemInfo(bagIndex, slotIndex)
itemID = C_Container.GetContainerItemID(bagIndex, slotIndex)
numSlots = C_Container.GetContainerNumSlots(bagIndex)
numFree, bagFamily = C_Container.GetContainerNumFreeSlots(bagIndex)
```

---

## What addons can and cannot do in 12.0.0

### Addons CAN:
- **Customize UI appearance** (frames, colors, textures, positions)
- **Display secret values** via `StatusBar:SetValue()`, Curves, and Duration objects
- **Skin Blizzard systems** (Boss Warnings, Damage Meters, Cooldown Manager)
- **Manage bags, auctions, professions, achievements, guilds**
- **Customize nameplates** visually (not logically)
- **Track secondary resources** (Holy Power, Stagger, Maelstrom Weaponâ€”whitelisted)
- **Process combat logs post-fight** for analysis

### Addons CANNOT:
- **Make computational decisions** based on combat data
- **Parse combat log in real-time** for custom logic
- **Implement rotation helpers** or priority systems
- **Track enemy cooldowns** for strategic recommendations
- **Create WeakAuras-style conditional triggers** combining combat states
- **Send combat data** between players during encounters
- **Access creature names/GUIDs** in instances

---

## Blizzard's native replacement systems

| System | Function | Addon Interaction |
|--------|----------|-------------------|
| **Cooldown Manager** | Tracks abilities, buffs, defensives | Skinnable, extensible via addons |
| **Boss Warnings** | Timeline of boss abilities | Skinnable by DBM/BigWigs |
| **Damage Meters** | Server-validated DPS/HPS | Containers for custom skins |
| **Assisted Highlight** | Suggests next ability | API accessible, no GCD penalty for reading |
| **Single-Button Assistant** | Automated rotation (0.2-0.3s GCD penalty) | Accessibility feature only |
| **Combat Audio** | Built-in warning sounds | Limited addon access |

### DBM/BigWigs adaptation
Both major boss mods now use a "skin over Blizzard containers" approach, displaying customized versions of Blizzard's Boss Timeline system with familiar audio cues where possible.

---

## TOC requirements for 12.0.0

```
## Interface: 120000
```

**Critical**: Mainline addons without interface version **120000** or higher **will not load**. No player override is available.