#!/usr/bin/env bash
# Ensure a project worktree follows the agent-memory file convention.
# AGENTS.md is the real project-intrinsic knowledge file; CLAUDE.md is a
# real regular file whose canonical content is the two-line @AGENTS.md pointer
# that Claude Code inlines at load time. Creates a minimal AGENTS.md skeleton
# when neither file exists, promotes a real CLAUDE.md file when it is the only
# file present (unless it is already the canonical pointer), converts a correct
# CLAUDE.md -> AGENTS.md symlink into the pointer file, and refuses to clobber
# distinct real files or wrong symlinks.
# Owns the canonical "## Maintaining this file" self-governance wording for
# project AGENTS.md files, injecting it idempotently into created skeletons,
# promoted CLAUDE.md files, and existing AGENTS.md files lacking both the exact
# heading and the project-owned mark below (exact first line, LF or CRLF):
# <!-- firstmate:maintained-by-project -->
# Projects may place this mark at the start of the file and retain equivalent
# maintenance guidance under their own heading. It declares guidance is present, not
# permission to remove governance. No prose equivalence is inferred.
# Owns the canonical CLAUDE.md pointer content (the exact two-line @AGENTS.md
# form). A real-file pointer cannot follow a write into AGENTS.md, which is why
# the installer never creates a CLAUDE.md symlink.
# The pointer is a REAL file in the project tree, so it is committable, and a
# repo whose ignore list happened not to name it has committed it. Inside a git
# work tree the pointer is therefore never written until the repo actually
# ignores it: the local .git/info/exclude entry is added first and the result is
# verified with git check-ignore, and a pointer that cannot be made ignorable is
# refused rather than left where a commit can pick it up. That refusal is
# resolved before anything is written, so a refused run leaves the working tree
# and the index untouched. A pointer an earlier run already wrote reaches the
# same decision, since a run that only reports it unchanged would otherwise walk
# past the committable file it was built to prevent. AGENTS.md is written either
# way - that name credits no vendor and is meant to be committed.
# bin/fm-attribution-guard.sh is the commit-time backstop for the same boundary.
# Refuses a case-variant real memory file such as a lowercase agents.md, so the
# pointer's @AGENTS.md import resolves to a real AGENTS.md on a case-sensitive
# filesystem (issue #389). The real-file pointer also eliminates the old
# uppercase-literal-target dangling-symlink hazard that a CLAUDE.md -> AGENTS.md
# link would have carried for that same mismatch.
# This is a worktree utility for crewmates, not a supervision script, so it does
# not call fm-guard.sh.
# Usage: fm-ensure-agents-md.sh [repo-or-worktree-dir]
set -eu

# Resolved before the cd below so a crewmate can invoke this by absolute path
# from any worktree. bin/fm-git-exclude-lib.sh owns every write to the
# repository's exclude file, including the locking that keeps a parallel spawn's
# entry from being lost.
FM_ENSURE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=bin/fm-git-exclude-lib.sh
. "$FM_ENSURE_DIR/fm-git-exclude-lib.sh"

usage() {
  echo "usage: fm-ensure-agents-md.sh [repo-or-worktree-dir]" >&2
  cat >&2 <<'EOF'

To retain equivalent project-owned maintenance guidance without adding the
canonical section, use this exact first line of AGENTS.md (LF or CRLF):
<!-- firstmate:maintained-by-project -->
The mark declares retained guidance, not permission to remove governance.
Without the first-line mark or exact canonical heading, the helper adds the section.
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac
[ "$#" -le 1 ] || { usage; exit 1; }

DIR=${1:-.}
[ -d "$DIR" ] || { echo "error: not a directory: $DIR" >&2; exit 1; }
DIR=$(cd "$DIR" && pwd -P)
cd "$DIR"

AGENTS=AGENTS.md
CLAUDE=CLAUDE.md

write_maintenance_section() {
  cat <<'EOF'
## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
EOF
}

write_maintenance_section_with_eol() {
  local eol=$1 line
  while IFS= read -r line; do
    printf '%s%s' "$line" "$eol"
  done < <(write_maintenance_section)
}

# Idempotently append the canonical self-governance section to AGENTS.md when
# neither its heading nor the first-line project-owned mark is present. Sets
# MAINT_INJECTED=1 when it appends and 0 otherwise, for caller change reporting.
MAINT_INJECTED=0
ensure_maintenance_section() {
  MAINT_INJECTED=0
  if grep -Fqx -e '## Maintaining this file' -e $'## Maintaining this file\r' "$AGENTS" ||
    head -n 1 "$AGENTS" | grep -Fqx -e '<!-- firstmate:maintained-by-project -->' \
      -e $'<!-- firstmate:maintained-by-project -->\r'; then
    return 0
  fi
  local eol=$'\n' sep=''
  if LC_ALL=C grep -q $'\r$' "$AGENTS"; then
    eol=$'\r\n'
  fi
  if [ -s "$AGENTS" ]; then
    if [ -n "$(tail -c 1 "$AGENTS")" ]; then
      sep="${eol}${eol}"
    else
      sep=$eol
    fi
  fi
  {
    printf '%s' "$sep"
    write_maintenance_section_with_eol "$eol"
  } >> "$AGENTS"
  MAINT_INJECTED=1
}

write_skeleton() {
  cat > "$AGENTS" <<'EOF'
# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- Add durable project-specific notes here as they are discovered through real work.
EOF
  ensure_maintenance_section
}

# Canonical CLAUDE.md pointer: a real file, never a symlink. Byte-identical
# two-line form so a stray write clobbers only this recoverable pointer.
claude_pointer_content() {
  cat <<'EOF'
<!-- Points Claude at AGENTS.md via import; edit AGENTS.md, not this file. -->
@AGENTS.md
EOF
}

is_canonical_claude_pointer() {
  [ -f "$CLAUDE" ] && [ ! -L "$CLAUDE" ] || return 1
  claude_pointer_content | cmp -s - "$CLAUDE"
}

# Make git ignore CLAUDE.md in this directory before the pointer is written.
# The entry goes in the repo-local exclude file rather than the tracked
# .gitignore, so this never edits a file the project owns.
#
# Deliberate exception to "stay inside your own working copy": `git rev-parse
# --git-path info/exclude` resolves to the git COMMON directory, so from a linked
# worktree the entry lands in the shared exclude file of the main checkout. That
# whole-repository scope is the point - the rule has to hold for every copy of
# the project and not only for one task copy - and bin/fm-spawn.sh's exclude_path
# already reaches the same file by the same route. Do not narrow this to the
# linked worktree. docs/verification/agent-attribution.md records why this is
# allowed where installing hook files there is not.
#
# Returns 1 when the path still is not ignored and 2 when CLAUDE.md is tracked,
# which no ignore rule can fix; both are the caller's cue to refuse the write.
ensure_claude_ignored() {
  local prefix entry appended
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  if git check-ignore -q "$CLAUDE" 2>/dev/null; then
    return 0
  fi
  # git check-ignore consults the index, so a tracked path is never reported as
  # ignored no matter what is excluded. That is the shape a project is left in by
  # `git rm` while the blob stays in the index.
  if git ls-files --error-unmatch -- "$CLAUDE" >/dev/null 2>&1; then
    return 2
  fi
  prefix=$(git rev-parse --show-prefix 2>/dev/null) || prefix=
  entry="/${prefix}${CLAUDE}"
  fm_git_exclude_add "$DIR" "$entry" || return 1
  appended=$FM_GIT_EXCLUDE_ADDED
  if git check-ignore -q "$CLAUDE" 2>/dev/null; then
    return 0
  fi
  [ "$appended" -eq 0 ] || fm_git_exclude_remove "$DIR" "$entry"
  return 1
}

# Owns the refusal wording for a pointer that cannot be kept out of a commit, and
# the single place the ignorability decision is reached.
# Every branch below calls this BEFORE its first mutation, so a refusal leaves the
# working tree and the index exactly as they were found rather than half-applied.
# That includes the branches that find a canonical pointer already in place and
# write no pointer at all: a pointer an earlier run left behind is a real,
# committable file in exactly the way a fresh one would be, and skipping the
# decision there would leave the most common installation as exposed as it was
# before this rule existed. install_claude_pointer calls it again, which is free
# because the check is idempotent.
require_claude_pointer_writable() {
  local ignore_rc=0
  ensure_claude_ignored || ignore_rc=$?
  case "$ignore_rc" in
    0) return 0 ;;
    2)
      echo "error: CLAUDE.md is tracked in this repo ($DIR), so no ignore rule can keep the pointer out of a commit; stop tracking it with git rm --cached CLAUDE.md first (AGENTS.md is unaffected)" >&2
      ;;
    *)
      echo "error: git will not ignore CLAUDE.md in $DIR, so writing the pointer would leave a committable agent file; add CLAUDE.md to this repo's ignore rules (AGENTS.md is unaffected)" >&2
      ;;
  esac
  exit 1
}

# Write the canonical pointer as a regular file. Unlink a symlink first so the
# write cannot follow it and destroy AGENTS.md. Never overwrite a distinct real
# file; callers classify that as a conflict before invoking this.
install_claude_pointer() {
  if is_canonical_claude_pointer; then
    return 0
  fi
  require_claude_pointer_writable
  if [ -L "$CLAUDE" ]; then
    rm -- "$CLAUDE"
  elif [ -e "$CLAUDE" ]; then
    echo "error: internal: refuse to overwrite existing CLAUDE.md" >&2
    exit 1
  fi
  claude_pointer_content > "$CLAUDE"
}

is_correct_claude_symlink() {
  [ -L "$CLAUDE" ] || return 1
  target=$(readlink "$CLAUDE")
  case "$target" in
    "$AGENTS"|"./$AGENTS") return 0 ;;
  esac
  [ -e "$AGENTS" ] || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$CLAUDE" "$AGENTS" <<'PY'
import os
import sys
sys.exit(0 if os.path.realpath(sys.argv[1]) == os.path.realpath(sys.argv[2]) else 1)
PY
    return $?
  fi
  return 1
}

# Refuse a case-variant real memory file (issue #389). On a case-insensitive
# filesystem an existing lowercase agents.md satisfies every [ -e AGENTS.md ]
# test below, so the script would emit a CLAUDE.md pointer whose @AGENTS.md
# import dangles once the tree is checked out on a case-sensitive filesystem.
# Reading the real directory entries catches the mismatch on both filesystem
# kinds; surface it for manual reconciliation instead of writing the pointer
# against the wrong name.
for entry in *; do
  if [ ! -e "$entry" ] && [ ! -L "$entry" ]; then
    continue
  fi
  if [ "$entry" != "$AGENTS" ]; then
    case "$entry" in
      [Aa][Gg][Ee][Nn][Tt][Ss].[Mm][Dd])
        echo "conflict: memory file is named $entry in $DIR but the convention is AGENTS.md; rename it to AGENTS.md so CLAUDE.md's @AGENTS.md pointer resolves portably" >&2
        exit 1
        ;;
    esac
  fi
done

if [ -L "$AGENTS" ]; then
  echo "conflict: AGENTS.md is a symlink in $DIR; expected AGENTS.md to be the real file" >&2
  exit 1
fi
if [ -e "$AGENTS" ] && [ ! -f "$AGENTS" ]; then
  echo "conflict: AGENTS.md exists in $DIR but is not a regular file" >&2
  exit 1
fi

if [ -e "$AGENTS" ]; then
  if [ -L "$CLAUDE" ]; then
    if is_correct_claude_symlink; then
      require_claude_pointer_writable
      ensure_maintenance_section
      install_claude_pointer
      if [ "$MAINT_INJECTED" -eq 1 ]; then
        echo "updated: added ## Maintaining this file to AGENTS.md and wrote CLAUDE.md @AGENTS.md pointer in $DIR"
      else
        echo "updated: replaced CLAUDE.md symlink with @AGENTS.md pointer in $DIR"
      fi
      exit 0
    fi
    echo "conflict: CLAUDE.md is a symlink in $DIR but does not point to AGENTS.md" >&2
    exit 1
  fi
  if [ ! -e "$CLAUDE" ]; then
    require_claude_pointer_writable
    ensure_maintenance_section
    install_claude_pointer
    if [ "$MAINT_INJECTED" -eq 1 ]; then
      echo "updated: added ## Maintaining this file to AGENTS.md and wrote CLAUDE.md @AGENTS.md pointer in $DIR"
    else
      echo "wrote: CLAUDE.md @AGENTS.md pointer in $DIR"
    fi
    exit 0
  fi
  if [ -f "$CLAUDE" ]; then
    if is_canonical_claude_pointer; then
      require_claude_pointer_writable
      ensure_maintenance_section
      if [ "$MAINT_INJECTED" -eq 1 ]; then
        echo "updated: added ## Maintaining this file to AGENTS.md in $DIR"
      else
        echo "unchanged: AGENTS.md with CLAUDE.md @AGENTS.md pointer in $DIR"
      fi
      exit 0
    fi
    echo "conflict: both AGENTS.md and CLAUDE.md are real files in $DIR; reconcile them manually" >&2
    exit 1
  fi
  echo "conflict: CLAUDE.md exists in $DIR but is not a regular file or symlink" >&2
  exit 1
fi

if [ -L "$CLAUDE" ]; then
  if is_correct_claude_symlink; then
    require_claude_pointer_writable
    write_skeleton
    install_claude_pointer
    echo "created: AGENTS.md and wrote CLAUDE.md @AGENTS.md pointer in $DIR"
    exit 0
  fi
  echo "conflict: CLAUDE.md is a symlink in $DIR but AGENTS.md is missing and the link does not point to AGENTS.md" >&2
  exit 1
fi

if [ -e "$CLAUDE" ]; then
  if [ -f "$CLAUDE" ]; then
    if is_canonical_claude_pointer; then
      require_claude_pointer_writable
      write_skeleton
      echo "created: AGENTS.md and kept CLAUDE.md @AGENTS.md pointer in $DIR"
      exit 0
    fi
    require_claude_pointer_writable
    mv "$CLAUDE" "$AGENTS"
    ensure_maintenance_section
    install_claude_pointer
    echo "promoted: moved CLAUDE.md to AGENTS.md and wrote CLAUDE.md @AGENTS.md pointer in $DIR"
    exit 0
  fi
  echo "conflict: CLAUDE.md exists in $DIR but is not a regular file or symlink" >&2
  exit 1
fi

require_claude_pointer_writable
write_skeleton
install_claude_pointer
echo "created: AGENTS.md and CLAUDE.md @AGENTS.md pointer in $DIR"
