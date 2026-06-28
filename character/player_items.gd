extends RefCounted
class_name PlayerItems
## Hand-item ids and mapping to torch / terrain-edit behavior.


enum Item {
	NONE,
	TORCH,
	PICKAXE_DESTROY,
	PICKAXE_ADD,
}


static func item_from_edit_mode(mode: TerrainBrush.EditMode) -> Item:
	match mode:
		TerrainBrush.EditMode.DESTROY:
			return Item.PICKAXE_DESTROY
		TerrainBrush.EditMode.ADD:
			return Item.PICKAXE_ADD
	return Item.NONE


static func edit_mode_from_item(item: Item) -> TerrainBrush.EditMode:
	match item:
		Item.PICKAXE_DESTROY:
			return TerrainBrush.EditMode.DESTROY
		Item.PICKAXE_ADD:
			return TerrainBrush.EditMode.ADD
	return TerrainBrush.EditMode.OFF
