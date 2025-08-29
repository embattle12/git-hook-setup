#!/usr/bin/env bash
# Thorough test suite for DV pre-commit access-policy hook
set -euo pipefail

# -------------------- helpers --------------------
say()   { printf "\n\033[36m%s\033[0m\n" "$*"; }
pass()  { printf "  \033[32m✅ PASS\033[0m %s\n" "$*"; }
fail()  { printf "  \033[31m❌ FAIL\033[0m %s\n" "$*"; FAILED=$((FAILED+1)); }
die()   { printf "\033[31mFATAL:\033[0m %s\n" "$*"; exit 1; }

hash256() {
  local s="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$s" | sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$s" | shasum -a 256 | awk '{print $1}'
  elif command -v python >/dev/null 2>&1; then
    python - <<PY
import hashlib, sys
print(hashlib.sha256(sys.argv[1].encode()).hexdigest())
PY
  else
    die "Need sha256sum/shasum/python for token hashing."
  fi
}

unset_bypass() {
  unset DV_HOOK_BYPASS || true
  unset DV_HOOK_BYPASS_REASON || true
}

set_user() {
  local name="$1"
  git config user.name "$name"
  git config user.email "$(echo "$name" | tr ' ' .)@example.com"
}

git_try_commit() {
  local msg="$1"
  git add -A >/dev/null
  set +e
  git commit -m "$msg" >/dev/null 2>&1
  local rc=$?
  set -e
  return $rc
}

expect_block() {
  local desc="$1"
  if git_try_commit "$desc"; then
    fail "$desc (expected BLOCK)"
  else
    pass "$desc (blocked)"
    git reset --hard >/dev/null
  fi
}

expect_pass() {
  local desc="$1"
  if git_try_commit "$desc"; then
    pass "$desc"
  else
    fail "$desc (expected PASS)"
    git reset --hard >/dev/null
  fi
}

write_policy() {
  # Args:
  #  $1 LOCKED json
  #  $2 RESTRICTED json
  #  $3 DELETION json
  #  $4 FREEZE json
  #  $5 EMERGENCY json
  mkdir -p config
  cat > config/hook_policy.json <<JSON
{
  "version": 1,
  "config_admins": ["$ADMIN_USER"],
  "options": {
    "case_sensitive_users": true,
    "expand_env": true,
    "treat_patterns_as_absolute_when_starting_with_slash": true,
    "log_path": "simlog/precommit_access.log"
  },
  "global_bypass": { "allowed_extensions": [".md", ".txt", ".csv"] },
  "locked": $1,
  "restricted": $2,
  "deletion_protected": $3,
  "emergency_bypass": $5,
  "freeze": $4
}
JSON
}

detect_hook_src() {
  local given="$1"
  if [[ -n "${given:-}" ]]; then printf '%s' "$given"; return; fi
  if [[ -n "${HOOK_SRC:-}" ]]; then printf '%s' "$HOOK_SRC"; return; fi
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    local root; root="$(git rev-parse --show-toplevel)"
    [[ -f "$root/.git/hooks/pre-commit" ]] && printf '%s' "$root/.git/hooks/pre-commit" && return
  fi
  printf ''
}

usage() {
  cat <<USAGE
Usage: $0 [--hook /path/to/pre-commit]
If --hook is omitted, uses \$HOOK_SRC or .git/hooks/pre-commit of the current repo.
USAGE
}

# -------------------- args --------------------
HOOK_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --hook) HOOK_ARG="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) die "Unknown arg: $1";;
  esac
done

FAILED=0

HOOK_SRC="$(detect_hook_src "$HOOK_ARG")"
[[ -n "$HOOK_SRC" ]] || die "Could not locate hook. Pass --hook /path/to/pre-commit or set HOOK_SRC."
[[ -f "$HOOK_SRC" ]] || die "Hook not found at: $HOOK_SRC"

# -------------------- identities used --------------------
ADMIN_USER="Ajinkya"
RESTRICT_ALLOWED="Vishal"
RESTRICT_DENIED="Alice"
FREEZE_ALLOWED="Ajinkya K"
EMERGENCY_ALLOWED="Vishal"

# -------------------- sandbox --------------------
SANDBOX="$(mktemp -d -t dvhooktest.XXXXXX)"
say "Creating sandbox repo at: $SANDBOX"
cd "$SANDBOX"
git init >/dev/null
git config init.defaultBranch main
git checkout -b main >/dev/null

# Silence CRLF warnings (Windows Git) inside the sandbox only
git config core.autocrlf false
git config core.safecrlf false

# Create tree & seed files
mkdir -p design doc sw tb simlog
echo "simlog/" > .gitignore
echo "// rtl"        > design/apb_sram.v
echo "# doc"         > doc/readme.md
echo "// sw secret"  > sw/setup.cfg
echo "// testbench"  > tb/sample_tb.sv

# Initial seed commit WITHOUT the hook
set_user "$ADMIN_USER"
git add -A >/dev/null
git commit -m "seed repo" --no-verify >/dev/null

# Install hook AFTER the seed
mkdir -p .git/hooks
cp "$HOOK_SRC" .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

# Tokens
ONE_TIME_TOKEN="SOS-ONCE"
REUSE_TOKEN="SOS-REUSE"
EB_ONE_SHA="$(hash256 "$ONE_TIME_TOKEN")"
EB_REU_SHA="$(hash256 "$REUSE_TOKEN")"
FREEZE_TOKEN="FREEZE-ONCE"
FREEZE_SHA="$(hash256 "$FREEZE_TOKEN")"

LOCKED='[ { "path": "design/**" } ]'
RESTRICTED='[ { "path": "sw/**", "allowed_users": ["'"$RESTRICT_ALLOWED"'"], "allowed_extensions": [".md"] } ]'
DELETION='["design/**", "sw/**"]'
FREEZE='{
  "enabled": false,
  "branch": "main",
  "windows": [ { "paths": ["tb/**"] } ],
  "allowed_users": ["'"$FREEZE_ALLOWED"'", "'"$RESTRICT_ALLOWED"'"],
  "require_reason": true,
  "tokens": [ { "label": "Freeze-One", "sha256": "'"$FREEZE_SHA"'", "reusable": false, "expires": "2025-12-31 00:00:00" } ],
  "priority": "override_all"
}'
EMERGENCY='{
  "enabled": true,
  "allowed_users": ["'"$EMERGENCY_ALLOWED"'", "'"$ADMIN_USER"'"],
  "require_reason": true,
  "tokens": [
    { "label": "EB-Once", "sha256": "'"$EB_ONE_SHA"'", "reusable": false, "expires": "2025-12-31 00:00:00" },
    { "label": "EB-Reuse", "sha256": "'"$EB_REU_SHA"'", "reusable": true,  "expires": "2025-12-31 00:00:00" }
  ]
}'

# Commit policy as admin (hook active)
write_policy "$LOCKED" "$RESTRICTED" "$DELETION" "$FREEZE" "$EMERGENCY"
git add config/hook_policy.json >/dev/null
expect_pass "add policy (admin)"

# -------------------- tests --------------------
say "Global allow outside protected areas"
set_user "$RESTRICT_DENIED"
echo "note" >> doc/notes.md
git add doc/notes.md >/dev/null
expect_pass "docs (.md) allowed anywhere"

say "Locked area: design/**"
echo "// change" >> design/apb_sram.v
git add design/apb_sram.v >/dev/null
expect_block "modify under locked design/**"

say "Locked area + global .md allowed"
echo "# design doc" > design/README.md
git add design/README.md >/dev/null
expect_pass ".md allowed in locked area (global bypass)"

say "Restricted area: sw/**"
set_user "$RESTRICT_DENIED"
echo "# sw readme" > sw/README.md
git add sw/README.md >/dev/null
expect_pass "per-path .md allowed in restricted area"

echo "// secret change" >> sw/setup.cfg
git add sw/setup.cfg >/dev/null
expect_block "restricted change by non-allowed user"

set_user "$RESTRICT_ALLOWED"
echo "// allowed change" >> sw/setup.cfg
git add sw/setup.cfg >/dev/null
expect_pass "restricted change by allowed user"

say "Deletion protection (admin-only)"
# 1) Try to add a non-bypassed file in locked area -> should BLOCK
set_user "$RESTRICT_DENIED"
echo "// temp seed" > design/seed_for_delete.sv
git add design/seed_for_delete.sv >/dev/null
expect_block "add .sv under locked design/** (blocked)"

# 2) Recreate & commit same file using EMERGENCY reusable token -> PASS (to seed tracked file)
echo "// temp seed" > design/seed_for_delete.sv
git add design/seed_for_delete.sv >/dev/null
export DV_HOOK_BYPASS="$REUSE_TOKEN"; export DV_HOOK_BYPASS_REASON="seed tracked file in locked dir"
expect_pass "seed tracked file in locked dir via reusable bypass"
unset_bypass

# 3) Non-admin delete -> BLOCK (admin-only delete)
set_user "$RESTRICT_DENIED"
git rm -f design/seed_for_delete.sv >/dev/null
expect_block "delete in deletion_protected by non-admin"

# 4) Same delete with EMERGENCY one-time token -> PASS, then reuse should FAIL
echo "// temp seed" > design/seed_for_delete.sv
git add design/seed_for_delete.sv >/dev/null
export DV_HOOK_BYPASS="$REUSE_TOKEN"; export DV_HOOK_BYPASS_REASON="reseed for one-time delete"
expect_pass "reseed via reusable token"
unset_bypass

git rm -f design/seed_for_delete.sv >/dev/null
export DV_HOOK_BYPASS="$ONE_TIME_TOKEN"; export DV_HOOK_BYPASS_REASON="urgent delete"
expect_pass "delete with emergency one-time token"
unset_bypass

# Recreate then try one-time again -> should BLOCK (already used)
echo "// temp again" > design/seed_for_delete.sv
git add design/seed_for_delete.sv >/dev/null
export DV_HOOK_BYPASS="$REUSE_TOKEN"; export DV_HOOK_BYPASS_REASON="reseed after one-time"
expect_pass "reseed via reusable token (after one-time used)"
unset_bypass

git rm -f design/seed_for_delete.sv >/dev/null
export DV_HOOK_BYPASS="$ONE_TIME_TOKEN"; export DV_HOOK_BYPASS_REASON="reuse should fail"
expect_block "reuse same one-time token should fail"
unset_bypass

say "Policy protection (never bypassable) + admin modify"
# Non-admin attempt -> BLOCK (not bypassable)
set_user "$RESTRICT_DENIED"
# overwrite policy with same content (still counts as modifying the file)
write_policy "$LOCKED" "$RESTRICTED" "$DELETION" "$FREEZE" "$EMERGENCY"
git add config/hook_policy.json >/dev/null
export DV_HOOK_BYPASS="$REUSE_TOKEN"; export DV_HOOK_BYPASS_REASON="try bypass policy edit"
expect_block "non-admin modifying policy is blocked even with bypass"
unset_bypass

# Admin actually changes a value (append .log to global bypass) -> PASS
set_user "$ADMIN_USER"
sed -e 's/"allowed_extensions": \[".md", ".txt", ".csv"\]/"allowed_extensions": [".md", ".txt", ".csv", ".log"]/' \
  config/hook_policy.json > config/hook_policy.json.tmp && mv config/hook_policy.json.tmp config/hook_policy.json
git add config/hook_policy.json >/dev/null
expect_pass "admin can modify policy"

say "Freeze (toggle) overrides all"
# Turn freeze ON (tb/**)
set_user "$ADMIN_USER"
FREEZE_ON='{
  "enabled": true,
  "branch": "main",
  "windows": [ { "paths": ["tb/**"] } ],
  "allowed_users": ["'"$FREEZE_ALLOWED"'", "'"$RESTRICT_ALLOWED"'"],
  "require_reason": true,
  "tokens": [ { "label": "Freeze-One", "sha256": "'"$FREEZE_SHA"'", "reusable": false, "expires": "2025-12-31 00:00:00" } ],
  "priority": "override_all"
}'
write_policy "$LOCKED" "$RESTRICTED" "$DELETION" "$FREEZE_ON" "$EMERGENCY"
git add config/hook_policy.json >/dev/null
expect_pass "toggle freeze on (admin)"

# Non-allowed user: change in tb/** -> BLOCK
set_user "$RESTRICT_DENIED"
echo "// tb change" >> tb/sample_tb.sv
git add tb/sample_tb.sv >/dev/null
expect_block "freeze blocks tb/** for non-allowed user"

# Allowed user but no token -> BLOCK
set_user "$RESTRICT_ALLOWED"
echo "// tb change 2" >> tb/sample_tb.sv
git add tb/sample_tb.sv >/dev/null
expect_block "freeze requires token even for allowed user"

# Allowed user WITH token -> PASS
echo "// tb change 3" >> tb/sample_tb.sv
git add tb/sample_tb.sv >/dev/null
export DV_HOOK_BYPASS="$FREEZE_TOKEN"; export DV_HOOK_BYPASS_REASON="release hotfix"
expect_pass "freeze bypass with valid token (allowed user)"
unset_bypass

# Outside frozen paths still allowed during freeze
set_user "$RESTRICT_DENIED"
echo "x" >> doc/readme.md
git add doc/readme.md >/dev/null
expect_pass "outside frozen paths allowed during freeze"

say "Rename edge: rename out of protected dir (admin-only delete on old path)"
# Seed tracked file in locked dir via reusable bypass
set_user "$ADMIN_USER"
echo "// keep" > design/keep.sv
git add design/keep.sv >/dev/null
export DV_HOOK_BYPASS="$REUSE_TOKEN"; export DV_HOOK_BYPASS_REASON="seed for rename"
expect_pass "seed tracked file in locked dir via bypass"
unset_bypass

# Now as non-admin, rename -> should BLOCK (admin-only delete on old path)
set_user "$RESTRICT_DENIED"
git mv design/keep.sv moved_keep.sv >/dev/null || true
expect_block "rename from deletion_protected design/** should block non-admin"

git reset --hard >/dev/null

say "Case sensitivity toggle"
set_user "$ADMIN_USER"
# Flip case sensitivity off
sed -e 's/"case_sensitive_users": true/"case_sensitive_users": false/' \
  config/hook_policy.json > config/hook_policy.json.tmp && mv config/hook_policy.json.tmp config/hook_policy.json
git add config/hook_policy.json >/dev/null
expect_pass "admin flips case_sensitive_users=false"

set_user "vishal"
echo "// change" >> sw/setup.cfg
git add sw/setup.cfg >/dev/null
expect_pass "restricted allowlist matches regardless of case"

# -------------------- summary --------------------
say "Sandbox: $SANDBOX"
if [[ "$FAILED" -eq 0 ]]; then
  say "ALL TESTS PASSED 🎉"
else
  say "$FAILED TEST(S) FAILED. Check $SANDBOX/simlog/precommit_access.log and $SANDBOX/.git/dv-hooks/bypass_ledger.json"
fi
