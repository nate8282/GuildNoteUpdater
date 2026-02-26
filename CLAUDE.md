# GuildNoteUpdater - Claude Code Project Guide

## Project Overview
World of Warcraft addon that automatically updates guild notes with character item level, specialization, professions, and main/alt status. Written in Lua targeting WoW Retail (Interface 120000 / Patch 12.0.0 Midnight).

## Repository
- GitHub: nate8282/GuildNoteUpdater
- CurseForge Project ID: 1096987
- License: MIT

## Project Structure
```
GuildNoteUpdater/
├── GuildNoteUpdater.toc       # Addon manifest (Interface version, metadata, file list)
├── GuildNoteUpdater.lua        # All addon logic (single-file addon)
├── GuildNoteUpdater.xml        # UI frame definitions
├── .busted                     # Busted test framework config
├── .luacheckrc                 # Luacheck linting config with WoW globals
├── .gitignore
├── DEPRECATED_APIS.md          # ⚠️ Removed/deprecated WoW APIs and their replacements
├── spec/
│   ├── wow_api_mock.lua        # WoW API mock layer for busted tests
│   └── guild_note_updater_spec.lua  # Busted test suite
├── tests/
│   └── test_addon.lua          # Legacy unit tests (kept for backwards compat)
├── .github/
│   └── workflows/
│       ├── test.yml            # CI: Busted tests + legacy tests + Luacheck
│       └── release.yml         # Release: BigWigsMods/packager -> CurseForge + GitHub
├── CONTRIBUTING.md
├── README.md
├── LICENSE
└── World_of_Warcraft_API_Reference_for_Patch_12_0_0__Midnight_.md
```

## Development Workflow

### Branching Strategy
- `main` - stable, release-ready code
- Feature branches: `feature/<short-description>`
- Bug fix branches: `fix/<short-description>`
- Always branch from `main`, PR back to `main`

### Commit Guidelines
- Never commit as "Claude" or reference AI tools in commit messages
- Use git config: `N8 <52011990+nate8282@users.noreply.github.com>`
- Commit messages: imperative mood, concise ("Add profession toggle", "Fix nil error in spec lookup")
- Only commit when explicitly asked

### Before Every Commit
1. Run busted tests: `busted --verbose` (or `lua5.3 tests/test_addon.lua` as fallback)
2. Run linter: `luacheck GuildNoteUpdater.lua` (uses `.luacheckrc` automatically)
3. Verify all tests pass and no lint errors

### Before Writing WoW API Code
- **Check `DEPRECATED_APIS.md` first** — if an API you plan to use is listed there, use the documented replacement instead
- When you discover a newly broken/removed API in-game, add it to `DEPRECATED_APIS.md` immediately (old code, error text, replacement, notes), then update mocks and `.luacheckrc`

### Versioning & Releasing
- `MAJOR.0.0` = huge feature, `X.MINOR.0` = regular feature, `X.Y.PATCH` = bug fix
- **Version checklist — update ALL of these on every release:**
  1. `GuildNoteUpdater.toc` → `## Version: X.Y.Z`
  2. UI version display → reads from `.toc` automatically via `C_AddOns.GetAddOnMetadata`
  3. PR title → `vX.Y.Z - ...`
  4. Git tag → `vX.Y.Z` (push to trigger release pipeline)
  5. GitHub Release + CurseForge → auto-published by BigWigsMods/packager on tag push
- Requires `CF_API_KEY` secret in GitHub repo settings
- Current: v1.9.1

## Coding Standards

### Lua Style
- 4-space indentation
- `camelCase` for function and variable names
- Global addon frame: `GuildNoteUpdater = CreateFrame("Frame")`
- Per-character settings keyed by `"Name-RealmNoSpaces"` format
- Guild note max **31 characters** - always truncate gracefully

### WoW Addon Patterns
- Use `C_Timer.After(seconds, fn)` for deferred work after events
- Register events with `frame:RegisterEvent("EVENT_NAME")`
- Handle events via `frame:SetScript("OnEvent", handler)`
- SavedVariables persist between sessions (declared in .toc)
- Use `UIDropDownMenu_*` API for dropdown menus
- Frame templates: `BasicFrameTemplateWithInset`, `UICheckButtonTemplate`, `InputBoxTemplate`

### Testing
- **Primary**: Busted framework in `spec/` directory
  - Mock helper: `spec/wow_api_mock.lua` (loaded automatically via `.busted` config)
  - Tests: `spec/guild_note_updater_spec.lua`
  - Run: `busted --verbose`
- **Legacy**: Custom runner in `tests/test_addon.lua`
  - Run: `lua5.3 tests/test_addon.lua`
- **CI**: Both test suites run on push/PR to main via GitHub Actions
- **Linting**: Luacheck with `.luacheckrc` (no inline args needed)

### Key Constraints
- This addon is NOT affected by 12.0.0 Secret Values (guild/character info APIs are safe)
- Must work without any external Lua libraries (WoW provides its own Lua 5.1 runtime)
- All UI must use Blizzard frame templates and API
- No C/native code - pure Lua only

## WoW API Reference
For full API documentation, read: `World_of_Warcraft_API_Reference_for_Patch_12_0_0__Midnight_.md`

## Skills
- `wow-api-reference` - Quick lookup of WoW API functions, structures, events, and 12.0.0 restrictions
