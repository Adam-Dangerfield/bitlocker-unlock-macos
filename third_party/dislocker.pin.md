# Vendored dislocker pin

This project pins `third_party/dislocker` to a specific upstream commit. The
pin is enforced two ways:

1. **`.gitmodules`** records the submodule URL and `build.sh` uses
   `git -C third_party/dislocker rev-parse HEAD` to confirm the working tree
   matches the SHA below.
2. **This file** is the human-readable record — SHA, tag, date, and reason
   for the choice. Out-of-band documentation in case the submodule machinery
   is bypassed.

| Field | Value |
|---|---|
| **Vendored at** | `21ef6e58deb400502121e80fc0dfc7d9974e364f` |
| **Tag/describe** | `v0.7.4` (release, 2026-10-21) |
| **Date pinned** | 2026-11-01 |
| **Upstream** | https://github.com/Aorimn/dislocker |
| **Reason** | Bumped to v0.7.4 for CVE-2026-107634 (heap OOB read in metadata parser, upstream `9158e9e`) and CVE-2026-107635 (datum size underflow, upstream `0706462`). Originally pinned for F7-03 supply-chain pinning — see [docs/security/SECURITY_REVIEW_2026-05-18.md](../docs/security/SECURITY_REVIEW_2026-05-18.md) |
| **License** | GPLv2 (upstream) |

## How to update the pin

```bash
cd third_party/dislocker
git fetch origin
git checkout <NEW_SHA>             # explicit, not a branch
cd ../..
git add third_party/dislocker      # records the new submodule SHA

# Then edit third_party/dislocker.pin.md with the new SHA, date, reason.
# build.sh will refuse to build until the file and the submodule agree.
```

Any update should be a deliberate commit reviewed for security-relevant
changes. Do not let dislocker float on a branch.

## Local patches

`build.sh` applies every `third_party/patches/*.patch` to the pinned tree for
the duration of the build and reverts them on exit, so the submodule stays
clean at the pinned SHA. Re-check each patch whenever the pin moves.

| Patch | Why |
|---|---|
| `0001-dislocker-fuse-use-plain-fuse3-api-for-fuse-t.patch` | Since upstream `aafbdfb`, `dislocker-fuse.c` uses macFUSE 5's `fuse_darwin_*` API whenever `__APPLE__` is defined. FUSE-T (our Path B backend) only provides the plain libfuse3 API. The patch gates the darwin branch behind `DIS_FUSE_DARWIN_API`, which we never define. |
