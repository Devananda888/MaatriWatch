$ErrorActionPreference = 'Stop'
Write-Host "Fetching latest Flutter release info..."
$json = Invoke-RestMethod -Uri "https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json"
$release = $json.releases | Where-Object { $_.hash -eq $json.current_release.stable }
if ($release -is [array]) { $release = $release[0] }
$url = $json.base_url + "/" + $release.archive
Write-Host "URL: $url"

$zipPath = "$env:TEMP\flutter.zip"
if (!(Test-Path $zipPath)) {
    Write-Host "Downloading Flutter..."
    Invoke-WebRequest -Uri $url -OutFile $zipPath
} else {
    Write-Host "Flutter zip already downloaded."
}

Write-Host "Extracting Flutter to C:\..."
Expand-Archive -Path $zipPath -DestinationPath "C:\" -Force
Write-Host "Flutter extracted to C:\flutter"
