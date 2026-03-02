# Guild Note Updater

> **This addon is abandoned and no longer maintained. See below for why.**

Guild Note Updater was a World of Warcraft addon that automatically updated a character's guild note with their item level, specialization, professions, and main/alt status on login or when gear, spec, or professions changed.

---

## Why This Addon No Longer Works

### The Core Problem

With WoW 12.0 (Midnight), Blizzard introduced the **Secret Values** system, which blocks addon access to any API that can write guild data. `C_GuildInfo.SetNote` is now fully protected. Calling it from addon code does nothing and produces no error; the call is simply silently dropped. There is no supported workaround.

### What Was Attempted

**1. Direct API call (`C_GuildInfo.SetNote`)**
The original implementation. Worked through WoW 11.x. Silently blocked in 12.0.

**2. Hooking Blizzard's guild note edit dialog**
Blizzard's own note editor uses a protected editBox. Any string value that originates in addon code is considered "tainted." Inserting a tainted string into a protected editBox causes the subsequent `AcceptGuildInfo` call to fail with a Lua security error. The hook fires but cannot write anything.

**3. Registering for `GUILD_ROSTER_UPDATE` and retrying**
Same problem. The event fires correctly but the write is still blocked by taint regardless of when it is attempted.

**4. Clipboard / `C_Clipboard.SetText`**
`C_Clipboard.SetText` does not exist in the 12.0 API. The WoW client does not expose clipboard write access to addons.

**5. Custom StaticPopup with an editBox**
A popup was created that pre-filled the desired note text so the player could copy it and paste it manually into the guild frame. This technically works around taint because the popup is addon-owned and involves no protected API calls. However, the required steps (read popup, open guild roster, click the character, click the note field, paste, confirm) are enough manual work that the addon provides no real value over just typing the note yourself.

### Summary

The addon cannot write guild notes in WoW 12.0. Every direct API path is blocked, every indirect path hits the taint system, and the only remaining option requires enough manual steps to make the automation pointless.

If Blizzard ever restores addon access to `C_GuildInfo.SetNote` or provides an equivalent API, this project could be revived. The last working version was **v1.14.2**, targeting Interface 110107 (WoW 11.x).
