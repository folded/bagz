# Fork maintenance

This repository is a fork of [google-deepmind/bagz](https://github.com/google-deepmind/bagz)
carrying fixes and additions that have not yet landed upstream. This document
describes how the fork is organised and how to cut a release.

## Branch layout

| Branch         | Purpose                                                                  |
| -------------- | ------------------------------------------------------------------------ |
| `main`         | Mirrors `upstream/main` exactly. Never committed to directly.            |
| `fix/<name>`   | One patch intended to be PR'd upstream. Branched from `main`.            |
| `fork/<name>`  | Fork-only content (CI, tooling) that will never go upstream.             |
| `fork`         | Disposable integration branch. Rebuilt from scratch on every release.    |

`fork` = `main` + every `fix/*` + every `fork/*`, merged in the order listed in
[`tools/fork-branches.txt`](tools/fork-branches.txt). Release tags are cut
from `fork`.

## One-time setup

```bash
git remote add upstream https://github.com/google-deepmind/bagz.git
git config rerere.enabled true   # auto-reapply rebase conflict resolutions
```

Enable GitHub Pages in Settings → Pages → Branch: `gh-pages` / `/ (root)` so
the simple index publishes to `https://<you>.github.io/bagz/simple/`.

## Versioning

Release tags use PEP 440 local versions:

    v<upstream-version>+fork.<N>

- `<upstream-version>` — the upstream version the fork is based on.
- `<N>` — bump whenever fork content changes against the same upstream base;
  reset to 1 when `<upstream-version>` changes.

Examples: `v0.1.2+fork.1`, `v0.1.2+fork.2`, `v0.2.0+fork.1`.

The `+` local segment means these wheels cannot be uploaded to public PyPI —
they are published to GitHub Releases and indexed on the `gh-pages` branch.

## Release cycle

The entire cycle is driven by [`tools/fork-release.sh`](tools/fork-release.sh):

```bash
tools/fork-release.sh all 0.1.2+fork.1
git push origin v0.1.2+fork.1
```

Pushing the tag triggers `.github/workflows/wheels.yml`, which builds wheels
for manylinux_2_28 (x86_64, aarch64) and macOS (x86_64, arm64), attaches them
to a GitHub Release, and regenerates the simple index on `gh-pages`.

The `all` subcommand is a shortcut for running these in order:

| Step      | What it does                                                                    |
| --------- | ------------------------------------------------------------------------------- |
| `sync`    | `git fetch upstream` + fast-forward `main` to `upstream/main`.                  |
| `rebase`  | Rebase every branch in `tools/fork-branches.txt` onto the new `main`.           |
| `rebuild` | Re-create `fork` from `main` and merge each listed branch in order (`--no-ff`). |
| `tag`     | Annotated tag on the tip of `fork`.                                             |

If a rebase or merge conflict occurs, the script stops. Resolve the conflict,
run `git rebase --continue` (or `git commit` for a merge), then re-run the
failing step.

## Pruning merged patches

After upstream accepts a fix, drop it from the fork:

```bash
tools/fork-release.sh prune
```

This reports every `fix/*` branch whose tip is already in `upstream/main`.
For each one:

1. Remove the line from `tools/fork-branches.txt`.
2. `git branch -D fix/<name>`.
3. `git push origin --delete fix/<name>` if it was pushed.

## Consuming the fork

Downstream projects pin against the simple index:

```toml
# pyproject.toml (uv / pdm)
[tool.uv]
extra-index-url = ["https://<you>.github.io/bagz/simple/"]

dependencies = ["bagz==0.1.2+fork.1"]
```

```
# requirements.txt
--extra-index-url https://<you>.github.io/bagz/simple/
bagz==0.1.2+fork.1
```

pip, uv, poetry, and pdm all resolve the right wheel for the consumer's
platform automatically. No OS-specific pins required.
