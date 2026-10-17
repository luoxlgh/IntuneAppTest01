$dotnetInstalled = [bool](Get-Command dotnet -ErrorAction SilentlyContinue)
$gitInstalled    = [bool](Get-Command git    -ErrorAction SilentlyContinue)

if ($dotnetInstalled -and $gitInstalled) {
    Write-Host "Detected: dotnet and git are installed"
    exit 0
}

exit 1