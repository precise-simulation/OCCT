param(
  [Parameter(Mandatory)]
  [ValidateSet('Shared', 'Static')]
  [string]$Linkage,

  [Parameter(Mandatory)]
  [string]$SourceDir,

  [Parameter(Mandatory)]
  [string]$BuildDir,

  [Parameter(Mandatory)]
  [string]$InstallDir,

  [Parameter(Mandatory)]
  [ValidateSet('Production', 'Default')]
  [string]$BuildOptProfile,

  [Parameter(Mandatory)]
  [string]$BuildEnvName,

  [Parameter(Mandatory)]
  [string]$InstallEnvName
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lean-profile.ps1')

$toolkits = $LeanRootToolkits -join ';'
$configure = @(
  '-S', $SourceDir,
  '-B', $BuildDir,
  '-G', 'Visual Studio 17 2022',
  '-A', 'x64',
  "-DBUILD_LIBRARY_TYPE:STRING=$Linkage",
  '-DCMAKE_POLICY_DEFAULT_CMP0091=NEW',
  '-DCMAKE_MSVC_RUNTIME_LIBRARY:STRING=MultiThreadedDLL',
  "-DBUILD_OPT_PROFILE=$BuildOptProfile",
  '-DBUILD_USE_PCH=OFF'
)
foreach ($option in $LeanDisabledCMakeOptions) {
  $configure += "-D$option=OFF"
}
$configure += @(
  "-DBUILD_ADDITIONAL_TOOLKITS=$toolkits",
  '-DUSE_MMGR_TYPE=NATIVE',
  '-D3RDPARTY_DIR=',
  "-DINSTALL_DIR=$InstallDir"
)

& cmake @configure
if ($LASTEXITCODE -ne 0) { throw 'OCCT configure failed.' }

$cache = (Get-Content (Join-Path $BuildDir 'CMakeCache.txt') -Raw) -replace "`r`n?", "`n"
foreach ($required in @(
  "BUILD_LIBRARY_TYPE:STRING=$Linkage",
  'CMAKE_MSVC_RUNTIME_LIBRARY:STRING=MultiThreadedDLL',
  "BUILD_OPT_PROFILE:STRING=$BuildOptProfile",
  'USE_MMGR_TYPE:STRING=NATIVE'
)) {
  if (-not $cache.Contains($required)) {
    throw "Expected CMake cache entry missing: $required"
  }
}

foreach ($option in $LeanDisabledCMakeOptions) {
  $match = [regex]::Match($cache, "(?m)^$([regex]::Escape($option)):[^=]*=(.*)$")
  if ($match.Success -and $match.Groups[1].Value.Trim() -ne 'OFF') {
    throw "CMake cache option is not disabled: $option=$($match.Groups[1].Value.Trim())"
  }
}

$toolkitPattern = [regex]::Escape($toolkits)
if ($cache -notmatch "(?m)^BUILD_ADDITIONAL_TOOLKITS:[^=]*=$toolkitPattern$") {
  throw 'BUILD_ADDITIONAL_TOOLKITS does not match the lean root toolkit set.'
}
if ($cache -notmatch '(?m)^3RDPARTY_DIR:[^=]*=$') {
  throw '3RDPARTY_DIR is not empty in the CMake cache.'
}

$toolkitProjects = @(Get-ChildItem $BuildDir -File -Recurse -Filter 'TK*.vcxproj')
if ($toolkitProjects.Count -eq 0) {
  throw 'No OCCT toolkit Visual Studio projects were generated.'
}
foreach ($project in $toolkitProjects) {
  $projectText = Get-Content $project.FullName -Raw
  if (-not $projectText.Contains('<RuntimeLibrary>MultiThreadedDLL</RuntimeLibrary>')) {
    throw "$($project.Name) does not encode the /MD runtime contract."
  }
  if ($projectText.Contains('<RuntimeLibrary>MultiThreaded</RuntimeLibrary>')) {
    throw "$($project.Name) unexpectedly encodes the /MT runtime."
  }
}

"$BuildEnvName=$BuildDir" >> $env:GITHUB_ENV
"$InstallEnvName=$InstallDir" >> $env:GITHUB_ENV
