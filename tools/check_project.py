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
  * scripts are tab indented, brackets balance, and no func has an empty body
  * every property set on a scripted node exists as an @export on that script

Run: python3 tools/check_project.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SCRIPT_RE = re.compile(r'\[ext_resource type="Script" path="([^"]+)" id="([^"]+)"\]')
EXT_RE = re.compile(r'\[ext_resource [^\]]*path="([^"]+)"')
EXT_ANY_RE = re.compile(r'\[ext_resource type="(\w+)" path="([^"]+)" id="([^"]+)"\]')
INSTANCE_RE = re.compile(r'instance=ExtResource\("([^"]+)"\)')
PROPERTY_RE = re.compile(r"^(\w+)\s*=", re.M)
EXPORT_VAR_RE = re.compile(r"^@export[^\n]*\n(?:var|const)?\s*(?:var|const)?\s*(\w+)", re.M)
EXPORT_INLINE_RE = re.compile(r"^@export\w*(?:\([^)]*\))?\s+var\s+(\w+)", re.M)

# Built-in node properties a scene may legitimately set on any node. Kept as
# a list rather than inferred, because the alternative is either an engine
# database or a checker that silently allows typos.
BUILTIN_PROPERTIES = set("""
anchor_bottom anchor_left anchor_right anchor_top anchors_preset autowrap_mode
bus collision_layer collision_mask color columns custom_minimum_size disabled
editor_description enabled flip_h flip_v floor_snap_length grow_horizontal
grow_vertical horizontal_alignment input_pickable layer layout_mode light_mask
limit_bottom limit_left limit_right limit_top max_value min_value modulate
monitorable monitoring motion_mode mouse_filter offset offset_bottom offset_left
offset_right offset_top page physics_material_override pitch_scale
position position_smoothing_enabled position_smoothing_speed priority
process_mode rotation rotation_degrees scale script self_modulate shape size
size_flags_horizontal size_flags_vertical skew step stream text texture
texture_filter top_level unique_name_in_owner value vertical_alignment visible
volume_db z_as_relative z_index zoom
""".split())
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


def check_scripts():
    for dirpath, _dirs, files in os.walk(os.path.join(ROOT, "scripts")):
        for filename in files:
            if not filename.endswith(".gd"):
                continue
            full = os.path.join(dirpath, filename)
            raw = open(full, encoding="utf-8").read()
            clean = "\n".join(COMMENT_RE.sub("", line) for line in STRING_RE.sub('""', raw).splitlines())
            for opener, closer in (("(", ")"), ("[", "]"), ("{", "}")):
                if clean.count(opener) != clean.count(closer):
                    problems.append("%s has unbalanced %s%s" % (rel(full), opener, closer))
            lines = clean.splitlines()
            for index, line in enumerate(lines):
                if line.startswith("func ") or line.startswith("\tfunc "):
                    body = next((l for l in lines[index + 1:] if l.strip()), "")
                    if not body.startswith("\t"):
                        problems.append("%s:%d has an empty body" % (rel(full), index + 1))
            for index, line in enumerate(raw.splitlines()):
                if line.startswith(" ") and line.strip():
                    problems.append("%s:%d is space indented, Godot convention is tabs" % (rel(full), index + 1))


def script_exports(script_path):
    if not os.path.exists(script_path):
        return None
    source = open(script_path, encoding="utf-8").read()
    names = set(EXPORT_INLINE_RE.findall(source))
    # @export on its own line, var on the next.
    for block in re.findall(r"^@export[^\n]*\n\s*var\s+(\w+)", source, re.M):
        names.add(block)
    return names


def check_node_properties():
    """A property set on a scripted node must be an @export or a built-in.

    This is aimed squarely at the generated map scenes: a mistyped
    `lucky_chance` is silently ignored by Godot at load, so the level plays
    slightly wrong forever and nothing ever says why.
    """
    for dirpath, _dirs, files in os.walk(os.path.join(ROOT, "scenes")):
        for filename in files:
            if not filename.endswith(".tscn"):
                continue
            scene = os.path.join(dirpath, filename)
            text = open(scene, encoding="utf-8").read()
            ext = {mid: (kind, path) for kind, path, mid in EXT_ANY_RE.findall(text)}
            script_ids = {mid for mid, (kind, _p) in ext.items() if kind == "Script"}

            for raw in text.split("[node ")[1:]:
                block = "[node " + raw
                header = block.split("]", 1)[0]
                body = block.split("]", 1)[1] if "]" in block else ""
                owner_script = None

                instanced = INSTANCE_RE.search(header)
                if instanced:
                    ref = ext.get(instanced.group(1))
                    if ref and ref[0] == "PackedScene":
                        inner = res_to_path(ref[1])
                        if os.path.exists(inner):
                            inner_script, _paths, _unique = parse_scene(inner)
                            if inner_script:
                                owner_script = res_to_path(inner_script)
                else:
                    assign = SCRIPT_ASSIGN_RE.search(body)
                    if assign and assign.group(1) in script_ids:
                        owner_script = res_to_path(ext[assign.group(1)][1])

                if owner_script is None:
                    continue
                exports = script_exports(owner_script)
                if exports is None:
                    continue
                node_name = NODE_RE.match(block).group(1) if NODE_RE.match(block) else "?"
                for prop in PROPERTY_RE.findall(body):
                    if prop in BUILTIN_PROPERTIES or prop in exports:
                        continue
                    problems.append("%s: node %s sets %s, not an @export on %s"
                                    % (rel(scene), node_name, prop, rel(owner_script)))


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
check_scripts()
check_node_properties()
check_autoloads()

if problems:
    print("FAIL")
    for problem in sorted(set(problems)):
        print("  - " + problem)
    sys.exit(1)
print("OK: scene bindings, resource paths and autoloads all resolve.")
