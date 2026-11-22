#Requires -Version 5.1
<#
.SYNOPSIS
    Update checker for btop-plus-plus (Windows version)

.DESCRIPTION
    Compares currently pinned versions (from build.sh) against the latest
    available versions and reports whether newer versions exist.

.NOTES
    Requirements: network access, tar.exe (included in Windows 10 1803+). Docker is NOT required.
    This script is READ-ONLY and does not modify any files.
    Exit codes: 0 = all up to date, 1 = newer versions available
#>

$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$BuildSh = Join-Path $ScriptDir "build.sh"

# Counters for summary
$script:NewerBaseImage = 0
$script:NewBaseLine = 0
$script:NewerAlpine = 0
$script:NewerGitHub = 0

Write-ColorOutput "=== Checking for updates ===" "Cyan"
Write-Host "Reading current versions from build.sh..."
Write-Host ""

# ============================================================================
# Extract current versions from build.sh
# ============================================================================

if (-not (Test-Path $BuildSh)) {
    Write-ColorOutput "ERROR: build.sh not found at $BuildSh" "Red"
    exit 1
}

$BuildShContent = Get-Content $BuildSh -Raw

function Get-DefaultValue {
    param([string]$VarName)
    $pattern = "(?m)^${VarName}=`"?([^`"#\r\n]*)`"?"
    if ($BuildShContent -match $pattern) {
        return $Matches[1].Trim()
    }
    return ""
}

$CurrentAlpine = Get-DefaultValue "DEFAULT_ALPINE_VERSION"
$CurrentBtop = Get-DefaultValue "DEFAULT_BTOP_VERSION"

# Extract base line (e.g., "3.24" from "3.24.4")
$CurrentBaseLine = ($CurrentAlpine -split "\.")[0..1] -join "."

Write-Host "Current versions from build.sh:"
Write-Host "  Alpine: $CurrentAlpine (line $CurrentBaseLine)"
Write-Host "  btop++: $CurrentBtop"
Write-Host "  ttyd: (not pinned - latest in Alpine branch)"
Write-Host ""

# ============================================================================
# Base Image Check
# ============================================================================

Write-ColorOutput "--- Base Image ---" "Cyan"
Write-Host "alpine (Docker Hub)"
Write-Host "  Current: $CurrentAlpine"

function Test-BaseImage {
    try {
        $response = Invoke-RestMethod -Uri "https://hub.docker.com/v2/repositories/library/alpine/tags?page_size=100" -TimeoutSec 15 -ErrorAction Stop
    }
    catch {
        Write-ColorOutput "  WARNING: Could not fetch tags from Docker Hub" "Yellow"
        Write-Host "  Manual check: https://hub.docker.com/_/alpine/tags"
        return
    }

    $tags = $response.results.name | Where-Object { $_ -match "^\d+\.\d+\.\d+$" } |
        Sort-Object { [version]$_ } -Unique

    if (-not $tags) {
        Write-ColorOutput "  WARNING: No matching tags found" "Yellow"
        return
    }

    # Latest patch in the same line (e.g., 3.24.x)
    $sameLineLatest = $tags | Where-Object { $_.StartsWith("$CurrentBaseLine.") } | Select-Object -Last 1

    if (-not $sameLineLatest) {
        Write-Host "  Same line ($CurrentBaseLine): $CurrentAlpine (no newer found)"
    }
    elseif ($sameLineLatest -eq $CurrentAlpine) {
        Write-Host "  Same line ($CurrentBaseLine): $sameLineLatest " -NoNewline
        Write-ColorOutput "(up to date)" "Green"
    }
    else {
        Write-Host "  Same line ($CurrentBaseLine): current $CurrentAlpine -> available $sameLineLatest " -NoNewline
        Write-ColorOutput "(NEWER)" "Yellow"
        $script:NewerBaseImage = 1
    }

    # New base line (e.g., 3.25.x)
    $latest = $tags | Select-Object -Last 1
    $latestLine = ($latest -split "\.")[0..1] -join "."
    if ($latestLine -ne $CurrentBaseLine) {
        Write-ColorOutput "  New base line available: $latest (consider migrating)" "Yellow"
        $script:NewBaseLine = 1
    }
    else {
        Write-Host "  No new base line available beyond $CurrentBaseLine"
    }
}

Test-BaseImage
Write-Host ""

# ============================================================================
# Alpine Packages Check
# ============================================================================

Write-ColorOutput "--- Alpine Packages (v$CurrentBaseLine) ---" "Cyan"

# Download the community APKINDEX once and extract it with tar.exe
$script:ApkIndex = ""
$tmpDir = Join-Path ([IO.Path]::GetTempPath()) ("apkindex-" + [guid]::NewGuid())
try {
    New-Item -ItemType Directory -Path $tmpDir | Out-Null
    $archive = Join-Path $tmpDir "APKINDEX.tar.gz"
    Invoke-WebRequest -Uri "https://dl-cdn.alpinelinux.org/alpine/v$CurrentBaseLine/community/x86_64/APKINDEX.tar.gz" `
        -OutFile $archive -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
    # Use the Windows tar.exe explicitly (Git's tar does not understand "C:\" paths)
    $tarExe = Join-Path $env:SystemRoot "System32\tar.exe"
    if (-not (Test-Path $tarExe)) { $tarExe = "tar.exe" }
    & $tarExe -xzf $archive -C $tmpDir APKINDEX 2>$null
    $indexFile = Join-Path $tmpDir "APKINDEX"
    if (Test-Path $indexFile) {
        $script:ApkIndex = Get-Content $indexFile -Raw
    }
}
catch {
    # Handled below (could not fetch)
}
finally {
    Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
}

function Test-AlpinePackage {
    param(
        [string]$PkgName,
        [string]$CurrentVersion
    )

    $available = ""
    if ($script:ApkIndex -and $script:ApkIndex -match "(?m)^P:$([regex]::Escape($PkgName))\r?\nV:([^\r\n]+)") {
        $available = $Matches[1].Trim()
    }

    $currentLabel = if ($CurrentVersion) { $CurrentVersion } else { "(latest)" }

    if (-not $available) {
        Write-Host "${PkgName}: current $currentLabel -> " -NoNewline
        Write-ColorOutput "could not fetch (check: https://pkgs.alpinelinux.org/packages?name=$PkgName&branch=v$CurrentBaseLine)" "Yellow"
        return
    }

    if (-not $CurrentVersion) {
        Write-Host "${PkgName}: current (latest) -> available $available " -NoNewline
        Write-ColorOutput "(using latest)" "Green"
    }
    elseif ($CurrentVersion -eq $available) {
        Write-Host "${PkgName}: current $CurrentVersion -> available $available " -NoNewline
        Write-ColorOutput "(up to date)" "Green"
    }
    else {
        Write-Host "${PkgName}: current $CurrentVersion -> available $available " -NoNewline
        Write-ColorOutput "(NEWER)" "Yellow"
        $script:NewerAlpine++
    }
}

Test-AlpinePackage "ttyd" ""
Write-Host ""

# ============================================================================
# GitHub Components Check
# ============================================================================

Write-ColorOutput "--- GitHub Components ---" "Cyan"

function Test-GitHubRelease {
    param(
        [string]$ComponentName,
        [string]$Repo,
        [string]$CurrentVersion
    )

    try {
        $response = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -TimeoutSec 15 -ErrorAction Stop
        $latest = $response.tag_name -replace "^v", ""
    }
    catch {
        Write-Host "${ComponentName}: current $CurrentVersion -> " -NoNewline
        Write-ColorOutput "could not fetch latest (API rate limit?)" "Yellow"
        Write-Host "  Manual check: https://github.com/$Repo/releases"
        return
    }

    if (($CurrentVersion -replace "^v", "") -eq $latest) {
        Write-Host "${ComponentName}: current $CurrentVersion -> latest $latest " -NoNewline
        Write-ColorOutput "(up to date)" "Green"
    }
    else {
        Write-Host "${ComponentName}: current $CurrentVersion -> latest $latest " -NoNewline
        Write-ColorOutput "(NEWER)" "Yellow"
        $script:NewerGitHub++
    }
}

Test-GitHubRelease "btop++" "aristocratos/btop" $CurrentBtop
Write-Host ""

# ============================================================================
# Summary
# ============================================================================

Write-ColorOutput "=== Summary ===" "Cyan"

$totalNewer = $script:NewerBaseImage + $script:NewBaseLine + $script:NewerAlpine + $script:NewerGitHub

if ($script:NewerBaseImage -gt 0) { Write-ColorOutput "Base image has a newer version available." "Yellow" }
if ($script:NewBaseLine -gt 0) { Write-ColorOutput "A new Alpine line is available (migration recommended; re-check package versions)." "Yellow" }
if ($script:NewerAlpine -gt 0) { Write-ColorOutput "$($script:NewerAlpine) Alpine package(s) have newer versions." "Yellow" }
if ($script:NewerGitHub -gt 0) { Write-ColorOutput "$($script:NewerGitHub) GitHub component(s) have newer versions." "Yellow" }

if ($totalNewer -eq 0) {
    Write-ColorOutput "All components are up to date." "Green"
    exit 0
}
else {
    Write-Host ""
    Write-Host "Consider updating build.sh and releasing a new image."
    exit 1
}
