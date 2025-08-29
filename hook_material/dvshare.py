#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
dvshare: ephemeral, policy-free file sharing for local changes.
Creates a private share under .git/dv-share/<ID>, with TTL & auto-prune.

Subcommands:
  create  [--ttl 24h|2h30m|15m|3d] [--id LABEL] [--note TEXT] <files...>
  pack    <ID> [--out simlog]
  list
  info    <ID>
  remove  <ID>
  prune
  apply   <zip|folder> [--mode patch|copy]

Notes:
- Shares live under:  .git/dv-share/<ID>/{files/,share.patch,manifest.json}
- "pack" creates:     <out>/dvshare_<ID>.zip (ready to send)
- "apply" (on coworker side) uses 'git apply --3way --reject' (patch mode),
  or copies raw files preserving relative paths (copy mode).
"""

import argparse, os, sys, json, shutil, hashlib, zipfile, tempfile, subprocess, re
from datetime import datetime, timedelta
from pathlib import Path

def run(cmd, cwd=None, check=True):
    return subprocess.run(cmd, cwd=cwd, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, check=check)

def repo_root():
    return run(["git", "rev-parse", "--show-toplevel"]).stdout.strip()

def head_commit(root):
    try:
        return run(["git", "rev-parse", "HEAD"], cwd=root).stdout.strip()
    except Exception:
        return None

def relpath_under(root, p):
    p = os.path.abspath(p)
    root = os.path.abspath(root)
    if not p.startswith(root + os.sep):
        raise ValueError(f"path {p} not under repo {root}")
    return os.path.normpath(os.path.relpath(p, root)).replace("\\", "/")

DUR_RE = re.compile(r"(?P<num>\d+)\s*(?P<unit>[smhd])", re.I)
def parse_ttl(s: str) -> timedelta:
    """e.g. 90m, 2h30m, 1d, 45s"""
    if not s: return timedelta(days=1)
    total = timedelta(0)
    for m in DUR_RE.finditer(s):
        n = int(m.group("num"))
        u = m.group("unit").lower()
        total += {"s": timedelta(seconds=n),
                  "m": timedelta(minutes=n),
                  "h": timedelta(hours=n),
                  "d": timedelta(days=n)}[u]
    if total == timedelta(0):
        raise ValueError(f"invalid TTL: {s}")
    return total

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1<<20), b""):
            h.update(chunk)
    return h.hexdigest()

def ensure_dir(p):
    os.makedirs(p, exist_ok=True)

def share_base(root):
    return os.path.join(root, ".git", "dv-share")

def manifest_path(root, sid):
    return os.path.join(share_base(root), sid, "manifest.json")

def load_manifest(root, sid):
    with open(manifest_path(root, sid), "r", encoding="utf-8") as f:
        return json.load(f)

def save_manifest(root, sid, data):
    ensure_dir(os.path.join(share_base(root), sid))
    with open(manifest_path(root, sid), "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)

def now_iso():
    return datetime.now().isoformat(timespec="seconds")

def gen_id():
    return datetime.now().strftime("%Y%m%d_%H%M%S")

def git_diff_patch(root, files, out_patch):
    # Create a patch against HEAD for the given paths
    cmd = ["git", "diff", "--binary", "HEAD", "--"] + files
    p = run(cmd, cwd=root, check=False)
    with open(out_patch, "w", encoding="utf-8", errors="ignore") as f:
        f.write(p.stdout)
    return p.returncode == 0

def cmd_create(args):
    root = repo_root()
    sid = args.id or gen_id()
    sb = os.path.join(share_base(root), sid)
    files_dir = os.path.join(sb, "files")
    ensure_dir(files_dir)

    ttl = parse_ttl(args.ttl) if args.ttl else timedelta(days=1)
    created = datetime.now()
    expires = created + ttl

    file_entries = []
    rels = []
    for user_path in args.files:
        abs_p = os.path.abspath(user_path)
        if not os.path.isfile(abs_p):
            print(f"[dvshare] skip (not a file): {user_path}")
            continue
        rel = relpath_under(root, abs_p)
        rels.append(rel)
        dst = os.path.join(files_dir, rel)
        ensure_dir(os.path.dirname(dst))
        shutil.copy2(abs_p, dst)
        file_entries.append({"path": rel, "sha256": sha256_file(abs_p)})

    if not file_entries:
        print("[dvshare] nothing to share")
        return 1

    # also produce a patch for these files
    patch_path = os.path.join(sb, "share.patch")
    git_diff_patch(root, rels, patch_path)

    meta = {
        "id": sid,
        "creator": run(["git", "config", "user.name"], check=False).stdout.strip() or os.getenv("USERNAME") or os.getenv("USER"),
        "created_at": created.isoformat(timespec="seconds"),
        "expires_at": expires.isoformat(timespec="seconds"),
        "base_commit": head_commit(root),
        "note": args.note or "",
        "files": file_entries,
    }
    save_manifest(root, sid, meta)

    print(f"[dvshare] created {sid}")
    print(f"  files: {len(file_entries)}")
    print(f"  path : {sb}")
    print(f"  ttl  : {args.ttl or '24h'} (expires {meta['expires_at']})")
    print("  next : dvshare pack", sid)
    return 0

def cmd_pack(args):
    root = repo_root()
    sb = os.path.join(share_base(root), args.id)
    man = os.path.join(sb, "manifest.json")
    if not os.path.isfile(man):
        print(f"[dvshare] share not found: {args.id}")
        return 1
    out_dir = os.path.abspath(args.out or os.path.join(root, "simlog"))
    ensure_dir(out_dir)
    out_zip = os.path.join(out_dir, f"dvshare_{args.id}.zip")
    with zipfile.ZipFile(out_zip, "w", compression=zipfile.ZIP_DEFLATED) as z:
        # root files
        for name in ("manifest.json", "share.patch"):
            p = os.path.join(sb, name)
            if os.path.isfile(p):
                z.write(p, arcname=name)
        # files/
        files_root = os.path.join(sb, "files")
        for dirpath, _, filenames in os.walk(files_root):
            for fn in filenames:
                ap = os.path.join(dirpath, fn)
                rel = os.path.relpath(ap, sb).replace("\\", "/")
                z.write(ap, arcname=rel)
    print(f"[dvshare] packed -> {out_zip}")
    print("  send this zip to your co-worker")
    return 0

def cmd_list(_args):
    root = repo_root()
    base = share_base(root)
    if not os.path.isdir(base):
        print("[dvshare] no shares")
        return 0
    rows = []
    for sid in sorted(os.listdir(base)):
        try:
            m = load_manifest(root, sid)
            rows.append((sid, m.get("expires_at",""), len(m.get("files",[])), m.get("note","")))
        except Exception:
            rows.append((sid, "?", 0, "(broken manifest)"))
    if not rows:
        print("[dvshare] no shares")
        return 0
    print(f"{'ID':<18} {'EXPIRES':<20} {'N':>3}  NOTE")
    for sid, exp, n, note in rows:
        print(f"{sid:<18} {exp:<20} {n:>3}  {note}")
    return 0

def cmd_info(args):
    root = repo_root()
    m = load_manifest(root, args.id)
    print(json.dumps(m, indent=2))
    print(f"[path] {os.path.join(share_base(root), args.id)}")
    return 0

def cmd_remove(args):
    root = repo_root()
    p = os.path.join(share_base(root), args.id)
    if os.path.isdir(p):
        shutil.rmtree(p, ignore_errors=True)
        print(f"[dvshare] removed {args.id}")
    else:
        print(f"[dvshare] not found: {args.id}")
        return 1
    return 0

def cmd_prune(_args):
    root = repo_root()
    base = share_base(root)
    now = datetime.now()
    if not os.path.isdir(base):
        return 0
    removed = 0
    for sid in list(os.listdir(base)):
        manp = os.path.join(base, sid, "manifest.json")
        try:
            with open(manp, "r", encoding="utf-8") as f:
                m = json.load(f)
            exp = m.get("expires_at")
            if exp and now > datetime.fromisoformat(exp):
                shutil.rmtree(os.path.join(base, sid), ignore_errors=True)
                removed += 1
        except Exception:
            # broken manifest -> remove
            shutil.rmtree(os.path.join(base, sid), ignore_errors=True)
            removed += 1
    print(f"[dvshare] pruned {removed} expired share(s)")
    return 0

def is_zip(path): return str(path).lower().endswith(".zip")

def apply_patch(root, patch_path):
    p = run(["git", "apply", "--3way", "--reject", patch_path], cwd=root, check=False)
    sys.stdout.write(p.stdout); sys.stdout.write(p.stderr)
    return p.returncode

def apply_copy(root, files_dir):
    # Copy with backup if destination exists
    copied = 0
    for dirpath, _, filenames in os.walk(files_dir):
        for fn in filenames:
            src = os.path.join(dirpath, fn)
            rel = os.path.relpath(src, files_dir).replace("\\", "/")
            dst = os.path.join(root, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            if os.path.exists(dst):
                shutil.copy2(dst, dst + ".bak")
            shutil.copy2(src, dst)
            copied += 1
    print(f"[dvshare] copied {copied} file(s); backups: *.bak")
    return 0

def cmd_apply(args):
    root = repo_root()
    path = os.path.abspath(args.source)
    temp = None
    try:
        if is_zip(path):
            temp = tempfile.mkdtemp(prefix="dvshare_")
            with zipfile.ZipFile(path) as z:
                z.extractall(temp)
            files_dir = os.path.join(temp, "files")
            patch = os.path.join(temp, "share.patch")
        else:
            files_dir = os.path.join(path, "files")
            patch = os.path.join(path, "share.patch")

        mode = (args.mode or "patch").lower()
        if mode == "patch" and os.path.isfile(patch) and os.path.getsize(patch) > 0:
            rc = apply_patch(root, patch)
            if rc != 0:
                print("[dvshare] patch failed; you can retry with --mode copy")
                return rc
            print("[dvshare] patch applied")
            return 0
        else:
            if not os.path.isdir(files_dir):
                print("[dvshare] no files/ to copy; abort")
                return 2
            return apply_copy(root, files_dir)
    finally:
        if temp: shutil.rmtree(temp, ignore_errors=True)

def main():
    ap = argparse.ArgumentParser(prog="dvshare", description="Ephemeral sharing of local changes.")
    sp = ap.add_subparsers(dest="cmd", required=True)

    p = sp.add_parser("create", help="create a share with selected files")
    p.add_argument("--ttl", default="24h", help="time to live (e.g., 2h, 90m, 3d)")
    p.add_argument("--id", help="custom ID/label")
    p.add_argument("--note", help="free-form note")
    p.add_argument("files", nargs="+")
    p.set_defaults(func=cmd_create)

    p = sp.add_parser("pack", help="pack a share into a zip")
    p.add_argument("id")
    p.add_argument("--out", help="output dir (default simlog)")
    p.set_defaults(func=cmd_pack)

    sp.add_parser("list", help="list shares").set_defaults(func=cmd_list)

    p = sp.add_parser("info", help="show manifest of a share")
    p.add_argument("id")
    p.set_defaults(func=cmd_info)

    p = sp.add_parser("remove", help="remove a share")
    p.add_argument("id")
    p.set_defaults(func=cmd_remove)

    sp.add_parser("prune", help="delete expired shares").set_defaults(func=cmd_prune)

    p = sp.add_parser("apply", help="apply a zip/folder in current repo")
    p.add_argument("source", help="zip file or extracted folder")
    p.add_argument("--mode", choices=["patch","copy"], help="apply mode (default patch)")
    p.set_defaults(func=cmd_apply)

    args = ap.parse_args()
    try:
        rc = args.func(args)
    except Exception as e:
        print(f"[dvshare] ERROR: {e}")
        rc = 1
    sys.exit(rc)

if __name__ == "__main__":
    main()
