# WoW Deprecated and Removed APIs

**Check this file before writing any WoW API code.** If you are about to use an API listed here, use the documented replacement instead.

---

## Removed APIs

### `GameTooltip:HookScript("OnTooltipSetUnit", callback)`

| Field | Detail |
|---|---|
| **Removed in** | WoW Retail 9.0 (Shadowlands) |
| **In-game error** | `GameTooltip:HookScript(): Doesn't have a "OnTooltipSetUnit" script` |
| **Discovered** | v1.8.0 development, bug reported on Patch 12.0.0 (Midnight) |

**Old code (DO NOT USE):**
```lua
GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip, ...)
    local name = UnitName("mouseover")
    -- ...
end)
```

**Replacement:** `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, callback)`
```lua
TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
    local unitName = data and data.name
    -- ...
end)
```

**Notes:**
- `data.name` is the unit name (equivalent to old `UnitName("mouseover")`)
- Guard with `if not TooltipDataProcessor then return end` for safety
- Globals needed: `TooltipDataProcessor`, `Enum` (add to `.luacheckrc` read_globals)
- Mock for tests: see `spec/wow_api_mock.lua` and `tests/test_addon.lua`

---

### `GuildRosterSetPublicNote(index, note)`

| Field | Detail |
|---|---|
| **Removed in** | WoW Retail 12.0.0 (Midnight) |
| **In-game error** | `attempt to call global 'GuildRosterSetPublicNote' (a nil value)` |
| **Discovered** | v1.14.1, reported on Patch 12.0.1 |

**Old code (DO NOT USE):**
```lua
GuildRosterSetPublicNote(guildIndex, newNote)
```

**Replacement:** `C_GuildInfo.SetNote(guid, note, isPublic)`
```lua
local _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, guid = GetGuildRosterInfo(guildIndex)
if guid then
    C_GuildInfo.SetNote(guid, newNote, true)  -- true = public note
end
```

**Notes:**
- New API takes a player GUID (17th return value of `GetGuildRosterInfo`) instead of a roster index
- `C_GuildInfo` was already in `.luacheckrc` read_globals — no change needed there
- `GuildRosterSetPublicNote` must be removed from `.luacheckrc` read_globals
- Update mock: add `guid` field to mock guild members, add `C_GuildInfo.SetNote` stub

---

## Workflow

When discovering a new deprecated/removed API:
1. Fix the code to use the replacement
2. Add an entry to this file with: removed version, error text, old code, new code, notes
3. Update mocks in `spec/wow_api_mock.lua` and `tests/test_addon.lua`
4. Update `.luacheckrc` if new globals are needed
