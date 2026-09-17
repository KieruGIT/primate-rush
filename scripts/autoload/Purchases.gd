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
# The singleton does not exist in the editor, so every call is guarded.
# Unguarded calls crash the desktop build, which is where all the actual
# development happens.
# ============================================================

signal entitlement_changed(unlocked: bool)
signal purchase_finished(success: bool, message: String)
signal products_ready(products: Variant)

## Entitlement identifier configured in the RevenueCat dashboard.
const ENTITLEMENT_ID: String = "premium_monkeys"
## Product identifier from the auto-created Test Store product list.
const PRODUCT_ID: String = "premium_monkeys_unlock"

## Where the Test Store key is read from, in priority order. The key never
## lives in source: secrets.cfg is gitignored, and treating a low-risk test
## key as a secret is the habit that stops a real key leaking later.
const SECRETS_PATH: String = "res://secrets.cfg"
const ENV_VAR: String = "REVENUECAT_TEST_KEY"

var _rc: Object = null
var _unlocked: bool = false
var _pending: bool = false


func _ready() -> void:
	_load_local_entitlement()
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
	# Third argument is the plugin's observer/debug flag; true keeps verbose
	# logging on, which is worth the noise while the purchase is unproven.
	_rc.call("initialize", key, "", true)
	_rc.call("check_entitlement", ENTITLEMENT_ID)


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


func is_available() -> bool:
	return _rc != null


func has_premium() -> bool:
	return _unlocked


func is_purchase_pending() -> bool:
	return _pending


func buy_premium() -> void:
	if _pending:
		return
	if _rc == null:
		# Desktop stub: unlock locally so the rest of the game can be built
		# and tested without a phone in hand. Never reached on device.
		_set_unlocked(true)
		purchase_finished.emit(true, "Stub unlock (no store on this platform)")
		return
	_pending = true
	_rc.call("purchase", PRODUCT_ID)


func restore() -> void:
	if _rc == null:
		purchase_finished.emit(false, "No store on this platform")
		return
	_rc.call("restore_purchases")


func fetch_products() -> void:
	if _rc != null:
		_rc.call("fetch_products", [PRODUCT_ID])


# --- Plugin callbacks ----------------------------------------------

func _on_purchase_result(result: Variant) -> void:
	_pending = false
	var ok := _result_looks_successful(result)
	if ok:
		_set_unlocked(true)
	purchase_finished.emit(ok, str(result))


func _on_entitlement(info: Variant) -> void:
	_set_unlocked(_entitlement_active(info))


func _on_customer_info_changed(info: Variant) -> void:
	_set_unlocked(_entitlement_active(info))


func _on_restore_finished(info: Variant) -> void:
	_set_unlocked(_entitlement_active(info))
	purchase_finished.emit(_unlocked, "Restore finished")


func _on_products(products: Variant) -> void:
	products_ready.emit(products)


# --- Result parsing ------------------------------------------------
#
# The plugin hands back plain dictionaries whose shape is not contractual,
# so both helpers are written to be wrong-shape tolerant rather than to
# assume a schema that a plugin update can change.

func _result_looks_successful(result: Variant) -> bool:
	if result is bool:
		return result
	if result is Dictionary:
		if result.has("success"):
			return bool(result["success"])
		if result.has("error") and result["error"] != null and str(result["error"]) != "":
			return false
		return _entitlement_active(result)
	return false


func _entitlement_active(info: Variant) -> bool:
	if info is bool:
		return info
	if info is Dictionary:
		if info.has("active"):
			return bool(info["active"])
		if info.has("entitlements"):
			var ents: Variant = info["entitlements"]
			if ents is Dictionary and ents.has(ENTITLEMENT_ID):
				var ent: Variant = ents[ENTITLEMENT_ID]
				if ent is Dictionary:
					return bool(ent.get("isActive", ent.get("active", true)))
				return true
			if ents is Array:
				return ents.has(ENTITLEMENT_ID)
		if info.has(ENTITLEMENT_ID):
			return true
	return false


func _set_unlocked(value: bool) -> void:
	if value == _unlocked:
		return
	_unlocked = value
	_save_local_entitlement()
	entitlement_changed.emit(value)


# --- Key and cache -------------------------------------------------

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
func _save_local_entitlement() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("entitlements", ENTITLEMENT_ID, _unlocked)
	cfg.save("user://entitlements.cfg")


func _load_local_entitlement() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://entitlements.cfg") == OK:
		_unlocked = bool(cfg.get_value("entitlements", ENTITLEMENT_ID, false))
