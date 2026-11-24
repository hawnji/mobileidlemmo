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


func setup(p_registry: DataRegistry, p_inventory: Inventory, title: String, p_is_storage := false) -> void:
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
	_grid = ItemGrid.new()
	_grid.registry = registry
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


func close() -> void:
	if inventory and inventory.changed.is_connected(refresh):
		inventory.changed.disconnect(refresh)
	super.close()
