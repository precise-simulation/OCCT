# OCCT SDK release workflow

This directory documents the combined OCCT SDK release process used for
`occt-sdk-8.0.1` and its Windows SDK replacements, adapted from the validated
7.9.3 workflow. The published `occt-sdk-8.0.1-r2` added a lean Windows static
SDK. The published `occt-sdk-8.0.1-r3` replaced the full upstream Windows shared
package with a source-built lean shared SDK and narrowed the Linux and macOS
packages to the same 28-toolkit profile.

The combined release publishes one GitHub release containing qualified lean SDKs
for Windows, Linux, and macOS. Every package is built from the exact upstream
OCCT source commit and uses the same geometry/data-exchange toolkit closure.

The default branch is intentionally automation-only. It does not carry a live
OCCT source tree: each producer sparse-checks out this repository's `.github/`
automation and checks out `Open-Cascade-SAS/OCCT` separately at the exact
upstream source SHA selected by the release workflow.

## Release architecture

The live release workflow is `.github/workflows/build-latest-occt-sdk.yml` on the
default branch. It detects a new stable upstream GitHub Release, builds all three
platform families from the exact upstream source commit, qualifies the complete
16-file candidate, and publishes the combined SDK release only after every check
passes. Routine releases do not require installing or editing a version-specific
`.github/workflows/release-occt-sdk.yml`.

`.github/occt-sdk-release/release-template.yml` is a version-specific recovery
example derived from immutable `occt-sdk-8.0.1-r3`. It is not an exact historical
snapshot: its reusable producer calls resolve from the automation revision that
executes it. The automatic release path does not execute or copy it.

- Linux uses `.github/workflows/build-linux-packages.yml` and produces lean native
  x86_64 shared and static SDKs with the pinned manylinux2014/glibc 2.17 producer.
- macOS uses `.github/workflows/build-macos-packages.yml` and produces lean native
  arm64 and x86_64 shared and static SDKs targeting macOS 13.0. There is no
  universal2 package.
- Windows shared is a source-built x64 VC143 SDK using the geometry and
  data-exchange toolkit closure with optional third-party integrations disabled.
  It is relocated, consumed by an external CMake project, repackaged,
  re-extracted, and consumed again before upload.
- Windows static is a lean x64 VC143 SDK built on `windows-2022` from the same
  pinned source commit with optional third-party dependencies disabled. It is
  relocated, consumed by an external CMake project, repackaged, re-extracted, and
  consumed again before upload.
- The publish job downloads all producer artifacts, verifies the exact 16-file
  SDK inventory and adjacent checksums, creates an exact-SHA upstream source
  archive plus checksum, creates a draft release, verifies GitHub's uploaded
  asset digests for all 18 files, and only then publishes it. The final release
  must be immutable.

The release tag identifies the **workflow revision**, while every source-built
SDK independently pins the official OCCT release commit.
This separation is intentional: release automation can be fixed without changing
the OCCT source being packaged.

## Current 8.0.1 references

The original immutable 8.0.1 release uses:

| Item | Value |
| --- | --- |
| Combined release tag | `occt-sdk-8.0.1` |
| Workflow commit used by the release | `07a7e05ffcd3cec81e0ed37afdf61b2e35047178` |
| Upstream OCCT tag | `V8.0.1` |
| Upstream OCCT source commit | `b8f597c677811d1f9f4d8a97f5ae2825c0353a42` |
| Windows asset | `occt-combined-release-no-pch.zip` |
| Windows size | `257767212` bytes |
| Windows SHA-256 | `afe36b6abcc7964d0f8b0404ccb16e7c1f6ddd8e43b450c865f7e7f092440e9d` |
| Linux baseline | x86_64, glibc 2.17 |
| macOS baseline | macOS 13.0, native arm64 and x86_64 |
| macOS toolchain | Xcode 16.4, checksum-pinned CMake 4.4.3 |
| Published files | 14 |

The combined release was published on 2026-10-06. GitHub reports it as immutable,
and the release tag resolves directly to the workflow commit above.

The immutable `occt-sdk-8.0.1-r2` release keeps the same Linux, macOS, and
official Windows shared inputs and adds the qualified lean Windows static SDK.
It contains 16 files.

The immutable `occt-sdk-8.0.1-r3` release was published on 2026-11-01 from
workflow commit `39db8383d636fa90504dad663f51e9001508eeb9`. It keeps the
16-file inventory while replacing the full Windows shared ZIP with the
source-built lean shared SDK and narrowing all source-built platform SDKs to the
same 28-toolkit profile. The retained r3-derived template is a manual recovery
example, not an exact historical snapshot; future normal releases use the live
automatic workflow instead.

## When upstream publishes the next OCCT release

The preferred path is now `.github/workflows/build-latest-occt-sdk.yml`. It
checks the official `Open-Cascade-SAS/OCCT` GitHub Release metadata, peels the
published stable tag to an exact commit, verifies the version from OCCT's own
`adm/cmake/version.cmake`, and passes that version/SHA into the reusable Linux,
macOS, and Windows SDK builders. The builders check out the official upstream
repository directly, so a new source release no longer has to be imported into
this fork before it can be qualified.

If every platform build and relocated consumer test passes, the workflow verifies
the full 16-file SDK candidate inventory, re-resolves the upstream tag to make sure it
did not move during the build, and uploads candidate metadata alongside the
platform workflow artifacts. For a genuinely new upstream version on the default
branch, a final publish job then re-downloads those same run artifacts, repeats
the inventory/source checks, archives the exact upstream source commit with an
adjacent SHA-256 checksum, creates lightweight `occt-sdk-X.Y.Z` at the exact
automation revision, creates a draft GitHub Release, verifies every uploaded
GitHub asset digest, publishes the release, and requires GitHub to report it as
immutable. The exact lean toolkit closure, system-library requirements, and
producer baselines remain a release-specific compatibility contract; incompatible
upstream changes fail before publication.

The workflow polls daily at 06:17 UTC and can also be run manually for an exact
stable upstream tag. GitHub requires both scheduled and manually dispatched
workflows to exist on the repository's default branch. This fork's default branch
is `master`. Automatic publication is additionally gated to the default branch,
so dispatching the workflow from another branch can qualify a candidate but
cannot create a tag or release.

Manual runs also expose `force_qualify`. This is intended for validating the
automation against an already-published known-good release (for example 8.0.1)
or deliberately re-running qualification after automation changes. It does not
bypass the source-SHA provenance check, and it never republishes an existing SDK
version.

An existing published, non-prerelease, immutable SDK release with tag
`occt-sdk-X.Y.Z` (or an immutable replacement such as `occt-sdk-X.Y.Z-r2`)
suppresses another automatic build for that upstream version, but only when every
matching release records the same exact upstream source SHA. A stale draft,
mutable/prerelease state, or source mismatch is treated as an incomplete or
provenance-sensitive release state and fails closed. Suffixes such as `-rc1` are
not treated as immutable replacement releases. If a new release fails
qualification, fix the automation/profile and rerun it.

Do not create a new fork release branch from upstream `master` merely because
the development version has advanced. The SDK branches and releases in this fork
are intended to correspond to identifiable upstream release tags.

As of 2026-11-02, the latest upstream stable GitHub Release is `V8.0.1`.
Upstream `master` identifies itself as `8.1.0-dev1`, so 8.1 is the next
development line but is not yet a stable release to package.

For automatic qualification and publication, the normal policy is:

1. Wait for a new upstream GitHub Release/tag.
2. Prefer the final stable release for a durable SDK release.
3. Keep automatic publication limited to final stable upstream releases.
   Prerelease qualification is a separate deliberate process and must not reuse
   the stable-release publication path implicitly.
4. Read the GitHub Release's actual `tag_name`; do not derive the tag from its
   display name. For example, the 8.0.1 release name is `V8_0_1` while its
   actual tag is `V8.0.1`.
5. Peel the published tag to its exact commit and build that commit directly
   from `Open-Cascade-SAS/OCCT`.
6. Let the existing lean-profile checks decide whether the release still matches
   the qualified SDK contract. If it does not, update the profile/toolchain
   assumptions deliberately and rerun qualification.

Useful release-state checks are:

```bash
gh api repos/Open-Cascade-SAS/OCCT/releases/latest \
  --jq '{tag_name, name, published_at, assets: [.assets[] | {name, size, digest}]}'

git ls-remote --tags https://github.com/Open-Cascade-SAS/OCCT.git \
  'refs/tags/V8*'

gh api repos/Open-Cascade-SAS/OCCT/contents/adm/cmake/version.cmake?ref=master \
  --jq '.content' |
  base64 --decode
```

Once a new release exists, the automation builds that upstream commit directly.
If qualification fails, re-audit the configured CMake variables, toolkit closure,
and system-library assumptions against the new upstream source. Do not assume
that the 8.0.1 compatibility contract remains valid.

## Preparing a future version

Use the upstream stable release as the source of truth. Routine stable releases
do not require a source import or a per-release branch. If qualification exposes
a compatibility change, verify all of the following before editing the profile
or platform baselines:

1. OCCT version, for example `8.0.1`.
2. Upstream GitHub Release tag, for example `V8.0.1`.
3. The commit to which that upstream tag resolves after peeling annotated tags.

Useful checks are:

```bash
git ls-remote --tags https://github.com/Open-Cascade-SAS/OCCT.git \
  refs/tags/V8.0.1 'refs/tags/V8.0.1^{}'
```

For an annotated upstream tag, use the peeled `^{}` commit. For a lightweight
tag, the tag ref itself is already the commit.

Verify that the selected upstream tag resolves to the same source commit pinned
by every platform producer.

## Version update checklist

The automatic candidate workflow supplies the detected version and exact source
SHA as workflow inputs, so routine upstream releases no longer require changing
version strings throughout the producer helpers. The `8.0.1` values retained as
defaults in the reusable workflows are the baseline used when those workflows
run directly from the automation branch.

### Producer workflows

In `.github/workflows/build-linux-packages.yml`:

- keep `master` as the automation branch;
- if advancing the direct-run baseline, change the `workflow_dispatch` defaults
  and the corresponding fallback values used by branch-triggered runs;
- review the manylinux producer image tag/digest and glibc baseline. Keep the
  existing pin if it is still the intended reproducible producer.

In `.github/workflows/build-macos-packages.yml`:

- keep `master` as the automation branch;
- if advancing the direct-run baseline, change the `workflow_dispatch` defaults
  and the corresponding fallback values used by branch-triggered runs;
- review the macOS runner labels, Xcode pin, CMake pin, and deployment target.
  Change them only deliberately and validate both architectures after doing so.

In `.github/workflows/build-windows-packages.yml`:

- keep `master` as the automation branch;
- if advancing the direct-run baseline, change the `workflow_dispatch` defaults
  and the corresponding fallback values used by branch-triggered runs;
- review the Windows runner/toolchain and the lean shared/static toolkit closure;
- review `.github/windows-occt-sdk/` alongside the workflow; the configure and
  installed-SDK validation logic is shared by both Windows linkage jobs there;
- keep the lean shared dependency exclusion list, relocation checks, and manifest
  expectations in sync with the release verifier;
- keep the static external-consumer definitions
  `OCCT_STATIC_BUILD;OCCT_NO_PLUGINS` and required Windows system libraries in
  sync with the manifest and release verifier.

In `.github/workflows/validate-lean-profile.yml`:

- keep `master` in the pull-request and push branch filters;
- keep its path filters synchronized with every file that duplicates values from
  `.github/occt-sdk-release/lean-profile.json`.

The producer artifacts currently use a three-day Actions retention period. They
are temporary transport artifacts; the GitHub Release is the durable output.

### Producer helpers

The Linux/macOS producers and release verifiers take the OCCT version from the
workflow environment; there is no per-release version string to update in those
helpers.

If a platform baseline changes, update both the package naming and its verifier.
For example, changing the macOS deployment target requires corresponding changes
to the `macos13` package prefix and the `13.0` manifest check. Changing the Linux
glibc baseline requires corresponding changes to `glibc2.17` package names and
manifest validation.

### Combined release workflow

The normal combined release path is `.github/workflows/build-latest-occt-sdk.yml`.
It derives `OCCT_VERSION`, `OCCT_SOURCE_SHA`, the upstream tag, and the SDK
release tag from the stable upstream GitHub Release at runtime. There is no
per-release workflow file to install and no version/source pin to edit for a
routine new upstream release.

The retained `.github/occt-sdk-release/release-template.yml` is intentionally
bound to the 8.0.1 r3 release shape, but it is only a recovery example derived
from that release. It invokes reusable producers from the revision that executes
it and therefore is not a self-contained reproduction of r3. Use it only when
deliberately preparing a manual replacement/recovery workflow; in that
exceptional case every tag, version, source SHA, producer revision, and package
expectation must be reviewed before use.

In `.github/occt-sdk-release/verify-release-assets.sh`, update the exact Windows
lean-shared and static asset names, manifest expectations, and total inventory
when the package shape changes.

After editing, search for stale release-specific values. For example:

```bash
rg -n --glob '!release-template.yml' \
  '8\.0\.1|V8\.0\.1|b8f597c67781|OCCT_801|macos13|13\.0|glibc2\.17' \
  .github/linux-occt-sdk \
  .github/macos-occt-sdk \
  .github/occt-sdk-release \
  .github/workflows/build-linux-packages.yml \
  .github/workflows/build-macos-packages.yml \
  .github/workflows/build-windows-packages.yml \
  .github/workflows/build-latest-occt-sdk.yml \
  .github/workflows/validate-lean-profile.yml
```

Some platform baseline strings can legitimately remain unchanged. Every match
should nevertheless be reviewed before release.

## Validation before publication

Do not create the combined release tag manually for a routine upstream release.
The automatic workflow creates it only after all producer and combined candidate
checks pass.

At minimum:

1. Run `git diff --check` and review the complete release-related diff.
2. Merge the reviewed workflow/helpers to the default branch so scheduled runs
   use the intended automation revision.
3. Confirm the Linux producer builds both shared and static packages and passes
   its compatibility matrix on Ubuntu 20.04, 22.04, and 24.04. OCCT 8.0.1
   headers do not compile with Ubuntu 20.04's default GCC 9, so the focal
   compatibility jobs deliberately use GCC 10 while retaining the Ubuntu 20.04
   runtime/glibc environment.
4. Confirm the macOS producer builds and consumes all four native combinations:
   arm64/shared, arm64/static, x86_64/shared, and x86_64/static.
5. Confirm the Windows workflow builds, relocates, packages, re-extracts, and
   consumes both the lean shared and lean static SDKs.
6. Confirm manifests contain the exact upstream source SHA and version.
7. Confirm relocation tests pass. The resulting SDKs must not depend on the
   original runner workspace, build tree, Xcode path, or SDK path.
8. Confirm the Windows shared DLL dependency scan rejects every disabled optional
   runtime family.

`workflow_dispatch` can be used as an end-to-end preflight. A run dispatched from
a non-default branch can build and qualify but cannot publish. A default-branch
run for a new stable upstream version is publication-capable; use
`force_qualify` when the intent is to re-check an already-published version
without creating another release.

Pull requests that modify the orchestrator, any producer workflow or helper tree,
or the combined release verifier also run the orchestrator as a forced
qualification against the current stable upstream release. Pull-request refs can
never enter the publish job, so this exercises the full reusable
build/qualification path without creating a tag or GitHub Release.

Ordinary pushes to the configured producer branches start a producer only when that
producer's workflow or helper paths change. Documentation-only commits and
unrelated branch changes therefore do not launch SDK builds. Never use a skip
marker for changes that affect release workflows, helpers, source pins, or
package contents when a qualification run is required.

## Creating the combined release

The combined release tag must point to the exact commit containing the reviewed
workflow and helper implementation. Use a **lightweight tag**. The release
workflow creates `occt-sdk-X.Y.Z` at `${{ github.sha }}` after qualification and
verifies through the GitHub API that the tag resolves directly to that commit.
If an unpublished tag from an interrupted retry already exists, it may be reused
only when it resolves to the same automation revision; any conflicting tag fails
closed.

For a new stable upstream release, the workflow:

1. builds and qualifies the Linux SDKs;
2. builds and qualifies the four macOS SDKs;
3. builds and qualifies the lean Windows shared and static SDKs;
4. verifies the combined inventory;
5. re-checks the upstream tag after qualification and re-verifies the same run
   artifacts;
6. archives the exact upstream source commit and writes its SHA-256 checksum;
7. creates the lightweight SDK tag at the automation revision;
8. creates a draft GitHub Release from the 16 qualified SDK files plus the two
   preserved source files;
9. verifies all uploaded GitHub asset digests while still a draft;
10. publishes the release;
11. verifies the tag again and requires GitHub to report the published release
    as immutable.

The workflow-level concurrency group serializes detection/build/publish runs, so
two automatic release attempts cannot race each other.

## Expected release inventory

The qualified SDK candidate remains exactly 16 files, the same count as immutable
r2/r3. New automatic releases add an exact upstream source archive and its
adjacent SHA-256 file, so the final published release contains exactly 18 assets.
The r3-derived recovery example retains the historical 16-file release shape.

- Windows: 1 lean shared ZIP + checksum and 1 lean static ZIP + checksum = 4 files.
- Linux: shared and static `.tar.gz` archives + 2 `.sha256` files = 4 files.
- macOS: arm64/x86_64 × shared/static archives + 4 `.sha256` files = 8 files.
- Source preservation: exact upstream Git tree archive + checksum = 2 files.

The preserved source archive follows:

```text
opencascade-X.Y.Z-source-<source-sha12>.tar.gz
```

The adjacent `.sha256` file is uploaded and both files are covered by GitHub's
release-asset digest verification before publication.

Linux package names follow:

```text
opencascade-X.Y.Z-linux-x86_64-glibc2.17-{shared|static}-<source-sha12>.tar.gz
```

macOS package names follow:

```text
opencascade-X.Y.Z-macos13-{arm64|x86_64}-{shared|static}-<source-sha12>.tar.gz
```

The source-built lean Windows package names follow:

```text
opencascade-X.Y.Z-windows-x86_64-vc143-shared-lean-<source-sha12>.zip
opencascade-X.Y.Z-windows-x86_64-vc143-static-lean-<source-sha12>.zip
```

The shared manifest records the production optimization profile, exact toolkit
closure, and `optional-third-party=none`. The static manifest additionally
records the consumer compile definitions
`OCCT_STATIC_BUILD;OCCT_NO_PLUGINS` and the Windows system libraries required
by the lean toolkit closure. The validation workflow consumes each source-built
SDK before and after packaging.

## Windows lean shared SDK implementation

The r3 producer replaced the upstream full shared ZIP with a source-built shared
SDK for consumers that want the same small geometry/data-exchange surface as the
lean static SDK without static OCCT linkage.

The lean shared producer uses the pinned upstream OCCT source, `windows-2022`,
Visual Studio 2022 x64 Release, `BUILD_LIBRARY_TYPE=Shared`, the production OCCT
optimization profile, precompiled headers disabled, and the native memory
manager. It forces CMake policy `CMP0091=NEW` and verifies the generated toolkit
projects encode `MultiThreadedDLL`, so the VC143 `/MD` ABI contract is checked
before compilation. It disables the broad OCCT modules and explicitly requests
`TKDESTEP;TKDEIGES;TKDESTL;TKOffset;TKMesh`, producing the same exact 28-toolkit
closure documented for the static package below. `TKDECascade` is rejected.

Freetype, FreeImage, FFmpeg, OpenVR, RapidJSON, Draco, TBB, Eigen, Tcl, Tk, VTK,
OpenGL, GLES2, and D3D are disabled and `3RDPARTY_DIR` is empty. The installed
SDK must contain exactly 28 `TK*.dll` files and matching 28 `TK*.lib` import
libraries. Every toolkit DLL is inspected with `dumpbin /dependents`; imports of
the disabled optional integrations are rejected.

The shared SDK is copied to a new location and consumed through its installed
`OpenCASCADEConfig.cmake`. The external consumer requires the package to report
`OpenCASCADE_BUILD_SHARED_LIBS=ON`, verifies that the exported binary, library,
include, and resource directories remain inside the relocated prefix, builds a
box, exercises offsetting and meshing, round-trips STEP and IGES, writes/reads
STL, and runs with the relocated OCCT binary directory on `PATH`. After
packaging, the ZIP is extracted into another fresh location and the same
configure/build/run check is repeated after the original build/install trees
have been moved out of their recorded paths. The final
executable must import OCCT DLLs including `TKernel.dll` and `TKDESTEP.dll`, and
every imported `TK*.dll` must exist in the extracted package.

## Windows static SDK implementation

Linux and macOS already publish both shared and static SDK variants. The specific
addition made for `occt-sdk-8.0.1-r2` was the Windows static SDK described in
this section; r2 still uses the official upstream Windows ZIP for shared linkage.
The published r3 release replaced that shared package with the lean source-built
variant described above while retaining the lean static contract here.

The Windows static package in `occt-sdk-8.0.1-r2` is intentionally not a
static rebuild of every optional OCCT component. It is a **lean static SDK**
containing the OCCT toolkit closure needed for the geometry and data-exchange
use cases qualified by this repository.

### Build configuration

The Windows static producer uses:

- upstream OCCT source commit
  `b8f597c677811d1f9f4d8a97f5ae2825c0353a42`, the same source revision used
  by Linux/macOS and corresponding to upstream `V8.0.1`;
- `windows-2022`, Visual Studio 2022, x64, Release configuration;
- `BUILD_LIBRARY_TYPE:STRING=Static`;
- `CMP0091=NEW` plus `CMAKE_MSVC_RUNTIME_LIBRARY=MultiThreadedDLL`, with the
  generated toolkit projects checked for `MultiThreadedDLL`; OCCT itself is linked
  statically but uses the dynamic MSVC runtime (`/MD`), not the static CRT
  (`/MT`);
- `BUILD_OPT_PROFILE=Default`;
- precompiled headers disabled;
- OCCT's native memory manager.

The broad OCCT modules are disabled and the producer explicitly requests these
top-level toolkits:

```text
TKDESTEP
TKDEIGES
TKDESTL
TKOffset
TKMesh
```

OCCT then resolves their transitive toolkit dependencies. The successful
8.0.1 qualification produced this exact 28-toolkit closure:

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

`TKDECascade` is explicitly rejected from the lean closure.

The producer disables optional third-party integrations:

```text
Freetype
FreeImage
FFmpeg
OpenVR
RapidJSON
Draco
TBB
Eigen
Tcl
Tk
VTK
OpenGL
GLES2
D3D
```

`3RDPARTY_DIR` is left empty, and the package manifest records
`optional-third-party=none`. This makes the Windows static SDK self-contained
with respect to those optional OCCT integrations and prevents consumers from
silently requiring the upstream third-party bundle.

### What is actually shipped

The installed static SDK must contain:

- exactly 28 OCCT `.lib` files corresponding to the closure above;
- zero OCCT `.dll` files;
- installed headers and CMake package files;
- OCCT's `LICENSE_LGPL_21.txt` and `OCCT_LGPL_EXCEPTION.txt`;
- `sdk-manifest.txt`, which records source/workflow provenance, toolchain,
  linkage, toolkit closure, and the required consumer settings;
- an adjacent SHA-256 checksum for the final ZIP.

The successful 8.0.1 qualification measured the 28 static OCCT libraries at
`548862194` bytes (523.436 MiB). The compressed published static SDK ZIP is
`118774584` bytes (113.272 MiB). These sizes are evidence for this release,
not fixed requirements for future OCCT/toolchain versions.

### MSVC runtime contract

"Static OCCT" here means OCCT toolkit linkage is static; it does **not** mean
that the Microsoft C/C++ runtime is statically linked.

Every installed OCCT `.lib` is inspected with `dumpbin /directives`:

- any `LIBCMT` default-library directive is rejected because it indicates
  static CRT (`/MT`) linkage;
- the validation requires evidence of `MSVCRT`, confirming the intended
  dynamic CRT (`/MD`) contract.

This avoids mixing incompatible MSVC runtime models in downstream applications.

### Consumer contract

For OCCT 8.0.1, the installed OCCT CMake package does not propagate everything
needed by a static consumer. Consumers of this package must currently define:

```text
OCCT_STATIC_BUILD
OCCT_NO_PLUGINS
```

and link these Windows system libraries in addition to
`${OpenCASCADE_LIBRARIES}`:

```text
advapi32
gdi32
user32
wsock32
psapi
windowscodecs
winmm
```

Those requirements are recorded in `sdk-manifest.txt` as:

```text
consumer-definitions=OCCT_STATIC_BUILD;OCCT_NO_PLUGINS
consumer-system-libs=advapi32;gdi32;user32;wsock32;psapi;windowscodecs;winmm
```

This is an explicit compatibility contract, not an arbitrary workaround. For a
future OCCT release, first check whether upstream's installed CMake targets have
started exporting the static definitions/system requirements themselves. Remove
the explicit consumer settings only after a remote consumer qualification proves
that they are no longer required.

### Qualification performed

The Windows static artifact is accepted only after all of the following pass:

1. configure and install the pinned OCCT source as the lean static closure;
2. verify exactly 28 toolkits, exactly 28 `.lib` files, no `.dll` files, and
   no unexpected `TKDECascade`;
3. inspect every static library's MSVC default-library directives to enforce the
   `/MD` runtime contract;
4. copy the installed SDK to a different directory to prove it is relocatable;
5. configure an external CMake consumer using only the relocated install;
6. build a small executable that creates and offsets geometry, meshes it, and
   round-trips STEP, IGES, and STL so the five lean root toolkit families are
   exercised from the relocated package;
7. run that executable and require every operation to succeed;
8. package the SDK, manifest, licenses, and checksum into the final ZIP;
9. extract that ZIP into another fresh location and repeat the external consumer
   configure/build/run;
10. inspect the final consumer executable with `dumpbin /dependents` and reject
    any dependency matching `TK*.dll`.

The r2 static qualification was GitHub Actions run `37910758624`; its final
executable demonstrated real static OCCT linkage rather than merely producing
`.lib` files. For r3, the expanded root-family consumer and the new lean shared
build were qualified on GitHub Actions before release publication.

Every archive has an adjacent `.sha256` file. The r3 release workflow rejected
missing files, extra files, checksum failures, source/version mismatches, and an
asset count other than 16.

## Recovering from a failed release run

If an automatic run fails before publication, its publish step deletes only a
draft that it can still prove belongs to that workflow attempt. If GitHub accepts
publication but then reports that same workflow-owned release as mutable, the
step deletes the mutable release and fails the run. The lightweight SDK tag is
retained for safe retry. A cancellation or runner failure can still leave a draft
or mutable release behind. Before retrying:

1. Diagnose and fix the workflow on the default branch.
2. Make sure every older automatic run is terminal.
3. Remove any stale draft release for the intended tag.
4. If a stale tag exists and still points to the same automation revision, a
   rerun can reuse it. If the fix requires a new automation commit, delete the
   unpublished stale tag first; the next successful run will recreate it at the
   new `${{ github.sha }}`.

Example:

```bash
release_tag=occt-sdk-X.Y.Z
git push origin ":refs/tags/$release_tag"
```

Never reuse or move a tag after its release has been successfully published.
Published combined SDK releases are expected to be immutable. If a published
release needs replacement, use a new release/version rather than mutating the
existing one.

## Post-release verification and cleanup

After the workflow succeeds, verify through the GitHub API/UI that:

- the release is non-draft and non-prerelease unless intentionally configured
  otherwise;
- the tag is the release tag configured for this release;
- the release has exactly the configured asset inventory (18 assets for new
  automatic releases: 16 SDK files plus the exact-source archive and checksum;
  historical r3-shaped recovery releases remain 16 assets);
- the published release is immutable;
- Linux/macOS filenames contain the expected 12-character source SHA prefix;
- the preserved source archive filename contains the expected source SHA prefix
  and its adjacent `.sha256` file verifies;
- release notes record the complete source SHA and workflow revision.

The Actions artifacts are duplicates of the published release assets. After the
release is verified, they may be deleted immediately to reclaim Actions storage.
Failed and cancelled experimental workflow runs can also be deleted. Successful
run records are useful provenance and may be kept after their artifacts are
removed. The workflows use a three-day artifact retention as a fallback.

Legacy per-platform release tags such as `occt-linux-sdk-X.Y.Z` and
`occt-macos-sdk-X.Y.Z` are not required by the combined release process. Future
versions should normally publish only `occt-sdk-X.Y.Z` unless there is a specific
reason to maintain standalone platform releases.

## Reproducibility and provenance rules

Keep these properties when adapting the workflow:

- Pin the exact upstream OCCT source commit; do not build a moving branch head.
- Keep GitHub Actions referenced by commit SHA.
- Keep producer tool/container inputs pinned where practical.
- Validate the version read from OCCT's own `adm/cmake/version.cmake` against the
  configured release version.
- Record both the workflow/event commit and upstream source commit in manifests.
- Build Linux in the pinned producer and then consume the packaged result on the
  compatibility distributions.
- Build each macOS architecture natively and consume the packaged result after
  relocation.
- Build the lean Windows shared SDK from the same pinned source and 28-toolkit
  closure, keep optional third-party integrations disabled, inspect toolkit DLL
  dependencies, and validate a relocated external consumer both before and after
  packaging.
- Build the Windows static SDK from the same pinned source, keep its optional
  third-party surface explicit, and validate a relocated external consumer both
  before and after packaging. Until upstream OCCT exports the static compile
  definitions through its installed CMake targets, consumers must define
  `OCCT_STATIC_BUILD` and `OCCT_NO_PLUGINS` explicitly as recorded in the
  package manifest.
- Publish through a draft first and verify GitHub's asset digests before making
  the release public.
- Require the final published release to be immutable.

These checks are the core of the release design. Changing version numbers should
not weaken them.
