# notifications

Plays a sound and shows a **clickable** Windows toast whenever Claude Code needs your input
(permission prompts, or an idle "waiting for you" state). Clicking the toast jumps straight to
the terminal **window and tab** running that session.

## How it works

```
Claude Code ──[Notification hook]──> notify.ps1
                                       │  • plays a sound
                                       │  • captures this session's window handle + tab title
                                       └─ shows a WinRT toast whose click target is
                                          claudefocus:hwnd=<h>&tab=<title>

user clicks toast ──> Windows launches the claudefocus: URL ──> focus.ps1
                                       │  • UI Automation finds the tab whose title matches
                                       │    across EVERY Windows Terminal window and selects it
                                       │    (all WT windows share one process, so the embedded
                                       │    hwnd alone can't tell them apart)
                                       └─ raises that window to the foreground (AttachThreadInput
                                          to beat the foreground lock). hwnd is a fallback only.
```

Three pieces:

| File | Role |
|------|------|
| `notify.ps1` | Hook target. Sound + toast; embeds the window handle and tab title in the click link. |
| `focus.ps1`  | Protocol target. UI-Automation-selects the matching tab across all WT windows, then raises that window (embedded hwnd is a fallback). |
| `claudefocus:` protocol (HKCU) | Makes the toast clickable and routes the click to `focus.ps1`. |

## Install / uninstall

From the repo root:

```powershell
.\install.ps1   -Modules notifications
.\uninstall.ps1 -Modules notifications
```

The installer copies the two scripts to `~/.claude/hooks`, registers the protocol under
`HKCU\Software\Classes\claudefocus`, and adds a `Notification` hook to `~/.claude/settings.json`.
Open Claude Code's `/hooks` once (or restart) afterward so the hook loads.

## Optional: also ping when a turn finishes

The hook is on the `Notification` event (permission / idle prompts). To also get pinged when
Claude finishes a whole turn, add the same command under the `Stop` event in
`~/.claude/settings.json`:

```json
"Stop": [
  { "hooks": [ { "type": "command",
      "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:/Users/<you>/.claude/hooks/notify.ps1\"",
      "async": true } ] }
]
```

## Notes & limitations

- **Tab matching is by title text.** The leading spinner/status glyph (e.g. `✳`, `⠐`) is
  ignored, so matching survives the animation. If two tabs run Claude on the *same* topic, the
  first match wins.
- **Windows Terminal only** for the exact-tab jump (uses WT's UI Automation tab elements). In
  other terminals it still focuses the window; the tab step is simply skipped.
- **Toasts suppressed?** Check Focus Assist / Do Not Disturb (Settings → System → Notifications).
  The sound still plays regardless.
- The toast uses the built-in Windows PowerShell AppUserModelID, so it shows under
  "Windows PowerShell" in notification settings.

## Requirements

Windows 10/11, Windows PowerShell 5.1+, Claude Code with `~/.claude/settings.json`.
