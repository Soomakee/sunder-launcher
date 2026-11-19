# Publishing Sunder (for Saia)

## Publish an update

Double-click **`publish.bat`**. It:

- bumps the version in `sunder/project.godot` (0.1.3 → 0.1.4, shown bottom-left on the main menu),
- exports the game (debug build, same as Project > Export) and the launcher,
- uploads them as a new GitHub Release.

Players get it the next time they open the launcher.

Options (from a terminal in this folder):
```
.\publish.ps1 -Notes "Faster staff heavies"   # release notes
.\publish.ps1 -Version 0.2.0                  # pick the version yourself
.\publish.ps1 -DryRun                         # build + zip only, upload nothing
```

If Godot moves, edit `$Godot` at the top of `publish.ps1`.

## How it works

Each release has `Sunder.zip` (the game), `version.txt`, `SunderLauncher.exe` and `SunderLauncher.zip`.
The launcher reads `releases/latest/download/version.txt`, compares it with the version it
installed in its `game` folder, and downloads `Sunder.zip` when they differ. Offline, it starts
the installed version.

This repo is public so players can download without a GitHub account. The game's source
lives in the private `Soomakee/Sunder` repo.

Changing the launcher itself: edit `Launcher.gd` in Godot, then publish as usual. Players only
need the new launcher if you tell them to re-download it; the old one keeps working.

## New PC setup

```
winget install GitHub.cli
gh auth login
```

## Testing locally

Serve a `dist/` folder (`publish.ps1 -DryRun` makes one) and point the launcher at it:
```
python -m http.server 8765 --directory dist
Godot_console.exe --headless --path . -- --base-url=http://localhost:8765 --root=C:/temp/launcher-test --no-launch
```
An exported launcher also reads `launcher.cfg` next to the exe:
```
[launcher]
base_url="http://localhost:8765"
```
