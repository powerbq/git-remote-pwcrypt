#!/usr/bin/env bash
# Tests for passphrase mode (pwcrypt, passphrase mode).
# Uses a local bare repository, which pwcrypt drives through the same
# git-transport ("gitception") code path as GitHub.
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
export PATH="$here:$PATH"
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
export GNUPGHOME="$W/gnupg"; mkdir -m 700 "$GNUPGHOME"   # empty keyring: no GPG keys at all
export HOME="$W/home"; mkdir "$HOME"
git config --global user.name tester
git config --global user.email tester@example.com
git config --global init.defaultBranch main
git config --global pwcrypt.s2k-count 1048576   # fast for tests

# askpass: returns contents of $W/pass, logs every call
cat > "$W/askpass" <<'EOF'
#!/bin/sh
echo "$1" >> "$ASKLOG"
cat "$PASSFILE"
EOF
chmod +x "$W/askpass"
export PWCRYPT_ASKPASS="$W/askpass" ASKLOG="$W/asklog" PASSFILE="$W/pass"
asks() { local n; n=$(wc -l < "$ASKLOG" 2>/dev/null || echo 0); : > "$ASKLOG"; echo "$n"; }
pass=0; fail=0
ok()  { echo "  PASS: $*"; pass=$((pass+1)); }
bad() { echo "  FAIL: $*"; fail=$((fail+1)); }
expect() { if [ "$1" = "$2" ]; then ok "$3 ($1)"; else bad "$3 (got '$1', want '$2')"; fi; }

P1='Zq#8v!L2^p&9*Rk$w@X3%m(T)7_e+Y=u{J}4[b]5|c\6:d;F"g<H>i,K.l?N/o~0`Q 1-r'
printf '%s' "$P1" > "$PASSFILE"
git init -q --bare "$W/server.git"
URL="pwcrypt::$W/server.git"

echo "== 1. first push creates repo, asks NEW passphrase twice"
git init -q "$W/a"; cd "$W/a"
mkdir -p env; echo "TOP-SECRET-MARKER-42" > env/secret.conf; echo "alias ll='ls -l'" > env/.bashrc
git add -A; git commit -qm "first"
git remote add origin "$URL"
git push -q origin main 2>"$W/err" || { cat "$W/err"; bad "first push"; }
expect "$(asks)" 2 "prompts on first push"

echo "== 2. second push: exactly one prompt"
echo more >> env/.bashrc; git commit -qam second
git push -q origin main 2>/dev/null && ok "push" || bad "push"
expect "$(asks)" 1 "prompts on push"

echo "== 3. clone elsewhere: one prompt, content intact"
cd "$W"
git clone -q "$URL" b 2>/dev/null && ok "clone" || bad "clone"
expect "$(asks)" 1 "prompts on clone"
expect "$(cat b/env/secret.conf)" "TOP-SECRET-MARKER-42" "file content"
cd b
expect "$(git log --format=%s | tr '\n' ' ')" "second first " "history"

echo "== 4. push from b, pull in a: one prompt each"
echo third > env/new; git add -A; git commit -qm third
git push -q origin main 2>/dev/null; expect "$(asks)" 1 "prompts on push from b"
cd "$W/a"; git pull -q origin main 2>/dev/null; expect "$(asks)" 1 "prompts on pull"
expect "$(cat env/new)" third "pulled content"

echo "== 5. server holds no plaintext; outer commits are anonymous"
cd "$W/server.git"
if git cat-file --batch-all-objects --batch 2>/dev/null | grep -a -q -e TOP-SECRET-MARKER -e "alias ll" -e secret.conf; then
  bad "plaintext found on server"; else ok "no plaintext on server"; fi
expect "$(git log -1 --format="%an <%ae> %at" master)" "root <root@localhost> 1356994801" "outer commit metadata (fixed anonymous author/date)"

echo "== 6. wrong passphrase: refused after 3 tries"
cd "$W/a"; printf 'wrong' > "$PASSFILE"
if git fetch -q origin 2>"$W/err"; then bad "fetch with wrong pass succeeded"; else ok "fetch refused"; fi
expect "$(asks)" 3 "tries"
grep -q "wrong passphrase" "$W/err" && ok "error message" || bad "error message: $(cat "$W/err")"

echo "== 7. change passphrase"
P2='second-Passphrase-#2-with-ünïcødé'
printf '%s' "$P1" > "$PASSFILE"
cat > "$W/askpass2" <<EOF
#!/bin/sh
echo "\$1" >> "\$ASKLOG"
case "\$1" in *NEW*|*repeat*) printf '%s' '$P2';; *) printf '%s' '$P1';; esac
EOF
chmod +x "$W/askpass2"
PWCRYPT_ASKPASS="$W/askpass2" git-remote-pwcrypt --change-passphrase origin 2>"$W/err" && ok "change" || { bad "change"; cat "$W/err"; }
expect "$(asks)" 3 "prompts (old + new + repeat)"
printf '%s' "$P1" > "$PASSFILE"
git fetch -q origin 2>/dev/null && bad "old passphrase still works" || ok "old passphrase rejected"
asks >/dev/null
cd "$W/a"; printf '%s' "$P2" > "$PASSFILE"
cd "$W"; rm -rf c
git clone -q "$URL" c 2>/dev/null && ok "clone with new passphrase" || bad "clone with new passphrase"
expect "$(cat c/env/new 2>/dev/null)" third "content after change"
asks >/dev/null

echo "== 8. mismatched new passphrase on change: nothing uploaded"
cd "$W/a"
cat > "$W/askpass3" <<EOF
#!/bin/sh
case "\$1" in *repeat*) printf x2;; *NEW*) printf x1;; *) printf '%s' '$P2';; esac
EOF
chmod +x "$W/askpass3"
before=$(git -C "$W/server.git" rev-parse master)
PWCRYPT_ASKPASS="$W/askpass3" git-remote-pwcrypt --change-passphrase origin 2>/dev/null && bad "mismatch accepted" || ok "mismatch refused"
expect "$(git -C "$W/server.git" rev-parse master)" "$before" "server unchanged"

echo "== 9. forged manifest (unencrypted OpenPGP literal packet) is rejected"
cd "$W"; git clone -q --mirror server.git evil.git
manifest=91bd0c092128cf2e60e1a608c31e92caf1f9c1595f83f2890ef17c0e4881aa0a   # fixed manifest name
git -C evil.git ls-tree master | grep -q "$manifest" || bad "manifest not found in tree"
forged=$(printf '%s\n' "0000000000000000000000000000000000000000 refs/heads/main" "repo :id:x" | gpg --batch --store -o - | git -C evil.git hash-object -w --stdin)
tree=$(git -C evil.git ls-tree master | grep -v "$manifest" | { cat; printf '100644 blob %s\t%s\n' "$forged" "$manifest"; } | git -C evil.git mktree)
git -C evil.git update-ref refs/heads/master "$(echo x | git -C evil.git commit-tree "$tree")"
cd "$W/a"; git remote add evil "pwcrypt::$W/evil.git"
if git fetch -q evil 2>"$W/err"; then bad "forged manifest accepted"; else ok "forged manifest rejected"; fi
grep -q "not passphrase-encrypted" "$W/err" && ok "detected as unencrypted" || bad "message: $(cat "$W/err")"
asks >/dev/null

echo "== 10. tampered manifest (one byte flipped) is rejected"
rm -rf "$W/evil.git"; git clone -q --mirror "$W/server.git" "$W/evil.git"
blob=$(git -C "$W/evil.git" ls-tree master | grep "$manifest" | awk '{print $3}')
git -C "$W/evil.git" cat-file blob "$blob" > "$W/m"
size=$(wc -c < "$W/m"); printf '\x00' | dd of="$W/m" bs=1 seek=$((size-30)) conv=notrunc 2>/dev/null
nb=$(git -C "$W/evil.git" hash-object -w "$W/m")
tree=$(git -C "$W/evil.git" ls-tree master | grep -v "$manifest" | { cat; printf '100644 blob %s\t%s\n' "$nb" "$manifest"; } | git -C "$W/evil.git" mktree)
git -C "$W/evil.git" update-ref refs/heads/master "$(echo x | git -C "$W/evil.git" commit-tree "$tree")"
if git fetch -q evil 2>/dev/null; then bad "tampered manifest accepted"; else ok "tampered manifest rejected"; fi
asks >/dev/null

echo "== 11. local-directory backend works too"
cd "$W/a"; git remote add dir "pwcrypt::$W/plaindir"
git push -q dir main 2>/dev/null && ok "push to dir" || bad "push to dir"
expect "$(asks)" 2 "prompts (new repo)"
if grep -r -a -q TOP-SECRET-MARKER "$W/plaindir"; then bad "plaintext in dir"; else ok "no plaintext in dir"; fi

echo "== 13. --reencrypt: all blobs new, nothing to push, same passphrase"
cd "$W/a"; printf '%s' "$P2" > "$PASSFILE"; git pull -q origin main 2>/dev/null; asks >/dev/null
lst() { git -C "$W/server.git" ls-tree master | awk '{print $3, $4}' | sort -k2; }
lst > "$W/r_before"
git-remote-pwcrypt --reencrypt origin 2>"$W/err" && ok "reencrypt" || { bad "reencrypt"; cat "$W/err"; }
expect "$(asks)" 1 "prompts on reencrypt"
lst > "$W/r_after"
expect "$(comm -12 <(awk '{print $1}' "$W/r_before" | sort) <(awk '{print $1}' "$W/r_after" | sort) | wc -l)" 0 "server blobs shared with before"
expect "$(awk '{print $2}' "$W/r_after" | grep -c -v '^91bd0c09')" 1 "packfiles after (one)"
old_packs=$(awk '{print $2}' "$W/r_before" | grep -v '^91bd0c09' | wc -l)
[ "$old_packs" -gt 1 ] && ok "had $old_packs packs before" || bad "expected several packs before"
cd "$W"; rm -rf d
git clone -q "$URL" d 2>/dev/null && ok "clone after reencrypt" || bad "clone after reencrypt"
expect "$(git -C d log --format=%s | tr '\n' ' ')" "third second first " "history after reencrypt"
asks >/dev/null

echo "== 12. passphrase never in argv/environment of child processes"
cd "$W/a"; printf '%s' "$P2" > "$PASSFILE"
( while [ ! -e "$W/stop" ]; do cat /proc/[0-9]*/cmdline /proc/[0-9]*/environ 2>/dev/null | tr '\0' '\n' | grep -q 'second-Passphras[e]' && echo LEAK > "$W/leak"; done ) >/dev/null 2>&1 &
spy=$!
for i in 1 2 3 4 5; do git fetch -q origin 2>"$W/err12" || { bad "fetch under observation failed: $(cat "$W/err12")"; break; }; done
touch "$W/stop"; wait $spy 2>/dev/null || true
[ -e "$W/leak" ] && bad "passphrase seen in /proc" || ok "not seen in /proc cmdline/environ"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
