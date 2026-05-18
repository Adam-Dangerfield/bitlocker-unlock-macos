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
| **Vendored at** | `38dab03175cb5798d625375154e716665201bae1` |
| **Tag/describe** | `38dab03` (no annotated tag in upstream at this commit) |
| **Date pinned** | 2026-05-18 |
| **Upstream** | https://github.com/Aorimn/dislocker |
| **Reason** | F7-03 supply-chain pinning — see [docs/security/SECURITY_REVIEW_2026-05-18.md](../docs/security/SECURITY_REVIEW_2026-05-18.md) |
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
