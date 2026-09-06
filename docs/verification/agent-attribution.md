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

## Refusal, verified 2026-09-06

`tests/fm-attribution-guard.test.sh` is the reusable proof and drives real commits and pushes rather than inspecting the guard's source.

```
$ bash tests/fm-attribution-guard.test.sh
ok - fm-attribution-guard: every ruled message shape keeps its verdict
ok - fm-attribution-guard: a decorated agent co-author trailer refuses the commit
ok - fm-attribution-guard: a commented agent trailer refuses the commit
ok - fm-attribution-guard: the configured comment marker is read by both rules
ok - fm-attribution-guard: a verbose commit under a configured marker still commits
ok - fm-attribution-guard: a verbose commit removing a trailer still commits
ok - fm-attribution-guard: a trailer below a typed scissors line is refused at push
ok - fm-attribution-guard: agent co-author trailer refuses the commit
ok - fm-attribution-guard: a second harness's co-author trailer refuses the commit
ok - fm-attribution-guard: a human co-author still commits
ok - fm-attribution-guard: a human whose name is also a product name still commits
ok - fm-attribution-guard: a human at GitHub's private address still commits
ok - fm-attribution-guard: a bot at GitHub's private address is still refused
ok - fm-attribution-guard: env-names names exactly what export-env assigns
ok - fm-attribution-guard: a human whose name contains an agent token still commits
ok - fm-attribution-guard: a co-author at an agent vendor host refuses the commit
ok - fm-attribution-guard: a session link refuses the commit
ok - fm-attribution-guard: a session link on a co-author line refuses the commit
ok - fm-attribution-guard: ordinary links to a vendor's own site still commit
ok - fm-attribution-guard: an agent product or conversation link refuses the commit
ok - fm-attribution-guard: a generated-with credit refuses the commit
ok - fm-attribution-guard: the harness byline refuses the commit
ok - fm-attribution-guard: a hyphenated credit trailer refuses the commit
ok - fm-attribution-guard: wording about co-authored-by trailers still commits
ok - fm-attribution-guard: an agent co-author trailer is refused by one rule
ok - fm-attribution-guard: a hyphen-prefixed credit verb still refuses the commit
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

The commit-msg pass stops reading at git's scissors marker, because everything below it is the verbose diff `git commit -v` puts in the buffer and git discards.
Reading it would refuse a commit for the text it removes, which is exactly the captain's own cleanup work on the trailers this control exists to ban.
The residual is stated rather than hidden: a scissors line typed into a message by hand hides what follows it from the first gate, and the pre-push pass, which reads the recorded message where such a line is ordinary text, is what refuses it before anything leaves the machine.
Punctuation of any kind decorates a trailer - `- `, `* `, `> `, `>> `, `| `, `-- `, `1. `, a surrounding quote - with one exception: a single `-` or `+` followed straight by the key is a diff line rather than a decorated trailer.
Both message rules read the comment marker the repository configures, under `core.commentString` or `core.commentChar` and however many characters it is, since git builds both its comment lines and its scissors line from that marker.
The one shape not followed is `auto`, which resolves to `#` here rather than to the character git would pick for the message at hand.

Both message passes peel a leading `#` and judge what it hides, because `git commit -m` and `git commit -F` clean the message with `whitespace`, which keeps commentary, and only a message the author edits is cleaned with `strip`.
A `#`-prefixed agent trailer therefore reaches history under `-m`, which is why the commit gate reads it rather than skipping it.
The disclosed cost of reading both passes the same way is the opposite case: an attribution line typed into an editor comment that git would have dropped is refused too, which costs one re-edit.

A URL rule that reads only the host cannot tell a vendor's agent transcript from that vendor's careers page, so the hosts are split and the split is a disclosed limit rather than a claim of completeness.
Any URL on a transcript host such as `claude.ai` or `chatgpt.com` is refused, while a host that is also the vendor's company site - `anthropic.com`, `claude.com`, `cursor.com`, `openai.com`, `x.ai`, `xai.com`, `moonshot.cn`, `moonshot.ai`, `deepmind.com` - is refused only when the path names the agent product or a shared conversation.
An agent product page on one of those hosts whose path is not in that short list therefore passes the URL rule, which is the deliberate price of keeping ordinary reference links committable: this repository's own `bin/fm-bootstrap.sh` cites `https://cursor.com/cli`, and install, pricing, research and careers pages are not attribution.
The token and credit rules still cover such a line whenever it names an agent, which is what refuses the harness byline `Generated with [Claude Code](https://claude.com/claude-code)` independently of its link.
Every one of those domains keeps its full strength as a mail domain, so a co-author address at any of them is refused, subdomains included: the address rule requires a dot before the vendor host so a domain that merely ends in one of those strings - `mailbox.ai` ends in `x.ai` - stays somebody else's.

`noreply` on its own is not a bot signal, and that is a deliberate narrowing rather than an oversight.
GitHub gives every account a private `<id>+<user>@users.noreply.github.com` address and puts it in every co-author trailer it generates - web UI, squash merge, co-author suggestion - so reading the word alone as evidence refused a real person whose given name happens to be a Tier B token, which is the one thing the tier split exists to prevent.
The word still counts at a vendor host, `bot@` and `[bot]` are untouched, and GitHub's own bots all carry the `[bot]` suffix, so `github-actions[bot]` at that same private address keeps refusing.

`tests/fm-spawn-attribution.test.sh` proves a real spawn delivers both layers, and `tests/fm-ensure-agents-md.test.sh` proves an UNTRACKED `CLAUDE.md` pointer is never left committable.
That includes a pointer an earlier run already wrote, which the script now brings under the ignore rule instead of reporting unchanged.

```
$ bash tests/fm-spawn-attribution.test.sh
ok - fm-spawn: the attribution guard is armed in the pane before launch
ok - fm-spawn: every harness gets the same arming
ok - fm-spawn: an undeliverable arming refuses the launch
ok - fm-spawn: the guard survives a filtered launch environment
ok - fm-spawn: a claude worker's own commit and PR byline is switched off
```

A `CLAUDE.md` the repository already tracks is out of scope for both layers, in every shape it takes: the pointer file, a symlink left by the older installer, and a real memory file with its own content are left byte-identical and only reported, and no message asks a worker to untrack one.
That is deliberate and it is the same line the guard draws when it lets an already-tracked path be added, modified, and pushed; `bin/fm-git-tracked-lib.sh` is the one owner both scripts read it from.
The residual gap is therefore stated rather than hidden: a project that deliberately committed a `CLAUDE.md` keeps it, and both layers keep letting it be changed and pushed.
Only what the project does not carry yet is refused or excluded, which is the case the two leaks that started this work fell into.

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

A launch path that FILTERS the environment defeats the arming as completely as unsetting it, without anyone unsetting anything.
`config/launch-env-allowlist` is such a path: it rewrites the launch as `/usr/bin/env -i <retained names> /bin/sh -c '<launch>'`, and it dropped the three arming names, so a worker launched under that supported feature committed with no hook at all.
`bin/fm-attribution-guard.sh env-names` is now the one owner of those names, `bin/fm-spawn.sh` reads the list from there and retains it unconditionally, and a spawn that cannot obtain it refuses to launch rather than starting an unguarded worker.
`tests/fm-spawn-attribution.test.sh` proves it by running the launch environment a real spawn produced and committing through it.
The remote job paths (`bin/fm-remote-entrypoint.sh`, `bin/fm-remote-job-worker.sh`) also use `env -i`, but they compose the environment of a Firstmate command rather than of a worker's pane, and that command arms its own pane afterwards, so they are not on this boundary.

`bin/fm-ensure-agents-md.sh` does write one line into that shared `.git`, and that is deliberate rather than an oversight.
The two cases are not the same: a hook file changes how every commit made from the captain's own checkout behaves, while an `info/exclude` entry only stops one vendor-named file from being committed anywhere in that repository.
Stopping that file everywhere in the repository, not only in one task copy, is the requirement, so the shared scope of the common directory is the point rather than a cost.
`bin/fm-spawn.sh`'s `exclude_path` already writes to the same file by the same route.
