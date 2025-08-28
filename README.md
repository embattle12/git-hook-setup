# DV Git Hook — Access Policy (Pre‑Commit)

A pure‑Python **pre‑commit** hook that enforces repository access policy from a single, admin‑owned JSON file. It supports hard locks, restricted areas, global/per‑path extension exceptions, admin‑only deletes, protected policy edits, and an auditable **emergency bypass** with tokens.

> Keep this README updated as we ship new features.

---

## What’s included (v1)

* **Locked paths**: hard‑deny any change under specified patterns (e.g., `design/**`).
* **Restricted paths**: only whitelisted `allowed_users` may change (e.g., `sw/**`).
* **Global extension bypass**: extensions (e.g., `.md`, `.txt`, `.csv`) are always allowed anywhere (except deletes/renames of protected paths).
* **Per‑path extension exceptions**: each locked/restricted entry can allow certain extensions.
* **Admin‑only deletes/renames**: deletions or renames originating from **deletion‑protected** paths are allowed **only for admins**.
* **Admin‑only policy edits**: only `config_admins` can modify `config/hook_policy.json`. This rule is **not bypassable**.
* **Emergency bypass** (optional, auditable): `DV_HOOK_BYPASS` + `DV_HOOK_BYPASS_REASON` for users permitted by policy and holding a valid token (SHA‑256 stored in policy). Supports **reusable** or **one‑time** tokens and optional expiry. Usage is logged to `simlog/precommit_access.log` and `.git/dv-hooks/bypass_ledger.json`.
* **Logging**: All decisions appended to `simlog/precommit_access.log`.
* **Freeze windows**: toggle-based (on/off) or local-time date windows for selected paths (e.g., `tb/**`). Freeze overrides all other allows; during freeze only `allowed_users` can commit with a valid token (`DV_HOOK_BYPASS` + `DV_HOOK_BYPASS_REASON`).
* **Smoke test gate**: auto-runs fast checks when risky areas change. TB changes trigger `cdtc cpuss__sanity`, `runTest -do compile`, `runTest -do elab`. SW header changes trigger `cdtc cpuss__Sanity`, `runTest -do sw`. Fails can be `warn` or `block`, output saved to `simlog/smoke.log`.

---

## Repo layout (relevant parts)

```
<repo-root>/
├── .git/
│   └── hooks/
│       └── pre-commit        # Python hook (executable)
├── config/
│   └── hook_policy.json      # Admin-owned policy (version-controlled)
├── simlog/                   # Hook logs (gitignored)
└── script/                   # (optional) helper tools
```

> Place this README at repo root as `README.md`.

---

## Installation

1. **Python**: Ensure `python` is on PATH (Windows/Linux/macOS). On Windows, if only `python.exe` exists, we already use `#!/usr/bin/env python`.

2. **Install the hook**:

   * Save the Python file as `.git/hooks/pre-commit`.
   * Make it executable on Unix: `chmod +x .git/hooks/pre-commit`.

3. **Create policy**: Add `config/hook_policy.json` (see examples below) and commit as a `config_admins` user.

4. **Ignore logs**: Add to `.gitignore`:

   ```
   simlog/
   ```

5. **Test**: Try changing a locked file (should block), then a normal file (should pass).

---

## Policy file (schema & examples)

**Location:** `config/hook_policy.json` (version‑controlled). Only `config_admins` may modify it. All behavior is driven from here.

\$1{
"version": 1,
"config\_admins": \["Ajinkya"],
"options": {
"case\_sensitive\_users": true,
"expand\_env": true,
"treat\_patterns\_as\_absolute\_when\_starting\_with\_slash": true,
"log\_path": "simlog/precommit\_access.log",
"ui": { "color": true, "show\_hints": true, "show\_admins": true, "show\_allowed\_users": true, "max\_files\_per\_group": 20 }
},
"global\_bypass": { "allowed\_extensions": \[".md", ".txt", ".csv"] },
"locked": \[ { "path": "design/**" } ],
"restricted": \[
{ "path": "sw/**", "allowed\_users": \["Vishal", "Ashraf"], "allowed\_extensions": \[".md", ".txt"] }
],
"deletion\_protected": \["design/**", "sw/**"],
"emergency\_bypass": {
"enabled": true,
"allowed\_users": \["Ajinkya", "Vishal"],
"require\_reason": true,
"tokens": \[ { "label": "OpsWindow", "sha256": "<SHA256>", "reusable": false, "expires": "2025-12-31 00:00:00" } ]
},
"freeze": {
"enabled": true,
"branch": "main",
"windows": \[ { "paths": \["tb/**"] } ],
"allowed\_users": \["Ajinkya K", "Vishal"],
"require\_reason": true,
"tokens": \[ { "label": "Freeze-Sep", "sha256": "\<SHA256\_OF\_FREEZE\_TOKEN>", "reusable": false, "expires": "2025-09-09 00:00:00" } ],
"priority": "override\_all"
},
"smoke\_test": {
"enabled": true,
"mode": "warn",
"timeout\_sec": 1200,
"shell": "csh",
"setup\_csh": "setup.csh",
"paths\_compile\_elab": \["tb/**", "sim/**", "tb/agents/**", "tb/env/**"],
"cmds\_compile\_elab": \[
\["cdtc", "cpuss\_\_sanity"],
\["runTest", "-do", "compile"],
\["runTest", "-do", "elab"]
],
"sw\_header\_globs": \["sw/**/*.h", "sw/\*\*/*.hpp", "sw/\*\*/\*.hh"],
"cmds\_sw": \[
\["cdtc", "cpuss\_\_Sanity"],
\["runTest", "-do", "sw"]
]
}
}\$3

### Field reference

* **version** *(int)*: Schema version for future migrations.
* **config\_admins** *(string\[])*: Users allowed to change `hook_policy.json`.
* **options** *(object)*:

  * **case\_sensitive\_users** *(bool)*: Compare user names case‑sensitively.
  * **expand\_env** *(bool)*: Expand env vars like `$RF_TOP` in patterns.
  * **treat\_patterns\_as\_absolute\_when\_starting\_with\_slash** *(bool)*: If a pattern begins with `/`, treat it as filesystem‑absolute; otherwise repo‑relative.
  * **log\_path** *(string)*: Where to append human log.
* **global\_bypass** *(object)*:

  * **allowed\_extensions** *(string\[])*: Extensions (with or without leading dot) always allowed anywhere (except deletes/renames from protected paths).
* **locked** *(array of objects)*: Areas where **nobody** can change files.

  * **path** or **files** *(string or string\[])*: Glob pattern(s) (supports `*`, `?`, `**`). Repo‑relative unless pattern starts with `/`.
  * **allowed\_extensions** *(string\[]; optional)*: Per‑entry exception list (e.g., allow `.md`).
* **restricted** *(array of objects)*: Areas where only certain users can change files.

  * **path**/**files**: Same as above.
  * **allowed\_users** *(string\[])*: Users who may change.
  * **allowed\_extensions** *(string\[]; optional)*: Per‑entry exceptions for everyone.
* **deletion\_protected** *(string\[])*: Patterns where **deletes/renames** (of the source path) are **admin‑only**.
* **emergency\_bypass** *(object; optional)*:

  * **enabled** *(bool)*: Turn the feature on/off.
  * **allowed\_users** *(string\[])*: Only these users may bypass.
  * **require\_reason** *(bool)*: Require `DV_HOOK_BYPASS_REASON`.
  * **tokens** *(array)*: Whitelisted tokens (hashed):

    * **label** *(string)*: Human label for audits.
    * **sha256** *(string)*: SHA‑256 hex of the secret token.
    * **reusable** *(bool)*: `true` = can be used multiple times; `false` = one‑time.
    * **expires** *(string; optional)*: ISO date/time after which token is invalid.

> **Precedence:** Locked → Restricted → Default allow. Global extension bypass applies before those (except for deletions/renames from protected paths). Policy edits are enforced first and are **not bypassable**.

---

## Pattern syntax

* Use `**` for recursive matches (e.g., `design/**`).
* Use repo‑relative paths by default; prefix `/` to make a pattern absolute to the filesystem root (rarely needed).
* Env vars such as `$RF_TOP` expand if `options.expand_env=true`.

---

## How decisions are made

1. Read staged changes via `git diff --cached --name-status -M` (detects renames/moves).
2. If `config/hook_policy.json` is staged by a non‑admin → **block** (never bypassable).
3. **Freeze check** (if `freeze.enabled=true`): if current time is inside any active window and path matches a frozen pattern, mark as **BLOCK (freeze active)**. This step runs **before** all other checks when `priority=override_all`.
4. **Deletion protection**: deletes/renames from `deletion_protected` paths are **admin‑only**.
5. **Global extension bypass** (non‑deletes): if extension matches global allowlist (e.g., `.md/.txt/.csv`) → allow.
6. **Locked** entries: block unless per‑entry `allowed_extensions` permits the file type.
7. **Restricted** entries: allow only if author ∈ `allowed_users` or per‑entry extension exception matches.
8. Log every decision to `simlog/precommit_access.log`.
9. **Bypass order**: first attempt **Freeze bypass**, then **Emergency bypass** (if enabled).
10. **Smoke Test Gate** (if enabled and no violations remain):

    * If TB/sim risky paths changed → run `cdtc cpuss__sanity`, `runTest -do compile`, `runTest -do elab`.
    * If C/C++ headers under `sw/**` changed → run `cdtc cpuss__Sanity`, `runTest -do sw`.
    * Results recorded in `simlog/smoke.log`; failures either **warn** or **block** per `mode`.
11. If violations remain → fail the commit with a clear list of offending paths.

---

## Emergency bypass — admin & developer guide

### Admin: create/rotate a token

1. Pick a secret token, e.g. `SOS-1234`.
2. Compute SHA‑256 and paste into policy:

   * **Python**: `python - <<'PY'\nimport hashlib; print(hashlib.sha256(b"SOS-1234").hexdigest())\nPY`
   * **Git Bash/macOS**: `printf 'SOS-1234' | sha256sum | awk '{print $1}'`
3. Add to `emergency_bypass.tokens` with `label`, `reusable` (true/false), and optional `expires`.
4. Commit the policy as a `config_admins` user.
5. Share the **plaintext token** privately with allowed users.

### Developer: use a token

* **Bash/Git Bash/macOS**

  ```bash
  DV_HOOK_BYPASS="SOS-1234" \
  DV_HOOK_BYPASS_REASON="Urgent hotfix during freeze" \
  git commit -m "hotfix: restricted area change"
  ```
* **Windows PowerShell**

  ```powershell
  $env:DV_HOOK_BYPASS = "SOS-1234"
  $env:DV_HOOK_BYPASS_REASON = "Urgent hotfix during freeze"
  git commit -m "hotfix: restricted area change"
  ```

**One‑time tokens** (`reusable:false`) are automatically invalidated after first use; **reusable tokens** can be used multiple times until expiry or removal from policy.

**Auditing**: Every bypass is appended to `simlog/precommit_access.log` and recorded in `.git/dv-hooks/bypass_ledger.json` with user, label, reason, violations, timestamp.

---

## Freeze windows (release mode)

Two supported modes (no timezone complexity):

### Option A — Toggle (simplest)

Freeze is active whenever `enabled: true`. No dates required.

```json
"freeze": {
  "enabled": true,
  "branch": "main",
  "windows": [ { "paths": ["tb/**"] } ],
  "allowed_users": ["Ajinkya K", "Vishal"],
  "require_reason": true,
  "tokens": [
    { "label": "Freeze-Sep", "sha256": "<SHA256_OF_FREEZE_TOKEN>", "reusable": false, "expires": "2025-09-09 00:00:00" }
  ],
  "priority": "override_all"
}
```

### Option B — Local-time windows (no offsets)

Provide `from`/`to` in local machine time (e.g., `YYYY-MM-DD HH:MM:SS`). **Do not** include `+05:30` or `Z`.

```json
"freeze": {
  "enabled": true,
  "branch": "main",
  "windows": [
    { "from": "2025-08-29 00:00:00", "to": "2025-08-31 23:59:59", "paths": ["tb/**"] }
  ],
  "allowed_users": ["Ajinkya K", "Vishal"],
  "require_reason": true,
  "tokens": [
    { "label": "Freeze-Sep", "sha256": "<SHA256_OF_FREEZE_TOKEN>", "reusable": false, "expires": "2025-09-09 00:00:00" }
  ],
  "priority": "override_all"
}
```

**Behavior**: During freeze, all changes under frozen paths are blocked. Users in `allowed_users` can commit by setting `DV_HOOK_BYPASS` (plaintext token) and `DV_HOOK_BYPASS_REASON`.

**Notes**:

* Prefer **Option A** for reliability across machines.
* For Option B, make sure teammates agree on a common local timezone or pre‑convert the window.
* Freeze tokens are **separate** from `emergency_bypass.tokens`. The hook first resolves **Freeze bypass**, then **Emergency bypass**.

---

## Smoke Test Gate

**What it does:** When risky areas change, the hook runs quick checks before the commit finalizes.

* **TB / sim changes** → run in order: `cdtc cpuss__sanity`, `runTest -do compile`, `runTest -do elab`.
* **SW header changes** (`sw/**/*.h`, `sw/**/*.hpp`, `sw/**/*.hh`) → run: `cdtc cpuss__Sanity`, `runTest -do sw`.

**Config (in `smoke_test`):**

* `enabled` (`true|false`): turn on/off.
* `mode` (`"warn"|"block"`): whether failures block the commit.
* `timeout_sec` (int): per-command timeout.
* `shell` (`"csh"|"sh"`): use `csh` when your environment needs `source setup.csh`.
* `setup_csh` (string): path to setup (e.g., `setup.csh`).
* `paths_compile_elab` (globs): which paths trigger TB compile+elab checks.
* `cmds_compile_elab` (array of argv arrays): commands to run for TB path changes.
* `sw_header_globs` (globs): header patterns to trigger SW step.
* `cmds_sw` (array): commands to run when headers are touched.

**Logs:** Output is saved to `simlog/smoke.log`.

**Tips:**

* Start with `mode: "warn"`; flip to `"block"` once green and stable.
* Make sure `cdtc` and `runTest` are on PATH (or available after `source setup.csh`).

---

## Troubleshooting

* **“Python was not found …” (Windows):** Install Python and ensure `python` is on PATH. Our shebang uses `env python` to work with `python.exe`.
* **Hook didn’t run:** Ensure file is at `.git/hooks/pre-commit` and is executable (`chmod +x`).
* **Blocked editing policy as non‑admin:** Expected — this is never bypassable.
* **Bypass failed:** Check that you’re in `emergency_bypass.allowed_users`, token hasn’t expired, `DV_HOOK_BYPASS_REASON` is set (if required), and for one‑time tokens that it hasn’t been used already.
* **Case sensitivity of users:** Controlled by `options.case_sensitive_users`.
* **Logs not in Git:** Add `simlog/` to `.gitignore` (recommended).

---

## Roadmap (future options)

* Forbidden extensions & LFS enforcement
* Size limits per extension (e.g., block `.vcd` > N MB)
* Linters/formatters per extension (Verible, clang‑format, black)
* Dry‑run/test gates (e.g., call `script/runTest.sh` when `tb/tests/**` changes)
* Branch‑aware policies
* Commit‑message policies (tickets, sign‑off, GPG)

---

## Changelog

* **2025‑08‑29** — v1.2: Added **Smoke Test Gate** (TB compile+elab & SW header checks), JSON-configurable with `warn|block` modes; updated examples and decision flow.
* **2025‑08‑29** — v1.1: Added **Freeze windows (release mode)** with two modes: toggle and local‑time windows. Updated policy examples, decision order, and troubleshooting.
* **2025‑08‑29** — v1 initial: locked/restricted areas, global/per‑path extension exceptions, deletion protection (admin‑only), admin‑only policy edits, emergency bypass with tokens, full logging & ledger.
