# OCCT SDK release workflow

This directory documents the combined OCCT SDK release process used for
`occt-sdk-8.0.1`, adapted from the validated 7.9.3 workflow. The intent is to
make future OCCT SDK releases reproducible without reconstructing the release
procedure from workflow history.

The combined release publishes one GitHub release containing qualified SDKs for
Windows, Linux, and macOS. Linux and macOS are built from an exact upstream OCCT
source commit. Windows is copied byte-for-byte from the official upstream OCCT
release after its identity, size, digest, and source tag have been verified.

## Release architecture

The release is driven by `.github/workflows/release-occt-sdk.yml`.

- Linux uses `.github/workflows/build-linux-packages.yml` and produces native
  x86_64 shared and static SDKs with the pinned manylinux2014/glibc 2.17 producer.
- macOS uses `.github/workflows/build-macos-packages.yml` and produces native
  arm64 and x86_64 shared and static SDKs targeting macOS 13.0. There is no
  universal2 package.
- Windows uses the official upstream combined VC x64 package rather than
  rebuilding OCCT. The workflow verifies upstream metadata and then recomputes
  the downloaded package digest locally.
- The publish job downloads all producer artifacts, verifies the exact inventory
  and adjacent checksums, creates a draft release, verifies GitHub's uploaded
  asset digests, and only then publishes it. The final release must be immutable.

The release tag identifies the **workflow revision**, while the Linux/macOS
source revision is independently pinned to the official OCCT release commit.
This separation is intentional: release automation can be fixed without changing
the OCCT source being packaged.

## Current 8.0.1 release candidate

The 8.0.1 release candidate uses:

| Item | Value |
| --- | --- |
| Combined release tag | `occt-sdk-8.0.1` |
| Release branch | `OCCT-801` |
| Workflow commit used by the release | set after producer validation |
| Upstream OCCT tag | `V8.0.1` |
| Upstream OCCT source commit | `b8f597c677811d1f9f4d8a97f5ae2825c0353a42` |
| Windows asset | `occt-combined-release-no-pch.zip` |
| Windows size | `257767212` bytes |
| Windows SHA-256 | `afe36b6abcc7964d0f8b0404ccb16e7c1f6ddd8e43b450c865f7e7f092440e9d` |
| Linux baseline | x86_64, glibc 2.17 |
| macOS baseline | macOS 13.0, native arm64 and x86_64 |
| macOS toolchain | Xcode 16.4, checksum-pinned CMake 4.4.3 |
| Expected published files | 14 |

The release tag must be created only after the Linux and macOS producer workflows
have passed for the candidate workflow revision.

## Preparing a future version

Use the upstream stable release as the source of truth. Before editing the
workflows, determine all of the following:

1. OCCT version, for example `8.0.1`.
2. Upstream release tag, for example `V8_0_1`.
3. The commit to which that upstream tag resolves after peeling annotated tags.
4. The exact official Windows combined x64 Release asset name.
5. The Windows asset byte size and SHA-256 reported by the upstream release.
6. The release branch in this fork, for example `OCCT-801`.

Useful checks are:

```bash
git ls-remote --tags https://github.com/Open-Cascade-SAS/OCCT.git \
  refs/tags/V8_0_1 'refs/tags/V8_0_1^{}'

gh api repos/Open-Cascade-SAS/OCCT/releases/tags/V8_0_1 \
  --jq '.assets[] | [.name, .size, .digest, .browser_download_url] | @tsv'
```

For an annotated upstream tag, use the peeled `^{}` commit. For a lightweight
tag, the tag ref itself is already the commit.

Do not infer the Windows filename, size, or digest from an older release. Read
them from the new upstream release and verify that the selected upstream tag
resolves to the same source commit used by Linux and macOS.

## Version update checklist

Several files intentionally contain explicit version information. Update all of
them for a new release.

### Producer workflows

In `.github/workflows/build-linux-packages.yml`:

- change the pull-request and push branch to the new release branch;
- change `OCCT_VERSION`;
- change the pinned source SHA;
- rename the version-derived source variable such as `OCCT_801_BASE_SHA` and all
  references to it;
- review the manylinux producer image tag/digest and glibc baseline. Keep the
  existing pin if it is still the intended reproducible producer.

In `.github/workflows/build-macos-packages.yml`:

- change the pull-request and push branch to the new release branch;
- change `OCCT_VERSION`;
- change the pinned source SHA;
- rename the version-derived source variable such as `OCCT_801_BASE_SHA` and all
  references to it;
- review the macOS runner labels, Xcode pin, CMake pin, and deployment target.
  Change them only deliberately and validate both architectures after doing so.

The producer artifacts currently use a three-day Actions retention period. They
are temporary transport artifacts; the GitHub Release is the durable output.

### Producer helpers

Update the hard-coded version in:

- `.github/linux-occt-sdk/build-sdk.sh`
- `.github/linux-occt-sdk/verify-release-assets.sh`
- `.github/macos-occt-sdk/build-sdk.sh`
- `.github/macos-occt-sdk/verify-release-assets.sh`

If a platform baseline changes, update both the package naming and its verifier.
For example, changing the macOS deployment target requires corresponding changes
to the `macos13` package prefix and the `13.0` manifest check. Changing the Linux
glibc baseline requires corresponding changes to `glibc2.17` package names and
manifest validation.

### Combined release workflow

In `.github/workflows/release-occt-sdk.yml`, update:

- the exact tag trigger `occt-sdk-X.Y.Z`;
- `OCCT_VERSION`;
- `OCCT_SOURCE_SHA`;
- `WINDOWS_ASSET`;
- `WINDOWS_ASSET_SIZE`;
- `WINDOWS_ASSET_SHA256`;
- `WINDOWS_ASSET_URL`;
- both occurrences of the upstream tag URL;
- the `SOURCE_SHA` and `WINDOWS_SHA256` values in the publish job;
- the Windows release description if the upstream package/toolchain name changed.

In `.github/occt-sdk-release/verify-release-assets.sh`, update the exact Windows
asset filename.

After editing, search for stale release-specific values. For example:

```bash
rg -n '8\.0\.1|V8\.0\.1|b8f597c67781|OCCT_801|macos13|13\.0|glibc2\.17' \
  .github/linux-occt-sdk \
  .github/macos-occt-sdk \
  .github/occt-sdk-release \
  .github/workflows/build-linux-packages.yml \
  .github/workflows/build-macos-packages.yml \
  .github/workflows/release-occt-sdk.yml
```

Some platform baseline strings can legitimately remain unchanged. Every match
should nevertheless be reviewed before release.

## Validation before tagging

Do not create the combined release tag until the producer workflows pass for the
new version and source pin.

At minimum:

1. Run `git diff --check` and review the complete release-related diff.
2. Push the release workflow/helpers to the intended release branch.
3. Confirm the Linux producer builds both shared and static packages and passes
   its compatibility matrix on Ubuntu 20.04, 22.04, and 24.04.
4. Confirm the macOS producer builds and consumes all four native combinations:
   arm64/shared, arm64/static, x86_64/shared, and x86_64/static.
5. Confirm manifests contain the exact upstream source SHA and version.
6. Confirm relocation tests pass. The resulting SDKs must not depend on the
   original runner workspace, build tree, Xcode path, or SDK path.
7. Verify the Windows upstream asset metadata before tagging.

The combined workflow can also be started with `workflow_dispatch` as an
end-to-end preflight. Its publish job is deliberately gated to a tag push, so a
manual run builds/verifies the inputs without publishing a release.

Ordinary pushes to the configured release branch start the Linux and macOS
producer workflows. A documentation-only commit can use `[skip ci]`; never use a
skip marker for changes that affect release workflows, helpers, source pins, or
package contents.

## Creating the combined release

The combined release tag must point to the exact commit containing the reviewed
workflow and helper implementation. Use a **lightweight tag**. The release
workflow verifies that the GitHub tag resolves directly to the workflow event
commit; the known-good 7.9.3 release also used a lightweight tag.

Example for version `8.0.1`:

```bash
git switch OCCT-801
git pull --ff-only origin OCCT-801
git rev-parse HEAD

git tag occt-sdk-8.0.1 HEAD
git push origin refs/tags/occt-sdk-8.0.1
```

Pushing the exact configured tag starts `.github/workflows/release-occt-sdk.yml`.
The workflow then:

1. builds and qualifies the Linux SDKs;
2. builds and qualifies the four macOS SDKs;
3. downloads and verifies the official Windows package;
4. verifies the combined inventory;
5. creates a draft GitHub Release;
6. verifies all uploaded GitHub asset digests while still a draft;
7. publishes the release;
8. verifies that GitHub reports the published release as immutable.

Do not move or recreate the release tag while an earlier run for that tag is
still active. Tag-triggered runs intentionally do not cancel each other.

## Expected release inventory

The current release shape contains exactly 14 files:

- Windows: 1 official combined ZIP + 1 `.sha256` file = 2 files.
- Linux: shared and static `.tar.gz` archives + 2 `.sha256` files = 4 files.
- macOS: arm64/x86_64 × shared/static archives + 4 `.sha256` files = 8 files.

Linux package names follow:

```text
opencascade-X.Y.Z-linux-x86_64-glibc2.17-{shared|static}-<source-sha12>.tar.gz
```

macOS package names follow:

```text
opencascade-X.Y.Z-macos13-{arm64|x86_64}-{shared|static}-<source-sha12>.tar.gz
```

Every archive has an adjacent `.sha256` file. The release workflow rejects
missing files, extra files, checksum failures, source/version mismatches, and an
asset count other than 14.

## Recovering from a failed release run

If a tag-triggered run fails before publication:

1. Diagnose and fix the workflow on the release branch.
2. Make sure every older run for the release tag is terminal; cancel obsolete
   runs before retagging.
3. Check that no stale draft release remains for the tag. The workflow normally
   removes a draft that it created when publication fails.
4. Delete the failed remote/local tag, recreate the lightweight tag at the fixed
   workflow commit, and push it again.

Example:

```bash
git push origin :refs/tags/occt-sdk-8.0.1
git tag -d occt-sdk-8.0.1
git tag occt-sdk-8.0.1 <fixed-workflow-commit>
git push origin refs/tags/occt-sdk-8.0.1
```

Never reuse or move a tag after its release has been successfully published.
Published combined SDK releases are expected to be immutable. If a published
release needs replacement, use a new release/version rather than mutating the
existing one.

## Post-release verification and cleanup

After the workflow succeeds, verify through the GitHub API/UI that:

- the release is non-draft and non-prerelease unless intentionally configured
  otherwise;
- the tag is the expected `occt-sdk-X.Y.Z` tag;
- there are exactly 14 release assets;
- the published release is immutable;
- Linux/macOS filenames contain the expected 12-character source SHA prefix;
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
- Treat the official Windows package as provenance-sensitive input: verify its
  upstream tag, source commit, filename, size, URL, and SHA-256 before copying it.
- Publish through a draft first and verify GitHub's asset digests before making
  the release public.
- Require the final published release to be immutable.

These checks are the core of the release design. Changing version numbers should
not weaken them.
