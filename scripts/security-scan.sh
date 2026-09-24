#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(git rev-parse --show-toplevel)"

fail=0

# High-signal secret formats. Keep this list conservative to avoid treating
# documented variable names and generated-at-runtime placeholders as secrets.
secret_re='(github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{16,}|sk_live_[A-Za-z0-9]{16,}|-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----)'

current_matches="$(git grep -nEI "$secret_re" -- . ':(exclude)scripts/security-scan.sh' || true)"
if [[ -n "$current_matches" ]]; then
  echo "Potential committed secret detected in tracked files:" >&2
  printf '%s\n' "$current_matches" >&2
  fail=1
fi

# Scan patch content from the complete local Git history. Commit metadata is
# checked separately below.
history_matches="$(git log -p --all --no-color --format= | grep -EI "$secret_re" || true)"
if [[ -n "$history_matches" ]]; then
  echo "Potential secret-like value detected in Git history:" >&2
  printf '%s\n' "$history_matches" | head -n 40 >&2
  fail=1
fi

# Public project files should not contain personal e-mail addresses. Allow only
# service/example addresses and systemd unit names that resemble e-mail syntax.
email_re='[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}'
email_matches="$(
  git grep -nEI "$email_re" -- . ':(exclude)scripts/security-scan.sh' 2>/dev/null |
    grep -Evi '(@users\.noreply\.github\.com|noreply@github\.com|git@github\.com|@example\.(com|org|net)|pve-container@[0-9]+\.service)' || true
)"
if [[ -n "$email_matches" ]]; then
  echo "Unexpected e-mail-like value detected in tracked files:" >&2
  printf '%s\n' "$email_matches" >&2
  fail=1
fi

metadata_emails="$(
  git log --all --format='%ae%n%ce' |
    sed '/^$/d' |
    sort -u |
    grep -Evi '(@users\.noreply\.github\.com$|^noreply@github\.com$)' || true
)"
if [[ -n "$metadata_emails" ]]; then
  echo "Non-noreply e-mail address detected in Git commit metadata:" >&2
  printf '%s\n' "$metadata_emails" >&2
  fail=1
fi

if (( fail )); then
  exit 1
fi

echo "Security scan OK: no common committed secret formats or unexpected personal e-mail addresses found."
