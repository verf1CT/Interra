param(
    [switch]$Watch = $false
)

$desktop = [Environment]::GetFolderPath('Desktop')
$targetPath = Join-Path $desktop "interra-ios.ipa"
$sideloadlyPath = "C:\Sideloadly\interra-ios.ipa"
$stateFile = Join-Path $PSScriptRoot ".last_synced_release.txt"

function Sync-LatestRelease {
    try {
        $latest = gh release list --limit 1 | Out-String
        if (-not $latest) { return }

        if ($latest -match '(build-\d+)') {
            $tag = $matches[1]
            $lastTag = ""
            if (Test-Path $stateFile) {
                $lastTag = (Get-Content $stateFile -Raw).Trim()
            }

            if ($tag -ne $lastTag -or -not (Test-Path $targetPath)) {
                Write-Host "New build detected: $tag. Downloading latest IPA..." -ForegroundColor Cyan
                gh release download $tag -p "interra-ios.ipa" --dir $desktop --clobber
                if (Test-Path "C:\Sideloadly") {
                    Copy-Item $targetPath $sideloadlyPath -Force -ErrorAction SilentlyContinue
                }
                Set-Content -Path $stateFile -Value $tag
                Write-Host "SUCCESS: Downloaded $tag to Desktop: $targetPath" -ForegroundColor Green
            } else {
                Write-Host "Desktop already has the latest version ($tag)." -ForegroundColor Gray
            }
        }
    } catch {
        Write-Warning "Sync error: $_"
    }
}

Sync-LatestRelease

if ($Watch) {
    Write-Host "Watching for new GitHub releases every 60 seconds (Ctrl+C to stop)..." -ForegroundColor Yellow
    while ($true) {
        Start-Sleep -Seconds 60
        Sync-LatestRelease
    }
}
