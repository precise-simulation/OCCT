# OCCT SDK release automation

This repository's default branch contains the automation used to detect official
Open CASCADE Technology (OCCT) releases, build lean SDK packages, qualify the
resulting artifacts, and publish immutable GitHub Releases.

The default branch intentionally does **not** vendor an OCCT source tree. Build
jobs resolve an official release from `Open-Cascade-SAS/OCCT`, peel its tag to
an exact source commit, and check out that upstream commit separately from this
repository's automation files.

## Active workflows

- `.github/workflows/build-latest-occt-sdk.yml` detects and publishes new
  stable upstream OCCT SDK releases.
- `.github/workflows/build-linux-packages.yml` builds and validates Linux SDKs.
- `.github/workflows/build-macos-packages.yml` builds and validates macOS SDKs.
- `.github/workflows/build-windows-packages.yml` builds and validates Windows SDKs.
- `.github/workflows/validate-lean-profile.yml` checks that the shared lean
  packaging profile stays consistent across platforms.

Platform-specific build and verification helpers live under
`.github/*-occt-sdk/`. Release policy, verification, and recovery material
live under `.github/occt-sdk-release/`.

## Source provenance

The automation keeps the workflow revision and OCCT source revision separate:

1. the release workflow identifies an official stable upstream release;
2. the upstream tag is peeled to an exact OCCT source SHA;
3. each platform builder checks out this repository only for `.github/`
   automation and checks out `Open-Cascade-SAS/OCCT` separately at that SHA;
4. artifact manifests and release notes record the exact upstream source SHA;
5. an `occt-sdk-X.Y.Z` release tag identifies the automation revision that
   qualified and published those artifacts;
6. automatic releases also attach an exact-SHA upstream source archive and its
   SHA-256 checksum so the packaged source remains available with the immutable
   binary release.

See `.github/occt-sdk-release/README.md` for the detailed release contract and
failure/recovery rules.

## Historical OCCT source

Removing the source tree from the default branch does not rewrite repository
history. Historical OCCT commits, branches, and existing SDK tags remain
available through Git.

## License

The repository retains `LICENSE_LGPL_21.txt` and
`OCCT_LGPL_EXCEPTION.txt` for OCCT licensing and provenance. SDK artifacts
built from upstream OCCT remain subject to the applicable OCCT licensing terms.
