# Shared Godot editor + export template setup for build scripts.
$script:ProjectRoot = Split-Path -Parent $PSScriptRoot
$script:GodotDir = Join-Path $PSScriptRoot "godot"
$script:GodotExe = Join-Path $GodotDir "Godot_v4.6.1-stable_win64.exe"
$script:GodotVersion = "4.6.1-stable"
$script:TemplatesDir = Join-Path $env:APPDATA "Godot\export_templates\4.6.1.stable"

function Ensure-Godot {
	param(
		[string[]]$RequiredTemplates = @("web_nothreads_release.zip")
	)

	if (-not (Test-Path $GodotExe)) {
		New-Item -ItemType Directory -Force -Path $GodotDir | Out-Null
		$editorZip = Join-Path $env:TEMP "Godot_v$GodotVersion`_win64.exe.zip"
		$editorUrl = "https://github.com/godotengine/godot/releases/download/$GodotVersion/Godot_v$GodotVersion`_win64.exe.zip"
		Write-Host "Downloading Godot $GodotVersion editor..."
		Invoke-WebRequest -Uri $editorUrl -OutFile $editorZip
		Expand-Archive -Path $editorZip -DestinationPath $GodotDir -Force
	}

	$missingTemplates = @()
	foreach ($template in $RequiredTemplates) {
		if (-not (Test-Path (Join-Path $TemplatesDir $template))) {
			$missingTemplates += $template
		}
	}

	if ($missingTemplates.Count -eq 0) {
		return
	}

	$templatesTpz = Join-Path $env:TEMP "Godot_v$GodotVersion`_export_templates.tpz"
	$templatesUrl = "https://github.com/godotengine/godot/releases/download/$GodotVersion/Godot_v$GodotVersion`_export_templates.tpz"
	Write-Host "Downloading Godot $GodotVersion export templates..."
	Invoke-WebRequest -Uri $templatesUrl -OutFile $templatesTpz
	Remove-Item -Path $TemplatesDir -Recurse -Force -ErrorAction SilentlyContinue
	New-Item -ItemType Directory -Force -Path $TemplatesDir | Out-Null
	$templatesZip = "$templatesTpz.zip"
	Copy-Item -Path $templatesTpz -Destination $templatesZip -Force
	Expand-Archive -Path $templatesZip -DestinationPath $TemplatesDir -Force
	Remove-Item -Path $templatesZip -Force -ErrorAction SilentlyContinue
	$nestedTemplates = Join-Path $TemplatesDir "templates"
	if (Test-Path $nestedTemplates) {
		Move-Item (Join-Path $nestedTemplates "*") $TemplatesDir -Force
		Remove-Item -Path $nestedTemplates -Recurse -Force
	}

	foreach ($template in $RequiredTemplates) {
		if (-not (Test-Path (Join-Path $TemplatesDir $template))) {
			throw "Missing export template: $template"
		}
	}
}

function Invoke-GodotExport {
	param(
		[string]$PresetName,
		[string]$ExportPath
	)

	$exportDir = Split-Path -Parent $ExportPath
	if ($exportDir -and -not (Test-Path $exportDir)) {
		New-Item -ItemType Directory -Force -Path $exportDir | Out-Null
	}

	Write-Host "Exporting $PresetName to $ExportPath ..."
	& $GodotExe --headless --path $ProjectRoot --export-release $PresetName $ExportPath

	$deadline = (Get-Date).AddMinutes(10)
	while (-not (Test-Path $ExportPath) -and (Get-Date) -lt $deadline) {
		Start-Sleep -Milliseconds 250
	}
	if (-not (Test-Path $ExportPath)) {
		throw "Godot export failed; $ExportPath was not created."
	}
}
