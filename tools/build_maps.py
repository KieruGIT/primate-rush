"""BUILD MAPS - writes the level scenes from the layouts below.

    python tools/build_maps.py [project_root]

The layouts are the source of truth for scenes/maps/*.tscn: a platform is one
line here, and the collision box, its gray-box rect, the route the bots follow
and the art (LevelSkin) all follow from it. Editing a generated .tscn by hand
works, but the next run of this script overwrites it.

Check a layout change with the bot race before keeping it:
    godot --headless --fixed-fps 60 res://tools/BotRace.tscn -- --map=map_a
"""
import sys

EXT = [
    ('Script', 'res://scripts/world/MapData.gd', '1_map'),
    ('PackedScene', 'res://scenes/Vine.tscn', '2_vine'),
    ('PackedScene', 'res://scenes/Climbable.tscn', '3_climb'),
    ('PackedScene', 'res://scenes/Checkpoint.tscn', '4_check'),
    ('PackedScene', 'res://scenes/FinishLine.tscn', '5_finish'),
    ('PackedScene', 'res://scenes/BananaSpawn.tscn', '6_banana'),
    ('PackedScene', 'res://scenes/BouncePad.tscn', '7_pad'),
]
GRAY = 'Color(0.22, 0.26, 0.24, 1)'


def f(v):
    v = float(v)
    return str(int(v)) if v == int(v) else str(v)


class Map:
    def __init__(self, node, display, spawn, axis=(1, 0), kill=1200, stride=(72, 0), palette=3):
        self.node, self.display, self.spawn, self.axis = node, display, spawn, axis
        self.kill, self.stride, self.palette = kill, stride, palette
        self.solids = []      # (name, x0, top, w, h)
        self.climbs = []      # (cx, cy, w, h)
        self.vines = []
        self.checks = []
        self.bananas = []
        self.route = []
        self.finish_at = None
        self.pads = []

    def _solid(self, kind, x0, top, w, h):
        self.solids.append(('%s%d' % (kind, len(self.solids) + 1), x0, top, w, h))

    def bound(self, x, top, bottom):
        """An invisible wall at the end of a level. Not drawn, not climbable."""
        self._solid('Bound', x - 24, top, 48, bottom - top)

    def ground(self, x0, x1, top, depth=100):
        self._solid('Ground', x0, top, x1 - x0, depth)

    def ledge(self, x0, x1, top):
        self._solid('Ledge', x0, top, x1 - x0, 32)

    def wall(self, x, top, bottom, width=48, grip=True):
        """A solid pillar; grip wraps it in a Climbable a little taller, so a
        monkey is still holding on as its feet clear the top."""
        self._solid('Wall', x - width / 2, top, width, bottom - top)
        if grip:
            self.climbs.append((x, (top - 20 + bottom) / 2, width + 48, bottom - top + 20))

    def climb_face(self, x, top, bottom, width=40):
        """Climbable strip against the face of a thick block."""
        self.climbs.append((x, (top - 20 + bottom) / 2, width, bottom - top + 20))

    def vine(self, x, y, length):
        self.vines.append((x, y, length))

    def check(self, x, top):
        self.checks.append((x, top - 60))

    def banana(self, x, top, value=1, lucky=0.1):
        self.bananas.append((x, top - 40, value, lucky))

    def way(self, x, top):
        self.route.append((x, top - 36))

    def pad(self, x, top, strength=1350):
        self.pads.append((x, top, strength))

    def finish(self, x, top, w=80, h=300):
        self.finish_at = (x, top - h / 2, w, h)

    def write(self, path):
        out = []
        subs = len(self.solids)
        out.append('[gd_scene load_steps=%d format=3]\n' % (len(EXT) + subs + 1))
        for kind, p, i in EXT:
            out.append('[ext_resource type="%s" path="%s" id="%s"]' % (kind, p, i))
        out.append('')
        for name, x0, top, w, h in self.solids:
            out.append('[sub_resource type="RectangleShape2D" id="Rect_%s"]\nsize = Vector2(%s, %s)\n' % (name, f(w), f(h)))
        out.append('[node name="%s" type="Node2D"]' % self.node)
        out.append('script = ExtResource("1_map")')
        out.append('display_name = "%s"' % self.display)
        out.append('spawn_point = Vector2(%s, %s)' % (f(self.spawn[0]), f(self.spawn[1])))
        out.append('spawn_stride = Vector2(%s, %s)' % (f(self.stride[0]), f(self.stride[1])))
        out.append('kill_depth = %s' % f(self.kill))
        out.append('progress_axis = Vector2(%s, %s)' % (f(self.axis[0]), f(self.axis[1])))
        if getattr(self, 'zoom', 0):
            out.append('camera_zoom = %s' % f(self.zoom))
        if getattr(self, 'blast', 0):
            out.append('blast_half_width = %s' % f(self.blast))
        out.append('skin_palette = %d\n' % self.palette)
        out.append('[node name="Level" type="StaticBody2D" parent="."]\ncollision_layer = 1\ncollision_mask = 0\n')
        for name, x0, top, w, h in self.solids:
            out.append('[node name="Col%s" type="CollisionShape2D" parent="Level"]' % name)
            out.append('position = Vector2(%s, %s)' % (f(x0 + w / 2), f(top + h / 2)))
            out.append('shape = SubResource("Rect_%s")\n' % name)
            out.append('[node name="Vis%s" type="ColorRect" parent="Level"]' % name)
            out.append('offset_left = %s\noffset_top = %s\noffset_right = %s\noffset_bottom = %s' % (f(x0), f(top), f(x0 + w), f(top + h)))
            out.append('color = %s\nmouse_filter = 2\n' % GRAY)
        out.append('[node name="Climbables" type="Node2D" parent="."]\n')
        for i, (cx, cy, w, h) in enumerate(self.climbs):
            out.append('[node name="Climbable%d" parent="Climbables" instance=ExtResource("3_climb")]' % (i + 1))
            out.append('position = Vector2(%s, %s)\nsize = Vector2(%s, %s)\n' % (f(cx), f(cy), f(w), f(h)))
        out.append('[node name="Vines" type="Node2D" parent="."]\n')
        for i, (x, y, length) in enumerate(self.vines):
            out.append('[node name="Vine%d" parent="Vines" instance=ExtResource("2_vine")]' % (i + 1))
            out.append('position = Vector2(%s, %s)\nlength = %s\n' % (f(x), f(y), f(length)))
        out.append('[node name="Checkpoints" type="Node2D" parent="."]\n')
        for i, (x, y) in enumerate(self.checks):
            out.append('[node name="Checkpoint%d" parent="Checkpoints" instance=ExtResource("4_check")]' % (i + 1))
            out.append('position = Vector2(%s, %s)\n' % (f(x), f(y)))
        if self.finish_at:
            x, y, w, h = self.finish_at
            out.append('[node name="FinishLine" parent="." instance=ExtResource("5_finish")]')
            out.append('position = Vector2(%s, %s)\nsize = Vector2(%s, %s)\n' % (f(x), f(y), f(w), f(h)))
        out.append('[node name="BananaSpawns" type="Node2D" parent="."]\n')
        for i, (x, y, v, luck) in enumerate(self.bananas):
            out.append('[node name="Spawn%d" parent="BananaSpawns" instance=ExtResource("6_banana")]' % (i + 1))
            out.append('position = Vector2(%s, %s)\nvalue = %d\nlucky_chance = %s\n' % (f(x), f(y), v, f(luck)))
        out.append('[node name="Pads" type="Node2D" parent="."]\n')
        for i, (x, top, strength) in enumerate(self.pads):
            out.append('[node name="Pad%d" parent="Pads" instance=ExtResource("7_pad")]' % (i + 1))
            out.append('position = Vector2(%s, %s)\nstrength = %s\n' % (f(x), f(top), f(strength)))
        out.append('[node name="Route" type="Node2D" parent="."]\n')
        for i, (x, y) in enumerate(self.route):
            out.append('[node name="Point%d" type="Marker2D" parent="Route"]' % (i + 1))
            out.append('position = Vector2(%s, %s)\n' % (f(x), f(y)))
        open(path, 'w', encoding='utf-8', newline='\n').write('\n'.join(out))


# ---------------------------------------------------------------------------
# JUNGLE RUN - left to right. Meadow, vine valley, cliff climb, plateau,
# ledge descent, second valley, final sprint. Every vine gap has a slower
# stepping-stone line underneath, so the vines are the fast way, not the
# only way, and the heaviest monkey can always finish.
# ---------------------------------------------------------------------------

def jungle_run():
    m = Map('MapA', 'Jungle Run', spawn=(160, 440), kill=1150)
    m.bound(-176, -1400, 600)
    # 1. Start meadow, a step up, the first gap.
    m.ground(-200, 1100, 500)
    m.ledge(700, 900, 380)
    m.ground(1100, 1520, 440)
    m.ground(1650, 2120, 460)
    m.check(1760, 460)
    m.way(1060, 500); m.way(1480, 440); m.way(1700, 460); m.way(2080, 460)
    for x in (300, 600, 1300, 1900):
        m.banana(x, 500 if x < 1100 else 440 if x < 1600 else 460)
    # 2. Vine valley. Stones under it: vines are the fast way, not the only.
    for x0, top in [(2180, 530), (2420, 550), (2660, 530)]:
        m.ledge(x0, x0 + 180, top)
        m.way(x0 + 90, top)
        m.banana(x0 + 90, top, 1, 0.1)
    for x in (2300, 2560, 2820):
        m.vine(x, 90, 190)
        m.banana(x, 360, 3, 0.25)
    m.ground(2910, 3500, 470)
    m.check(3040, 470)
    m.way(2990, 470)
    # 3. The cliff: spring up it, or climb the face.
    m.pad(3330, 470, 1200)
    m.way(3330, 470)
    m.ground(3500, 4380, 140, depth=330)
    m.climb_face(3500, 140, 470, width=90)
    m.way(3600, 140); m.way(3800, 140)
    m.check(3650, 140)
    m.ledge(3860, 4060, 20)
    m.banana(3960, 20, 4, 0.3); m.banana(4200, 140, 2, 0.15)
    # 4. Down the ledges.
    m.ledge(4480, 4700, 230); m.ledge(4800, 5020, 310)
    m.way(4340, 140); m.way(4590, 230); m.way(4910, 310)
    m.banana(4590, 230, 2, 0.15)
    # 5. Second valley, vines high over the stones.
    for x0, top in [(5090, 380), (5330, 400), (5570, 380)]:
        m.ledge(x0, x0 + 170, top)
        m.way(x0 + 85, top)
    for x in (5200, 5450, 5700):
        m.vine(x, -60, 210)
        m.banana(x, 250, 3, 0.25)
    m.ground(5810, 6500, 400)
    m.check(5960, 400)
    m.way(5900, 400)
    m.ledge(6000, 6220, 260); m.ledge(6320, 6540, 190)
    m.banana(6430, 190, 5, 0.35)
    # 6. Islands and a spring to the high plateau.
    m.ground(6500, 6780, 340)
    m.way(6460, 400); m.way(6700, 340)
    m.ground(6920, 7400, 360)
    m.check(7000, 360)
    m.way(6960, 360); m.way(7360, 360)
    m.ground(7500, 7900, 330)
    m.way(7560, 330)
    m.pad(7780, 330, 1300)
    m.way(7780, 330)
    m.ground(7900, 8400, 0, depth=300)
    m.climb_face(7900, 0, 300, width=90)
    m.check(8000, 0)
    m.way(8000, 0); m.way(8380, 0)
    m.banana(8150, 0, 3, 0.2)
    # 7. Stairs down into the third valley.
    for x0, top in [(8480, 80), (8780, 160), (9080, 240)]:
        m.ledge(x0, x0 + 200, top)
        m.way(x0 + 100, top)
    for x0, top in [(9340, 330), (9600, 350), (9860, 330)]:
        m.ledge(x0, x0 + 160, top)
        m.way(x0 + 80, top)
        m.banana(x0 + 80, top, 1, 0.1)
    for x in (9440, 9690, 9940):
        m.vine(x, -120, 220)
        m.banana(x, 150, 4, 0.3)
    # 8. Home straight.
    m.ground(10100, 11000, 380)
    m.check(10250, 380)
    m.way(10200, 380)
    m.finish(10800, 380)
    m.way(10800, 380)
    m.banana(10500, 380, 2, 0.2)
    m.bound(11024, -1400, 480)
    return m


def canopy_climb():
    """A spiral up a jungle shaft. Staircases, springs and a climb, and no
    ledge ever hangs over a place you jump from - a zig-zag of 80 px steps
    puts the ledge two up right above your head, so every jump bonks."""
    m = Map('MapB', 'Canopy Climb', spawn=(-940, 440), axis=(0, -1), kill=900, stride=(60, 0), palette=2)
    m.ground(-1000, 1000, 500)
    m.bound(-1024, -2400, 500)
    m.bound(1024, -2400, 500)
    m.banana(0, 500); m.banana(700, 500)

    def stairs(steps):
        for x0, x1, top in steps:
            m.ledge(x0, x1, top)
            m.way((x0 + x1) / 2, top)

    # 1. Staircase up and to the right, onto the first landing. Steps rise
    # 70 with 30 px gaps: the gorilla's full jump is ~106 px, and a stair
    # it can only just make is a stair it misses half the time.
    stairs([(-640, -470, 430), (-440, -270, 360), (-240, -70, 290), (-40, 130, 220),
            (160, 330, 150), (360, 530, 80)])
    m.ground(560, 1000, 10, depth=60)
    m.way(640, 10)
    m.check(640, 10)
    m.banana(-475, 360, 2, 0.15); m.banana(125, 150, 2, 0.15)
    # 2. Spring from the landing up to the second, which reaches back out
    # over the spring so a heavy monkey's short drift still lands on it.
    m.pad(880, 10, 1450)
    m.way(880, 10)
    m.ground(-268, 700, -450, depth=60)
    m.way(560, -450); m.way(-120, -450)
    m.check(200, -450)
    m.vine(-560, -760, 200)
    m.banana(880, -300, 4, 0.3)
    # 3. Climb the pillar at the landing's end.
    m.wall(-300, -900, -390, width=64)
    m.way(-250, -450)
    m.ground(-180, 260, -900, depth=60)
    m.way(-110, -900); m.way(200, -900)
    m.check(-60, -900)
    m.ledge(-800, -560, -760)
    m.banana(-680, -760, 5, 0.35)
    # 4. Two steps right, then the spring onto the summit.
    stairs([(290, 460, -970), (490, 660, -1040)])
    m.pad(610, -1040, 1500)
    m.way(610, -1040)
    m.ground(-340, 540, -1560, depth=60)
    m.way(300, -1560)
    m.vine(-620, -1520, 220)
    m.finish(0, -1560, w=260, h=90)
    m.way(0, -1560)
    return m


def slap_island():
    """2v2 Slap. One island, two perches, a top ledge, sea all round.
    Teams spawn on opposite halves; the middle is where it happens."""
    m = Map('SlapArena', 'Slap Island', spawn=(-360, 260), kill=720, stride=(240, 0))
    m.blast = 1250
    m.zoom = 0.78
    m.ground(-560, 560, 300, depth=120)
    m.ledge(-420, -200, 150); m.ledge(200, 420, 150)
    m.ledge(-110, 110, 20)
    m.vine(0, -280, 180)
    for x, top in [(-300, 300), (300, 300), (-310, 150), (310, 150), (0, 20), (0, 300)]:
        m.banana(x, top, 2, 0.3)
    return m


if __name__ == '__main__':
    root = sys.argv[1] if len(sys.argv) > 1 else '.'
    jungle_run().write(root + '/scenes/maps/MapA.tscn')
    canopy_climb().write(root + '/scenes/maps/MapB.tscn')
    slap_island().write(root + '/scenes/maps/SlapArena.tscn')
    print('maps written')
