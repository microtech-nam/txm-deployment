#Requires -Version 5.1
<#
    TSOAXAU Metals — Endpoint Deployment Bootstrapper
    Usage:  irm scripts.tsoaxaubmetals.com | iex
    Run from an elevated PowerShell session (MSI installs require admin).
#>

# ----------------------------------------------------------------------
# CONFIG  — all enrollment secrets live here
# ----------------------------------------------------------------------
$LevelApiKey  = "68ipcLgJvJ2RB7uhveXCkSHY:43510"
$AteraUrl     = "https://micro-tech.servicedesk.atera.com/api/utils/agent-install/windows/?cid=112&aeid=90e1f3798f0147a6a179f562e3655a79"
$AvZipUrl     = "https://github.com/user-attachments/files/28380833/Tsoaxaub_AV_Downloader.zip"  # zipped Trend Micro downloader .exe
# NOTE: $AvIdentifier was for the MSI/SILENTMODE flow. The downloader .exe carries its own
# account/group association, so it normally won't prompt for this. Kept only as a fallback.
$AvIdentifier = "cb68sNfWVYNK8KOeUJI/Eq7DuNY24IDWkovmAHtlLbY/YIsC0Q+s2wCBXcIjz/79pgOdqGDG6Y6KerTH8efVVCaslSxg44dHFxFQMzyYTDTxz9clsINZSGevBgP/Sf7R5BbX2y8wXAd+LBQDNz3E5g=="

# ----------------------------------------------------------------------
# Prerequisites
# ----------------------------------------------------------------------
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "This script must be run from an elevated (Administrator) PowerShell session."
    return
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Invoke-Msi {
    param([string]$MsiPath, [string]$ExtraArgs, [string]$LogPath)
    $argList = "/i `"$MsiPath`" $ExtraArgs"
    if ($LogPath) { $argList += " /L*v+ `"$LogPath`"" }
    $p = Start-Process msiexec.exe -ArgumentList $argList -Wait -PassThru
    switch ($p.ExitCode) {
        0     { Write-Host "  -> Success (exit 0)." -ForegroundColor Green }
        3010  { Write-Host "  -> Success, reboot required (exit 3010)." -ForegroundColor Green }
        1641  { Write-Host "  -> Success, reboot initiated (exit 1641)." -ForegroundColor Green }
        default { Write-Host "  -> msiexec returned exit code $($p.ExitCode)." -ForegroundColor Red }
    }
    return $p.ExitCode
}

function Get-File {
    param([string]$Uri, [string]$OutFile)
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing
    $ProgressPreference = 'Continue'
}

# ----------------------------------------------------------------------
# Installers
# ----------------------------------------------------------------------
function Install-LevelAgent {
    Write-Host "`n[Level] Installing Level RMM agent..." -ForegroundColor Cyan
    try {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "level.msi"
        Get-File -Uri "https://downloads.level.io/level.msi" -OutFile $tmp
        Invoke-Msi -MsiPath $tmp -ExtraArgs "LEVEL_API_KEY=$LevelApiKey" | Out-Null
    } catch {
        Write-Host "[Level] Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Install-AteraAgent {
    Write-Host "`n[Atera] Installing Atera RMM agent..." -ForegroundColor Cyan
    try {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "atera_setup.msi"
        Get-File -Uri $AteraUrl -OutFile $tmp
        Invoke-Msi -MsiPath $tmp -ExtraArgs "/qn" | Out-Null
    } catch {
        Write-Host "[Atera] Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Install-AntiVirus {
    Write-Host "`n[AV] Trend Micro Worry-Free agent (downloader stub)..." -ForegroundColor Cyan
    if ($AvZipUrl -like "*YOUR-HOST*") {
        Write-Host "[AV] AvZipUrl is not configured. Set it in CONFIG first." -ForegroundColor Red
        return
    }
    try {
        $stage = Join-Path $env:ProgramData "TSOAXAU_AV"
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        $zip = Join-Path $stage "av_downloader.zip"

        Write-Host "[AV] Downloading package..." -ForegroundColor Cyan
        Get-File -Uri $AvZipUrl -OutFile $zip

        Write-Host "[AV] Extracting..." -ForegroundColor Cyan
        Expand-Archive -LiteralPath $zip -DestinationPath $stage -Force

        $exe = Get-ChildItem -Path $stage -Filter *.exe -Recurse | Select-Object -First 1
        if (-not $exe) {
            Write-Host "[AV] No .exe found inside the archive." -ForegroundColor Red
            return
        }

        # Integrity check — confirm the binary is validly signed before running it.
        $sig = Get-AuthenticodeSignature -FilePath $exe.FullName
        if ($sig.Status -eq 'Valid') {
            Write-Host "[AV] Signature OK: $($sig.SignerCertificate.Subject)" -ForegroundColor DarkGray
        } else {
            Write-Host "[AV] WARNING: signature status is '$($sig.Status)'. Verify the file before continuing." -ForegroundColor Yellow
        }

        Write-Host "[AV] Launching downloader — complete the final install in its window." -ForegroundColor Cyan
        Write-Host "[AV] If the installer asks for an Identifier, use:" -ForegroundColor DarkGray
        Write-Host "     $AvIdentifier" -ForegroundColor DarkGray
        Start-Process -FilePath $exe.FullName -Wait

        Write-Host "[AV] Downloader closed. Confirm the Security Agent finished installing." -ForegroundColor Green
        Write-Host "[AV] Staged at: $($exe.FullName)" -ForegroundColor DarkGray
    } catch {
        Write-Host "[AV] Failed: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ----------------------------------------------------------------------
# Menu
# ----------------------------------------------------------------------
function Show-Menu {
    Write-Host "`n==== TSOAXAU Metals Deployment ====" -ForegroundColor Yellow
    Write-Host " 1) Install Level RMM agent"
    Write-Host " 2) Install Atera RMM agent"
    Write-Host " 3) Install Anti-Virus (Trend Micro)"
    Write-Host " A) Install ALL"
    Write-Host " Q) Quit"
}

do {
    Show-Menu
    $choice = (Read-Host "Select").ToUpper()
    switch ($choice) {
        '1' { Install-LevelAgent }
        '2' { Install-AteraAgent }
        '3' { Install-AntiVirus }
        'A' { Install-LevelAgent; Install-AteraAgent; Install-AntiVirus }
        'Q' { }
        default { Write-Host "Invalid choice." -ForegroundColor Red }
    }
} while ($choice -ne 'Q')

Write-Host "`nDone." -ForegroundColor Green
