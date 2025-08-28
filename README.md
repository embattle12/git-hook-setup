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

### Minimal working example (valid JSON)

```json
{
  "version": 1,
  "config_admins": ["Ajinkya"],
  "options": {
    "case_sensitive_users": true,
    "expand_env": true,
    "treat_patterns_as_absolute_when_starting_with_slash": true,
    "log_path": "simlog/precommit_access.log"
  },
  "global_bypass": { "allowed_extensions": [".md", ".txt", ".csv"] },
  "locked": [ { "path": "design/**" } ],
  "restricted": [
    {
      "path": "sw/**",
      "allowed_users": ["Vishal", "Ashraf"],
      "allowed_extensions": [".md", ".txt"]
    }
  ],
  "deletion_protected": ["design/**", "sw/**"],
  "emergency_bypass": {
    "enabled": true,
    "allowed_users": ["Ajinkya", "Vishal"],
    "require_reason": true,
    "tokens": [
      {
        "label": "OpsWindow",
        "sha256": "<SHA256_OF_SECRET_TOKEN>",
        "reusable": false,
        "expires": "2025-12-31"
      }
    ]
  }
}
```

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

1. The hook reads staged changes via `git diff --cached --name-status -M` (detects renames).
2. If `config/hook_policy.json` is staged by a non‑admin → **block** (not bypassable).
3. For each change:

   * **Global extension bypass** (non‑delete) → allow.
   * If a **delete/rename** originates in a **deletion\_protected** path → admin‑only (can be bypassed only via emergency token; policy edits remain non‑bypassable).
   * Match **locked** entries → block; unless per‑entry `allowed_extensions` allows the file type.
   * Else match **restricted** entries → allow only if author ∈ `allowed_users` or per‑entry extension exception matches.
   * Else → allow by default.
4. All decisions are logged to `simlog/precommit_access.log`.
5. If any blocks remain and **emergency bypass** is enabled and correctly provided, they may be converted to **BYPASS‑ALLOW** (audited) depending on token validity.
6. If blocks remain without valid bypass → commit fails.

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
* Linters/formatters per extension (e.g., Verible, clang‑format, black)
* Dry‑run/test gates (e.g., call `script/runTest.sh` when `tb/tests/**` changes)
* Branch‑aware policies and freeze windows
* Commit‑message policies (tickets, sign‑off, GPG)

---

## Changelog

* **2025‑08‑29** — v1 initial: locked/restricted areas, global/per‑path extension exceptions, deletion protection (admin‑only), admin‑only policy edits, emergency bypass with tokens, full logging & ledger.
