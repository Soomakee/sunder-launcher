<#
  Publish a new Sunder build for playtesters.

  What it does:
    1. Bumps the game version in sunder\project.godot (0.1.3 -> 0.1.4), unless you pass -Version.
    2. Exports the game (Windows Desktop preset, debug build like Project > Export).
    3. Exports this launcher.
    4. Uploads Sunder.zip, version.txt and SunderLauncher.zip as a new GitHub Release.
  Every player's launcher picks the new version up the next time they open it.

  Usage (or just double-click publish.bat):
    .\publish.ps1
    .\publish.ps1 -Notes "Staff heavy 3 is faster"
    .\publish.ps1 -Version 0.2.0
    .\publish.ps1 -DryRun        # build and zip only, upload nothing, don't touch project.godot
#>
param(
    [string]$Version = "",
    [string]$Notes = "",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# --- Settings ----------------------------------------------------------------
$Repo        = "Soomakee/sunder-launcher"   # GitHub repo whose Releases hold the builds
$LauncherDir = $PSScriptRoot
$GameDir     = (Resolve-Path (Join-Path $LauncherDir "..\sunder")).Path
$Godot       = "C:\Users\Isaiah\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
$Preset      = "Windows Desktop"
# ------------------------------------------------------------------------------

# Runs gh quietly and returns its exit code. Windows PowerShell 5.1 turns a native
# command's stderr into a terminating error under ErrorActionPreference=Stop, so relax it here.
function Invoke-GhQuiet {
    $old = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { & gh @args *> $null } finally { $ErrorActionPreference = $old }
    return $LASTEXITCODE
}

function Step($text) { Write-Host ""; Write-Host "==> $text" -ForegroundColor Cyan }
function Die($text)  { Write-Host ""; Write-Host "ERROR: $text" -ForegroundColor Red; exit 1 }

if (-not (Test-Path $Godot)) { Die "Godot not found at $Godot. Edit `$Godot at the top of publish.ps1." }

if (-not $DryRun) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Die "GitHub CLI (gh) isn't installed. Run: winget install GitHub.cli   then: gh auth login"
    }
    if ((Invoke-GhQuiet auth status) -ne 0) { Die "GitHub CLI isn't signed in. Run: gh auth login" }
}

# --- 1. Version ----------------------------------------------------------------
Step "Choosing version"
$projectFile = Join-Path $GameDir "project.godot"
$projectText = [IO.File]::ReadAllText($projectFile)
$m = [regex]::Match($projectText, 'config/version="([^"]*)"')
if (-not $m.Success) { Die "No config/version in $projectFile" }
$current = $m.Groups[1].Value

function Test-ReleaseExists($v) {
    if ($DryRun) { return $false }
    return ((Invoke-GhQuiet release view "v$v" --repo $Repo) -eq 0)
}
function Get-NextPatch($v) {
    $parts = $v.Split(".")
    while ($parts.Count -lt 3) { $parts += "0" }
    $parts[2] = [string]([int]$parts[2] + 1)
    return ($parts[0..2] -join ".")
}

if ($Version -eq "") {
    $Version = Get-NextPatch $current
    while (Test-ReleaseExists $Version) { $Version = Get-NextPatch $Version }
} elseif (Test-ReleaseExists $Version) {
    Die "Release v$Version already exists on $Repo. Pick another -Version."
}
Write-Host "Game version: $current -> $Version"

if (-not $DryRun -and $Version -ne $current) {
    $newText = $projectText.Substring(0, $m.Groups[1].Index) + $Version +
               $projectText.Substring($m.Groups[1].Index + $m.Groups[1].Length)
    [IO.File]::WriteAllText($projectFile, $newText, (New-Object Text.UTF8Encoding($false)))
}

# --- 2. Export the game --------------------------------------------------------
Step "Exporting the game (takes a minute)"
$gameExe = Join-Path $GameDir "builds\Sunder.exe"
New-Item -ItemType Directory -Force (Split-Path $gameExe) | Out-Null
$started = Get-Date
$ErrorActionPreference = "Continue"
& $Godot --headless --path $GameDir --export-debug $Preset $gameExe 2>&1 | Out-Host
$ErrorActionPreference = "Stop"
if (-not (Test-Path $gameExe) -or (Get-Item $gameExe).LastWriteTime -lt $started) {
    Die "Game export failed (see the Godot output above)."
}

# --- 3. Export the launcher ----------------------------------------------------
Step "Exporting the launcher"
$launcherExe = Join-Path $LauncherDir "builds\SunderLauncher.exe"
New-Item -ItemType Directory -Force (Split-Path $launcherExe) | Out-Null
$started = Get-Date
$ErrorActionPreference = "Continue"
& $Godot --headless --path $LauncherDir --export-release $Preset $launcherExe 2>&1 | Out-Host
$ErrorActionPreference = "Stop"
if (-not (Test-Path $launcherExe) -or (Get-Item $launcherExe).LastWriteTime -lt $started) {
    Die "Launcher export failed (see the Godot output above)."
}

# --- 4. Package ----------------------------------------------------------------
Step "Packaging"
$dist = Join-Path $LauncherDir "dist"
if (Test-Path $dist) { Remove-Item -Recurse -Force $dist }
New-Item -ItemType Directory $dist | Out-Null

$gameFiles = @($gameExe)
$consoleExe = Join-Path $GameDir "builds\Sunder.console.exe"
if (Test-Path $consoleExe) { $gameFiles += $consoleExe }
Compress-Archive -Path $gameFiles -DestinationPath (Join-Path $dist "Sunder.zip")
Compress-Archive -Path $launcherExe -DestinationPath (Join-Path $dist "SunderLauncher.zip")
Copy-Item $launcherExe (Join-Path $dist "SunderLauncher.exe")   # bare exe: players can't run it from inside a zip by mistake
Set-Content -Path (Join-Path $dist "version.txt") -Value $Version -NoNewline -Encoding ascii
Get-ChildItem $dist | ForEach-Object { "{0,-22} {1,8:N1} MB" -f $_.Name, ($_.Length / 1MB) } | Out-Host

if ($DryRun) {
    Write-Host ""
    Write-Host "Dry run done. Files are in $dist (nothing uploaded)." -ForegroundColor Green
    exit 0
}

# --- 5. Upload -----------------------------------------------------------------
Step "Uploading release v$Version to github.com/$Repo"
if ($Notes -eq "") { $Notes = "Sunder $Version" }
$ErrorActionPreference = "Continue"   # gh prints upload progress on stderr
gh release create "v$Version" `
    (Join-Path $dist "Sunder.zip") (Join-Path $dist "version.txt") (Join-Path $dist "SunderLauncher.zip") (Join-Path $dist "SunderLauncher.exe") `
    --repo $Repo --title "Sunder $Version" --notes $Notes --latest
if ($LASTEXITCODE -ne 0) { Die "Upload failed. The build is still in $dist; run the script again to retry." }

Write-Host ""
Write-Host "Published Sunder $Version. Players get it next time they open the launcher." -ForegroundColor Green
Write-Host "Launcher download link for new players:"
Write-Host "  https://github.com/$Repo/releases/latest/download/SunderLauncher.exe"
