# Build Windows and macOS desktop exports.
param(
	[switch]$WindowsOnly,
	[switch]$MacOSOnly
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "godot_common.ps1")

$exportWindows = -not $MacOSOnly
$exportMacOS = -not $WindowsOnly

$requiredTemplates = @()
if ($exportWindows) {
	$requiredTemplates += "windows_release_x86_64.exe"
}
if ($exportMacOS) {
	$requiredTemplates += "macos.zip"
}

Ensure-Godot -RequiredTemplates $requiredTemplates

if ($exportWindows) {
	Invoke-GodotExport `
		-PresetName "Windows Desktop" `
		-ExportPath (Join-Path $ProjectRoot "builds\windows\PhysicsRoyale.exe")
	Write-Host "Windows build complete: builds\windows\PhysicsRoyale.exe"
}

if ($exportMacOS) {
	Invoke-GodotExport `
		-PresetName "macOS" `
		-ExportPath (Join-Path $ProjectRoot "builds\macos\PhysicsRoyale.zip")
	Write-Host "macOS build complete: builds\macos\PhysicsRoyale.zip"
}
