class_name InventoryPanel
extends ModalPanel
## Character bag (title shows used/capacity) or shared storage (with search
## and sort), depending on which inventory is passed in.

var registry: DataRegistry
var inventory: Inventory
var is_storage := false
var _grid: ItemGrid
var _summary: Label
var _title_base := ""
var world: SimulationWorld
var _actions: VBoxContainer
var _selected_item := ""
var _mail_btn: Button


func setup(p_registry: DataRegistry, p_inventory: Inventory, title: String, p_is_storage := false, p_world: SimulationWorld = null) -> void:
	world = p_world
	registry = p_registry
	inventory = p_inventory
	is_storage = p_is_storage
	_title_base = title
	set_title(title)
	_summary = UiTheme.label("", 20, UiTheme.TEXT_DIM)
	body.add_child(_summary)
	if is_storage:
		var tools := HBoxContainer.new()
		var search := LineEdit.new()
		search.placeholder_text = "Search items"
		search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		search.custom_minimum_size = Vector2(0, 52)
		search.text_changed.connect(func(t: String) -> void:
			_grid.filter_text = t
			refresh())
		tools.add_child(search)
		var sort := OptionButton.new()
		sort.custom_minimum_size = Vector2(170, 52)
		for s in ["Name", "Quantity", "Category"]:
			sort.add_item(s)
		sort.item_selected.connect(func(i: int) -> void:
			_grid.sort_mode = i
			refresh())
		tools.add_child(sort)
		body.add_child(tools)
	if is_storage and world:
		_mail_btn = UiTheme.button("", 18)
		_mail_btn.pressed.connect(func() -> void:
			world.claim_mailbox()
			refresh())
		body.add_child(_mail_btn)
	_actions = VBoxContainer.new()
	body.add_child(_actions)
	_grid = ItemGrid.new()
	_grid.registry = registry
	if world and is_storage:
		_grid.favorites = world.favorite_items
		_grid.locked = world.locked_items
		_grid.item_pressed.connect(func(id: String) -> void:
			_selected_item = id
			_show_actions())
	body.add_child(_grid)
	inventory.changed.connect(refresh)
	refresh()


func refresh() -> void:
	if not is_instance_valid(_grid):
		return
	var shown := _grid.show_items(inventory.items())
	if is_storage:
		_summary.text = "%d item types (%d slots), %s items total" % [inventory.distinct_count(), inventory.max_distinct, ItemGrid._fmt(inventory.total_units())]
	else:
		_summary.text = "%d / %d carried" % [inventory.total_units(), inventory.max_units]
	if shown == 0:
		_summary.text += "   (empty)" if inventory.is_empty() else "   (no matches)"
	if _mail_btn:
		var mail := 0
		for it in world.mailbox:
			mail += int(world.mailbox[it])
		_mail_btn.visible = mail > 0
		_mail_btn.text = "Mailbox: %d reward items waiting (storage was full). Move to storage" % mail


## Sell / lock / favourite / equip actions for the tapped storage item.
func _show_actions() -> void:
	for c in _actions.get_children():
		c.queue_free()
	if world == null or _selected_item.is_empty() or inventory.get_quantity(_selected_item) <= 0:
		return
	var id := _selected_item
	var item: Dictionary = registry.items.get(id, {})
	var qty := inventory.get_quantity(id)
	var head := UiTheme.label("%s x%d  -  sells for %d gold each" % [item.get("name", id), qty, world.sell_price(id)], 20, UiTheme.ACCENT)
	_actions.add_child(head)
	var d := UiTheme.label(String(item.get("description", "")), 15, UiTheme.TEXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_actions.add_child(d)
	var row := HBoxContainer.new()
	var amounts: Array = [[1, "Sell 1"]]
	if qty >= 10:
		amounts.append([10, "Sell 10"])
	if qty > 1:
		amounts.append([qty, "Sell all"])
	for spec in amounts:
		var amount: int = spec[0]
		var b := UiTheme.button(spec[1], 17)
		b.disabled = world.locked_items.has(id)
		b.pressed.connect(func() -> void:
			var err := world.sell_item(id, amount)
			if not err.is_empty():
				head.text = err
			refresh()
			_show_actions())
		row.add_child(b)
	var lock := UiTheme.button("Unlock" if world.locked_items.has(id) else "Lock", 17)
	lock.pressed.connect(func() -> void:
		world.set_item_locked(id, not world.locked_items.has(id))
		refresh()
		_show_actions())
	row.add_child(lock)
	var fav := UiTheme.button("Unfavourite" if world.favorite_items.has(id) else "Favourite", 17)
	fav.pressed.connect(func() -> void:
		world.set_item_favorite(id, not world.favorite_items.has(id))
		refresh()
		_show_actions())
	row.add_child(fav)
	_actions.add_child(row)
	if item.get("unlocks") is Dictionary:
		var use := UiTheme.button("Use (%s)" % String(item.unlocks.get("type", "")).capitalize(), 17)
		use.disabled = world.locked_items.has(id)
		use.pressed.connect(func() -> void:
			var r: Dictionary = world.use_item(id)
			refresh()
			_show_actions()
			if _actions.get_child_count() > 0:
				(_actions.get_child(0) as Label).text = String(r.get("error", "")) if not String(r.get("error", "")).is_empty() else String(r.get("message", "")))
		_actions.add_child(use)
	if not String(item.get("equip_slot", "")).is_empty() and world.characters.has(Game.selected_character_id):
		var ch: Adventurer = world.characters[Game.selected_character_id]
		var eq := UiTheme.button("Equip on %s" % ch.display_name.split(" ")[0], 17)
		eq.pressed.connect(func() -> void:
			var err := world.equip(ch.id, id)
			refresh()
			_show_actions()
			if not err.is_empty() and _actions.get_child_count() > 0:
				(_actions.get_child(0) as Label).text = err)
		_actions.add_child(eq)


func close() -> void:
	if inventory and inventory.changed.is_connected(refresh):
		inventory.changed.disconnect(refresh)
	super.close()
