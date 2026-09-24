extends Node

# ============================================================
# PURCHASES - RevenueCat wrapper.
#
# Plugin: GodotX RevenueCat (MIT, bundles the RevenueCat Android SDK).
# Target is the RevenueCat Test Store, not Google Play Billing: the Test
# Store needs no Play Console account, no products configured in a store,
# and still produces real CustomerInfo, real entitlements, and a real row
# in the RevenueCat dashboard. That is what the submission has to show.
#
# Five products, set up in the RevenueCat dashboard (project Primal Rush):
#   monkey_plus_v2     non-consumable  -> entitlement "monkey_plus"
#   starter_pack_v2    non-consumable  -> entitlement "starter_pack"
#   bananas_small_v2   consumable      -> 300 bananas
#   bananas_medium_v2  consumable      -> 1,100 bananas
#   bananas_large_v3   consumable      -> 3,000 bananas
# (The _v2/_v3 suffixes exist because Test Store prices cannot be edited:
# the first versions were retired and recreated at the right price.)
#
# Entitlements are the source of truth for the two unlocks. Bananas are a
# soft currency kept on the device (see Loot); a consumable only adds to it.
#
# The singleton does not exist in the editor, so every call is guarded and
# the desktop build grants purchases directly, so the whole shop can be
# built and demoed without a phone in hand.
# ============================================================

signal entitlement_changed(unlocked: bool)
signal purchase_finished(success: bool, message: String)
signal products_ready(products: Variant)
## A product's localized price arrived from RevenueCat.
signal prices_changed

const ENTITLEMENT_PLUS: String = "monkey_plus"
const ENTITLEMENT_STARTER: String = "starter_pack"

const PRODUCT_PLUS: String = "monkey_plus_v2"
const PRODUCT_STARTER: String = "starter_pack_v2"
const PRODUCT_BANANAS_S: String = "bananas_small_v2"
const PRODUCT_BANANAS_M: String = "bananas_medium_v2"
const PRODUCT_BANANAS_L: String = "bananas_large_v3"

## Bananas each consumable adds (bonus included).
const BANANA_PACKS: Dictionary = {
	PRODUCT_BANANAS_S: 300,
	PRODUCT_BANANAS_M: 1100,
	PRODUCT_BANANAS_L: 3000,
}

## Shown until RevenueCat answers (and on desktop, where it never does).
const FALLBACK_PRICES: Dictionary = {
	PRODUCT_PLUS: "$4.99",
	PRODUCT_STARTER: "$0.99",
	PRODUCT_BANANAS_S: "$0.99",
	PRODUCT_BANANAS_M: "$2.99",
	PRODUCT_BANANAS_L: "$6.99",
}

## Where the Test Store key is read from, in priority order. The key never
## lives in source: secrets.cfg is gitignored.
const SECRETS_PATH: String = "res://secrets.cfg"
const ENV_VAR: String = "REVENUECAT_TEST_KEY"

var _rc: Object = null
var _plus: bool = false
var _starter: bool = false
var _pending_product: String = ""
var _prices: Dictionary = {}


func _ready() -> void:
	_load_local_entitlements()
	if not Engine.has_singleton("GodotxRevenueCat"):
		# Expected in the editor and on any desktop build. Not an error.
		print_rich("[color=gray]RevenueCat singleton absent - store features run in stub mode.[/color]")
		return
	_rc = Engine.get_singleton("GodotxRevenueCat")
	_connect_signals()

	var key := _read_api_key()
	if key.is_empty():
		push_warning("No RevenueCat key found. Add %s or set %s." % [SECRETS_PATH, ENV_VAR])
		return
	# Third argument is the plugin's debug flag: verbose logs while the
	# purchase flow is being proven on a device.
	_rc.call("initialize", key, "", true)
	_refresh_entitlements()
	fetch_products()


func _connect_signals() -> void:
	# Signal names differ between plugin versions often enough that blind
	# connects are a startup crash waiting to happen.
	for entry in [
		["purchase_result", _on_purchase_result],
		["entitlement", _on_entitlement],
		["customer_info_changed", _on_customer_info_changed],
		["products", _on_products],
		["restore_finished", _on_restore_finished],
	]:
		var signal_name: String = entry[0]
		if _rc.has_signal(signal_name):
			_rc.connect(signal_name, entry[1])
		else:
			push_warning("RevenueCat plugin has no signal '%s'." % signal_name)


# --- What the game asks ----------------------------------------------

## Monkey Plus. Kept under the old name: the premium monkey, skins and
## hats have always asked has_premium(), and Monkey Plus is that unlock.
func has_premium() -> bool:
	return _plus


func has_plus() -> bool:
	return _plus


func has_starter() -> bool:
	return _starter


func price_of(product_id: String) -> String:
	return String(_prices.get(product_id, FALLBACK_PRICES.get(product_id, "")))


func is_busy() -> bool:
	return not _pending_product.is_empty()


# --- Buying ----------------------------------------------------------

func buy(product_id: String) -> void:
	if is_busy():
		return
	if (product_id == PRODUCT_PLUS and _plus) or (product_id == PRODUCT_STARTER and _starter):
		purchase_finished.emit(false, "Already owned")
		return
	if _rc == null:
		# Desktop stub: grant directly so the shop can be tested without a
		# phone. Never reached on a device with the plugin.
		_grant(product_id)
		purchase_finished.emit(true, _thanks_for(product_id))
		return
	_pending_product = product_id
	_rc.call("purchase", product_id)


## Kept for callers from before the shop had more than one product.
func buy_premium() -> void:
	buy(PRODUCT_PLUS)


func restore() -> void:
	if _rc == null:
		purchase_finished.emit(false, "No store on this platform")
		return
	_rc.call("restore_purchases")


func fetch_products() -> void:
	if _rc != null:
		_rc.call("fetch_products", [PRODUCT_PLUS, PRODUCT_STARTER, PRODUCT_BANANAS_S, PRODUCT_BANANAS_M, PRODUCT_BANANAS_L])


# --- Granting --------------------------------------------------------

func _grant(product_id: String) -> void:
	match product_id:
		PRODUCT_PLUS:
			_set_plus(true)
		PRODUCT_STARTER:
			_set_starter(true)
		_:
			if BANANA_PACKS.has(product_id):
				Loot.add_bananas(int(BANANA_PACKS[product_id]))


func _thanks_for(product_id: String) -> String:
	match product_id:
		PRODUCT_PLUS:
			return "Monkey Plus unlocked!"
		PRODUCT_STARTER:
			return "Starter Pack unlocked!"
	if BANANA_PACKS.has(product_id):
		return "+%d bananas!" % int(BANANA_PACKS[product_id])
	return "Purchase complete"


func _set_plus(value: bool) -> void:
	if value == _plus:
		return
	_plus = value
	_save_local_entitlements()
	if value:
		Loot.on_plus_unlocked()
	entitlement_changed.emit(value)


func _set_starter(value: bool) -> void:
	if value == _starter:
		return
	_starter = value
	_save_local_entitlements()
	if value:
		Loot.on_starter_unlocked()
	entitlement_changed.emit(_plus)


func _refresh_entitlements() -> void:
	if _rc == null:
		return
	if _rc.has_method("has_entitlement"):
		_set_plus(bool(_rc.call("has_entitlement", ENTITLEMENT_PLUS)))
		_set_starter(bool(_rc.call("has_entitlement", ENTITLEMENT_STARTER)))
	else:
		_rc.call("check_entitlement", ENTITLEMENT_PLUS)
		_rc.call("check_entitlement", ENTITLEMENT_STARTER)


# --- Plugin callbacks ------------------------------------------------

func _on_purchase_result(result: Variant) -> void:
	var product := _pending_product
	_pending_product = ""
	var ok := _result_looks_successful(result)
	if ok:
		_grant(product)
		_refresh_entitlements()
		purchase_finished.emit(true, _thanks_for(product))
	else:
		purchase_finished.emit(false, _error_text(result))


## The plugin sends (id, active). Older builds sent one dictionary.
func _on_entitlement(id: Variant, active: Variant = null) -> void:
	var on := _entitlement_active(id) if active == null else bool(active)
	var which := String(id) if active != null else ""
	if which == ENTITLEMENT_STARTER:
		_set_starter(on)
	elif which == ENTITLEMENT_PLUS or which.is_empty():
		_set_plus(on)


func _on_customer_info_changed(info: Variant) -> void:
	if info is Dictionary and (info as Dictionary).has("entitlements"):
		_set_plus(_has_active(info, ENTITLEMENT_PLUS))
		_set_starter(_has_active(info, ENTITLEMENT_STARTER))
	else:
		_refresh_entitlements()


func _on_restore_finished(info: Variant) -> void:
	_refresh_entitlements()
	var restored := info is Dictionary and bool((info as Dictionary).get("restored", false))
	purchase_finished.emit(restored, "Purchases restored" if restored else "Nothing to restore")


func _on_products(data: Variant) -> void:
	var list: Array = []
	if data is Dictionary:
		var raw: Variant = (data as Dictionary).get("products", null)
		if raw is Array:
			list = raw
		elif raw is Object and (raw as Object).has_method("size"):
			for i in int(raw.call("size")):
				list.append(raw.call("get", i))
	for product in list:
		if product is Dictionary and (product as Dictionary).has("id"):
			_prices[String(product["id"])] = String((product as Dictionary).get("price", ""))
	products_ready.emit(list)
	prices_changed.emit()


# --- Result parsing --------------------------------------------------
#
# The plugin hands back plain dictionaries whose shape is not contractual,
# so both helpers are written to be wrong-shape tolerant.

func _result_looks_successful(result: Variant) -> bool:
	if result is bool:
		return result
	if result is Dictionary:
		if result.has("success"):
			return bool(result["success"])
		if result.has("cancelled") and bool(result["cancelled"]):
			return false
		if result.has("error") and result["error"] != null and str(result["error"]) != "":
			return false
		return true
	return false


func _error_text(result: Variant) -> String:
	if result is Dictionary:
		if bool((result as Dictionary).get("cancelled", false)):
			return "Cancelled"
		var error := str((result as Dictionary).get("error", ""))
		if not error.is_empty():
			return error
	return "Purchase did not complete"


func _entitlement_active(info: Variant) -> bool:
	if info is bool:
		return info
	if info is Dictionary:
		if info.has("active"):
			return bool(info["active"])
		return _has_active(info, ENTITLEMENT_PLUS)
	return false


func _has_active(info: Dictionary, entitlement: String) -> bool:
	var ents: Variant = info.get("entitlements", null)
	if ents is Dictionary and (ents as Dictionary).has(entitlement):
		var ent: Variant = ents[entitlement]
		if ent is Dictionary:
			return bool(ent.get("isActive", ent.get("active", true)))
		return true
	if ents is Array:
		return (ents as Array).has(entitlement)
	return info.has(entitlement)


# --- Key and cache ---------------------------------------------------

func _read_api_key() -> String:
	var env := OS.get_environment(ENV_VAR)
	if not env.is_empty():
		return env
	var cfg := ConfigFile.new()
	if cfg.load(SECRETS_PATH) == OK:
		return str(cfg.get_value("revenuecat", "test_key", ""))
	return ""


## Cached locally so a relaunch without network does not visibly relock
## content the player already owns. RevenueCat remains the source of truth
## and overwrites this as soon as it answers.
func _save_local_entitlements() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("entitlements", ENTITLEMENT_PLUS, _plus)
	cfg.set_value("entitlements", ENTITLEMENT_STARTER, _starter)
	cfg.save("user://entitlements.cfg")


func _load_local_entitlements() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://entitlements.cfg") == OK:
		_plus = bool(cfg.get_value("entitlements", ENTITLEMENT_PLUS, cfg.get_value("entitlements", "premium_monkeys", false)))
		_starter = bool(cfg.get_value("entitlements", ENTITLEMENT_STARTER, false))
