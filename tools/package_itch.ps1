# Zip the builds/github export for itch.io (index.html at zip root).
$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ExportDir = Join-Path $ProjectRoot "builds\github"
$ExportHtml = Join-Path $ExportDir "index.html"
$ItchDir = Join-Path $ProjectRoot "builds\itch"
$OutZip = Join-Path $ItchDir "PhysicsRoyale-web.zip"

if (-not (Test-Path $ExportHtml)) {
	throw "Missing $ExportHtml - run tools/export_web.ps1 first."
}

New-Item -ItemType Directory -Force -Path $ItchDir | Out-Null

$staging = Join-Path $env:TEMP "PhysicsRoyale-web-itch"
if (Test-Path $staging) {
	Remove-Item -Path $staging -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $staging | Out-Null

Get-ChildItem -Path $ExportDir -File | Where-Object {
	$_.Name -ne ".nojekyll" -and $_.Extension -ne ".import"
} | ForEach-Object {
	Copy-Item -Path $_.FullName -Destination $staging
}

if (Test-Path $OutZip) {
	Remove-Item -Path $OutZip -Force
}
Compress-Archive -Path (Join-Path $staging "*") -DestinationPath $OutZip -Force
Remove-Item -Path $staging -Recurse -Force

Write-Host "Itch.io zip ready: $OutZip"
