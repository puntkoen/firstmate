#!/usr/bin/env bash
# Single owner of "does this repository already carry this path on purpose".
#
# Both halves of the attribution boundary ask that same question and must never
# answer it differently: bin/fm-attribution-guard.sh refuses a new agent-named
# path but leaves one the repository already tracks maintainable, and
# bin/fm-ensure-agents-md.sh must not demand an ignore entry for a CLAUDE.md
# pointer the repository committed on purpose. What a commit already carries is
# deliberate; what is not in it yet is what the boundary keeps out.
#
# The answer comes from a commit rather than from the index, so a path staged in
# this very run does not pass as deliberate, and an empty ref - which is what an
# unborn branch and a root commit both produce - carries nothing. The path is
# read the way git names it, relative to the repository root rather than to the
# caller's directory.
fm_git_path_tracked_at() {  # <ref> <repo-relative-path>
  local ref=$1 path=$2
  [ -n "$ref" ] || return 1
  git cat-file -e "$ref:$path" 2>/dev/null
}
