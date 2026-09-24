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
# Numbers every layout below is built around (base monkey, gorilla in
# brackets): a jump rises ~136 px (~113), jump + double jump ~230 (~195), a
# running jump crosses ~280 px (~220). So a plain hop is at most 90 up and
# 140 across, anything bigger gets a climbable wall or a spring, and every
# vine gap has stepping stones under it so the vines are the fast way, not
# the only way.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# JUNGLE RUN - a left-to-right parkour course. Steps, pillar hops over the
# water, a cliff climb, a treetop run, a drop-through descent, a vine valley,
# a chimney of climbing walls, a leap down and a sprint to the flag.
# ---------------------------------------------------------------------------

def jungle_run():
    m = Map('MapA', 'Jungle Run', spawn=(160, 440), kill=1150)
    m.bound(-176, -1400, 600)
    # 1. Start meadow.
    m.ground(-200, 700, 500)
    for x in (300, 600):
        m.banana(x, 500)
    m.way(640, 500)
    # 2. Steps up onto the first island.
    for x0, top in [(760, 430), (960, 360), (1160, 290)]:
        m.ledge(x0, x0 + 150, top)
        m.way(x0 + 75, top)
    m.banana(1235, 290, 2, 0.15)
    m.ground(1360, 1800, 300)
    m.check(1440, 300)
    m.way(1420, 300); m.way(1760, 300)
    # 3. Pillar hops over open water, with vines above for the brave.
    for x0, top in [(1920, 320), (2160, 300), (2400, 320)]:
        m.ground(x0, x0 + 120, top)
        m.way(x0 + 60, top)
        m.banana(x0 + 60, top, 1, 0.1)
    # Vine bottoms sit ~290 px over whatever you jump from: close enough
    # to reach with the double jump, far enough that a plain hop across
    # does not snag one by accident.
    for x in (2040, 2280, 2520):
        m.vine(x, -190, 200)
        m.banana(x, 60, 3, 0.25)
    m.ground(2640, 3180, 340)
    m.check(2720, 340)
    m.way(2700, 340)
    # 4. The cliff: climb the face, or take the spring.
    m.pad(3060, 340, 1200)
    m.way(3060, 340)
    m.ground(3180, 3820, 60, depth=280)
    m.climb_face(3180, 60, 340, width=90)
    m.check(3300, 60)
    m.way(3260, 60); m.way(3780, 60)
    m.banana(3500, 60, 3, 0.2)
    # 5. Treetop run: short ledges with gaps, high over the jungle floor.
    for x0, top in [(3920, 20), (4180, -20), (4440, 20), (4700, 60)]:
        m.ledge(x0, x0 + 160, top)
        m.way(x0 + 80, top)
    m.banana(4260, -20, 4, 0.3); m.banana(4780, 60, 2, 0.15)
    # 6. Drop-through descent: fall ledge to ledge.
    for x0, top in [(4960, 150), (5140, 240), (5320, 330)]:
        m.ledge(x0, x0 + 160, top)
        m.way(x0 + 80, top)
    m.ground(5480, 5760, 420)
    m.check(5560, 420)
    m.way(5540, 420)
    # 7. Vine valley over stepping stones.
    for x0, top in [(5860, 450), (6100, 470), (6340, 450)]:
        m.ledge(x0, x0 + 150, top)
        m.way(x0 + 75, top)
        m.banana(x0 + 75, top, 1, 0.1)
    for x in (5980, 6220, 6460):
        m.vine(x, -40, 200)
        m.banana(x, 200, 3, 0.25)
    m.ground(6560, 7050, 420)
    m.check(6640, 420)
    m.way(6620, 420); m.way(7020, 420)
    # 8. Chimney: climb a pillar, cross a ledge, climb the next pillar.
    m.wall(7074, 200, 420, width=48)
    m.way(7074, 200)
    m.ledge(7140, 7300, 200)
    m.way(7220, 200)
    m.wall(7340, -20, 200, width=48)
    m.way(7340, -20)
    m.ground(7420, 8000, -20, depth=120)
    m.check(7500, -20)
    m.way(7480, -20); m.way(7960, -20)
    m.banana(7700, -20, 5, 0.35)
    # 9. The leap down, stair by stair.
    for x0, top in [(8100, 80), (8360, 180), (8620, 280)]:
        m.ledge(x0, x0 + 180, top)
        m.way(x0 + 90, top)
    m.vine(8480, -330, 200)
    m.banana(8480, -100, 4, 0.3)
    m.ground(8900, 9640, 380)
    m.check(8980, 380)
    m.way(8960, 380); m.way(9600, 380)
    # 10. Sprint: one hop over the last gap to the flag.
    m.ledge(9720, 9840, 400)
    m.way(9780, 400)
    m.vine(9800, -100, 200)
    m.ground(9920, 10700, 380)
    m.way(9980, 380)
    m.finish(10500, 380)
    m.way(10500, 380)
    m.banana(10200, 380, 2, 0.2)
    m.bound(10724, -1400, 480)
    return m


def canopy_climb():
    """Vertical parkour up a jungle shaft: stairs, a climbing pillar, a
    spring, a wall, more stairs, a big spring and a last pillar to the
    summit. No ledge hangs over a place you jump from, and every spring
    lands on a platform that reaches back out over it."""
    m = Map('MapB', 'Canopy Climb', spawn=(-940, 440), axis=(0, -1), kill=900, stride=(60, 0), palette=2)
    m.ground(-1000, 1000, 500)
    m.bound(-1024, -2800, 500)
    m.bound(1024, -2800, 500)
    m.banana(0, 500); m.banana(700, 500)

    def stairs(steps):
        for x0, x1, top in steps:
            m.ledge(x0, x1, top)
            m.way((x0 + x1) / 2, top)

    # 1. Stairs up to the first landing. Rise 70, gaps 40.
    stairs([(-760, -600, 430), (-560, -400, 360), (-360, -200, 290)])
    m.ground(-160, 400, 220, depth=60)
    m.way(-120, 220); m.way(380, 220)
    m.check(0, 220)
    m.banana(-480, 360, 2, 0.15); m.banana(200, 220, 2, 0.15)
    # 2. Climb the pillar at the landing's end, then spring from its ledge.
    m.wall(440, -150, 220, width=48)
    m.way(440, -150)
    # The spring sits 180 px out from the landing above, so a light monkey
    # drifting back in on the way up clears the landing's edge.
    m.ledge(500, 780, -150)
    m.way(560, -150)
    m.pad(720, -150, 1500)
    m.way(720, -150)
    m.ground(-300, 540, -620, depth=60)
    m.way(460, -620); m.way(-260, -620)
    m.check(100, -620)
    m.banana(650, -400, 4, 0.3)
    # 3. The wall on the left end, then stairs back to the right.
    m.wall(-340, -1000, -620, width=48)
    m.way(-340, -1000)
    stairs([(-280, -100, -1000), (-60, 120, -1070), (160, 320, -1140)])
    m.ground(360, 900, -1210, depth=60)
    m.way(400, -1210); m.way(780, -1210)
    m.check(560, -1210)
    m.banana(-190, -1000, 3, 0.2)
    m.vine(-600, -1400, 220)
    m.banana(-600, -1150, 5, 0.35)
    # 4. The big spring onto the high landing.
    m.pad(820, -1210, 1550)
    m.way(820, -1210)
    m.ground(-200, 640, -1760, depth=60)
    m.way(560, -1760); m.way(-160, -1760)
    m.check(250, -1760)
    m.banana(820, -1500, 4, 0.3)
    # 5. Stairs left, a last pillar, the summit.
    stairs([(-400, -240, -1830), (-600, -440, -1900)])
    m.wall(-700, -2300, -1900, width=48)
    m.way(-700, -2300)
    # The summit starts clear of the pillar, so climbing its right face
    # never bumps the summit's underside.
    m.ground(-600, 300, -2300, depth=60)
    m.way(-560, -2300)
    m.vine(500, -2560, 220)
    m.finish(0, -2300, w=260, h=90)
    m.way(0, -2300)
    return m


def slap_island():
    """2v2 Slap, a platform-fighter stage: one big island in the middle,
    a small island off each side, floating platforms above, vines to swing
    across the gaps, and climbable cliff faces so a monkey knocked over the
    edge can grab on and haul itself back."""
    m = Map('SlapArena', 'Slap Island', spawn=(-420, 240), kill=720, stride=(280, 0))
    m.blast = 1450
    # The main island and its climbable sides.
    m.ground(-560, 560, 300, depth=120)
    m.climb_face(-560, 300, 420, width=40)
    m.climb_face(560, 300, 420, width=40)
    # Side islands, a little higher, with their inner faces climbable.
    m.ground(-1080, -780, 240, depth=80)
    m.ground(780, 1080, 240, depth=80)
    m.climb_face(-780, 240, 320, width=40)
    m.climb_face(780, 240, 320, width=40)
    # Floating platforms: two low, one high in the middle, two over the
    # side islands.
    m.ledge(-400, -180, 140); m.ledge(180, 400, 140)
    m.ledge(-110, 110, -10)
    m.ledge(-1010, -850, 80); m.ledge(850, 1010, 80)
    # Vines over the gaps and one over the middle.
    m.vine(-670, -120, 220)
    m.vine(670, -120, 220)
    m.vine(0, -300, 180)
    for x, top in [(-300, 300), (300, 300), (-290, 140), (290, 140), (0, -10), (0, 300), (-930, 240), (930, 240)]:
        m.banana(x, top, 2, 0.3)
    m.way(-420, 300); m.way(420, 300)
    return m


def banana_grove():
    """Banana Hoard. One big square jungle rather than a long run: a full
    floor, five tiers of platforms stacked above it, climbing walls at both
    ends, springs to the upper tiers and vines between them. Tiers are 140
    px apart, so one plain jump reaches the next one; the double jump is
    spare. Bananas are spread over every tier, richer the higher you go."""
    m = Map('BananaGrove', 'Banana Grove', spawn=(-150, 460), kill=1100, stride=(100, 0), palette=4)
    floor, t1, t2, t3, t4, t5 = 520, 380, 240, 100, -40, -180
    m.bound(-1624, -1400, 620)
    m.bound(1624, -1400, 620)
    m.ground(-1600, 1600, floor)
    # Climbing walls at the ends reach the top tier.
    m.wall(-1560, t5, floor, width=48)
    m.wall(1560, t5, floor, width=48)
    # Springs: two into the middle, two at the ends up to tier 3.
    for x in (-1300, -480, 480, 1300):
        m.pad(x, floor, 1350)
    # Tier 1: four wide ledges.
    t1_ledges = [(-1400, -1000), (-560, -160), (160, 560), (1000, 1400)]
    for x0, x1 in t1_ledges:
        m.ledge(x0, x1, t1)
    # Tier 2: three islands, thick so trees grow on them.
    t2_islands = [(-1180, -700), (-260, 260), (700, 1180)]
    for x0, x1 in t2_islands:
        m.ground(x0, x1, t2, depth=60)
    # Tier 3: four ledges.
    t3_ledges = [(-1480, -1080), (-560, -220), (220, 560), (1080, 1480)]
    for x0, x1 in t3_ledges:
        m.ledge(x0, x1, t3)
    # Tier 4: two islands and a middle ledge.
    m.ground(-1000, -560, t4, depth=60)
    m.ground(560, 1000, t4, depth=60)
    m.ledge(-160, 160, t4)
    # Tier 5: the top perches, joined to the walls.
    m.ledge(-1500, -1200, t5)
    m.ledge(1200, 1500, t5)
    m.ledge(-220, 220, t5)
    # Vines over the middle gaps near the top.
    for x in (-400, 400):
        m.vine(x, -520, 200)
    # Bananas everywhere, richer the higher you go.
    for x in range(-1400, 1500, 200):
        if abs(abs(x) - 480) > 60 and abs(abs(x) - 1300) > 60:
            m.banana(x, floor, 1, 0.08)
    for x0, x1 in t1_ledges:
        m.banana((x0 + x1) / 2, t1, 2, 0.12)
    for x0, x1 in t2_islands:
        m.banana(x0 + 80, t2, 2, 0.15)
        m.banana(x1 - 80, t2, 2, 0.15)
    for x0, x1 in t3_ledges:
        m.banana((x0 + x1) / 2, t3, 3, 0.2)
    for x in (-780, 780, 0):
        m.banana(x, t4, 4, 0.25)
    for x in (-1350, 1350, 0):
        m.banana(x, t5, 5, 0.35)
    # A loop for the bots: floor, springs, round the tiers and back.
    for x, top in [(-1200, floor), (-480, floor), (-600, t1), (-940, t2), (-780, t4), (0, t4), (780, t4),
                   (940, t2), (480, floor), (0, floor)]:
        m.way(x, top)
    return m


if __name__ == '__main__':
    root = sys.argv[1] if len(sys.argv) > 1 else '.'
    jungle_run().write(root + '/scenes/maps/MapA.tscn')
    canopy_climb().write(root + '/scenes/maps/MapB.tscn')
    slap_island().write(root + '/scenes/maps/SlapArena.tscn')
    banana_grove().write(root + '/scenes/maps/BananaGrove.tscn')
    print('maps written')
