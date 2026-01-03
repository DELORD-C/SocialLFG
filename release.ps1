<#
.SYNOPSIS
  Release helper for SocialLFG addon.

.DESCRIPTION
  Bumps version in SocialLFG.toc (or sets it explicitly), commits with message "Stable VX.X.X",
  creates tag "vX.X.X", pushes commit and tag, and builds a zip archive excluding the .git folder.

.PARAMETER Bump
  If specified, one of: patch, minor, major. Defaults to patch.

.PARAMETER Version
  Exact version to use (overrides -Bump).

.PARAMETER DryRun
  If set, shows actions without executing them.

.PARAMETER Force
  If set, allows running with a dirty working tree.

.EXAMPLE
  .\release.ps1 -Bump patch
  .\release.ps1 -Version 2.1.0
  .\release.ps1 -Bump minor -DryRun
#>

[CmdletBinding()]
param(
    [ValidateSet('patch','minor','major')]
    [string]$Bump = 'patch',

    [string]$Version,

    [switch]$DryRun,

    [switch]$Force
)

function Write-Info { Write-Host "[INFO]" $args -ForegroundColor Cyan }
function Write-Err { Write-Host "[ERROR]" $args -ForegroundColor Red }

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $ScriptRoot

$tocFile = Join-Path $ScriptRoot 'SocialLFG.toc'
if (-not (Test-Path $tocFile)) { Write-Err "Could not find $tocFile"; exit 1 }

# Read current version
$tocContent = Get-Content $tocFile -Raw
if ($tocContent -match '##\s*Version:\s*([0-9]+)\.([0-9]+)\.([0-9]+)') {
    $currentVersion = "$($matches[1]).$($matches[2]).$($matches[3])"
} else {
    Write-Err "Current version not found in $tocFile"; exit 1
}

Write-Info "Current version: $currentVersion"

function Increment-SemVer([string]$ver, [string]$part) {
    $parts = $ver.Split('.') | ForEach-Object {[int]$_}
    switch ($part) {
        'patch' { $parts[2] += 1 }
        'minor' { $parts[1] += 1; $parts[2] = 0 }
        'major' { $parts[0] += 1; $parts[1] = 0; $parts[2] = 0 }
    }
    return "$($parts[0]).$($parts[1]).$($parts[2])"
}

if ($Version) {
    # Validate provided version
    if ($Version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') { Write-Err "Version must be in X.Y.Z format"; exit 1 }
    $newVersion = $Version
} else {
    $newVersion = Increment-SemVer $currentVersion $Bump
}

Write-Info "New version will be: $newVersion"

if ($DryRun) { Write-Info "Dry run mode - no changes will be made" }

# Check git status
if (Get-Command git -ErrorAction SilentlyContinue) {
    $status = git status --porcelain 2>$null
    if ($status) {
        Write-Info "Working tree has uncommitted changes; they will be staged and included in the release commit."
    }
} else {
    Write-Err "git not found in PATH"; exit 1
}

# Update toc
$newTocContent = [regex]::Replace($tocContent, '(##\s*Version:\s*)([0-9]+\.[0-9]+\.[0-9]+)', { param($m) $m.Groups[1].Value + $newVersion })
if ($DryRun) {
    Write-Info ("Would update {0}: Version {1} -> {2}" -f $tocFile, $currentVersion, $newVersion)
} else {
    Set-Content -Path $tocFile -Value $newTocContent -Encoding UTF8
    Write-Info "Updated $tocFile"
} 

# Git commit
$commitMessage = "Stable V$newVersion"
$tagName = "v$newVersion"

if (-not $DryRun) {
    # Stage all changes (including untracked files)
    & git add -A
    if ($LASTEXITCODE -ne 0) { Write-Err "git add failed"; exit 1 }

    & git commit -m "$commitMessage"
    if ($LASTEXITCODE -ne 0) { Write-Err "git commit failed"; exit 1 }
    Write-Info "Committed with message: $commitMessage"

    # Create tag
    & git tag -a "$tagName" -m "Release $tagName"
    if ($LASTEXITCODE -ne 0) { Write-Err "git tag failed"; exit 1 }
    Write-Info "Created tag: $tagName"

    # Push commit and tag
    & git push origin HEAD
    if ($LASTEXITCODE -ne 0) { Write-Err "git push failed"; exit 1 }
    Write-Info "Pushed commit to origin"

    & git push origin "$tagName"
    if ($LASTEXITCODE -ne 0) { Write-Err "git push tag failed"; exit 1 }
    Write-Info "Pushed tag $tagName to origin"
} else {
    Write-Info "Dry-run: would stage all changes (git add -A) and run git commit/tag/push with message/tag: $commitMessage / $tagName"
}

# Create zip excluding .git
$releasesDir = Join-Path $ScriptRoot 'releases'
if (-not (Test-Path $releasesDir)) { New-Item -ItemType Directory -Path $releasesDir | Out-Null }
$zipName = "SocialLFG-$newVersion.zip"
$zipPath = Join-Path $releasesDir $zipName

if ($DryRun) {
    Write-Info "Dry-run: would create zip $zipPath excluding .git, .gitignore, release.ps1, and the releases folder"
} else {
    $tmp = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        Write-Info "Copying files to temporary directory..."
        # Copy all files and directories except .git, .gitignore, release.ps1 and releases directory
        Get-ChildItem -Path $ScriptRoot -Force | Where-Object { $_.Name -ne '.git' -and $_.Name -ne '.gitignore' -and $_.Name -ne 'release.ps1' -and $_.Name -ne 'releases' -and $_.FullName -ne $tmp } | ForEach-Object {
            $dest = Join-Path $tmp $_.Name
            if ($_.PSIsContainer) {
                Copy-Item -Path $_.FullName -Destination $dest -Recurse -Force
            } else {
                Copy-Item -Path $_.FullName -Destination $dest -Force
            }
        }

        if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($tmp, $zipPath)
        Write-Info "Created zip: $zipPath"
    } finally {
        Remove-Item -Recurse -Force $tmp
    }
}

Write-Info "Release process complete."
