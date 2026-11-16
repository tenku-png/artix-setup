#!/usr/bin/env python3
"""Scan staged Git blobs for common secrets without printing their contents."""
from __future__ import annotations
import base64
import re
import subprocess
import sys

PATTERNS = {
    "private-key-block": re.compile(rb"-----BEGIN (?:OPENSSH |RSA |EC |DSA )?PRIVATE KEY-----"),
    "github-token": re.compile(rb"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,})\b"),
    "aws-access-key": re.compile(rb"\bAKIA[0-9A-Z]{16}\b"),
    "credential-url": re.compile(rb"(?i)https?://[^/\s:@]+:[^/\s@]+@"),
}
WG_PRIVATE = re.compile(rb"(?im)^\s*PrivateKey\s*=\s*([A-Za-z0-9+/]{43}=)\s*$")
CREDENTIAL_ASSIGNMENT = re.compile(
    rb"(?im)^\s*[\"']?[A-Za-z0-9_-]*(?:password|passwd|token|secret|api[_-]?key)"
    rb"[A-Za-z0-9_-]*[\"']?\s*[:=]\s*[\"']?([A-Za-z0-9/+_.=-]{16,})"
)
SENSITIVE_NAMES = re.compile(
    r"(?:^|/)(?:id_(?:rsa|ed25519|ecdsa)(?:_sk)?|authorized_keys|\.env(?:\..*)?|"
    r"(?:wg|awg|amnezia|amnz)[^/]*\.(?:conf|backup)|[^/]+\.(?:pem|p12|pfx|kdbx))$", re.I
)


def main() -> int:
    names = subprocess.run(["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z"],
                           check=True, stdout=subprocess.PIPE).stdout.split(b"\0")
    findings = []
    for raw_name in filter(None, names):
        name = raw_name.decode("utf-8", "replace")
        blob = subprocess.run(["git", "show", f":{name}"], stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL)
        if blob.returncode:
            continue
        data = blob.stdout
        rules = [rule for rule, pattern in PATTERNS.items() if pattern.search(data)]
        for match in CREDENTIAL_ASSIGNMENT.finditer(data):
            value = match.group(1).lower()
            if not value.startswith((b"your-", b"replace-", b"change-me", b"placeholder", b"redacted", b"example")):
                rules.append("credential-assignment")
                break
        for match in WG_PRIVATE.finditer(data):
            try:
                if len(base64.b64decode(match.group(1), validate=True)) == 32:
                    rules.append("wireguard-private-key")
                    break
            except Exception:
                pass
        sensitive_name = bool(SENSITIVE_NAMES.search(name)) and name != ".env.example"
        if rules or sensitive_name:
            findings.append((name, sorted(set(rules + (["sensitive-filename"] if sensitive_name else [])))))
    if findings:
        print("secret scan blocked this commit; review these staged paths (contents are hidden):", file=sys.stderr)
        for name, rules in findings:
            print(f"  {name}: {', '.join(rules)}", file=sys.stderr)
        return 1
    print("secret scan: no common credentials or private-key material found in staged files")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
