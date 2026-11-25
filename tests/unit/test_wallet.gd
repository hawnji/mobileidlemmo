extends WbTestCase
## Currency transactions: earn, spend, atomic multi-spend, validation, save.


func _wallet() -> Wallet:
	return Wallet.new(registry().currency_list)


func test_earn_and_spend() -> void:
	var w := _wallet()
	assert_true(w.earn("gold", 100, "test"))
	assert_true(w.spend("gold", 30, "test"))
	assert_eq(w.get_balance("gold"), 70)
	assert_eq(int(w.totals_earned.gold), 100)
	assert_eq(int(w.totals_spent.gold), 30)
	assert_eq(w.history.size(), 2)
	assert_eq(int(w.history[1].delta), -30)


func test_cannot_overspend() -> void:
	var w := _wallet()
	w.earn("gold", 10, "test")
	assert_false(w.spend("gold", 11, "test"))
	assert_eq(w.get_balance("gold"), 10)


func test_rejects_invalid_amounts_and_currencies() -> void:
	var w := _wallet()
	assert_false(w.earn("gold", 0, "x"))
	assert_false(w.earn("gold", -5, "x"))
	assert_false(w.earn("doubloons", 5, "x"))
	w.earn("gold", 10, "x")
	assert_false(w.spend("gold", -5, "x"), "negative spend would mint money")
	assert_eq(w.get_balance("gold"), 10)


func test_spend_many_is_atomic() -> void:
	var w := _wallet()
	w.earn("gold", 100, "x")
	w.earn("gems", 5, "x")
	assert_false(w.spend_many({"gold": 50, "gems": 10}, "x"))
	assert_eq(w.get_balance("gold"), 100, "nothing charged when one currency is short")
	assert_eq(w.get_balance("gems"), 5)
	assert_true(w.spend_many({"gold": 50, "gems": 5}, "x"))
	assert_eq(w.get_balance("gold"), 50)
	assert_eq(w.get_balance("gems"), 0)


func test_balance_is_capped() -> void:
	var w := _wallet()
	w.earn("gold", Wallet.MAX_BALANCE, "x")
	w.earn("gold", 1000, "x")
	assert_eq(w.get_balance("gold"), Wallet.MAX_BALANCE)


func test_save_round_trip_and_tamper_clamp() -> void:
	var w := _wallet()
	w.earn("gold", 123, "x")
	w.earn("gems", 7, "x")
	var w2 := _wallet()
	w2.load_dict(w.to_dict())
	assert_eq(w2.get_balance("gold"), 123)
	assert_eq(w2.get_balance("gems"), 7)
	var w3 := _wallet()
	w3.load_dict({"balances": {"gold": -50, "fake": 99}})
	assert_eq(w3.get_balance("gold"), 0)
	assert_eq(w3.get_balance("fake"), 0)


func test_new_world_has_starting_balances() -> void:
	var w := new_world()
	assert_eq(w.wallet.get_balance("gold"), 200)
	assert_eq(w.wallet.get_balance("gems"), 300)
	assert_eq(w.wallet.get_balance("recruitment_tokens"), 10)
