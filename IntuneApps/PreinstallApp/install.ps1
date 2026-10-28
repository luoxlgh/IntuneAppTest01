# ==========================
# Config
# ==========================
$ErrorActionPreference = "Stop"

$LogDir  = "C:\ProgramData\MyCompany\Logs"
$LogFile = Join-Path $LogDir "intune-install.log"

$DotnetDir = Join-Path $env:ProgramFiles "dotnet"
$DotnetExe = Join-Path $DotnetDir "dotnet.exe"

$GitDir = Join-Path $env:ProgramFiles "Git"
$GitCmdDir = Join-Path $GitDir "cmd"
$GitExe = Join-Path $GitCmdDir "git.exe"

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

Start-Transcript -Path $LogFile -Append

function Log {
    param([string]$Message)

    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$time - $Message"
}

function Test-Executable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $exists = Test-Path -LiteralPath $Path -PathType Leaf
    Log "Check executable [$Path]: $exists"

    return $exists
}

function Add-MachinePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Cannot add missing directory to PATH: $Path"
    }

    $machinePath = [Environment]::GetEnvironmentVariable(
        "Path",
        [EnvironmentVariableTarget]::Machine
    )

    $pathEntries = @(
        $machinePath -split ";" |
            ForEach-Object { $_.Trim().TrimEnd("\") } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    $normalizedPath = $Path.Trim().TrimEnd("\")

    if ($pathEntries -notcontains $normalizedPath) {
        $updatedMachinePath = if ([string]::IsNullOrWhiteSpace($machinePath)) {
            $normalizedPath
        } else {
            "$($machinePath.TrimEnd(';'));$normalizedPath"
        }

        [Environment]::SetEnvironmentVariable(
            "Path",
            $updatedMachinePath,
            [EnvironmentVariableTarget]::Machine
        )

        Log "Added to machine PATH: $normalizedPath"
    } else {
        Log "Machine PATH already contains: $normalizedPath"
    }
}

function Refresh-CurrentProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable(
        "Path",
        [EnvironmentVariableTarget]::Machine
    )

    $userPath = [Environment]::GetEnvironmentVariable(
        "Path",
        [EnvironmentVariableTarget]::User
    )

    if ([string]::IsNullOrWhiteSpace($userPath)) {
        $env:Path = $machinePath
    } else {
        $env:Path = "$machinePath;$userPath"
    }

    Log "Refreshed PATH for the current installation process"
}

function Download-File {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$OutFile
    )

    Log "Downloading: $Url -> $OutFile"

    try {
        Invoke-WebRequest `
            -Uri $Url `
            -OutFile $OutFile `
            -UseBasicParsing

        Log "Download completed: $OutFile"
    }
    catch {
        Log "Download failed: $($_.Exception.Message)"
        throw
    }
}

function Install-Exe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$File,

        [Parameter(Mandatory = $true)]
        [string]$Arguments
    )

    Log "Installing: $File $Arguments"

    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) {
        throw "Installer not found: $File"
    }

    $process = Start-Process `
        -FilePath $File `
        -ArgumentList $Arguments `
        -Wait `
        -PassThru

    Log "Installer exit code: $($process.ExitCode)"

    if ($process.ExitCode -notin @(0, 3010)) {
        throw "Installation failed: $File (ExitCode=$($process.ExitCode))"
    }

    if ($process.ExitCode -eq 3010) {
        Log "Installer requested a restart, but installation completed successfully"
    }
}

try {
    $TempDir = Join-Path $env:ProgramData "MyCompany\Temp"

    Log "Temp directory: $TempDir"

    New-Item `
        -ItemType Directory `
        -Path $TempDir `
        -Force |
        Out-Null

    # ==========================
    # Install .NET SDK
    # ==========================

    if (-not (Test-Executable -Path $DotnetExe)) {
        Log "Installing .NET SDK"

        $dotnetInstaller = Join-Path $TempDir "dotnet-install.ps1"

        Download-File `
            -Url "https://dot.net/v1/dotnet-install.ps1" `
            -OutFile $dotnetInstaller

        Log "Running .NET SDK installer"

        & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -NoProfile `
            -NonInteractive `
            -ExecutionPolicy Bypass `
            -File $dotnetInstaller `
            -InstallDir $DotnetDir `
            -Channel "LTS"

        if ($LASTEXITCODE -ne 0) {
            throw ".NET installation failed with exit code $LASTEXITCODE"
        }

        if (-not (Test-Executable -Path $DotnetExe)) {
            throw ".NET installation completed, but dotnet.exe was not found at $DotnetExe"
        }

        Log ".NET SDK installed successfully"
    }
    else {
        Log ".NET SDK already installed; skipping installation"
    }

    Add-MachinePath -Path $DotnetDir

    # ==========================
    # Install Git
    # ==========================

    if (-not (Test-Executable -Path $GitExe)) {
        Log "Installing Git"

        $headers = @{
            "User-Agent" = "Intune-Installation-Script"
        }

        $release = Invoke-RestMethod `
            -Uri "https://api.github.com/repos/git-for-windows/git/releases/latest" `
            -Headers $headers

        $asset = $release.assets |
            Where-Object {
                $_.name -match 'Git-[\d.]+-64-bit\.exe$'
            } |
            Select-Object -First 1

        if (-not $asset) {
            throw "Cannot find the 64-bit Git for Windows installer"
        }

        $gitInstaller = Join-Path $TempDir $asset.name

        Download-File `
            -Url $asset.browser_download_url `
            -OutFile $gitInstaller

        Install-Exe `
            -File $gitInstaller `
            -Arguments "/VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS"

        if (-not (Test-Executable -Path $GitExe)) {
            throw "Git installation completed, but git.exe was not found at $GitExe"
        }

        Log "Git installed successfully"
    }
    else {
        Log "Git already installed; skipping installation"
    }

    Add-MachinePath -Path $GitCmdDir

    # Refresh only the current PowerShell process.
    Refresh-CurrentProcessPath

    # ==========================
    # Final validation
    # ==========================

    if (-not (Test-Executable -Path $DotnetExe)) {
        throw "Final validation failed: dotnet.exe is missing"
    }

    if (-not (Test-Executable -Path $GitExe)) {
        throw "Final validation failed: git.exe is missing"
    }

    $dotnetVersion = & $DotnetExe --version
    $gitVersion = & $GitExe --version

    Log ".NET version: $dotnetVersion"
    Log "Git version: $gitVersion"

    # This validates Get-Command in the current process only.
    $dotnetCommand = Get-Command "dotnet.exe" -ErrorAction ErrorAction SilentlyContinue
    $gitCommand = Get-Command "git.exe" -ErrorAction SilentlyContinue

    Log "dotnet resolved in current process: $([bool]$dotnetCommand)"
    Log "git resolved in current process: $([bool]$gitCommand)"

    if (-not $dotnetCommand -or -not $gitCommand) {
        throw "Installation succeeded, but commands could not be resolved after refreshing the current process PATH"
    }

    Log "ALL COMPONENTS INSTALLED SUCCESSFULLY"
    exit 0
}
catch {
    Log "ERROR: $($_.Exception.Message)"
    Log "STACK TRACE: $($_.ScriptStackTrace)"
    exit 1
}
finally {
    Log "===== INSTALL FINISHED ====="

    
