# Lean OCCT SDK profile

Status: implemented for `occt-sdk-8.0.1-r3`

Target branch: `OCCT-801`

This file records the design decisions behind the lean OCCT SDK profile. The
original implementation plan was completed by commit `07671f0089`
(`build: add lean OCCT SDK release profile`) and released as
`occt-sdk-8.0.1-r3` from commit `39db8383d6`. The one-shot active release
workflow was removed after publication; the retained release template and
release README document the current reusable process.

## Design

The lean profile targets geometry and data-exchange consumers without unused
visualization backends or optional third-party runtimes. All broad OCCT modules
are disabled and the source builds explicitly request these toolkit roots:

```text
TKDESTEP
TKDEIGES
TKDESTL
TKOffset
TKMesh
```

For OCCT 8.0.1 those roots resolve to the qualified 28-toolkit closure enforced
by the platform package validators. `TKService` and `TKV3d` remain in that
closure because they are transitively required by the selected data-exchange
toolkits; their unused optional external backends are disabled instead of
patching OCCT's toolkit dependency metadata. `TKDECascade` is explicitly
excluded.

The source-built producers disable FreeType, FreeImage, FFmpeg, OpenVR,
RapidJSON, Draco, TBB, Eigen, Tcl/Tk, VTK, OpenGL, GLES2, and D3D, use the
native OCCT memory manager, and leave `3RDPARTY_DIR` empty. Platform-specific
settings such as `USE_XLIB`, deployment targets, generators, compiler/runtime
selection, and optimization settings remain in the individual producers.

## Package contract

Validation for every platform establishes the exact OCCT toolkit closure from
both the installed libraries and the exported CMake package. Shared builds also
inspect binary dependencies so a disabled optional runtime cannot be hidden by
the producer environment merely because its files are omitted from the archive.

The final packages are qualified through external consumers from relocated or
freshly extracted SDKs. Those consumers exercise STEP, IGES, STL, offsetting,
and meshing so all five requested root families participate in qualification.

The OCCT 8.0.1 platform contracts retained by this profile are:

- Windows x64 VC143 with the dynamic MSVC runtime (`/MD`) for both shared and
  static OCCT linkage;
- Linux x86_64 with the glibc 2.17 baseline;
- macOS 13.0 with native arm64 and x86_64 packages using the selected Xcode
  16.4 toolchain.

These values describe the 8.0.1 release and must be re-audited when porting the
SDK automation to a later OCCT or toolchain release.

## Current sources of truth

The live release and validation contract is maintained in:

- `.github/occt-sdk-release/README.md`;
- `.github/workflows/build-windows-packages.yml`;
- `.github/linux-occt-sdk/`;
- `.github/macos-occt-sdk/`;
- `.github/occt-sdk-release/verify-release-assets.sh`.

The original plan also covered downstream Netgen and Geomtool migration after
the OCCT SDK release. Those consumer updates are outside this repository and
are not tracked by this historical design note.
