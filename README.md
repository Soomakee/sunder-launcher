# Sunder Launcher

Keeps playtesters on the latest Sunder build. Players open the launcher; it checks
GitHub for a newer version, downloads and installs it if there is one, then starts the game.

How it works: each published build is a **GitHub Release** on `Soomakee/sunder-launcher`
with three files: `Sunder.zip` (the game), `version.txt` (e.g. `0.1.4`) and
`SunderLauncher.zip`. The launcher reads
`https://github.com/Soomakee/sunder-launcher/releases/latest/download/version.txt`,
compares it with the copy it installed, and downloads `Sunder.zip` when they differ.
If there's no internet it starts the version already installed.

The repo must be **public** so friends can download without a GitHub account.
Only this launcher and the game builds go in it; the game's source stays private.

---

## For Saia: one-time setup

1. Install the GitHub CLI and sign in (pick GitHub.com, HTTPS, log in with a browser):
   ```
   winget install GitHub.cli
   gh auth login
   ```
2. Create the public repo from this folder and push it (run inside `sunder-launcher`):
   ```
   gh repo create Soomakee/sunder-launcher --public --source . --push
   ```

## For Saia: publishing an update

Double-click **`publish.bat`**. That's it. It:

- bumps the version in `sunder/project.godot` (0.1.3 → 0.1.4, shown bottom-left on the main menu),
- exports the game (debug build, same as Project > Export) and the launcher,
- uploads them as a new release.

Players get it the next time they open the launcher. Both players should publish-then-launch
before an online session so the main-menu version matches.

Options (from a terminal in this folder):
```
.\publish.ps1 -Notes "Faster staff heavies"   # release notes
.\publish.ps1 -Version 0.2.0                  # pick the version yourself
.\publish.ps1 -DryRun                         # build + zip only, upload nothing
```

If Godot moves, edit `$Godot` at the top of `publish.ps1`.

Changing the launcher itself: edit `Launcher.gd` in Godot, then publish as usual. The new
launcher is in each release's `SunderLauncher.zip`; players only need it if you tell them to
re-download (the old one keeps working).

---

## For players

1. Download **SunderLauncher.zip**:
   https://github.com/Soomakee/sunder-launcher/releases/latest/download/SunderLauncher.zip
2. Unzip it into its own folder, e.g. `Documents\Sunder` (not Program Files, it needs to write there).
3. Double-click **SunderLauncher.exe**. The first time it downloads the game (~35 MB), then starts it.
   Always open Sunder through the launcher and you'll always have the newest version.

Windows may show "Windows protected your PC" the first time, because the launcher isn't
code-signed. Click **More info → Run anyway**.

If an update says it couldn't replace the old version, close Sunder and press **Retry**.

---

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
