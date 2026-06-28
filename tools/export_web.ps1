# Build the Godot web export for GitHub Pages and package the itch.io zip.
param(
	[switch]$Serve,
	[switch]$SkipItch,
	[int]$Port = 8060
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "godot_common.ps1")

$ExportDir = Join-Path $ProjectRoot "builds\github"
$ExportHtml = Join-Path $ExportDir "index.html"

Ensure-Godot -RequiredTemplates @("web_nothreads_release.zip")

New-Item -ItemType Directory -Force -Path $ExportDir | Out-Null
$nojekyll = Join-Path $ExportDir ".nojekyll"
if (-not (Test-Path $nojekyll)) {
	New-Item -ItemType File -Force -Path $nojekyll | Out-Null
}

Invoke-GodotExport -PresetName "Web" -ExportPath $ExportHtml

$wasmPath = Join-Path $ExportDir "index.wasm"
$deadline = (Get-Date).AddMinutes(5)
while (-not (Test-Path $wasmPath) -and (Get-Date) -lt $deadline) {
	Start-Sleep -Milliseconds 250
}
if (-not (Test-Path $wasmPath)) {
	throw "Godot web export failed; $wasmPath was not created."
}

Write-Host "GitHub Pages build complete: $ExportDir"

if (-not $SkipItch) {
	& (Join-Path $PSScriptRoot "package_itch.ps1")
}

if ($Serve) {
	Write-Host "Serving at http://127.0.0.1:$Port/ (Ctrl+C to stop)"
	Push-Location $ExportDir
	try {
		python -m http.server $Port
	} finally {
		Pop-Location
	}
}
