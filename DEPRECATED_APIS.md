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

## Workflow

When discovering a new deprecated/removed API:
1. Fix the code to use the replacement
2. Add an entry to this file with: removed version, error text, old code, new code, notes
3. Update mocks in `spec/wow_api_mock.lua` and `tests/test_addon.lua`
4. Update `.luacheckrc` if new globals are needed
