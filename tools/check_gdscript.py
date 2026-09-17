#!/usr/bin/env python3
"""Cross-file GDScript checks that do not need the engine.

check_project.py covers scene wiring. This covers the code itself, and it
exists because this project is written without a Godot binary to parse it:
a renamed function or a changed signature is otherwise found at runtime, on
a phone, mid-playtest.

What it checks:

  * every bare call (`foo(...)`, not `obj.foo(...)`) resolves to a function
    on the class or one of its project-defined ancestors
  * argument counts match the definition, accounting for default values
  * `Klass.CONST`, `Klass.Enum.VALUE` and autoload members exist
  * `@onready var x = $Path` targets are not obviously misspelled members

Engine methods are allow-listed in tools/engine_api.json rather than
guessed, so an unknown name is a real finding instead of noise.

Run: python3 tools/check_gdscript.py
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS = os.path.join(ROOT, "scripts")
ALLOWLIST = os.path.join(ROOT, "tools", "engine_api.json")

STRING_RE = re.compile(r'"(?:[^"\\]|\\.)*"')
COMMENT_RE = re.compile(r"#.*")
CLASS_NAME_RE = re.compile(r"^class_name\s+(\w+)", re.M)
EXTENDS_RE = re.compile(r"^extends\s+([\w.]+)", re.M)
FUNC_DEF_RE = re.compile(r"^func\s+(\w+)\s*\(([^)]*)\)", re.M)
MEMBER_RE = re.compile(r"^(?:@onready\s+|@export[^\n]*\n)?(?:var|const)\s+(\w+)", re.M)
SIMPLE_MEMBER_RE = re.compile(r"^\s*(?:@onready\s+)?(?:var|const)\s+(\w+)", re.M)
SIGNAL_RE = re.compile(r"^signal\s+(\w+)", re.M)
ENUM_RE = re.compile(r"^enum\s+(\w+)\s*\{([^}]*)\}", re.M)
# No leading dot, $ or @: those are member calls, node paths and annotations.
CALL_RE = re.compile(r"(?<![\w.$@])([a-z_]\w*)\s*\(")
# Owner.method(...) where Owner is a name, for the arity passes below.
QUALIFIED_CALL_RE = re.compile(r"\b(\w+)\.(\w+)\s*\(")
KEYWORDS = {"if", "elif", "while", "for", "return", "match", "and", "or", "not",
            "in", "await", "assert", "func", "super", "range"}

problems = []


def strip(source):
    """Strings first: a # inside a string is not a comment."""
    return COMMENT_RE.sub("", STRING_RE.sub('""', source))


def split_args(raw):
    """Parameter list to (min_args, max_args), honouring defaults."""
    raw = raw.strip()
    if not raw:
        return 0, 0
    depth, current, parts = 0, "", []
    for char in raw:
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
        if char == "," and depth == 0:
            parts.append(current)
            current = ""
        else:
            current += char
    parts.append(current)
    required = sum(1 for part in parts if "=" not in part)
    return required, len(parts)


class Script:
    def __init__(self, path, source):
        self.path = path
        self.source = source
        self.clean = strip(source)
        match = CLASS_NAME_RE.search(self.clean)
        self.class_name = match.group(1) if match else None
        match = EXTENDS_RE.search(self.clean)
        self.extends = match.group(1) if match else None
        self.funcs = {name: split_args(args) for name, args in FUNC_DEF_RE.findall(self.clean)}
        self.members = set(SIMPLE_MEMBER_RE.findall(self.clean))
        self.signals = set(SIGNAL_RE.findall(self.clean))
        self.enums = {}
        for name, body in ENUM_RE.findall(self.clean):
            values = set()
            for entry in body.split(","):
                entry = entry.split("=")[0].strip()
                if entry:
                    values.add(entry)
            self.enums[name] = values


def load_scripts():
    scripts = []
    for dirpath, _dirs, files in os.walk(SCRIPTS):
        for filename in sorted(files):
            if filename.endswith(".gd"):
                full = os.path.join(dirpath, filename)
                scripts.append(Script(full, open(full, encoding="utf-8").read()))
    return scripts


def rel(path):
    return os.path.relpath(path, ROOT)


def main():
    engine = json.load(open(ALLOWLIST, encoding="utf-8"))
    engine_calls = set(engine["methods"]) | set(engine["globals"])

    scripts = load_scripts()
    by_class = {s.class_name: s for s in scripts if s.class_name}
    autoloads = {}
    project = open(os.path.join(ROOT, "project.godot"), encoding="utf-8").read()
    section = project.split("[autoload]")[1].split("[display]")[0]
    for line in section.strip().splitlines():
        if "=" not in line:
            continue
        name, res = line.split("=", 1)
        res = res.strip().strip('"').lstrip("*").replace("res://", "")
        for script in scripts:
            if rel(script.path).replace(os.sep, "/") == res:
                autoloads[name.strip()] = script

    def ancestry(script):
        """The script plus every project-defined class it extends."""
        chain, seen = [script], set()
        current = script
        while current and current.extends and current.extends in by_class:
            if current.extends in seen:
                break
            seen.add(current.extends)
            current = by_class[current.extends]
            chain.append(current)
        return chain

    for script in scripts:
        chain = ancestry(script)
        known = {}
        for ancestor in chain:
            for name, arity in ancestor.funcs.items():
                known.setdefault(name, arity)

        for line_no, line in enumerate(script.clean.splitlines(), 1):
            stripped = line.lstrip()
            if stripped.startswith("func ") or stripped.startswith("signal "):
                continue
            for name in CALL_RE.findall(line):
                if name in KEYWORDS:
                    continue
                if name in engine_calls or name in known:
                    pass
                else:
                    problems.append("%s:%d calls %s(), which is not defined here or in an ancestor"
                                    % (rel(script.path), line_no, name))
                    continue
                if name not in known:
                    continue
                low, high = known[name]
                opened = line.find(name + "(")
                if opened < 0:
                    continue
                args = count_args(line[opened + len(name):])
                if args is None:
                    continue
                if args < low or args > high:
                    problems.append("%s:%d calls %s() with %d args, definition takes %d to %d"
                                    % (rel(script.path), line_no, name, args, low, high))

        check_qualified(script, by_class, autoloads, engine)

    check_unique_method_arity(scripts, engine)

    if problems:
        print("FAIL")
        for problem in sorted(set(problems)):
            print("  - " + problem)
        sys.exit(1)
    print("OK: %d scripts, calls and signatures resolve." % len(scripts))


def check_unique_method_arity(scripts, engine):
    """Arity for calls like `player.take_hit(...)`.

    Type inference is out of scope, so this only judges a method name that
    exactly one class in the project defines and the engine does not. If a
    name is unique, any call to it has to be that one, which is enough to
    catch a signature that changed without its call sites.
    """
    owners = {}
    for script in scripts:
        for name, arity in script.funcs.items():
            owners.setdefault(name, []).append((script, arity))
    unique = {
        name: entries[0]
        for name, entries in owners.items()
        if len(entries) == 1 and name not in engine["methods"] and name not in engine["globals"]
    }

    for script in scripts:
        for line_no, line in enumerate(script.clean.splitlines(), 1):
            for owner, method in QUALIFIED_CALL_RE.findall(line):
                if method not in unique or owner in {"self"}:
                    continue
                definition, (low, high) = unique[method]
                opened = line.find("." + method + "(")
                if opened < 0:
                    continue
                args = count_args(line[opened + len(method) + 1:])
                if args is None:
                    continue
                if args < low or args > high:
                    problems.append(
                        "%s:%d calls .%s() with %d args, %s defines %d to %d"
                        % (rel(script.path), line_no, method, args,
                           rel(definition.path), low, high))


def count_args(tail):
    """Args in the call starting at tail[0] == '('. None if it spans lines."""
    if not tail.startswith("("):
        return None
    depth, args, seen = 0, 0, False
    for char in tail:
        if char in "([{":
            depth += 1
            if depth == 1:
                continue
        elif char in ")]}":
            depth -= 1
            if depth == 0:
                return args + 1 if seen else 0
        if depth >= 1:
            if char == "," and depth == 1:
                args += 1
            elif not char.isspace():
                seen = True
    return None


def check_qualified(script, by_class, autoloads, engine):
    """Klass.MEMBER and Autoload.member references."""
    targets = dict(by_class)
    targets.update(autoloads)
    pattern = re.compile(r"\b(%s)\.(\w+)(?:\.(\w+))?" % "|".join(re.escape(k) for k in targets))
    for line_no, line in enumerate(script.clean.splitlines(), 1):
        for owner, first, second in pattern.findall(line):
            other = targets[owner]
            chain = [other]
            current = other
            while current.extends in by_class:
                current = by_class[current.extends]
                chain.append(current)
            names = set()
            enums = {}
            for ancestor in chain:
                names |= set(ancestor.funcs) | ancestor.members | ancestor.signals | set(ancestor.enums)
                enums.update(ancestor.enums)
            if first in engine["methods"] or first in engine["object_members"]:
                continue
            if first not in names:
                problems.append("%s:%d references %s.%s, which %s does not define"
                                % (rel(script.path), line_no, owner, first, owner))
                continue
            if second and first in enums and second not in enums[first]:
                problems.append("%s:%d references %s.%s.%s, not a value of that enum"
                                % (rel(script.path), line_no, owner, first, second, ))


if __name__ == "__main__":
    main()
