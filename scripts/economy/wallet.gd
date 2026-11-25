class_name Wallet
extends RefCounted
## Currency balances with an append-only transaction log. Every change goes
## through earn() / spend() / spend_many(), which are atomic and reject
## negative, NaN or overflowing amounts. In the online build the Economy
## Service owns balances and this becomes a read-through cache.

signal changed

const MAX_BALANCE := 1_000_000_000_000
const LOG_SIZE := 100

var balances := {}  # currency -> int
var history: Array[Dictionary] = []  # most recent transactions
var totals_earned := {}
var totals_spent := {}
var valid_currencies := {}


func _init(currency_defs: Array = []) -> void:
	for c in currency_defs:
		valid_currencies[String(c.id)] = true


func setup_starting(currency_defs: Array) -> void:
	for c in currency_defs:
		var start := int(c.get("starting", 0))
		if start > 0:
			earn(String(c.id), start, "starting_balance")


func get_balance(currency: String) -> int:
	return int(balances.get(currency, 0))


func can_afford(costs: Dictionary) -> bool:
	for c in costs:
		if int(costs[c]) < 0 or get_balance(c) < int(costs[c]):
			return false
	return true


func earn(currency: String, amount: int, reason: String) -> bool:
	if amount <= 0 or not _valid(currency):
		return false
	var nb := mini(get_balance(currency) + amount, MAX_BALANCE)
	var delta := nb - get_balance(currency)
	balances[currency] = nb
	totals_earned[currency] = int(totals_earned.get(currency, 0)) + delta
	_record(currency, delta, reason)
	return true


func spend(currency: String, amount: int, reason: String) -> bool:
	return spend_many({currency: amount}, reason)


## All-or-nothing multi-currency spend.
func spend_many(costs: Dictionary, reason: String) -> bool:
	for c in costs:
		if not _valid(c) or int(costs[c]) < 0:
			return false
	if not can_afford(costs):
		return false
	for c in costs:
		var amt := int(costs[c])
		if amt == 0:
			continue
		balances[c] = get_balance(c) - amt
		totals_spent[c] = int(totals_spent.get(c, 0)) + amt
		_record(c, -amt, reason)
	return true


func _valid(currency: String) -> bool:
	return valid_currencies.is_empty() or valid_currencies.has(currency)


func _record(currency: String, delta: int, reason: String) -> void:
	history.append({"currency": currency, "delta": delta, "reason": reason, "balance": get_balance(currency)})
	if history.size() > LOG_SIZE:
		history.remove_at(0)
	changed.emit()


## Online build: the server owns some balances. Sets one without touching
## the earned / spent totals (the server already counted those).
func set_balance_from_server(currency: String, amount: int) -> void:
	if not _valid(currency):
		return
	var nb := clampi(amount, 0, MAX_BALANCE)
	if nb == get_balance(currency):
		return
	var delta := nb - get_balance(currency)
	balances[currency] = nb
	_record(currency, delta, "server_sync")


func to_dict() -> Dictionary:
	return {"balances": balances.duplicate(), "earned": totals_earned.duplicate(), "spent": totals_spent.duplicate()}


func load_dict(d: Dictionary) -> void:
	balances.clear()
	for k in d.get("balances", {}):
		if _valid(String(k)):
			balances[String(k)] = clampi(int(d.balances[k]), 0, MAX_BALANCE)
	for k in d.get("earned", {}):
		totals_earned[String(k)] = int(d.earned[k])
	for k in d.get("spent", {}):
		totals_spent[String(k)] = int(d.spent[k])
	changed.emit()
