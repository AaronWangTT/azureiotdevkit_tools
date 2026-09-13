---
name: board-manager-index-publish
description: 'Safely publish maintained AZ3166 Arduino Board Manager index entries in azureiotdevkit_tools. Use when adding or updating an AZ3166 Core release in package_azureboard_index.json, publishing Board Manager metadata, validating release archives, preparing or merging an index PR to maintenance, or updating a consumer such as HomeTemperature to a reviewed immutable index commit.'
argument-hint: '[core-version] [consumer-repository]'
user-invocable: true
disable-model-invocation: false
---

# AZ3166 Board Manager Index Publishing

Publish a maintained AZ3166 Core release through the reviewed `maintenance`
branch, then update consumers to the exact merged commit. Treat
[README.md](../../../README.md) and
[validate-package-index.yml](../../workflows/validate-package-index.yml) as the
controlling repository policy and CI implementation.

## Non-Negotiable Gates

- Keep `master` as archived upstream history. Never add maintained package
  entries there.
- Keep `maintenance` as the only long-lived publication branch. Prepare each
  index update on a short-lived branch from the latest `origin/maintenance` and
  merge it through a pull request; do not develop directly on `maintenance`.
- Publish the Core tag and immutable release archive from `devkit-sdk` before
  proposing its index entry. This repository publishes metadata, not Core
  binaries.
- Never trust a release note alone for archive metadata. Download the artifact
  and verify its byte size and SHA-256.
- Do not treat a pushed feature branch as publication. Publication is complete
  only when the entry is reachable from `origin/maintenance` and required CI is
  successful for the resulting maintenance commit.
- Never leave a consumer pinned to a feature-branch or pull-request-head commit.
  Such a commit may be used temporarily for pre-merge testing only. The final
  consumer pin must be the full 40-character reviewed commit reachable from
  `origin/maintenance` after merge.
- Keep index publication and consumer adoption in separate branches and pull
  requests. Merge the index first, then update consumers.
- Treat this skill as an operator workflow, not a substitute for repository
  rules. Confirm that branch protection or a ruleset requires pull requests and
  the package-index validation check on `maintenance`; if that cannot be
  verified, report that the process is documented but not technically enforced.
- Do not commit, push, open a pull request, merge, or delete a branch without
  explicit user authorization for that operation. Never expose Git credentials
  or tokens while checking remote state.

## Required Inputs

Confirm these values before editing:

1. Numeric Core version, such as `2.0.2`.
2. Public release tag and HTTPS archive URL.
3. Exact archive filename, byte size, and lowercase SHA-256.
4. Required tool dependencies and versions. Preserve existing pins unless the
   Core release intentionally changes them.
5. Consumer repositories that must adopt the new index entry.

Stop if the tag, package version, archive filename, release URL, checksum, or
size disagree.

## Publication State Model

Advance through these states in order. Do not skip a gate.

1. **Release ready**: the immutable Core archive exists and its metadata is
   independently verified.
2. **Index proposed**: one short-lived branch contains the minimal index entry.
3. **Index reviewed**: local validation and pull-request CI pass.
4. **Index published**: the pull request is merged into `maintenance`, and CI
   passes for the exact resulting maintenance commit.
5. **Consumer adopted**: consumers pin that full maintenance commit and pass
   their own installation, build, and test gates.

## Procedure

### 1. Establish Repository State

1. Confirm the working tree is clean and the expected remote is configured.
2. Fetch `origin` with pruning and tags.
3. Confirm `origin/HEAD` and the repository documentation designate
   `maintenance` as the publication branch.
4. Inspect existing platform entries and the newest release entry before
   editing.
5. Check for an existing branch or pull request for the requested version
   before creating another one.

### 2. Verify the Core Release

1. Confirm the exact tag exists in `devkit-sdk` and record its target commit.
2. Download the release archive to a temporary directory.
3. Compute its byte size and SHA-256 locally.
4. Confirm the archive is the canonical package produced for that version and
   that its runtime version API matches the tag.
5. Compare the measured values with release metadata. Stop on any mismatch.

Do not add a package-index entry for a draft, mutable, missing, or unverified
artifact.

### 3. Create the Index Branch

Start from the current remote publication branch, not from another feature
branch:

```powershell
git fetch origin --prune --tags
git switch maintenance
git pull --ff-only origin maintenance
$version = "2.0.2" # Replace with the release being published.
git switch -c "chore/az3166-core-$version-index"
```

The `chore/` prefix is recommended because this repository is publishing
metadata for a release created elsewhere. The exact prefix is not a functional
requirement; the branch must remain short-lived and target `maintenance`.

### 4. Add the Platform Entry

Update [package_azureboard_index.json](../../../package_azureboard_index.json)
with one platform entry containing:

- the maintained package name and `stm32f4` architecture;
- the exact semantic version;
- the public HTTPS release URL and archive filename;
- `SHA-256:<64 lowercase hexadecimal characters>`;
- the exact positive byte size;
- the AZ3166 board declaration;
- compiler and OpenOCD dependencies that resolve to existing tool definitions.

Preserve the existing JSON layout and chronological platform ordering. Do not
reformat unrelated entries or bundle documentation, consumer, or Core source
changes into this branch.

Confirm separately that `archiveFileName` is a safe leaf filename and matches
the final path segment of the release URL. The current validator requires both
fields but does not compare them.

### 5. Validate Locally

Run both repository validations:

```powershell
$version = "2.0.2" # Replace with the release being published.

& .\tools\Test-PackageIndex.ps1

& .\tools\Test-PackageIndex.ps1 `
    -VerifyArtifacts `
  -PlatformVersion $version `
    -ToolHost i686-mingw32
```

The artifact-aware check verifies the selected Core archive plus every tool
dependency referenced by that platform for the selected host. Repeat it for
other supported hosts when those release paths changed. Also run:

```powershell
git -c core.whitespace=cr-at-eol diff --check
git status --short --branch
git diff --stat
```

The `cr-at-eol` setting is required because the historical index is tracked as
CRLF. Require a minimal, intentional diff and a successful exit code from every
validation.

### 6. Publish Through Review

After explicit authorization:

1. Commit only the package-index change.
2. Push the short-lived branch.
3. Open a pull request targeting `maintenance`, not `master`.
4. Require the `Validate package index` workflow to pass for the exact PR head.
   It validates metadata, performs a clean Arduino IDE 1.8.19 Board Manager
   installation, checks compiler and OpenOCD installation, and compiles a smoke
   sketch.
5. Merge only after review and successful required checks.
6. Wait for the workflow triggered by the push to `maintenance` and require it
   to pass for the exact merged commit.

Do not call the feature branch published merely because its raw URL resolves or
local Board Manager installation succeeds.

### 7. Resolve the Published Commit

After merge:

```powershell
git fetch origin --prune
git rev-parse origin/maintenance
```

Record the full 40-character SHA. Confirm that:

- the commit is reachable from `origin/maintenance`;
- its index contains exactly one entry for the new version;
- the entry still contains the verified URL, filename, size, checksum, and tool
  dependencies;
- the raw URL using that SHA resolves and returns the expected entry;
- required CI passed for that SHA.

Use the resulting maintenance SHA even when the hosting platform used squash or
rebase merge and changed the feature commit identity.

### 8. Update Consumers Separately

Only after the index reaches **Index published** may a consumer make its final
adoption change.

1. Create a new consumer branch from its current remote base.
2. Pin the raw Board Manager index URL to the full published maintenance SHA.
3. Update the Core version, archive SHA-256, cache identity, editor paths,
   provenance notices, and version-specific documentation together.
4. Install from the pinned URL in a clean or known-good environment. Preserve
   compiler and OpenOCD directories shared by multiple Core versions; do not
   manually delete package-manager-owned shared tools during a Core upgrade.
5. Run the consumer's complete relevant compile and test suite.
6. Upload to hardware only after those checks pass and only when requested.
   Require the uploader's explicit verification marker, not merely exit code
   zero.
7. Commit, push, and open the consumer pull request only with explicit user
   authorization.

For HomeTemperature, run the repository-owned installer and
`firmware/tests/run-all-tests.ps1 -Action Verify` before an authorized upload.

## Failure and Recovery Rules

- If release metadata differs from measured bytes, stop and fix or republish
  the Core release. Never adjust the index to unverified values.
- If local index validation or PR CI fails, keep the entry unpublished and fix
  the index branch.
- If a consumer was pinned to a PR-head commit, do not merge that consumer
  change. Merge the index PR first and replace the pin with the resulting
  maintenance SHA.
- If the index PR is squash- or rebase-merged, discard the old feature SHA as a
  consumer pin and resolve the new maintenance SHA.
- If Board Manager state is inconsistent, validate with a clean portable
  Arduino installation. Do not hide the problem by deleting shared tool
  directories or weakening post-install checks.
- If any required post-merge CI check is missing, queued, cancelled, or failed,
  the index is not ready for consumer adoption.

## Final Report

Report:

- Core tag and source commit;
- archive URL, filename, size, and SHA-256;
- index branch and commit;
- pull request target and URL;
- PR and post-merge CI results;
- full published `origin/maintenance` SHA and immutable raw index URL;
- consumer branches and exact pinned SHA;
- local installation, compilation, test, and hardware-upload results;
- any unavailable validation and why it was not treated as passed.

Distinguish clearly among proposed, reviewed, published, and consumer-adopted
states.