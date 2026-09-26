extends Node

# ============================================================
# LOOT - the banana wallet, the cosmetics you own, and the gacha.
#
# Bananas are the soft currency: matches pay them, banana packs from the
# shop add them, and a pull costs PULL_COST. The random part only ever costs
# bananas, never real money directly.
#
# Four effect slots, each with its own items: TRAIL (behind you while you
# run), PUNCH (where your fist lands), CLIMB (while climbing and grabbing)
# and WIN (when you win). The premium skins and hats are in the pool too.
# Items marked "plus" only drop for Monkey Plus owners.
#
# Odds are fixed and shown on the gacha screen. A duplicate is refunded as
# bananas, so no pull is wasted. Monkey Plus also gives one free pull a day.
#
# All local to this device (user://loot.cfg), like the career stats: in a
# game with a backend this is what would sync, not what would be trusted.
# ============================================================

signal wallet_changed(bananas: int)
signal owned_changed
signal equipped_changed

const SAVE_PATH: String = "user://loot.cfg"
const PULL_COST: int = 100
const TEN_PULL_COST: int = 900
const START_BANANAS: int = 200
const DUPLICATE_REFUND: Array[int] = [25, 60, 150, 400]

enum Rarity { COMMON, RARE, LEGENDARY, MYTHIC }
const RARITY_NAMES: Array[String] = ["COMMON", "RARE", "LEGENDARY", "MYTHIC"]
const RARITY_COLORS: Array[Color] = [Color8(200, 210, 225), Color8(90, 170, 255), Color8(255, 196, 52), Color8(255, 80, 190)]
## Chance of each rarity per pull, in percent.
const ODDS: Array[float] = [64.0, 28.0, 7.0, 1.0]

const SLOTS: Array[StringName] = [&"trail", &"punch", &"climb", &"win"]
const SLOT_NAMES: Dictionary = {&"trail": "TRAIL", &"punch": "PUNCH", &"climb": "CLIMB", &"win": "WIN"}

## Every item. slot: an effect slot, or "skin"/"hat" for the existing looks.
const ITEMS: Dictionary = {
	# Trails
	&"trail_dust": {"slot": &"trail", "name": "Dust Kick", "rarity": Rarity.COMMON, "plus": false},
	&"trail_leaves": {"slot": &"trail", "name": "Leaf Swirl", "rarity": Rarity.RARE, "plus": false},
	&"trail_fire": {"slot": &"trail", "name": "Jungle Fire", "rarity": Rarity.LEGENDARY, "plus": false},
	&"trail_rainbow": {"slot": &"trail", "name": "Rainbow Dash", "rarity": Rarity.LEGENDARY, "plus": true},
	# Punch
	&"punch_sparks": {"slot": &"punch", "name": "Sparks", "rarity": Rarity.COMMON, "plus": false},
	&"punch_stars": {"slot": &"punch", "name": "Seeing Stars", "rarity": Rarity.RARE, "plus": false},
	&"punch_banana": {"slot": &"punch", "name": "Banana Burst", "rarity": Rarity.RARE, "plus": true},
	&"punch_thunder": {"slot": &"punch", "name": "Thunder Fist", "rarity": Rarity.LEGENDARY, "plus": false},
	# Climb
	&"climb_puff": {"slot": &"climb", "name": "Leaf Puff", "rarity": Rarity.COMMON, "plus": false},
	&"climb_sparkle": {"slot": &"climb", "name": "Sparkle Grip", "rarity": Rarity.RARE, "plus": false},
	&"climb_hearts": {"slot": &"climb", "name": "Hearts", "rarity": Rarity.RARE, "plus": false},
	&"climb_gold": {"slot": &"climb", "name": "Golden Grip", "rarity": Rarity.LEGENDARY, "plus": true},
	# Win
	&"win_confetti": {"slot": &"win", "name": "Confetti", "rarity": Rarity.COMMON, "plus": false},
	&"win_bananas": {"slot": &"win", "name": "Banana Rain", "rarity": Rarity.RARE, "plus": false},
	&"win_fireworks": {"slot": &"win", "name": "Fireworks", "rarity": Rarity.LEGENDARY, "plus": false},
	&"win_crown": {"slot": &"win", "name": "Crown Storm", "rarity": Rarity.LEGENDARY, "plus": true},
	# Looks from the style screen that can also drop
	&"skin_midnight": {"slot": &"skin", "name": "Midnight Skin", "rarity": Rarity.RARE, "plus": false, "look": &"midnight"},
	&"skin_golden": {"slot": &"skin", "name": "Golden Skin", "rarity": Rarity.LEGENDARY, "plus": false, "look": &"golden"},
	&"skin_night_swinger": {"slot": &"skin", "name": "Night Swinger", "rarity": Rarity.MYTHIC, "plus": false, "look": &"night_swinger"},
	&"skin_molten_titan": {"slot": &"skin", "name": "Molten Titan", "rarity": Rarity.MYTHIC, "plus": false, "look": &"molten_titan"},
	&"hat_tophat": {"slot": &"hat", "name": "Top Hat", "rarity": Rarity.RARE, "plus": false, "look": &"tophat"},
	&"hat_halo": {"slot": &"hat", "name": "Halo", "rarity": Rarity.LEGENDARY, "plus": false, "look": &"halo"},
	&"hat_crown": {"slot": &"hat", "name": "Crown", "rarity": Rarity.LEGENDARY, "plus": true, "look": &"crown"},
}

## What everyone starts with, so every slot has something equipped.
const FREE_ITEMS: Array[StringName] = [&"trail_dust", &"punch_sparks", &"climb_puff", &"win_confetti"]
## What the Starter Pack gives, on top of its bananas.
const STARTER_ITEMS: Array[StringName] = [&"skin_midnight", &"trail_leaves"]
const STARTER_BANANAS: int = 300
const PLUS_BANANAS: int = 500

var bananas: int = START_BANANAS
var owned: Dictionary = {}          # item id -> true
var equipped: Dictionary = {}       # slot -> item id
## Bananas the last finished match paid out, for the results screen.
var last_reward: int = 0
var _last_free_day: String = ""
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_load()
	for id in FREE_ITEMS:
		owned[id] = true
	for slot in SLOTS:
		if not equipped.has(slot):
			equipped[slot] = _first_owned_in(slot)


# --- Wallet ----------------------------------------------------------

func add_bananas(amount: int) -> void:
	bananas = maxi(bananas + amount, 0)
	_save()
	wallet_changed.emit(bananas)


func spend(amount: int) -> bool:
	if bananas < amount:
		return false
	bananas -= amount
	_save()
	wallet_changed.emit(bananas)
	return true


## Pay-out for one finished match, by place (1 is first). Every monkey gets
## something, the winner gets the most; banana hoard scores are added on top.
func reward_match(place: int, field: int, extra: int = 0) -> int:
	var table := [100, 40, 25, 15]
	var amount := int(table[clampi(place - 1, 0, table.size() - 1)]) if field > 1 else 20
	amount += maxi(extra, 0)
	last_reward = amount
	add_bananas(amount)
	return amount


# --- Ranked stake ----------------------------------------------------
#
# In a ranked match you can put bananas on yourself. The stake is taken when
# the match starts and paid back by how you finish: 1st triples it, 2nd
# gets one and a half times, 3rd gets half back, 4th loses it. In 2v2 a win
# doubles it, a draw returns it, a loss loses it.

const STAKES: Array[int] = [0, 50, 100, 250, 500]
const STAKE_PAYOUT: Array[float] = [3.0, 1.5, 0.5, 0.0]

## What the player chose for the next ranked match.
var stake: int = 0
## Taken from the wallet for the match in progress.
var _stake_locked: int = 0
## For the results screen: {"stake": int, "payout": int}. Empty if none.
var last_stake: Dictionary = {}


func set_stake(amount: int) -> void:
	stake = amount if STAKES.has(amount) else 0
	_save()


## Called when a ranked match starts. Takes the stake if you can afford it.
func lock_stake() -> void:
	_stake_locked = 0
	last_stake = {}
	if stake > 0 and spend(stake):
		_stake_locked = stake


## Called with the local player's finish. Returns the payout.
func settle_stake(place: int, won: bool, draw: bool, team_mode: bool) -> int:
	if _stake_locked <= 0:
		return 0
	var multiplier := 0.0
	if team_mode:
		multiplier = 1.0 if draw else (2.0 if won else 0.0)
	else:
		multiplier = STAKE_PAYOUT[clampi(place - 1, 0, STAKE_PAYOUT.size() - 1)]
	var payout := int(round(_stake_locked * multiplier))
	last_stake = {"stake": _stake_locked, "payout": payout}
	_stake_locked = 0
	if payout > 0:
		add_bananas(payout)
	return payout


# --- Owning and equipping --------------------------------------------

func owns(id: StringName) -> bool:
	return owned.has(id)


## A premium look counts as unlocked if the gacha dropped it.
func owns_look(slot: StringName, look: StringName) -> bool:
	for id in owned.keys():
		var entry: Dictionary = ITEMS.get(id, {})
		if entry.get("slot", &"") == slot and entry.get("look", &"") == look:
			return true
	return false


func equipped_in(slot: StringName) -> StringName:
	return StringName(equipped.get(slot, &""))


func equip(id: StringName) -> void:
	if not owns(id) or not ITEMS.has(id):
		return
	var slot: StringName = ITEMS[id]["slot"]
	if not SLOTS.has(slot):
		return
	equipped[slot] = id
	_save()
	equipped_changed.emit()


func items_in(slot: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in ITEMS.keys():
		if ITEMS[id]["slot"] == slot:
			out.append(id)
	return out


func item(id: StringName) -> Dictionary:
	return ITEMS.get(id, {})


# --- Gacha -----------------------------------------------------------

func can_pull(count: int = 1) -> bool:
	return bananas >= (PULL_COST if count == 1 else TEN_PULL_COST)


func has_free_pull() -> bool:
	return Purchases.has_plus() and _last_free_day != _today()


## Pays and pulls. Returns one result per pull:
## {id, rarity, new, refund}. Empty if the wallet is short.
func pull(count: int = 1, free: bool = false) -> Array:
	if free:
		if not has_free_pull():
			return []
		_last_free_day = _today()
		count = 1
	elif not spend(PULL_COST if count == 1 else TEN_PULL_COST):
		return []
	var results: Array = []
	for i in count:
		# The tenth pull of a ten-pull is at least rare.
		var floor_rarity := Rarity.RARE if count >= 10 and i == count - 1 else Rarity.COMMON
		results.append(_pull_one(floor_rarity))
	_save()
	owned_changed.emit()
	return results


func _pull_one(floor_rarity: int) -> Dictionary:
	var roll := _rng.randf() * 100.0
	var rarity: int = Rarity.COMMON
	if roll < ODDS[3]:
		rarity = Rarity.MYTHIC
	elif roll < ODDS[3] + ODDS[2]:
		rarity = Rarity.LEGENDARY
	elif roll < ODDS[3] + ODDS[2] + ODDS[1]:
		rarity = Rarity.RARE
	rarity = maxi(rarity, floor_rarity)
	var pool: Array[StringName] = []
	for id in ITEMS.keys():
		var entry: Dictionary = ITEMS[id]
		if int(entry["rarity"]) != rarity:
			continue
		if bool(entry["plus"]) and not Purchases.has_plus():
			continue
		pool.append(id)
	var id: StringName = pool[_rng.randi() % pool.size()]
	var fresh := not owns(id)
	var refund := 0
	if fresh:
		owned[id] = true
		# First copy of an effect goes straight on: the reveal is more fun
		# when you see it in your next match.
		var slot: StringName = ITEMS[id]["slot"]
		if SLOTS.has(slot):
			equipped[slot] = id
	else:
		refund = DUPLICATE_REFUND[rarity]
		bananas += refund
		wallet_changed.emit(bananas)
	return {"id": id, "rarity": rarity, "new": fresh, "refund": refund}


# --- Purchases -------------------------------------------------------

func on_plus_unlocked() -> void:
	if bool(_flag("plus_bonus_given")):
		return
	_set_flag("plus_bonus_given")
	add_bananas(PLUS_BANANAS)


func on_starter_unlocked() -> void:
	if bool(_flag("starter_given")):
		return
	_set_flag("starter_given")
	for id in STARTER_ITEMS:
		owned[id] = true
	equip(&"trail_leaves")
	add_bananas(STARTER_BANANAS)
	owned_changed.emit()


# --- Save ------------------------------------------------------------

var _flags: Dictionary = {}


func _flag(key: String) -> Variant:
	return _flags.get(key, false)


func _set_flag(key: String) -> void:
	_flags[key] = true
	_save()


func _first_owned_in(slot: StringName) -> StringName:
	for id in FREE_ITEMS:
		if ITEMS[id]["slot"] == slot:
			return id
	return &""


func _today() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("wallet", "bananas", bananas)
	cfg.set_value("wallet", "free_day", _last_free_day)
	cfg.set_value("wallet", "stake", stake)
	var ids: PackedStringArray = []
	for id in owned.keys():
		ids.append(String(id))
	cfg.set_value("items", "owned", ids)
	for slot in equipped.keys():
		cfg.set_value("equipped", String(slot), String(equipped[slot]))
	for key in _flags.keys():
		cfg.set_value("flags", key, _flags[key])
	cfg.save(SAVE_PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	bananas = int(cfg.get_value("wallet", "bananas", START_BANANAS))
	_last_free_day = str(cfg.get_value("wallet", "free_day", ""))
	stake = int(cfg.get_value("wallet", "stake", 0))
	for id in cfg.get_value("items", "owned", PackedStringArray()):
		if ITEMS.has(StringName(id)):
			owned[StringName(id)] = true
	if cfg.has_section("equipped"):
		for slot in cfg.get_section_keys("equipped"):
			var id := StringName(str(cfg.get_value("equipped", slot, "")))
			if owned.has(id) or FREE_ITEMS.has(id):
				equipped[StringName(slot)] = id
	if cfg.has_section("flags"):
		for key in cfg.get_section_keys("flags"):
			_flags[key] = cfg.get_value("flags", key)
