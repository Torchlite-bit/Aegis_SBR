#!/usr/bin/env python3
"""
Aegis_SBR — Lua 5.0 static verifier.

Two checks, run over the addon's .lua files, tuned for the Turtle WoW 1.12
client's single-pass Lua 5.0 loader (no external Lua interpreter available):

  1. BALANCE   — bracket / string / comment balance. Strips long comments
                 (--[[ ]] / --[=[ ]=]), line comments, long strings, and short
                 strings (with escapes) first, then verifies (), {}, [] nest
                 correctly with a type-aware stack. Catches the "unclosed table
                 / missing paren / stray brace" class of error that otherwise
                 only surfaces as a silent in-game load failure.

  2. ORDERING  — define-before-use audit. Lua 5.0 loads each file top-to-bottom
                 exactly once, so a local function/table used before its own
                 definition (in file order) crashes on load: the name inside the
                 earlier body binds to a (nil) global, not the later local. This
                 flags any function body that CALLS a local defined LATER in the
                 file OUTSIDE that body. A local first defined INSIDE the body
                 itself (e.g. captured by a closure) is in scope by the time it
                 runs and is deliberately not flagged. This has historically
                 caught real crashes (e.g. a layout row primitive placed above
                 the helper it calls).

Usage:
    python3 scripts/verify.py <file.lua> [more.lua ...]      # both checks
    python3 scripts/verify.py --balance <files>             # balance only
    python3 scripts/verify.py --ordering <files>            # ordering only
    python3 scripts/verify.py --all                         # every .lua in repo

Exit code is non-zero if any check fails, so it can gate a commit hook / CI.

NOTE: this is a heuristic static check, not a Lua parser. It is intentionally
conservative: BALANCE will not have false positives on well-formed code, and
ORDERING only reports a same-file local used above its definition. It does NOT
catch cross-file ordering (that is governed by the .toc load order — keep the
.toc order stable) or semantic/type errors. Always still test in-game.
"""

import sys
import os
import re
import glob


# --------------------------------------------------------------------------
# Shared: strip Lua comments and string literals, returning the "code only"
# text plus a count of any unterminated long-comment / long-string / short
# string encountered (those count as balance failures).
# --------------------------------------------------------------------------
def strip_lua(src):
    out = []
    i = 0
    n = len(src)
    unclosed_literal = 0
    while i < n:
        c = src[i]

        # line or long comment
        if src.startswith("--", i):
            j = i + 2
            m = re.match(r'\[(=*)\[', src[j:])
            if m:  # long comment --[[ ]] / --[=[ ]=]
                level = m.group(1)
                close = ']' + level + ']'
                start = j + len(m.group(0))
                end = src.find(close, start)
                if end == -1:
                    unclosed_literal += 1
                    i = n
                    continue
                i = end + len(close)
                continue
            else:  # line comment
                end = src.find('\n', i)
                i = n if end == -1 else end
                continue

        # long string [[ ]] / [=[ ]=]
        if c == '[':
            m = re.match(r'\[(=*)\[', src[i:])
            if m:
                level = m.group(1)
                close = ']' + level + ']'
                start = i + len(m.group(0))
                end = src.find(close, start)
                if end == -1:
                    unclosed_literal += 1
                    i = n
                    continue
                i = end + len(close)
                continue

        # short string "..." or '...'
        if c == '"' or c == "'":
            quote = c
            j = i + 1
            closed = False
            while j < n:
                if src[j] == '\\':
                    j += 2
                    continue
                if src[j] == quote:
                    j += 1
                    closed = True
                    break
                if src[j] == '\n':
                    break
                j += 1
            if not closed:
                unclosed_literal += 1
            i = j
            continue

        out.append(c)
        i += 1
    return ''.join(out), unclosed_literal


# --------------------------------------------------------------------------
# Check 1: bracket balance
# --------------------------------------------------------------------------
def check_balance(path):
    try:
        src = open(path, encoding='utf-8', errors='replace').read()
    except Exception as e:
        print(f"  {os.path.basename(path):28} ERROR reading: {e}")
        return False

    stripped, unclosed_literal = strip_lua(src)
    stack = []
    pairs = {')': '(', '}': '{', ']': '['}
    opens = set('({[')
    stray = 0
    paren = brace = bracket = 0

    for ch in stripped:
        if ch in opens:
            stack.append(ch)
        elif ch in pairs:
            if stack and stack[-1] == pairs[ch]:
                stack.pop()
            else:
                stray += 1
                if ch == ')':
                    paren += 1
                elif ch == '}':
                    brace += 1
                else:
                    bracket += 1

    for c in stack:  # leftover opens
        if c == '(':
            paren += 1
        elif c == '{':
            brace += 1
        else:
            bracket += 1

    unclosed = len(stack) + unclosed_literal
    ok = (paren == 0 and brace == 0 and bracket == 0
          and unclosed == 0 and stray == 0)
    extra = f" bracket={bracket}" if bracket else ""
    status = "OK" if ok else "FAIL"
    print(f"  {os.path.basename(path):28} paren={paren} brace={brace} "
          f"unclosed={unclosed} stray={stray}{extra} {status}")
    return ok


# --------------------------------------------------------------------------
# Check 2: define-before-use ordering (single-file, single-pass loader)
# --------------------------------------------------------------------------
def check_ordering(path):
    try:
        src = open(path, encoding='utf-8', errors='replace').read().split("\n")
    except Exception as e:
        print(f"  {os.path.basename(path):28} ERROR reading: {e}")
        return False

    # Record the first definition line of every local function / local var.
    defs = {}
    for i, ln in enumerate(src, 1):
        m = re.match(r'\s*local function (\w+)', ln) or re.match(r'\s*local (\w+)\s*=', ln)
        if m and m.group(1) not in defs:
            defs[m.group(1)] = i

    # Enumerate function bodies (both `function Name(` and `local function Name(`
    # and `function M:Name(`), so we can scan each body for forward calls.
    starts = []
    for i, ln in enumerate(src, 1):
        m = re.match(r'\s*(?:local function|function) ([\w:.]+)', ln)
        if m:
            starts.append((i, m.group(1)))

    issues = []
    for idx, (start, name) in enumerate(starts):
        end = starts[idx + 1][0] - 1 if idx + 1 < len(starts) else len(src)
        body = "\n".join(src[start:end])
        body = re.sub(r'--.*', '', body)          # drop line comments
        body = re.sub(r'"[^"]*"', '""', body)     # neutralize strings
        body = re.sub(r"'[^']*'", "''", body)
        for ident, dline in defs.items():
            # dline inside (start, end] is the body's own inner local (in scope
            # when the body runs); only a def past the body's end is a genuine
            # file-order forward reference.
            if dline > end and re.search(r'\b' + re.escape(ident) + r'\s*\(', body):
                issues.append(f"    '{name}' (line {start}) calls '{ident}' "
                              f"defined later (line {dline})")

    if issues:
        print(f"  {os.path.basename(path):28} ORDERING ISSUES:")
        for s in issues:
            print(s)
        return False
    print(f"  {os.path.basename(path):28} ordering OK")
    return True


# --------------------------------------------------------------------------
# Driver
# --------------------------------------------------------------------------
def repo_lua_files():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return sorted(glob.glob(os.path.join(root, "**", "*.lua"), recursive=True))


def main():
    args = sys.argv[1:]
    do_balance = do_ordering = True
    files = []

    for a in args:
        if a == "--balance":
            do_ordering = False
        elif a == "--ordering":
            do_balance = False
        elif a == "--all":
            files = repo_lua_files()
        else:
            files.append(a)

    if not files:
        files = repo_lua_files()
    if not files:
        print("No .lua files found.")
        return 1

    all_ok = True

    if do_balance:
        print("== BALANCE ==")
        for f in files:
            if not check_balance(f):
                all_ok = False
        print()

    if do_ordering:
        print("== ORDERING (define-before-use) ==")
        for f in files:
            if not check_ordering(f):
                all_ok = False
        print()

    print("RESULT:", "all checks passed" if all_ok else "FAILURES above")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
