# Build web (GitHub Pages + itch), Windows, and macOS exports.
$ErrorActionPreference = "Stop"

& (Join-Path $PSScriptRoot "export_web.ps1")
& (Join-Path $PSScriptRoot "export_desktop.ps1")

Write-Host "All exports complete."
