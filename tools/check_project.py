#!/usr/bin/env python3
"""Static sanity checks for the Godot project.

Godot only reports a broken node path or a missing unique name when the scene
actually runs, which on a two-phone LAN test is an expensive place to find out.
This checks what can be checked without the engine:

  * every $NodePath and %UniqueName a script uses exists in the scene that
    the script is attached to
  * every ext_resource path in a .tscn or .tres points at a file that exists
  * every preload() path in a script points at a file that exists
  * autoloads named in project.godot exist

Run: python3 tools/check_project.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SCRIPT_RE = re.compile(r'\[ext_resource type="Script" path="([^"]+)" id="([^"]+)"\]')
EXT_RE = re.compile(r'\[ext_resource [^\]]*path="([^"]+)"')
NODE_RE = re.compile(r'\[node name="([^"]+)"(?: type="[^"]*")?(?: parent="([^"]*)")?[^\]]*\]')
SCRIPT_ASSIGN_RE = re.compile(r'script = ExtResource\("([^"]+)"\)')
UNIQUE_RE = re.compile(r'unique_name_in_owner = true')
DOLLAR_RE = re.compile(r'\$([A-Za-z_][A-Za-z0-9_/]*)')
PERCENT_RE = re.compile(r'%([A-Za-z_][A-Za-z0-9_]*)')
PRELOAD_RE = re.compile(r'(?:preload|load)\("(res://[^"]+)"\)')
STRING_RE = re.compile(r'"(?:[^"\\]|\\.)*"')
COMMENT_RE = re.compile(r'#.*')


def strip_literals(source):
    """Drops strings and comments so a "%s" format code is not read as a
    unique node name, and a $ inside a comment is not read as a node path.

    Strings go first: a # inside a string literal is not a comment, and
    stripping comments first eats the rest of lines like "%s #%d".
    """
    source = STRING_RE.sub('""', source)
    return COMMENT_RE.sub("", source)

problems = []


def res_to_path(res):
    return os.path.join(ROOT, res.replace("res://", ""))


def parse_scene(path):
    """Returns (script_res_for_root, node_paths, unique_names)."""
    text = open(path, encoding="utf-8").read()
    ext_scripts = dict((mid, p) for p, mid in SCRIPT_RE.findall(text))
    blocks = text.split("[node ")
    node_paths = set()
    unique_names = set()
    root_script = None
    for index, raw in enumerate(blocks[1:]):
        block = "[node " + raw
        match = NODE_RE.match(block)
        if not match:
            continue
        name, parent = match.group(1), match.group(2)
        if index == 0:
            assign = SCRIPT_ASSIGN_RE.search(block)
            if assign:
                root_script = ext_scripts.get(assign.group(1))
        else:
            full = name if parent in (".", None, "") else "%s/%s" % (parent, name)
            node_paths.add(full)
        if UNIQUE_RE.search(block):
            unique_names.add(name)
    return root_script, node_paths, unique_names


def check_resource_paths():
    for dirpath, _dirs, files in os.walk(ROOT):
        if "/.git" in dirpath:
            continue
        for filename in files:
            if not filename.endswith((".tscn", ".tres")):
                continue
            full = os.path.join(dirpath, filename)
            for res in EXT_RE.findall(open(full, encoding="utf-8").read()):
                if not os.path.exists(res_to_path(res)):
                    problems.append("%s references missing resource %s" % (rel(full), res))


def check_script_loads():
    for dirpath, _dirs, files in os.walk(os.path.join(ROOT, "scripts")):
        for filename in files:
            if not filename.endswith(".gd"):
                continue
            full = os.path.join(dirpath, filename)
            for res in PRELOAD_RE.findall(open(full, encoding="utf-8").read()):
                if not os.path.exists(res_to_path(res)):
                    problems.append("%s preloads missing %s" % (rel(full), res))


def check_scene_bindings():
    for dirpath, _dirs, files in os.walk(os.path.join(ROOT, "scenes")):
        for filename in files:
            if not filename.endswith(".tscn"):
                continue
            scene = os.path.join(dirpath, filename)
            script_res, node_paths, unique_names = parse_scene(scene)
            if not script_res:
                continue
            script_path = res_to_path(script_res)
            if not os.path.exists(script_path):
                continue
            source = strip_literals(open(script_path, encoding="utf-8").read())
            for ref in set(DOLLAR_RE.findall(source)):
                if ref not in node_paths:
                    problems.append("%s uses $%s, absent from %s" % (rel(script_path), ref, rel(scene)))
            for ref in set(PERCENT_RE.findall(source)):
                if ref not in unique_names:
                    problems.append("%s uses %%%s, no unique node in %s" % (rel(script_path), ref, rel(scene)))


def check_autoloads():
    text = open(os.path.join(ROOT, "project.godot"), encoding="utf-8").read()
    section = text.split("[autoload]")[1].split("[display]")[0]
    for line in section.strip().splitlines():
        if "=" not in line:
            continue
        res = line.split("=", 1)[1].strip().strip('"').lstrip("*")
        if not os.path.exists(res_to_path(res)):
            problems.append("project.godot autoloads missing %s" % res)


def rel(path):
    return os.path.relpath(path, ROOT)


check_resource_paths()
check_script_loads()
check_scene_bindings()
check_autoloads()

if problems:
    print("FAIL")
    for problem in sorted(set(problems)):
        print("  - " + problem)
    sys.exit(1)
print("OK: scene bindings, resource paths and autoloads all resolve.")
