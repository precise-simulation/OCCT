# Lean shared OCCT SDK plan

Status: ready for implementation

Target branch: `OCCT-801`

## Goal

Produce a lean OCCT SDK profile for Geomtool-style geometry and data-exchange
consumers on Windows, Linux, and macOS, without unused visualization, media, VR,
font, image, parallel-runtime, or alternate-memory-manager dependencies.

The target is the already-qualified toolkit closure rooted at:

```text
TKDESTEP
TKDEIGES
TKDESTL
TKOffset
TKMesh
```

OCCT 8.0.1 resolves those roots to the 28-toolkit closure already qualified by
the Windows static SDK. That closure includes `TKService` and `TKV3d`
transitively because the data-exchange toolkits require them. The plan keeps
those OCCT toolkits but builds them with their optional external backends
disabled.

## Current state

Windows shared is the main outlier. `.github/workflows/build-windows-packages.yml`
currently downloads and republishes upstream OCCT 8.0.1's full shared package,
`occt-combined-release-no-pch.zip`. That package contains runtime dependencies
that the intended geometry/data-exchange consumers do not use directly,
including FreeType, FreeImage, FFmpeg, OpenVR, and the alternate OCCT memory
manager dependency.

Windows static already demonstrates the desired lean dependency and toolkit
model:

- all broad OCCT modules are disabled;
- `BUILD_ADDITIONAL_TOOLKITS=TKDESTEP;TKDEIGES;TKDESTL;TKOffset;TKMesh`;
- the installed closure is exactly 28 OCCT toolkits;
- `TKDECascade` is rejected;
- FreeType, FreeImage, FFmpeg, OpenVR, RapidJSON, Draco, TBB, Eigen, Tcl/Tk,
  VTK, OpenGL, GLES, and D3D are disabled;
- `USE_MMGR_TYPE=NATIVE`;
- `3RDPARTY_DIR` is empty.

Linux and macOS already disable visualization and the optional third-party
integrations above for both shared and static packages. They therefore should
not carry the Windows-style FreeImage/FFmpeg/OpenVR runtime baggage. However,
their builders still enable the complete FoundationClasses, ModelingData,
ModelingAlgorithms, ApplicationFramework, and DataExchange modules, so they
build more OCCT toolkits than the proven 28-toolkit consumer closure.

## Required lean profile

Use the equivalent of the following CMake configuration on all source-built SDK
producers:

```text
BUILD_MODULE_Draw=OFF
BUILD_MODULE_FoundationClasses=OFF
BUILD_MODULE_ModelingData=OFF
BUILD_MODULE_ModelingAlgorithms=OFF
BUILD_MODULE_ApplicationFramework=OFF
BUILD_MODULE_DataExchange=OFF
BUILD_MODULE_Visualization=OFF
BUILD_ADDITIONAL_TOOLKITS=TKDESTEP;TKDEIGES;TKDESTL;TKOffset;TKMesh

USE_FREETYPE=OFF
USE_FREEIMAGE=OFF
USE_FFMPEG=OFF
USE_OPENVR=OFF
USE_RAPIDJSON=OFF
USE_DRACO=OFF
USE_TBB=OFF
USE_EIGEN=OFF
USE_TCL=OFF
USE_TK=OFF
USE_VTK=OFF
USE_OPENGL=OFF
USE_GLES2=OFF
USE_D3D=OFF
USE_MMGR_TYPE=NATIVE
3RDPARTY_DIR=
```

Keep platform-specific switches such as `USE_XLIB=OFF`, deployment targets,
install-name settings, compiler/runtime selection, generators, and optimization
profiles in their existing platform producers.

The exact 28-toolkit closure qualified for OCCT 8.0.1 is:

```text
TKDESTEP
TKDE
TKBRep
TKernel
TKMath
TKXSBase
TKTopAlgo
TKG2d
TKCAF
TKCDF
TKLCAF
TKG3d
TKXCAF
TKShHealing
TKGeomBase
TKGeomAlgo
TKBO
TKPrim
TKService
TKV3d
TKVCAF
TKMesh
TKHLR
TKDEIGES
TKBool
TKDESTL
TKOffset
TKFillet
```

`TKDECascade` is not part of this profile.

## Implementation

### 1. Replace the Windows shared upstream package with a lean shared build

Update `.github/workflows/build-windows-packages.yml` so the shared job builds
from the pinned OCCT source
`b8f597c677811d1f9f4d8a97f5ae2825c0353a42` instead of downloading the full
upstream shared ZIP.

Build x64 Release with:

- `BUILD_LIBRARY_TYPE=Shared`;
- `CMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL`;
- the five toolkit roots above;
- the all-optional-off profile;
- `USE_MMGR_TYPE=NATIVE`;
- no third-party bundle.

Preserve the existing VC143 /MD ABI contract. Package the installed headers,
CMake package files, required OCCT DLL/import libraries, licenses, provenance
metadata, and checksum.

Inspect every packaged OCCT DLL with `dumpbin /dependents`. Reject imports from
disabled optional runtime families, including:

- FreeType and FreeImage;
- `avcodec`, `avformat`, `avutil`, and `swscale`;
- `openvr_api`;
- TBB and tbbmalloc;
- jemalloc.

Use family/pattern checks where runtime filenames are versioned rather than
pinning one historic DLL suffix.

### 2. Narrow Linux shared and static packages to the same toolkit closure

Update `.github/linux-occt-sdk/build-sdk.sh` to disable the broad module
switches and request only the five root toolkits through
`BUILD_ADDITIONAL_TOOLKITS`.

Preserve:

- the pinned manylinux2014 producer;
- glibc 2.17 compatibility;
- existing shared/static linkage behavior;
- reproducible packaging;
- relocation checks;
- symbol verification;
- Ubuntu 20.04, 22.04, and 24.04 consumer qualification.

Extend `.github/linux-occt-sdk/sdk_tools.py` so validation requires exactly the
28 expected OCCT toolkit names and rejects `TKDECascade`. Keep the existing
optional-runtime dependency rejection.

### 3. Narrow macOS shared and static packages to the same toolkit closure

Update `.github/macos-occt-sdk/build-sdk.sh` analogously.

Preserve:

- native arm64 and x86_64 packages;
- macOS 13.0 deployment target;
- the selected Xcode 16.4 toolchain;
- shared `@rpath` install-name behavior;
- static framework normalization;
- reproducible archive behavior;
- relocation and external-consumer qualification.

Extend `.github/macos-occt-sdk/sdk_tools.py` so validation requires the same
28 toolkit names and rejects `TKDECascade`. Keep the existing rejection of
disabled optional dependencies.

### 4. Make the lean closure part of the package contract

For all three platforms, package validation must establish both:

1. the OCCT toolkit set is exactly the intended 28-toolkit closure; and
2. shared binaries have no runtime dependency on any disabled optional
   integration.

Do not treat the absence of optional files in the archive alone as sufficient.
Inspect the binary dependency graph so missing runtime files cannot be hidden by
the producer environment.

Keep `TKService` and `TKV3d` when OCCT's data-exchange dependency graph
requires them. This work does not patch upstream OCCT toolkit dependency
metadata merely to remove their names from the package; it removes their unused
external backends.

### 5. Keep external-consumer qualification representative

Continue the existing external consumer that creates a box and writes STEP.

Add or retain focused checks sufficient to prove the five root toolkit families
are consumable from the final packaged SDK, covering STEP, IGES, STL, and the
modeling functionality required by the `TKOffset`/`TKMesh` roots without
turning the OCCT producer into Geomtool's functional test suite.

Run the consumers from relocated or freshly extracted packages without access to
the build/install staging tree.

### 6. Update the combined SDK release contract

Update:

- `.github/occt-sdk-release/release-template.yml`;
- `.github/occt-sdk-release/verify-release-assets.sh`;
- `.github/occt-sdk-release/README.md`.

Remove the contract that identifies the Windows shared SDK as the upstream full
`occt-combined-release-no-pch.zip` once the source-built shared artifact is
qualified.

Preserve exact source/workflow provenance, adjacent SHA-256 sidecars, exact
asset inventory, draft-release verification, digest verification after upload,
and immutable release publication.

Publish this as a new SDK release revision/tag. Do not replace or mutate
`occt-sdk-8.0.1-r2`.

### 7. Migrate downstream packages after the new OCCT SDK release

After the new OCCT SDK release is immutable:

1. update the precise-simulation Netgen SDK producer to consume the new lean
   shared OCCT SDK and regenerate its qualified OCCT runtime-closure metadata;
2. update Geomtool's OCCT release/tag/hash pins;
3. remove Geomtool's direct `TKDECascade` declaration where it is still
   present;
4. retain Geomtool's recursive dependency-driven Windows runtime packaging.

The final Geomtool Windows ZIP should lose FreeImage, FreeType, FFmpeg, OpenVR,
TBB, and jemalloc dependencies naturally because those imports no longer exist,
rather than through a packaging deny-list.

## Acceptance criteria

- Windows, Linux, and macOS shared SDKs expose the same qualified 28-toolkit
  closure for the geometry/data-exchange profile.
- Static SDKs use the same toolkit roots and closure on every platform where
  static packaging is supported.
- `TKDECascade` is absent from the lean SDK closure.
- Windows shared no longer republishes the upstream full shared ZIP.
- Shared SDK binaries have no runtime dependency on FreeType, FreeImage, FFmpeg,
  OpenVR, TBB/tbbmalloc, or jemalloc.
- Disabled optional third-party libraries are not shipped merely because they
  exist in a producer environment.
- Existing platform ABI/runtime contracts remain intact:
  - VC143 /MD on Windows;
  - glibc 2.17 baseline on Linux;
  - macOS 13 deployment target on arm64 and x86_64.
- Final packaged SDKs remain relocatable and pass external consumer
  configure/build/run from freshly extracted artifacts.
- Release verification continues to require exact provenance, checksums, and
  asset inventory.
- The new SDK is published under a new immutable release revision and then
  consumed by Netgen and Geomtool.

## Validation

All compilation, binary inspection requiring produced artifacts, external
consumer builds, runtime checks, and package qualification run on GitHub Actions
runners. Local work is limited to static inspection and workflow/script syntax
checks, consistent with this repository's development instructions.
