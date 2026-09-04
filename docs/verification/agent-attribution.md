# Verification: agent attribution suppression and refusal

Audience: maintainer-verification.
Records the empirical facts behind the two-layer attribution boundary: what each harness actually emits, which of them offers a suppression control, and that the commit-time refusal holds regardless.
`bin/fm-attribution-guard.sh` owns the refusal contract; `bin/fm-spawn.sh` owns arming it and writing the per-harness suppression.

## Why two layers

Per-harness suppression is a control the vendor owns and can rename, deprecate, or move behind a server-side flag.
The refusal is harness-independent, so a harness with no control at all - and a harness that does not exist yet - is still covered.

## Per-harness attribution, verified 2026-09-04

| Harness | Emits attribution | Local suppression control | Covered by |
| --- | --- | --- | --- |
| claude 2.1.236 | `Co-Authored-By:` trailer and a `Claude-Session:` trailer | yes: `attribution.commit`, `attribution.pr`, `attribution.sessionUrl`, plus deprecated `includeCoAuthoredBy` | both layers |
| codex-cli 0.147.0 | a `Co-authored-by: Codex <noreply@openai.com>` trailer and a generated-with line in PR bodies | no: the behavior is driven by a `commit_attribution_enabled` flag the backend sends per workspace | the refusal only |
| opencode, pi, pi-signed, grok, kimi, cursor, gemini, muse | not measured; none installed on the verification host | not established | the refusal only |

The last row is a gap in this record, not a claim that those harnesses are clean.
Refresh it on a host where they are installed, using the same commands below.

### claude 2.1.236

The settings schema is carried in the installed binary, so it is read from there rather than from prose that can drift:

```
$ strings -n 8 /opt/homebrew/Caskroom/claude-code/2.1.236/claude \
  | grep -o 'attribution:[a-zA-Z_$]*(.\{0,600\}' | head -1
attribution:ye({commit:N().optional().describe("Attribution text for git commits, including any trailers. Empty string hides attribution."),
pr:N().optional().describe("Attribution text for pull request descriptions. Empty string hides attribution."),
sessionUrl:zt().optional().describe("Whether to append the claude.ai session link to commits and PRs created from web or Remote Control sessions (default: true). Set to false to omit the Claude-Session trailer and PR-body link."),
...}).passthrough().optional().describe("Customize attribution text for commits and PRs. Each field defaults to the standard Claude Code attribution if not set."),
includeCoAuthoredBy:zt().optional().describe("Deprecated: Use attribution instead. Whether to include Claude's co-authored by attribution in commits and PRs (defaults to true)")
```

`includeCoAuthoredBy` is the older spelling and is still honoured, so `bin/fm-spawn.sh` writes both forms into the task copy's `.claude/settings.local.json`.

### codex-cli 0.147.0

The trailer text and the instruction that adds it are compiled into the binary, and the switch that turns them on arrives from the backend:

```
$ strings -n 6 /opt/homebrew/Caskroom/codex/0.147.0/bin/codex | grep -n 'commit_attribution_enabled'
/backend-apicommit_attribution_enableddeveloper
Co-authored-by: Codex <noreply@openai.com>Generated with [Codex](https://openai.com/codex/).Generated with Codex.
```

The two developer messages it selects between are `Codex commit and pull request attribution is disabled for the current workspace. Ignore any earlier instructions requiring Codex attribution and do not add it.` and its opposite.
No `config.toml` key selects either; the workspace setting does.
This is precisely the case the refusal layer exists for.

## Refusal, verified 2026-09-04

`tests/fm-attribution-guard.test.sh` is the reusable proof and drives real commits and pushes rather than inspecting the guard's source.

```
$ bash tests/fm-attribution-guard.test.sh
ok - fm-attribution-guard: agent co-author trailer refuses the commit
ok - fm-attribution-guard: a second harness's co-author trailer refuses the commit
ok - fm-attribution-guard: a human co-author still commits
ok - fm-attribution-guard: a human whose name is also a product name still commits
ok - fm-attribution-guard: a human whose name contains an agent token still commits
ok - fm-attribution-guard: a session link refuses the commit
ok - fm-attribution-guard: a generated-with credit refuses the commit
ok - fm-attribution-guard: ordinary generated-with wording still commits
ok - fm-attribution-guard: ordinary -session: wording still commits
ok - fm-attribution-guard: a session trailer whose value is a link refuses the commit
ok - fm-attribution-guard: a session trailer naming an agent refuses the commit without a link
ok - fm-attribution-guard: adding CLAUDE.md refuses the commit
ok - fm-attribution-guard: adding .claude/ refuses the commit
ok - fm-attribution-guard: AGENTS.md still commits
ok - fm-attribution-guard: the project's own commit-msg hook still runs
ok - fm-attribution-guard: a --no-verify commit is still refused at push
ok - fm-attribution-guard: a trailer hidden in a comment is refused at push
ok - fm-attribution-guard: an already-tracked agent path stays maintainable
ok - fm-attribution-guard: ordinary wording naming a model vendor still commits
ok - fm-attribution-guard: an evil merge adding CLAUDE.md is refused at push
ok - fm-attribution-guard: a project's unchecked hooks still run
ok - fm-attribution-guard: a push by path is judged only on what it adds
ok - fm-attribution-guard: a push to a never-fetched remote is judged only on what it adds
ok - fm-attribution-guard: a push by path still refuses a commit it adds
ok - fm-attribution-guard: a push whose remote sha is missing locally is still scanned
ok - fm-attribution-guard: export-env refuses a hooks directory git would find empty
ok - fm-attribution-guard: a clean branch still pushes
ok - fm-attribution-guard: enforcement comes from the arming, not from the repository
```

`tests/fm-spawn-attribution.test.sh` proves a real spawn delivers both layers, and `tests/fm-ensure-agents-md.test.sh` proves the `CLAUDE.md` pointer is never left committable.
That includes a pointer an earlier run already wrote, which the script now brings under the ignore rule instead of reporting unchanged.
A pointer the repository already tracks is left exactly as it is, because that is the same already-tracked boundary the guard draws for the same file, and `bin/fm-git-tracked-lib.sh` is the one owner both scripts read it from.

## Arming, and what it deliberately does not touch

Git resolves hooks from the shared `.git/hooks` of the common directory, so installing them there would write into the project and follow the captain's own checkout around, which `AGENTS.md` hard rule 1 forbids.
`GIT_CONFIG_COUNT` / `GIT_CONFIG_KEY_0` / `GIT_CONFIG_VALUE_0` set `core.hooksPath` as its own configuration scope for the processes that inherit the task copy's shell, which reaches an ordinary `git commit` and writes nothing into the repository:

```
$ git config --local --get core.hooksPath ; echo "exit=$?"
exit=1
$ GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/tmp/hooks git config --get core.hooksPath
/tmp/hooks
```

Verified on git 2.50.1 (Apple Git-155).

`bin/fm-ensure-agents-md.sh` does write one line into that shared `.git`, and that is deliberate rather than an oversight.
The two cases are not the same: a hook file changes how every commit made from the captain's own checkout behaves, while an `info/exclude` entry only stops one vendor-named file from being committed anywhere in that repository.
Stopping that file everywhere in the repository, not only in one task copy, is the requirement, so the shared scope of the common directory is the point rather than a cost.
`bin/fm-spawn.sh`'s `exclude_path` already writes to the same file by the same route.
