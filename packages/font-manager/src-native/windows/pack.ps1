<#
.SYNOPSIS
  Packs the NativeScript.FontManager C++/WinRT component into a NuGet package so other C++/WinRT
  projects (e.g. @nativescript/canvas) can consume it via <PackageReference>.

.DESCRIPTION
  Uses the binaries already published to packages/font-manager/platforms/windows/{x64,arm64}
  (run publish.ps1 first if they are missing/stale). Bootstraps nuget.exe if it is not on PATH.
  The version defaults to the "version" field of packages/font-manager/package.json.

.PARAMETER Version
  Package version. Defaults to the npm package version.

.PARAMETER OutputDirectory
  Where to write the .nupkg. Defaults to <repo>/dist/nuget.

.EXAMPLE
  pwsh ./pack.ps1
  pwsh ./pack.ps1 -Version 1.0.2

.NOTES
  To publish:  nuget push <pkg>.nupkg -Source https://api.nuget.org/v3/index.json -ApiKey <KEY>
#>
param(
  [string] $Version,
  [string] $OutputDirectory
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$nuspec = Join-Path $root 'nuget\NativeScript.FontManager.nuspec'
$pkgJson = Join-Path $root '..\..\package.json'
$platformsRoot = Join-Path $root '..\..\platforms\windows'

# Verify the published binaries exist.
$required = @(
  (Join-Path $platformsRoot 'x64\NativeScript.FontManager.dll'),
  (Join-Path $platformsRoot 'x64\NativeScript.FontManager.winmd'),
  (Join-Path $platformsRoot 'arm64\NativeScript.FontManager.dll')
)
foreach ($f in $required) {
  if (-not (Test-Path $f)) { throw "Missing $f - run publish.ps1 first." }
}

# Resolve version from package.json when not supplied.
if (-not $Version) {
  $Version = (Get-Content -Raw -LiteralPath $pkgJson | ConvertFrom-Json).version
  if (-not $Version) { throw 'Could not read version from package.json; pass -Version.' }
}

if (-not $OutputDirectory) {
  $OutputDirectory = Join-Path $root '..\..\..\..\dist\nuget'
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null

# Resolve nuget.exe (PATH, else bootstrap to TEMP).
$nuget = (Get-Command nuget -ErrorAction SilentlyContinue).Source
if (-not $nuget) {
  $nuget = Join-Path $env:TEMP 'nuget.exe'
  if (-not (Test-Path $nuget)) {
    Write-Host 'Downloading nuget.exe...'
    Invoke-WebRequest -Uri 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' -OutFile $nuget
  }
}
Write-Host "Using nuget: $nuget"
Write-Host "Packing NativeScript.FontManager $Version"

& $nuget pack $nuspec -Version $Version -OutputDirectory $OutputDirectory -NoDefaultExcludes -NonInteractive
if ($LASTEXITCODE -ne 0) { throw "nuget pack failed ($LASTEXITCODE)" }

$pkg = Join-Path $OutputDirectory "NativeScript.FontManager.$Version.nupkg"
Write-Host "`nCreated: $pkg" -ForegroundColor Green
Write-Host "Publish with:" -ForegroundColor Cyan
Write-Host "  nuget push `"$pkg`" -Source https://api.nuget.org/v3/index.json -ApiKey <YOUR_KEY>"
