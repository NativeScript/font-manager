<#
.SYNOPSIS
  Builds the NativeScript.FontManager C++/WinRT component and copies the resulting .dll + .winmd
  into packages/font-manager/platforms/windows/{x64,arm64} (the layout the NativeScript Windows
  runtime consumes, matching @nativescript/core's platforms/windows).

.PARAMETER Platforms
  Which platforms to build. Defaults to x64 and ARM64.

.PARAMETER Configuration
  MSBuild configuration. Defaults to Release.

.EXAMPLE
  pwsh ./publish.ps1
  pwsh ./publish.ps1 -Platforms x64
#>
param(
  [string[]] $Platforms = @('x64', 'ARM64'),
  [string] $Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$project = Join-Path $root 'FontManager\NativeScript.FontManager.vcxproj'
$platformsRoot = Join-Path $root '..\..\platforms\windows'

# Resolve MSBuild via vswhere.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw "vswhere not found - install Visual Studio 2022/2026 with the C++ workload." }
$msbuild = & $vswhere -latest -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
if (-not $msbuild) { throw 'MSBuild.exe not found via vswhere.' }
Write-Host "Using MSBuild: $msbuild"

# arch folder name per platform (matches core/platforms/windows: x64, arm64).
$archFolder = @{ 'x64' = 'x64'; 'ARM64' = 'arm64' }

$built = @()
$failed = @()

foreach ($plat in $Platforms) {
  Write-Host "`n=== Building $plat | $Configuration ===" -ForegroundColor Cyan
  $outDir = Join-Path $root "FontManager\bin\$plat\$Configuration\"
  try {
    & $msbuild $project -restore `
      -p:Configuration=$Configuration `
      -p:Platform=$plat `
      "-p:OutDir=$outDir" `
      -m -v:minimal
    if ($LASTEXITCODE -ne 0) { throw "MSBuild exited with code $LASTEXITCODE" }

    $dll = Join-Path $outDir 'NativeScript.FontManager.dll'
    $winmd = Join-Path $outDir 'NativeScript.FontManager.winmd'
    if (-not (Test-Path $dll)) { throw "expected output missing: $dll" }
    if (-not (Test-Path $winmd)) { throw "expected output missing: $winmd" }

    $dest = Join-Path $platformsRoot $archFolder[$plat]
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item $dll $dest -Force
    Copy-Item $winmd $dest -Force
    Write-Host "Copied NativeScript.FontManager.{dll,winmd} -> $dest" -ForegroundColor Green
    $built += $plat
  }
  catch {
    Write-Warning "Build/publish for $plat failed: $($_.Exception.Message)"
    $failed += $plat
  }
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
if ($built.Count)  { Write-Host "Published: $($built -join ', ')" -ForegroundColor Green }
if ($failed.Count) { Write-Host "Failed/skipped: $($failed -join ', ')" -ForegroundColor Yellow }
if (-not $built.Count) { throw 'No platforms were published.' }
