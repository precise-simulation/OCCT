param(
  [Parameter(Mandatory)]
  [ValidateSet('Shared', 'Static')]
  [string]$Linkage,

  [Parameter(Mandatory)]
  [string]$InstallDir,

  [Parameter(Mandatory)]
  [string]$ToolkitsEnvName,

  [string]$BinaryDirEnvName
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lean-profile.ps1')

function Find-Dumpbin {
  $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
  if (-not (Test-Path -LiteralPath $vswhere)) {
    throw "vswhere.exe not found: $vswhere"
  }
  $dumpbin = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find 'VC\Tools\MSVC\**\bin\Hostx64\x64\dumpbin.exe' | Select-Object -First 1).Trim()
  if (-not $dumpbin -or -not (Test-Path -LiteralPath $dumpbin)) {
    throw 'dumpbin.exe was not found in the Visual Studio installation.'
  }
  return $dumpbin
}

$config = Join-Path $InstallDir 'cmake/OpenCASCADEConfig.cmake'
if (-not (Test-Path -LiteralPath $config)) {
  throw "Missing OpenCASCADEConfig.cmake: $config"
}

if ($Linkage -eq 'Shared') {
  $shared = Select-String -Path $config -Pattern '^set \(OpenCASCADE_BUILD_SHARED_LIBS +ON\)$' | Select-Object -First 1
  if (-not $shared) {
    throw 'Installed OpenCASCADEConfig.cmake does not report a shared build.'
  }
}

$match = Select-String -Path $config -Pattern '^set \(OpenCASCADE_LIBRARIES (.*)\)$' | Select-Object -First 1
if (-not $match) {
  throw 'OpenCASCADE_LIBRARIES was not found.'
}
$libs = @($match.Matches[0].Groups[1].Value -split ';')
if ($libs.Count -ne $LeanExpectedToolkits.Count) {
  throw "Expected $($LeanExpectedToolkits.Count)-toolkit closure, got $($libs.Count): $($libs -join ',')"
}
$toolkitDiff = @(Compare-Object ($LeanExpectedToolkits | Sort-Object) ($libs | Sort-Object))
if ($toolkitDiff.Count -ne 0) {
  throw "Lean $($Linkage.ToLowerInvariant()) toolkit closure mismatch: $($toolkitDiff | Out-String)"
}
if ($libs -contains 'TKDECascade') {
  throw 'Unexpected TKDECascade in lean toolkit closure.'
}

$dumpbin = Find-Dumpbin
$files = @(Get-ChildItem $InstallDir -File -Recurse)
$installBytes = ($files | Measure-Object Length -Sum).Sum

if ($Linkage -eq 'Shared') {
  $binaryDir = Join-Path $InstallDir 'win64/vc14/bin'
  $libraryDir = Join-Path $InstallDir 'win64/vc14/lib'
  if (-not (Test-Path -LiteralPath $binaryDir)) {
    throw "Missing shared binary directory: $binaryDir"
  }
  if (-not (Test-Path -LiteralPath $libraryDir)) {
    throw "Missing shared library directory: $libraryDir"
  }

  $dlls = @(Get-ChildItem $binaryDir -File -Filter 'TK*.dll')
  $importLibs = @(Get-ChildItem $libraryDir -File -Filter 'TK*.lib')
  if ($dlls.Count -ne $LeanExpectedToolkits.Count) {
    throw "Expected $($LeanExpectedToolkits.Count) shared OCCT DLLs, got $($dlls.Count)."
  }
  if ($importLibs.Count -ne $LeanExpectedToolkits.Count) {
    throw "Expected $($LeanExpectedToolkits.Count) OCCT import libraries, got $($importLibs.Count)."
  }
  foreach ($toolkit in $libs) {
    if (-not (Test-Path -LiteralPath (Join-Path $binaryDir "$toolkit.dll"))) {
      throw "Missing shared toolkit DLL: $toolkit.dll"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $libraryDir "$toolkit.lib"))) {
      throw "Missing shared toolkit import library: $toolkit.lib"
    }
  }

  $allDlls = @(Get-ChildItem $InstallDir -File -Recurse -Filter '*.dll')
  if ($allDlls.Count -ne $LeanExpectedToolkits.Count) {
    throw "Lean shared install contains unexpected non-OCCT DLLs: $($allDlls.Name -join ',')"
  }

  foreach ($dll in $dlls) {
    $deps = (& $dumpbin /dependents $dll.FullName 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) {
      throw "dumpbin /dependents failed for $($dll.Name)."
    }
    if ($deps -match $LeanExcludedDependencyPattern) {
      throw "$($dll.Name) imports an excluded optional dependency."
    }
  }

  $dllBytes = ($dlls | Measure-Object Length -Sum).Sum
  Write-Host "toolkit-count=$($libs.Count)"
  Write-Host "toolkits=$($libs -join ',')"
  Write-Host "occt-install-bytes=$installBytes"
  Write-Host ("occt-install-mib={0:N3}" -f ($installBytes / 1MB))
  Write-Host "occt-shared-dll-bytes=$dllBytes"
  Write-Host ("occt-shared-dll-mib={0:N3}" -f ($dllBytes / 1MB))
  "$ToolkitsEnvName=$($libs -join ',')" >> $env:GITHUB_ENV
  if ($BinaryDirEnvName) {
    "$BinaryDirEnvName=$binaryDir" >> $env:GITHUB_ENV
  }
  return
}

$dlls = @(Get-ChildItem $InstallDir -File -Recurse -Filter '*.dll')
$staticLibs = @(Get-ChildItem $InstallDir -File -Recurse -Filter '*.lib')
if ($dlls.Count -ne 0) {
  throw "Static install unexpectedly contains DLLs: $($dlls.Name -join ',')"
}
if ($staticLibs.Count -ne $LeanExpectedToolkits.Count) {
  throw "Expected $($LeanExpectedToolkits.Count) static OCCT libraries, got $($staticLibs.Count)."
}

$dynamicCrtEvidence = 0
foreach ($lib in $staticLibs) {
  $directives = (& $dumpbin /directives $lib.FullName 2>&1 | Out-String)
  if ($LASTEXITCODE -ne 0) {
    throw "dumpbin /directives failed for $($lib.Name)."
  }
  if ($directives -match '(?i)DEFAULTLIB:"?LIBCMT') {
    throw "$($lib.Name) contains static MSVC CRT /MT directives."
  }
  if ($directives -match '(?i)DEFAULTLIB:"?MSVCRT') {
    $dynamicCrtEvidence++
  }
}
if ($dynamicCrtEvidence -eq 0) {
  throw 'Static OCCT libraries do not expose /MD MSVCRT directive evidence.'
}

$libBytes = ($staticLibs | Measure-Object Length -Sum).Sum
$pdbs = @(Get-ChildItem $InstallDir -File -Recurse -Filter '*.pdb')
$pdbBytes = ($pdbs | Measure-Object Length -Sum).Sum
if ($null -eq $pdbBytes) {
  $pdbBytes = 0
}
Write-Host "toolkit-count=$($libs.Count)"
Write-Host "toolkits=$($libs -join ',')"
Write-Host "occt-install-bytes=$installBytes"
Write-Host ("occt-install-mib={0:N3}" -f ($installBytes / 1MB))
Write-Host "occt-static-libs-bytes=$libBytes"
Write-Host ("occt-static-libs-mib={0:N3}" -f ($libBytes / 1MB))
Write-Host "occt-pdb-count=$($pdbs.Count)"
Write-Host ("occt-pdb-mib={0:N3}" -f ($pdbBytes / 1MB))
"$ToolkitsEnvName=$($libs -join ',')" >> $env:GITHUB_ENV
