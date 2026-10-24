# claude-code-guardrails

[![test](https://github.com/karam-ababneh/claude-code-guardrails/actions/workflows/test.yml/badge.svg)](https://github.com/karam-ababneh/claude-code-guardrails/actions/workflows/test.yml)

A deterministic safety hook for [Claude Code](https://docs.claude.com/en/docs/claude-code/overview).
It checks every shell command an AI coding agent wants to run, **before** it runs.

AI agents write and execute code quickly. Asking them to "be careful" is a request, not a guarantee.
This hook replaces the request with a rule that is enforced on every call, adds about 0.1 s,
and needs no LLM call.

## What it does

| Decision | Examples | Mechanism |
|---|---|---|
| **Block** | `git push --force`, `git reset --hard`, `DROP TABLE`, `TRUNCATE` in SQL, recursive delete outside temp/build folders, discarding a lockfile diff | exit code `2` — the command does not run, the reason goes back to the agent |
| **Ask** | `git remote -v` without a filter (may print access tokens), dev server while `.env` points at a hosted database | `permissionDecision: "ask"` |
| **Pass** | everything else, including `rm -rf node_modules`, `rm -rf /tmp/…`, the CSS class `truncate` | exit `0` |

### Design decisions

- **Block instead of ask for irreversible commands.** In auto mode an "ask" can be approved
  silently, so a guard that only asks behaves like a logbook.
- **Narrow patterns.** A guard that fires on harmless commands gets switched off. `truncate` is only
  matched as SQL or as the Unix command, not as a Tailwind class; recursive deletes inside
  `node_modules`, `dist/`, `build/` and `/tmp` pass.
- **A lockfile diff is a finding, not noise.** After an install it usually means dependency drift;
  discarding it can break `npm ci` in CI.

## Install

```bash
git clone https://github.com/karam-ababneh/claude-code-guardrails ~/claude-code-guardrails
```

Merge [`settings.example.json`](settings.example.json) into `~/.claude/settings.json`. Requires `bash` and `jq`.

Optional log of every decision: `export GUARD_LOG=~/.claude/bash-guard.log`

## Tests

```bash
bash tests/bash-guard.test.sh          # 19 table-driven cases: block / ask / pass
docker build -t guardrails . && docker run --rm guardrails
```

GitHub Actions runs ShellCheck, the tests on the runner and the tests inside Docker on every push.

The suite was mutation-tested: removing the lockfile rule or the recursive-delete rule makes it fail.

## Limits

This is a pattern-based safety net, not a sandbox. A determined or obfuscated command
(e.g. built from variables or base64) can get past it. Use it together with permission rules
and a sandbox, not instead of them.

## License

MIT
