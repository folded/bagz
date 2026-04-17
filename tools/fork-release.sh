#!/usr/bin/env bash
# Maintenance script for the fork. See FORK.md for the full workflow.
#
# Usage:
#   tools/fork-release.sh sync          Fast-forward main from upstream/main.
#   tools/fork-release.sh rebase        Rebase every branch in fork-branches.txt onto main.
#   tools/fork-release.sh rebuild       Rebuild the `fork` integration branch.
#   tools/fork-release.sh prune         Report fix/* branches already merged upstream.
#   tools/fork-release.sh tag <ver>     Tag the tip of `fork` as v<ver>.
#   tools/fork-release.sh all <ver>     sync + rebase + rebuild + tag.
#
# <ver> is a PEP 440 local version, e.g. 0.1.2+fork.1.
#
# Environment:
#   UPSTREAM_REMOTE  (default: upstream)
#   ORIGIN_REMOTE    (default: origin)

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
BRANCHES_FILE="$REPO_ROOT/tools/fork-branches.txt"
UPSTREAM_REMOTE=${UPSTREAM_REMOTE:-upstream}
ORIGIN_REMOTE=${ORIGIN_REMOTE:-origin}

branches() {
  require_branches_file
  grep -Ev '^\s*(#|$)' "$BRANCHES_FILE"
}

require_branches_file() {
  if [[ ! -f "$BRANCHES_FILE" ]]; then
    echo "error: $BRANCHES_FILE not found." >&2
    echo "Check out a branch that contains it (e.g. meta/ci-wheels or fork)." >&2
    exit 1
  fi
}

require_clean_tree() {
  if ! git diff-index --quiet HEAD --; then
    echo "error: working tree has uncommitted changes; commit or stash first" >&2
    exit 1
  fi
}

# Git stores refs as paths, so a ref named `foo` cannot coexist with refs
# under `foo/`. Validate before any destructive op that would create `foo`.
ensure_can_create_branch() {
  local ref="$1"
  local conflicting
  conflicting=$(git for-each-ref --format='%(refname:short)' "refs/heads/${ref}/")
  if [[ -n "$conflicting" ]]; then
    echo "error: cannot create branch '$ref'; conflicting branches exist:" >&2
    printf '  %s\n' $conflicting >&2
    exit 1
  fi
}

cmd_sync() {
  require_clean_tree
  git fetch "$UPSTREAM_REMOTE"
  git checkout main
  git merge --ff-only "$UPSTREAM_REMOTE/main"
  echo "main is at $(git rev-parse --short main) (==$UPSTREAM_REMOTE/main)"
}

cmd_rebase() {
  require_clean_tree
  local failed=0
  while read -r br; do
    echo "==> Rebasing $br onto main"
    if ! git rev-parse --verify "$br" >/dev/null 2>&1; then
      echo "    branch '$br' not found locally."
      echo "    If it exists on $ORIGIN_REMOTE: git checkout -b $br $ORIGIN_REMOTE/$br"
      failed=1
      continue
    fi
    git checkout "$br"
    if ! git rebase main; then
      echo "    rebase conflict on $br — resolve, run 'git rebase --continue', then re-run this script" >&2
      exit 1
    fi
  done < <(branches)
  git checkout main
  [[ $failed -eq 0 ]]
}

cmd_rebuild() {
  require_clean_tree
  ensure_can_create_branch fork
  # Read the branches list before the checkout discards the working tree —
  # fork-branches.txt doesn't exist on main. Use a while-loop instead of
  # mapfile for bash 3.2 compatibility (macOS system bash).
  local brs=()
  while IFS= read -r line; do
    brs+=("$line")
  done < <(branches)
  # Remember where we started so we can return there after rebuilding —
  # leaving the user on `fork` (a disposable branch) invites accidental
  # commits onto it.
  local starting_ref
  starting_ref=$(git symbolic-ref --quiet --short HEAD) || \
    starting_ref=$(git rev-parse HEAD)
  git checkout -B fork main
  for br in "${brs[@]}"; do
    echo "==> Merging $br into fork"
    if ! git merge --no-ff --no-edit "$br"; then
      echo "    merge conflict on $br — resolve, commit, then 'git checkout $starting_ref'" >&2
      exit 1
    fi
  done
  echo "fork is at $(git rev-parse --short fork)"
  git checkout --quiet "$starting_ref"
  echo "returned to $starting_ref"
}

cmd_prune() {
  git fetch "$UPSTREAM_REMOTE" --quiet
  local any=0
  for br in $(git for-each-ref --format='%(refname:short)' refs/heads/fix/); do
    if git merge-base --is-ancestor "$br" "$UPSTREAM_REMOTE/main"; then
      echo "$br is an ancestor of $UPSTREAM_REMOTE/main — remove from fork-branches.txt and 'git branch -D $br'"
      any=1
    fi
  done
  [[ $any -eq 0 ]] && echo "no fix/* branches have been merged upstream"
}

cmd_tag() {
  local ver="${1:-}"
  if [[ -z "$ver" ]]; then
    echo "error: version required, e.g. 0.1.2+fork.1" >&2
    exit 2
  fi
  local tag="v${ver}"
  if git rev-parse --verify "refs/tags/$tag" >/dev/null 2>&1; then
    echo "error: tag $tag already exists" >&2
    exit 1
  fi
  git tag -a "$tag" fork -m "$tag"
  echo "tagged $tag at $(git rev-parse --short fork)"
  echo "push to trigger the wheels workflow: git push $ORIGIN_REMOTE $tag"
}

cmd_all() {
  local ver="${1:-}"
  if [[ -z "$ver" ]]; then
    echo "error: version required, e.g. 0.1.2+fork.1" >&2
    exit 2
  fi
  cmd_sync
  cmd_rebase
  cmd_rebuild
  cmd_tag "$ver"
}

case "${1:-}" in
  sync)    shift; cmd_sync "$@" ;;
  rebase)  shift; cmd_rebase "$@" ;;
  rebuild) shift; cmd_rebuild "$@" ;;
  prune)   shift; cmd_prune "$@" ;;
  tag)     shift; cmd_tag "$@" ;;
  all)     shift; cmd_all "$@" ;;
  ""|-h|--help)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0 ;;
  *)
    echo "unknown subcommand: $1" >&2
    echo "run '$0 --help' for usage" >&2
    exit 2 ;;
esac
