#!/usr/bin/env bash
set -euo pipefail

# --------------------------------------------------------------------------------
# dvshare End-to-End Test
# - Runs from ANY git repo (treated as the "sender" repo)
# - Creates uncommitted files, shares them via dvshare, clones a receiver repo,
#   applies the package, and validates content.
# --------------------------------------------------------------------------------

# ----------- CONFIG: adapt if your dvshare CLI name/flags differ ---------------
DVSHARE_CANDIDATES=("./script/dvshare" ".git/hooks/dvshare")
DVSHARE_SHARE_FLAGS=(share)     # subcommand: share
DVSHARE_APPLY_FLAGS=(apply)     # subcommand: apply
# dvshare share output must include lines like:  SESSION=<id>   PKGDIR=/abs/path
# dvshare apply should accept:  dvshare apply --from <dir>
# ------------------------------------------------------------------------------

fail() { echo "❌ $*" >&2; exit 1; }
info() { echo "👉 $*"; }
pass() { echo "✅ $*"; }

git rev-parse --show-toplevel >/dev/null 2>&1 || fail "Run this inside a git repo (sender)."

SENDER_ROOT="$(git rev-parse --show-toplevel)"
pushd "$SENDER_ROOT" >/dev/null

# Locate dvshare executable
DVSHARE=""
for c in "${DVSHARE_CANDIDATES[@]}"; do
  if [[ -x "$c" ]]; then DVSHARE="$c"; break; fi
done
[[ -n "$DVSHARE" ]] || fail "Could not find dvshare at: ${DVSHARE_CANDIDATES[*]}"

info "Using dvshare: $DVSHARE"
git status --porcelain >/dev/null || fail "git status failed in sender repo."

# Temp sandboxes
WORK_BASE="${TMPDIR:-/tmp}/dvshare_e2e.$(date +%s).$$"
RECEIVER_DIR="$WORK_BASE/receiver"
INBOX_DIR="$WORK_BASE/inbox"     # simulates how you'd transfer the pkg folder
mkdir -p "$WORK_BASE" "$INBOX_DIR"

# Make sure required dirs exist to drop test files into
mkdir -p design script tb

# Create test files (uncommitted, local changes)
S_FILE1="design/dvshare_locked.sv"
S_FILE2="script/dvshare_tool.sh"
S_FILE3="tb/dvshare_seq_lib_pkg.sv"

cat > "$S_FILE1" <<'EOF'
/* sender: locked area sample */
module dvshare_locked;
endmodule
EOF

cat > "$S_FILE2" <<'EOF'
#!/usr/bin/env bash
echo "sender: script tool"
EOF
chmod +x "$S_FILE2"

cat > "$S_FILE3" <<'EOF'
// sender: tb sample sequence lib pkg
package dvshare_seq_lib_pkg;
endpackage
EOF

# Keep original contents for verification
ORIG_SUMS="$WORK_BASE/orig_sums.txt"
sha1sum "$S_FILE1" "$S_FILE2" "$S_FILE3" > "$ORIG_SUMS"

info "Created local (uncommitted) files on sender:"
printf "  - %s\n" "$S_FILE1" "$S_FILE2" "$S_FILE3"

# Share via dvshare (TTL short so prune can be tested)
LABEL="E2E-TEST"
TTL="3m"

info "Creating dvshare package (label=$LABEL, ttl=$TTL) ..."
set +e
# shellcheck disable=SC2068
OUT="$("$DVSHARE" ${DVSHARE_SHARE_FLAGS[@]} --label "$LABEL" --ttl "$TTL" -- "$S_FILE1" "$S_FILE2" "$S_FILE3" 2>&1)"
RC=$?
set -e
echo "$OUT"

[[ $RC -eq 0 ]] || fail "dvshare share failed (rc=$RC). Output above."

# Extract SESSION and PKGDIR from output
SESSION="$(echo "$OUT" | awk -F= '/^SESSION=/{print $2}' | tail -1)"
PKGDIR="$(echo "$OUT" | awk -F= '/^PKGDIR=/{print $2}' | tail -1)"

[[ -n "$SESSION" && -n "$PKGDIR" && -d "$PKGDIR" ]] || fail "Could not parse SESSION/PKGDIR from dvshare share output."

pass "dvshare created session=$SESSION"
info "pkgdir: $PKGDIR"

# Simulate "sending" the package to receiver (copy folder)
RECV_PKG="$INBOX_DIR/$(basename "$PKGDIR")"
cp -a "$PKGDIR" "$RECV_PKG"

# Create a fresh receiver repo by cloning current repo
info "Cloning receiver repo ..."
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "Not inside a git repo."
ORIGIN_URL="$(git config --get remote.origin.url || true)"
if [[ -n "$ORIGIN_URL" ]]; then
  git clone --quiet "$ORIGIN_URL" "$RECEIVER_DIR" || fail "Clone failed from $ORIGIN_URL"
else
  # No remote? clone from local path
  git clone --quiet "$SENDER_ROOT" "$RECEIVER_DIR" || fail "Clone failed from local path"
fi

# Make sure receiver has dvshare too (assumes versioned in repo)
if [[ ! -x "$RECEIVER_DIR/script/dvshare" && ! -x "$RECEIVER_DIR/.git/hooks/dvshare" ]]; then
  fail "Receiver clone lacks dvshare executable (expected script/dvshare or .git/hooks/dvshare)."
fi

pushd "$RECEIVER_DIR" >/dev/null

# Resolve dvshare path in receiver
DVSHARE_RX=""
if [[ -x "./script/dvshare" ]]; then DVSHARE_RX="./script/dvshare"
elif [[ -x ".git/hooks/dvshare" ]]; then DVSHARE_RX=".git/hooks/dvshare"
fi

info "Applying dvshare package on receiver ..."
set +e
OUT_APPLY="$("$DVSHARE_RX" ${DVSHARE_APPLY_FLAGS[@]} --from "$RECV_PKG" 2>&1)"
RC_APPLY=$?
set -e
echo "$OUT_APPLY"
[[ $RC_APPLY -eq 0 ]] || fail "dvshare apply failed (rc=$RC_APPLY)."

# Verify receiver got the files with same content
R_FILE1="design/dvshare_locked.sv"
R_FILE2="script/dvshare_tool.sh"
R_FILE3="tb/dvshare_seq_lib_pkg.sv"

[[ -f "$R_FILE1" && -f "$R_FILE2" && -f "$R_FILE3" ]] || fail "Receiver missing one or more files."

RECV_SUMS="$WORK_BASE/recv_sums.txt"
sha1sum "$R_FILE1" "$R_FILE2" "$R_FILE3" > "$RECV_SUMS"

diff -u "$ORIG_SUMS" "$RECV_SUMS" >/dev/null || {
  echo "Sender vs Receiver checksums differ!"
  echo "Sender:"
  cat "$ORIG_SUMS"
  echo "Receiver:"
  cat "$RECV_SUMS"
  fail "Content mismatch between sender and receiver."
}

pass "Receiver content matches sender shared files."

# Optional: stage & clean up on receiver to ensure no accidental commits
git restore --staged . >/dev/null 2>&1 || true
popd >/dev/null

# Optional: demonstrate prune (wait a bit and prune)
info "Waiting briefly to demonstrate prune (optional) ..."
sleep 3
set +e
$DVSHARE list || true
$DVSHARE prune || true
set -e

pass "dvshare E2E test completed."

echo
echo "Summary:"
echo "  Sender repo:   $SENDER_ROOT"
echo "  Receiver repo: $RECEIVER_DIR"
echo "  Package used:  $RECV_PKG"
echo "  Work dir:      $WORK_BASE"
echo
echo "You can inspect the receiver repo to confirm applied changes visually."
