﻿# ==========================
# Config
# ==========================
$ErrorActionPreference = "Stop"

$LogDir = "C:\ProgramData\MyCompany\Logs"
$LogFile = "$LogDir\intune-install.log"

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

Start-Transcript -Path $LogFile -Append

function Log {
    param([string]$msg)
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$time - $msg"
}

$TempDir = $env:TEMP
Log "TempDir: $TempDir"

if (!(Test-Path $TempDir)) {
    Log "TempDir does not exist. Creating..."
    New-Item -ItemType Directory -Path $TempDir | Out-Null
}

function Test-CommandExists {
    param([string]$cmd)
    $exists = [bool](Get-Command $cmd -ErrorAction SilentlyContinue)
    Log "Check command [$cmd]: $exists"
    return $exists
}

function Download-File {
    param(
        [string]$Url,
        [string]$OutFile
    )

    Log "Downloading: $Url → $OutFile"

    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
        Log "Download completed: $OutFile"
    } catch {
        Log "Download FAILED: $_"
        throw
    }
}

function Install-Exe {
    param(
        [string]$File,
        [string]$Arguments
    )

    Log "Installing: $File $Arguments"

    if (!(Test-Path $File)) {
        Log "Installer NOT FOUND: $File"
        throw "Missing installer: $File"
    }

    $process = Start-Process -FilePath $File -ArgumentList $Arguments -Wait -PassThru

    Log "ExitCode: $($process.ExitCode)"

    if ($process.ExitCode -ne 0) {
        throw "Install failed: $File (ExitCode=$($process.ExitCode))"
    }
}

try {
    if (-not (Test-CommandExists "dotnet")) {
        Log "Installing .NET SDK..."

        $dotnetInstaller = "$TempDir\dotnet-install.ps1"

        Download-File `
            -Url "https://dot.net/v1/dotnet-install.ps1" `
            -OutFile $dotnetInstaller

        Log "Running dotnet installer..."

        & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -ExecutionPolicy Bypass `
            -File $dotnetInstaller `
            -InstallDir "C:\Program Files\dotnet" `
            -Channel "LTS"

        Log "Updating PATH..."

        $envPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::Machine)

        if ($envPath -notlike "*C:\Program Files\dotnet*") {
            [Environment]::SetEnvironmentVariable(
                "Path",
                "$envPath;C:\Program Files\dotnet",
                [EnvironmentVariableTarget]::Machine
            )
            Log "PATH updated"
        } else {
            Log "PATH already contains dotnet"
        }
    } else {
        Log ".NET already installed — skipping"
    }
    
    if (-not (Test-CommandExists "git")) {
        Log "Installing Git..."

        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/git-for-windows/git/releases/latest"
        $asset = $rel.assets | Where-Object { $_.name -match '64-bit\.exe$' } | Select-Object -First 1

        if (-not $asset) {
            throw "Cannot find Git installer"
        }

        $gitInstaller = Join-Path $TempDir $asset.name

        Download-File `
            -Url $asset.browser_download_url `
            -OutFile $gitInstaller

        Install-Exe `
            -File $gitInstaller `
            -Arguments "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS"
    } else {
        Log "Git already installed — skipping"
    }

    Log "ALL COMPONENTS INSTALLED SUCCESSFULLY"
    exit 0

} catch {
    Log "ERROR OCCURRED: $_"
    Log "STACK TRACE: $($_.Exception.StackTrace)"
    exit 1

} finally {
    Log "===== INSTALL FINISHED ====="
    Stop-Transcript
}


$dotnetInstalled = [bool](Get-Command dotnet -ErrorAction SilentlyContinue)