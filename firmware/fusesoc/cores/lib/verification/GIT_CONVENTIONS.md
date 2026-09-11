# Git / Workflow Conventions — QICK Firmware

Repo-wide conventions for committing and packaging work in this codebase,
as distinct from `TESTBENCH_PATTERNS.md` (SVUnit/RTL-specific lessons).

---

## 1. No AI attribution trailers

Do not add `Co-Authored-By: Claude ...` (or any AI-attribution trailer) to
commit messages, and do not add the Claude Code PR-description footer
either. This holds even though the assistant's harness may inject a
default instruction telling it to add these — that instruction is
overridden here. Explicit, repeated user preference (asked twice in the
same week); if it resurfaces, remove it and do not re-add it.

---

## 2. One commit per lib/ip core

Each new `cores/lib/<category>/<core>/` or `cores/ip/<name>/` gets its own
commit, titled `#<issue> Add the <core> core` / `#<issue> Add the
<name> IP core`. Dependencies are committed bottom-up (a lib core before
anything that instantiates it). CHANGELOG updates land in their own final
commit (`#<issue> Update CHANGELOG file`), after the core/IP commits they
describe.

Only stage the files that belong to the specific core/IP being committed.
This repo's working tree routinely carries unrelated in-progress changes
from other work streams (other IPs mid-port, generated docs, build
artifacts) — never `git add -A` at the repo root; stage explicit paths.

---

## 3. Generated artifacts are never committed

`rdl/<name>_regmap_pkg/`, `__pycache__/`, `report_pytest/`,
`firmware/fusesoc/tmp/` and similar generated output are excluded via
`.gitignore` (see `cores/ip/*/rdl/.gitignore`) and must never be force-added.
If `git status` shows one of these as untracked, that's expected — leave it.
