# Build the Godot web export for GitHub Pages and package the itch.io zip.
param(
	[switch]$Serve,
	[switch]$SkipItch,
	[int]$Port = 8060
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$GodotDir = Join-Path $PSScriptRoot "godot"
$GodotExe = Join-Path $GodotDir "Godot_v4.6.1-stable_win64.exe"
$ExportDir = Join-Path $ProjectRoot "builds\github"
$ExportHtml = Join-Path $ExportDir "index.html"

function Ensure-Godot {
	if (Test-Path $GodotExe) {
		return
	}

	New-Item -ItemType Directory -Force -Path $GodotDir | Out-Null
	$version = "4.6.1-stable"
	$editorZip = Join-Path $env:TEMP "Godot_v$version`_win64.exe.zip"
	$templatesTpz = Join-Path $env:TEMP "Godot_v$version`_export_templates.tpz"
	$editorUrl = "https://github.com/godotengine/godot/releases/download/$version/Godot_v$version`_win64.exe.zip"
	$templatesUrl = "https://github.com/godotengine/godot/releases/download/$version/Godot_v$version`_export_templates.tpz"
	$templatesDir = Join-Path $env:APPDATA "Godot\export_templates\4.6.1.stable"

	Write-Host "Downloading Godot $version editor..."
	Invoke-WebRequest -Uri $editorUrl -OutFile $editorZip
	Expand-Archive -Path $editorZip -DestinationPath $GodotDir -Force

	if (-not (Test-Path (Join-Path $templatesDir "web_nothreads_release.zip"))) {
		Write-Host "Downloading Godot $version export templates..."
		Invoke-WebRequest -Uri $templatesUrl -OutFile $templatesTpz
		Remove-Item -Path $templatesDir -Recurse -Force -ErrorAction SilentlyContinue
		New-Item -ItemType Directory -Force -Path $templatesDir | Out-Null
		$templatesZip = "$templatesTpz.zip"
		Copy-Item -Path $templatesTpz -Destination $templatesZip -Force
		Expand-Archive -Path $templatesZip -DestinationPath $templatesDir -Force
		Remove-Item -Path $templatesZip -Force -ErrorAction SilentlyContinue
		$nestedTemplates = Join-Path $templatesDir "templates"
		if (Test-Path $nestedTemplates) {
			Move-Item (Join-Path $nestedTemplates "*") $templatesDir -Force
			Remove-Item -Path $nestedTemplates -Recurse -Force
		}
	}
}

Ensure-Godot
New-Item -ItemType Directory -Force -Path $ExportDir | Out-Null
$nojekyll = Join-Path $ExportDir ".nojekyll"
if (-not (Test-Path $nojekyll)) {
	New-Item -ItemType File -Force -Path $nojekyll | Out-Null
}

Write-Host "Exporting Web build to $ExportHtml ..."
& $GodotExe --headless --path $ProjectRoot --export-release "Web" $ExportHtml
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
