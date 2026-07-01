# claude-code-winkit

A Windows toolkit for [Claude Code](https://claude.com/claude-code) — small, self-contained modules that make Claude Code nicer to use on Windows.

Each module lives under `modules/` and installs independently. Install everything, or pick and choose.

## Modules

| Module | What it does |
|--------|--------------|
| [`notifications`](modules/notifications) | Plays a sound and shows a **clickable** Windows toast when Claude Code needs your input. Clicking the toast jumps to the exact terminal **window _and_ tab** running that session. |

_More modules to come._

## Requirements

- Windows 10/11
- Windows PowerShell 5.1+ (ships with Windows) — the installers use `powershell.exe`
- [Claude Code](https://claude.com/claude-code) installed, with `~/.claude/settings.json`

## Install

```powershell
# from the repo root — installs all modules
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1

# or just specific modules
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Modules notifications
```

After installing a module that adds a hook, open Claude Code's `/hooks` menu once (or restart Claude Code) so the new hook is picked up.

## Uninstall

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
# or: .\uninstall.ps1 -Modules notifications
```

## Layout

```
claude-code-winkit/
  install.ps1            # top-level: install selected modules
  uninstall.ps1
  lib/settings.ps1       # shared helper: safe JSON merge into ~/.claude/settings.json
  modules/
    notifications/       # module #1
      notify.ps1         # sound + clickable toast (hook target)
      focus.ps1          # brings the right window + tab to the foreground (protocol target)
      install.ps1
      uninstall.ps1
      README.md
```

Each module is fully self-contained: its own `install.ps1` / `uninstall.ps1` / `README.md`. Adding a new feature is just a new folder under `modules/`.

## License

MIT — see [LICENSE](LICENSE).
