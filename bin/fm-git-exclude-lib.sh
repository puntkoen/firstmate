#!/usr/bin/env bash
# Single owner for one line in a repository's .git/info/exclude.
#
# Two firstmate writers reach that file for the same project at the same time:
# bin/fm-spawn.sh keeps agent-owned dot-paths out of the index, and
# bin/fm-ensure-agents-md.sh keeps the CLAUDE.md pointer out of it and takes its
# own line back out when the pointer turns out to be unwritable. The file lives
# in the git COMMON directory and is shared by every worktree of the repository,
# which bin/fm-ensure-agents-md.sh records as deliberate, so an unlocked
# read-modify-write here silently drops a line a parallel spawn just appended.
#
# Every add and every remove therefore runs under one lock per repository,
# taken with bin/fm-wake-lib.sh's lock helpers like the rest of this repo, and a
# remove only ever takes the exact line it was given. The file is rewritten in
# place rather than replaced, so its inode, mode, and owner survive.

# shellcheck source=bin/fm-wake-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/fm-wake-lib.sh"

# Absolute path to the repository's exclude file. git prints --git-path relative
# to the directory it ran in, so it is resolved against that directory rather
# than against the caller's own, which need not be the same.
fm_git_exclude_file() {  # <work-dir>
  local dir=$1 excl top
  excl=$(git -C "$dir" rev-parse --git-path info/exclude 2>/dev/null) || return 1
  [ -n "$excl" ] || return 1
  case "$excl" in
    /*) ;;
    *)
      top=$(cd "$dir" 2>/dev/null && pwd -P) || return 1
      excl="$top/$excl"
      ;;
  esac
  printf '%s\n' "$excl"
}

# Set by fm_git_exclude_add to 1 when this call is the one that appended the
# entry and 0 when it was already there, so a caller knows whether a rollback of
# its own is warranted.
FM_GIT_EXCLUDE_ADDED=0

fm_git_exclude_add() {  # <work-dir> <entry>
  local dir=$1 entry=$2 excl lock rc=0
  FM_GIT_EXCLUDE_ADDED=0
  excl=$(fm_git_exclude_file "$dir") || return 1
  mkdir -p "$(dirname "$excl")" || return 1
  lock="$excl.fm-lock"
  fm_lock_acquire_wait "$lock" || return 1
  if ! grep -qxF -- "$entry" "$excl" 2>/dev/null; then
    # An unterminated last line would otherwise swallow the new entry.
    if [ -s "$excl" ] && [ -n "$(tail -c 1 "$excl")" ]; then
      printf '\n' >> "$excl" || rc=1
    fi
    if [ "$rc" -eq 0 ]; then
      if printf '%s\n' "$entry" >> "$excl"; then
        # shellcheck disable=SC2034 # Consumed by sourcing callers (bin/fm-ensure-agents-md.sh ensure_claude_ignored).
        FM_GIT_EXCLUDE_ADDED=1
      else
        rc=1
      fi
    fi
  fi
  fm_lock_release "$lock"
  return "$rc"
}

# grep exits 1 when it selected nothing, which here means the file held our
# entry and nothing else, and 2 or more when it could not read the file at all.
# Reading both as "nothing survives" truncated a file this call had failed to
# read, and the file is shared by every worktree of the repository, so that
# silently dropped the captain's own ignore rules and any a parallel spawn had
# just written. An unreadable file is therefore left exactly as it is and the
# call refuses, with grep's own diagnostic left on stderr rather than discarded.
fm_git_exclude_remove() {  # <work-dir> <entry>
  local dir=$1 entry=$2 excl lock kept status=0 rc=0
  excl=$(fm_git_exclude_file "$dir") || return 1
  lock="$excl.fm-lock"
  fm_lock_acquire_wait "$lock" || return 1
  if [ -f "$excl" ]; then
    kept=$(grep -vxF -- "$entry" "$excl") || status=$?
    if [ "$status" -ge 2 ]; then
      echo "error: fm_git_exclude_remove: could not read $excl, so it is left untouched and $entry stays in it" >&2
      rc=1
    elif [ -n "$kept" ]; then
      printf '%s\n' "$kept" > "$excl" || rc=1
    else
      : > "$excl" || rc=1
    fi
  fi
  fm_lock_release "$lock"
  return "$rc"
}
