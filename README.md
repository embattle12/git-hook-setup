# DV Pre‑commit Policy Hook & Smoke Gate — **Admin + User Guide**

This repo ships with a production‑ready **pre‑commit** hook that protects your verification workbench while keeping dev velocity high.

It enforces **path‑based access control**, **admin‑only deletes**, **config integrity**, **freeze windows**, and an optional **Smoke Test Gate** (compile/elab or SW header step) — all **policy‑driven** from a single JSON file you (the admin) own.

It also includes an **ephemeral sharing tool** (`dvshare`) for safely handing a set of local (uncommitted) files to a teammate without committing them.

---

## TL;DR for Users

1. **Install the hook** (already in this repo). Nothing to do except keep `config/hook_policy.json` up to date.
2. If a commit is **blocked**, the hook prints *exactly why* (🔒 locked, 👤 restricted, 🛑 delete, 🧊 freeze) and how to fix.
3. Docs (`.md`, `.txt`, `.csv`) are globally allowed unless you try to **delete/rename** protected files.
4. If you’re on the **allowed list** and you’ve been given a **bypass token**, you may use:

   ```bash
   DV_HOOK_BYPASS="<token>" DV_HOOK_BYPASS_REASON="<why>" git commit -m "..."
   ```
5. When risky areas change (e.g., `tb/**`), the hook can run **Smoke Checks** (fast `compile/elab` or `sw` header) before the commit finishes.

---

## Repository Layout (recap)

```
├── config/
│   └── hook_policy.json      # the only file admins edit to control behavior
├── .git/hooks/pre-commit     # the Python hook (installed here)
├── script/
│   ├── runTest, runTest.sh   # dummy runner used by Smoke Gate
│   ├── cdtc                  # tiny stub used by Smoke Gate
│   ├── dvshare, dvshare.py   # ephemeral share utility
│   └── test_hook.sh          # regression suite for the hook
└── simlog/
    ├── precommit_access.log  # decision audit trail
    └── smoke.log             # smoke gate output
```

---

## Installation

The hook is already located at `.git/hooks/pre-commit`. If you reclone or need to reinstall:

```bash
cp script/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

Ensure the runner stubs are executable (used by Smoke Gate):

```bash
chmod +x script/runTest script/runTest.sh script/cdtc
```

If you use `setup.csh`, make sure it puts `script/` on PATH (already configured in this repo). If not, add:

```csh
setenv TB_SCRIPT "$PWD/script"
if ( "$path" !~ *"$TB_SCRIPT"* ) set path = ( "$TB_SCRIPT" $path )
```

---

## Policy File (Single Source of Truth)

**Location:** `config/hook_policy.json`
**Who can edit:** only users listed in `config_admins`
**Enforcement:** policy edits by non‑admins are **blocked** and **never bypassable**.

### Minimal, complete example

```json
{
  "version": 1,
  "config_admins": ["Ajinkya"],
  "options": {
    "case_sensitive_users": true,
    "expand_env": true,
    "treat_patterns_as_absolute_when_starting_with_slash": true,
    "log_path": "simlog/precommit_access.log",
    "ui": { "color": true, "show_hints": true, "show_admins": true, "show_allowed_users": true, "max_files_per_group": 20 }
  },
  "global_bypass": { "allowed_extensions": [".md", ".txt", ".csv"] },

  "locked": [ { "path": "design/**" } ],

  "restricted": [
    { "path": "sw/**", "allowed_users": ["Vishal", "Ashraf"], "allowed_extensions": [".md", ".txt"] }
  ],

  "deletion_protected": ["design/**", "sw/**"],

  "emergency_bypass": {
    "enabled": true,
    "allowed_users": ["Ajinkya", "Vishal"],
    "require_reason": true,
    "tokens": [
      { "label": "OpsWindow", "sha256": "<SHA256>", "reusable": false, "expires": "2025-12-31 00:00:00" }
    ]
  },

  "freeze": {
    "enabled": false,
    "branch": "main",
    "windows": [ { "paths": ["tb/**"] } ],
    "allowed_users": ["Ajinkya K", "Vishal"],
    "require_reason": true,
    "tokens": [
      { "label": "Freeze-Sep", "sha256": "<SHA256_OF_FREEZE_TOKEN>", "reusable": false, "expires": "2025-09-09 00:00:00" }
    ],
    "priority": "override_all"
  },

  "smoke_test": {
    "enabled": true,
    "mode": "warn",
    "timeout_sec": 1200,
    "shell": "csh",
    "setup_csh": "setup.csh",
    "paths_compile_elab": ["tb/**", "sim/**", "tb/agents/**", "tb/env/**"],
    "cmds_compile_elab": [
      ["cdtc", "cpuss__sanity"],
      ["runTest", "-do", "compile"],
      ["runTest", "-do", "elab"]
    ],
    "sw_header_globs": ["sw/**/*.h", "sw/**/*.hpp", "sw/**/*.hh"],
    "cmds_sw": [
      ["cdtc", "cpuss__Sanity"],
      ["runTest", "-do", "sw"]
    ]
  }
}
```

### Field‑by‑field reference

#### `options`

* `case_sensitive_users` (bool): compare `user.name` case‑sensitively.
* `expand_env` (bool): expand `$VARS` in patterns.
* `treat_patterns_as_absolute_when_starting_with_slash` (bool): if a pattern starts with `/`, treat it as an absolute path anchored at the filesystem; otherwise it’s resolved against the repo root.
* `log_path` (string): audit log file; created if missing.
* `ui` (object): presentation controls

  * `color` (true/false/null): force color on/off; `null` = auto.
  * `show_hints`, `show_admins`, `show_allowed_users` (bool): toggle details.
  * `max_files_per_group` (int): truncate long file lists in the error box.

#### `global_bypass`

* `allowed_extensions` (list): doc‑ish extensions allowed **everywhere** for adds/modifies (not for deletes/renames). Example: `.md`, `.txt`, `.csv`.

#### `locked`

* Array of entries; each entry:

  * `path` or `files`: glob(s) that are **hard‑deny** for everyone.
  * `allowed_extensions` (optional): per‑entry extension exceptions (e.g., allow `.md` inside an otherwise locked area).

#### `restricted`

* Array of entries; each entry:

  * `path` or `files`: glob(s) that are **allowed only** to `allowed_users`.
  * `allowed_users` (list): exact names from `git config user.name` (honors `case_sensitive_users`).
  * `allowed_extensions` (optional): e.g., allow `.md` for everyone in `sw/**`.

#### `deletion_protected`

* List of globs where **deletes/renames** are **admin‑only** (users in `config_admins`).

> **Rename note:** a rename counts as **delete** of the old path + add of the new path. Old path is validated against `deletion_protected`.

#### `emergency_bypass`

* `enabled` (bool): master toggle.
* `allowed_users` (list): users who may bypass **non‑freeze** violations.
* `require_reason` (bool): require `DV_HOOK_BYPASS_REASON`.
* `tokens` (list): each token entry has:

  * `label` (string), `sha256` (hex), `reusable` (bool), `expires` (`YYYY‑MM‑DD HH:MM:SS`).

**Usage:**

```bash
DV_HOOK_BYPASS="<plaintext_token>" DV_HOOK_BYPASS_REASON="hotfix" git commit -m "..."
```

* **One‑time** tokens are recorded in `.git/dv-hooks/bypass_ledger.json` and can’t be reused.
* **Reusable** tokens may be used multiple times until `expires`.

**Hashing a token** (generate the `sha256`):

```bash
# Linux/macOS
printf '%s' 'MY-T0KEN' | shasum -a 256 | awk '{print $1}'
# Windows Git Bash
printf '%s' 'MY-T0KEN' | sha256sum | awk '{print $1}'
# Python (any OS)
python - <<'PY'
import hashlib;print(hashlib.sha256(b'MY-T0KEN').hexdigest())
PY
```

#### `freeze`

* `enabled` (bool): simplest **toggle freeze** (no dates). When true, all matching paths are frozen.
* `branch` (string): typically `main`.
* `windows` (array): optional **local‑time** windows with fields:

  * `from` / `to` ("YYYY‑MM‑DD HH\:MM\:SS"), **omit** timezone offsets.
  * `paths` (globs): defaults to `"**"` when not given.
* `allowed_users` (list): users allowed to bypass freeze (with a **freeze token** below).
* `require_reason` (bool): require `DV_HOOK_BYPASS_REASON`.
* `tokens` (list): **freeze‑scoped** tokens (separate from `emergency_bypass`). Same fields as above.
* `priority` ("override\_all"): freeze is checked **before** other rules.

**Freeze bypass:**

```bash
DV_HOOK_BYPASS="<freeze_token>" DV_HOOK_BYPASS_REASON="release fix" git commit -m "..."
```

#### `smoke_test`

* `enabled` (bool): master toggle.
* `mode` ("warn" | "block"): warn allows commit, block prevents commit on failure.
* `timeout_sec` (int): per‑command timeout.
* `shell` ("csh" | "sh"): `csh` recommended when you must `source setup.csh`.
* `setup_csh` (string): path to your setup script (e.g., `setup.csh`).
* `paths_compile_elab` (globs): touching these triggers TB **compile + elab** sequence.
* `cmds_compile_elab` (list of argv): default is `cdtc cpuss__sanity`, `runTest -do compile`, `runTest -do elab`.
* `sw_header_globs` (globs): header patterns that trigger SW step (`.h`, `.hpp`, `.hh`).
* `cmds_sw` (list of argv): default `cdtc cpuss__Sanity`, `runTest -do sw`.

**Logs:** `simlog/smoke.log`
**Stubs provided:** `script/cdtc`, `script/runTest`, `script/runTest.sh` (simulate via `RUNTEST_FAIL`, `CDTC_FAIL`).

---

## Decision Flow (What the Hook Does)

1. Read staged changes with rename detection.
2. **Block** if a non‑admin staged `config/hook_policy.json` (never bypassable).
3. If `freeze.enabled` and window active → mark matching files as **BLOCK (freeze)**.
4. If file is a **delete/rename** under `deletion_protected` → **BLOCK (admin‑only delete)**.
5. If **global bypass extension** (e.g., `.md/.txt/.csv`) and not a delete → ALLOW.
6. If path matches **locked** → **BLOCK** (unless per‑entry ext exception).
7. If path matches **restricted** → ALLOW only for `allowed_users` (or per‑entry ext exception).
8. Write a decision line for each file to `simlog/precommit_access.log`.
9. Try **freeze bypass** first (with freeze token); then **emergency bypass** for anything else.
10. If no violations remain and `smoke_test.enabled`, run **Smoke Gate** for triggered areas.
11. If still clean → ✅ success; otherwise show a grouped error box with fixes/hints.

---

## User Interface & Env Toggles

* The hook prints tidy **Unicode boxes** with color and emoji (auto width; emoji‑safe).
* Turn off color with `NO_COLOR=1`.
* Minimal output: `DV_HOOK_MUTE=1`.
* Hide hints: `DV_HOOK_TIPS=0`.
* Debug per‑file decisions: `DV_HOOK_SHOW_DECISIONS=1`.
* Force a wider box: `DV_HOOK_BOX_MIN=72`.

Example bypass (with reason):

```bash
DV_HOOK_BYPASS="SOS-REUSE" DV_HOOK_BYPASS_REASON="hotfix" git commit -m "..."
```

---

## Ephemeral Share (dvshare)

Share a selection of **local, uncommitted files** with a teammate *without committing* anything. Shares live under `.git/dv-share/<ID>` and **auto‑expire**. The pre‑commit hook **auto‑prunes** expired shares.

### Commands

```
script/dvshare create  --ttl 2h [--id LABEL] [--note TEXT] <files...>
script/dvshare pack    <ID> [--out simlog]
script/dvshare list
script/dvshare info    <ID>
script/dvshare remove  <ID>
script/dvshare prune
script/dvshare apply   <zip|folder> [--mode patch|copy]
```

* `create` snapshots raw files under `.git/dv-share/<ID>/files/` and emits a `share.patch` against `HEAD`.
* `pack` makes a zip (`simlog/dvshare_<ID>.zip`) to send.
* `apply` (co‑worker): tries `git apply --3way --reject` (patch mode) or copies raw files (`--mode copy`, backups to `*.bak`).
* `prune` removes expired shares; the hook calls it automatically on each commit.

**Examples**

```bash
# Share 10 files for 2 hours
script/dvshare create --ttl 2h tb/sample_tb.sv tb/env/apb_env.sv sw/util.h sim/simInput.tcl ...
script/dvshare pack <ID_SHOWN>

# Coworker in their repo
script/dvshare apply ~/Downloads/dvshare_<ID>.zip --mode patch
# or
script/dvshare apply ~/Downloads/dvshare_<ID>.zip --mode copy
```

---

## Test Suite

A full regression of the hook logic is available:

```bash
bash script/test_hook.sh               # uses .git/hooks/pre-commit by default
bash script/test_hook.sh --hook /path/to/pre-commit
```

The suite seeds a sandbox repo, installs the hook, commits the policy as admin, and exercises:

* global bypass docs; locked `design/**`; restricted `sw/**` (per‑path `.md` allowed)
* deletion protection (admin‑only); emergency tokens (one‑time + reusable)
* policy protection (never bypassable); freeze toggle & tokens
* rename edge cases; case sensitivity flip

**Tip:** Windows Git Bash users may want `git config core.autocrlf false` inside the sandbox to silence CRLF warnings.

---

## Troubleshooting

**“Policy file not found”**
Create `config/hook_policy.json` and commit it **as an admin**.

**“Python was not found” (Windows)**
Install Python and ensure `python` or `py` is on PATH. As a stopgap, use `py script/dvshare.py ...` or edit `script/dvshare` to call `py`.

**Token doesn’t work**

* Ensure your user is listed under the corresponding `allowed_users` (emergency/freeze).
* Ensure `DV_HOOK_BYPASS_REASON` is set when `require_reason` is true.
* For one‑time tokens, check `.git/dv-hooks/bypass_ledger.json` — once used, they can’t be reused.
* Check `expires` hasn’t passed.

**Freeze windows confusing**
Prefer the simple toggle (`"enabled": true`) during release. If using date windows, provide **local‑time** strings without timezone offsets.

**CRLF issues**
On Windows, ensure scripts have LF endings. You can run `dos2unix` on hook/scripts if needed.

**Hook not firing**
Confirm the file is executable and located at `.git/hooks/pre-commit`. Try `bash -x .git/hooks/pre-commit` after staging files.

---

## Governance & Best Practices

* Keep `config/hook_policy.json` under **code review**; only `config_admins` may edit.
* Start with permissive settings (`smoke_test.mode = "warn"`), then tighten to `"block"` once green.
* Use **per‑path extension exceptions** sparingly; prefer `global_bypass` for docs/logs only.
* Keep **tokens short‑lived** and **distribution controlled**; rotate after a release.
* Check `simlog/precommit_access.log` during audits; it records every decision.

---

## Changelog

* **2025‑08‑29 — v1.3**
  Added **Ephemeral Share (dvshare)** tool and automatic pruning via the pre‑commit hook; expanded Admin Guide.

* **2025‑08‑29 — v1.2**
  Added **Smoke Test Gate** (TB compile+elab & SW header checks), JSON‑configurable with `warn|block` modes; updated decision flow.

* **2025‑08‑29 — v1.1**
  Added **Freeze windows** (toggle or local‑time windows), priority override, and separate tokens.

* **2025‑08‑29 — v1.0**
  Core policy: locked/restricted areas, global/per‑path extension exceptions, deletion protection (admin‑only), admin‑only policy edits, emergency bypass with tokens, logging & ledger, friendly UI.
