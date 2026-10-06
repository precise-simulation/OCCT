# OCCT 7.9.3 combined SDK release

## Goal

Publish one `precise-simulation/OCCT` release for OCCT 7.9.3 containing the
qualified SDK artifacts for all supported desktop platforms:

- Windows x64: copy the official Open-Cascade-SAS 7.9.3 combined Release package
  byte-for-byte and verify its upstream SHA-256.
- Linux x86_64: build and qualify shared and static SDKs with the existing pinned
  manylinux2014/glibc 2.17 producer.
- macOS x86_64 and arm64: build and qualify shared and static SDKs with the
  existing macOS producer.

The 7.9.3 workflow accepts only the exact release tag `occt-sdk-7.9.3`; a future
OCCT version must update the pinned source and platform metadata before its tag is
enabled.

## Source and artifact identity

Linux and macOS both compile the exact official OCCT 7.9.3 source commit
`a016080bf6738d6aeae020badee4e888ad1540a5`. The release tag points to the
workflow revision, so build automation can evolve without changing the OCCT source
identity recorded in each manifest.

The Windows package is
`opencascade-7.9.3-vc14-64-combined.zip` from the official `V7_9_3` release. It
already contains both the OCCT Release installation and `3rdparty-vc14-64`. Its
required size is 258,814,881 bytes and its SHA-256 is
`afbef3457fbc4a2bdca0608e0fe284392f51e4c2c42ccbfb9df7168d8e4eb9b3`.

## Workflow

`.github/workflows/release-occt-sdk.yml` calls the Linux and macOS package
workflows as reusable workflows, downloads and verifies the official Windows
package, then publishes only after every platform build and compatibility job has
passed.

The Windows import checks the live upstream `V7_9_3` release metadata for the
exact asset name, size and digest, peels the upstream release tag to the canonical
OCCT source commit, downloads the URL returned by that release metadata, and then
recomputes size and SHA-256 locally before upload.

The release contains exactly 14 uploaded assets:

- 2 Windows files: the combined ZIP and its `.sha256` file.
- 4 Linux files: shared/static archives and their `.sha256` files.
- 8 macOS files: x86_64/arm64 shared/static archives and their `.sha256` files.

The publish job re-verifies every platform inventory, every adjacent checksum,
the Windows upstream digest, the release tag target, the total 14-file inventory,
and GitHub's computed digest for every uploaded asset before publishing the draft.
After publication it also requires GitHub to report the release as immutable.

## Acceptance

The work is complete when a push of `occt-sdk-7.9.3` runs the Linux and macOS
hosted qualification matrices successfully, verifies the copied Windows package,
publishes one non-draft release with exactly the 14 expected assets, and a final
API read confirms the release tag and asset digests.
