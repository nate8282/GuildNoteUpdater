# Changelog

All notable changes to GuildNoteUpdater are documented here.

## [1.12.0] - 2026-02-25

### Added
- **`/gnu roster`** — prints a guild summary to chat: member count with GNU notes, average item level, Main/Alt counts, and profession coverage
- **`/gnu roster mains`** — same summary but item level average filtered to Mains only
- **Stale note warning in tooltips** — when hovering a guild member who is in your party/raid, a yellow warning appears if their note item level is 15+ levels below their live item level

---

## [1.11.0] - 2026-02-25

### Added
- **Minimap button** — click to toggle the settings panel, drag to reposition around the minimap edge. Can be hidden via the settings panel.
- **Configurable update trigger** — choose when notes are written:
  - *On Events* (default) — updates on login, equipment changes, and spec changes
  - *On Login Only* — only updates when you log in
  - *Manual Only* — never updates automatically; use `/gnu update` to force a write
- `/gnu update` slash command — forces an immediate note update regardless of trigger mode
- Custom scroll & quill icon for the minimap button

### Fixed
- Note not clearing when all "Show" fields are unchecked (was silently skipped, now clears the guild note)

---

## [1.10.0] - 2025-12

### Added
- **Per-field visibility toggles** — checkboxes to individually show or hide item level, spec, each profession, and main/alt in the guild note
- **Note lock** — lock the guild note to prevent the addon from overwriting it while still keeping your settings

---

## [1.9.1] - 2025-11

### Fixed
- Notification label text clipping at the right edge of the settings frame
- Notification label clipping fixed by shortening label text
- Guild note writes are now suppressed during combat lockdown

---

## [1.9.0] - 2025-11

### Added
- **Show update notification** setting — toggle the chat message that appears when your guild note is updated
- Addon version displayed in the settings panel title bar

---

## [1.8.0] - 2025-10

### Changed
- Removed role abbreviation (T/H/D) feature — spec name alone is used

### Fixed
- Tooltip hook updated to use `TooltipDataProcessor` API (WoW 9.0+ retail)
- Spacing between professions checkbox and spec label in settings

---

## [1.7.0] - 2025-09

### Added
- Live note preview in the settings panel with color-coded character counter
- Tooltip shows guild members' note when hovering their nameplate/unit frame
- Visual save confirmation message in chat when note is written
- Configurable spec display toggle (show or hide spec in note)
- Role abbreviation toggle (T/H/D prefix instead of full spec name) *(removed in v1.8.0)*
- ESC key closes the settings panel

### Fixed
- `PLAYER_EQUIPMENT_CHANGED` debounced to prevent 15+ redundant writes per gear swap
- Guard against item level 0 being written before inventory fully loads
- Note prefix now saved on focus-lost (not only on Enter key)
- Premature event registration at file scope removed

---

## [1.6.0] - 2025-08

### Added
- Cross-realm character support — settings are now keyed by `Name-Realm` so characters on different realms are tracked independently

### Fixed
- `strtrim` nil error
- Undefined `specDropdown` variable

---

## [1.5.0] - 2025-07

### Added
- CurseForge packaging via BigWigsMods/packager
- Automated unit tests and GitHub Actions CI

---

## [1.4] - 2025-06

### Added
- Updated TOC interface version to 120000 (Patch 12.0.0 Midnight)
- Community contributions: debug mode, enhancements from Issues #2 and #7

---

## [1.3] - 2024

### Fixed
- Automatic item level not updating correctly on armor changes

---

## [1.2] - 2024

### Added
- Additional features (profession display, main/alt label improvements)

### Changed
- Guild note format no longer uses hyphens as separators

---

## [1.1] - 2024

### Added
- Initial public release
- Auto-updates guild note with item level, specialization, professions, and main/alt status on login and gear/spec changes
