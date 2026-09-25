<#
.SYNOPSIS
  Builds the TensorFlow Lite C shared library for Windows x64 and stages it into
  native/third_party/tflite.

.DESCRIPTION
  The result of this script is already committed to the repository, so a normal
  `flutter build windows` needs nothing from here. Run it only to refresh the
  vendored binary, to move to a new TensorFlow release, or to verify the
  committed artifacts are reproducible.

  Steps: shallow-clone the pinned TensorFlow tag, apply
  tflite-<ref>-proton.patch, build tensorflow/lite/c, then stage the headers and
  libraries. See ../README.md for what each patch hunk is for.

  Requires: git, cmake, ninja, and Visual Studio 2019+ with the C++ toolchain.

.EXAMPLE
  ./build_tflite.ps1
.EXAMPLE
  ./build_tflite.ps1 -WorkDir D:\tflite -Ref v2.17.0
#>
[CmdletBinding()]
param(
  # TensorFlow git tag to build. A matching tflite-<ref>-proton.patch must exist
  # next to this script; patches are not portable across releases.
  [string]$Ref = 'v2.17.0',

  # Scratch directory for the TensorFlow clone and the CMake build tree. Kept
  # outside the repo by default because it grows to several GB.
  [string]$WorkDir = (Join-Path $env:TEMP 'proton-tflite-build'),

  # Skip staging, e.g. to inspect the build output before committing it.
  [switch]$NoStage
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Abi        = 'windows-x64'
$ToolsDir   = $PSScriptRoot
$VendorDir  = Join-Path (Split-Path $ToolsDir -Parent) 'third_party/tflite'
$PatchFile  = Join-Path $ToolsDir "tflite-$Ref-proton.patch"
$SourceDir  = Join-Path $WorkDir 'tensorflow_src'
$BuildDir   = Join-Path $WorkDir 'build-c'

function Step($message) { Write-Host "==> $message" -ForegroundColor Cyan }

foreach ($tool in 'git', 'cmake', 'ninja') {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
    throw "$tool is required but was not found on PATH."
  }
}
if (-not (Test-Path $PatchFile)) {
  throw "No patch for $Ref at $PatchFile. Building a different TensorFlow release needs its own patch."
}

# The MSVC environment has to be active for the compiler, and vcvars64 can only
# export it into a cmd session, so the cmake calls below are wrapped in one.
Step 'Locating Visual Studio'
$vsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (-not (Test-Path $vsWhere)) { throw "vswhere.exe not found; install Visual Studio 2019 or newer." }
$vsRoot = & $vsWhere -latest -products * `
  -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsRoot) { throw 'No Visual Studio installation with the C++ toolchain was found.' }
$vcVars = Join-Path $vsRoot 'VC/Auxiliary/Build/vcvars64.bat'
if (-not (Test-Path $vcVars)) { throw "vcvars64.bat not found under $vsRoot." }
Write-Host "    $vsRoot"

function Invoke-InVcEnv([string]$CommandLine) {
  # stderr is merged so CMake's progress output is not mistaken for failure.
  cmd /c "`"$vcVars`" >nul 2>&1 && $CommandLine" 2>&1 | ForEach-Object { Write-Host $_ }
  if ($LASTEXITCODE -ne 0) { throw "Command failed ($LASTEXITCODE): $CommandLine" }
}

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

if (Test-Path (Join-Path $SourceDir '.git')) {
  Step "Reusing TensorFlow clone at $SourceDir"
} else {
  Step "Cloning TensorFlow $Ref (shallow)"
  & git clone --depth 1 --branch $Ref https://github.com/tensorflow/tensorflow.git $SourceDir
  if ($LASTEXITCODE -ne 0) { throw "git clone failed ($LASTEXITCODE)." }
}

Step "Applying $(Split-Path $PatchFile -Leaf)"
# --reverse --check succeeds only when the patch is already in the tree, which
# makes re-running this script safe.
& git -C $SourceDir apply --reverse --check $PatchFile 2>$null
if ($LASTEXITCODE -eq 0) {
  Write-Host '    already applied, skipping'
} else {
  & git -C $SourceDir apply --verbose $PatchFile
  if ($LASTEXITCODE -ne 0) { throw "Failed to apply $PatchFile ($LASTEXITCODE)." }
}

# Building tensorflow/lite/c (rather than tensorflow/lite) yields the
# self-contained tensorflowlite_c library; the plugin links the C API only.
# TFLITE_C_BUILD_SHARED_LIBS defaults to ON there and is set explicitly so the
# intent survives a CMake default change.
Step 'Configuring (Release, Ninja)'
Invoke-InVcEnv "cmake -G Ninja -S `"$SourceDir/tensorflow/lite/c`" -B `"$BuildDir`" -DCMAKE_BUILD_TYPE=Release -DTFLITE_C_BUILD_SHARED_LIBS=ON"

Step 'Building tensorflowlite_c (this takes a while)'
Invoke-InVcEnv "cmake --build `"$BuildDir`" --config Release"

$dll = Join-Path $BuildDir 'tensorflowlite_c.dll'
$lib = Join-Path $BuildDir 'tensorflowlite_c.lib'
foreach ($artifact in $dll, $lib) {
  if (-not (Test-Path $artifact)) { throw "Expected build output missing: $artifact" }
}

if ($NoStage) {
  Step "Build complete; staging skipped. Artifacts in $BuildDir"
  return
}

Step "Staging into third_party/tflite"
$incDir = Join-Path $VendorDir 'include'
$libDir = Join-Path $VendorDir "lib/$Abi"
if (Test-Path $incDir) { Remove-Item -Recurse -Force $incDir }
New-Item -ItemType Directory -Force -Path $incDir, $libDir | Out-Null

# Only the C API surface and what it includes transitively; the full tree is
# ~4000 headers and the plugin compiles against none of the C++ API.
#
# include/ is shared by every platform, which is safe because the same tag and
# patch produce the same headers no matter which platform stages them.
$headerDirs = @(
  'tensorflow/lite/c',
  'tensorflow/lite/core',
  'tensorflow/lite/core/c',
  'tensorflow/lite/core/async/c'
)
$staged = 0
foreach ($rel in $headerDirs) {
  $from = Join-Path $SourceDir $rel
  $to   = Join-Path $incDir $rel
  New-Item -ItemType Directory -Force -Path $to | Out-Null
  foreach ($header in Get-ChildItem $from -Filter *.h -File) {
    Copy-Item -Force $header.FullName $to
    $staged++
  }
}
# builtin_ops.h is the one header needed from tensorflow/lite itself.
Copy-Item -Force (Join-Path $SourceDir 'tensorflow/lite/builtin_ops.h') (Join-Path $incDir 'tensorflow/lite')
$staged++

Copy-Item -Force $dll, $lib $libDir
# Apache-2.0 requires the licence to travel with the redistributed binary.
Copy-Item -Force (Join-Path $SourceDir 'LICENSE') (Join-Path $VendorDir 'LICENSE')

Write-Host ''
Step 'Done'
Write-Host "    $staged headers -> $incDir"
Write-Host "    tensorflowlite_c.dll/.lib -> $libDir"
Write-Host "    Update the version table in native/README.md if $Ref changed, then commit."
