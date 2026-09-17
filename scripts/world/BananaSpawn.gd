class_name BananaSpawn
extends Marker2D

# ============================================================
# BANANA SPAWN - a place bananas appear, with a payout.
#
# Value is set by the level designer, not by height maths, because "hard to
# reach" is about the route, not the altitude. A banana behind a swing you
# have to chain twice is worth more than one on a taller but trivial ledge.
# ============================================================

## Points awarded. Higher spawns should be harder to reach, not just higher.
@export_range(1, 5, 1) var value: int = 1
## Odds this spawn produces a lucky box instead of bananas.
@export_range(0.0, 1.0, 0.05) var lucky_chance: float = 0.12


func _ready() -> void:
	add_to_group(&"banana_spawn")
