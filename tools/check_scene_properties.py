#!/usr/bin/env python3
"""The one scene check Godot will not do for you.

Godot silently ignores a property a .tscn sets that the node's script does
not declare. Nothing is logged, so a mistyped `lucky_chance` means the level
plays subtly wrong forever. That matters here because the map scenes are
generated, where a typo is one bad string away and invisible in review.

Everything else - parse errors, missing node paths, bad resource paths,
wrong signatures - is caught properly by running the engine itself:

    godot --headless --editor --quit        # imports, reports parse errors
    godot --headless res://tools/Smoke.tscn # runs every scene and mode

Run: python3 tools/check_scene_properties.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

EXT_RE = re.compile(r'\[ext_resource type="(\w+)" path="([^"]+)" id="([^"]+)"\]')
NODE_RE = re.compile(r'\[node name="([^"]+)"')
INSTANCE_RE = re.compile(r'instance=ExtResource\("([^"]+)"\)')
SCRIPT_RE = re.compile(r'script = ExtResource\("([^"]+)"\)')
PROPERTY_RE = re.compile(r"^(\w+)\s*=", re.M)
EXPORT_RE = re.compile(r"^@export[^\n]*\n?\s*(?:var\s+(\w+))?", re.M)

# Properties any node may set regardless of its script.
BUILTIN = set("""
anchor_bottom anchor_left anchor_right anchor_top anchors_preset autowrap_mode
bus collision_layer collision_mask color columns custom_minimum_size disabled
editor_description enabled flip_h flip_v floor_snap_length grow_horizontal
grow_vertical horizontal_alignment input_pickable layer layout_mode light_mask
max_value min_value modulate monitorable monitoring motion_mode mouse_filter
offset offset_bottom offset_left offset_right offset_top page pitch_scale
placeholder_text position position_smoothing_enabled position_smoothing_speed
priority process_mode rotation rotation_degrees scale script self_modulate
shape size size_flags_horizontal size_flags_vertical skew step stream text
texture texture_filter top_level unique_name_in_owner value vertical_alignment
visible volume_db z_as_relative z_index zoom
""".split())


def exports_of(script_res):
    path = os.path.join(ROOT, script_res.replace("res://", ""))
    if not os.path.exists(path):
        return None
    source = open(path, encoding="utf-8").read()
    names = set(re.findall(r"^@export\w*(?:\([^)]*\))?\s+var\s+(\w+)", source, re.M))
    names |= set(re.findall(r"^@export[^\n]*\n\s*var\s+(\w+)", source, re.M))
    return names


def root_script_of(scene_path):
    text = open(scene_path, encoding="utf-8").read()
    ext = {i: (k, p) for k, p, i in EXT_RE.findall(text)}
    first = text.split("[node ")[1] if "[node " in text else ""
    match = SCRIPT_RE.search(first)
    return ext[match.group(1)][1] if match and match.group(1) in ext else None


def main():
    problems = []
    for dirpath, _dirs, files in os.walk(os.path.join(ROOT, "scenes")):
        for filename in files:
            if not filename.endswith(".tscn"):
                continue
            scene = os.path.join(dirpath, filename)
            text = open(scene, encoding="utf-8").read()
            ext = {i: (k, p) for k, p, i in EXT_RE.findall(text)}

            for index, raw in enumerate(text.split("[node ")[1:]):
                block = "[node " + raw
                header, _, body = block.partition("]")
                script_res = None

                instanced = INSTANCE_RE.search(header)
                if instanced and instanced.group(1) in ext:
                    inner = os.path.join(ROOT, ext[instanced.group(1)][1].replace("res://", ""))
                    if os.path.exists(inner):
                        script_res = root_script_of(inner)
                elif index == 0:
                    match = SCRIPT_RE.search(body)
                    if match and match.group(1) in ext:
                        script_res = ext[match.group(1)][1]

                if script_res is None:
                    continue
                exports = exports_of(script_res)
                if exports is None:
                    continue
                name = NODE_RE.match(block).group(1) if NODE_RE.match(block) else "?"
                for prop in PROPERTY_RE.findall(body):
                    if prop not in BUILTIN and prop not in exports:
                        problems.append("%s: node %s sets %s, not an @export on %s"
                                        % (os.path.relpath(scene, ROOT), name, prop, script_res))

    if problems:
        print("FAIL")
        for problem in sorted(set(problems)):
            print("  - " + problem)
        sys.exit(1)
    print("OK: every scene property matches an export.")


if __name__ == "__main__":
    main()
