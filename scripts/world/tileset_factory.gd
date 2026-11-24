class_name TilesetFactory
extends RefCounted
## Builds the terrain TileSet from data/regions/terrain.json and the tile
## atlas. Atlas coordinates and animation frames come from data, so new
## terrain or final art only needs a JSON edit + PNG swap.

const ATLAS_PATH := "res://assets/environments/tiles/greenvale_tiles.png"
const SOURCE_ID := 0


static func build(registry: DataRegistry, tile_px := 32) -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(tile_px, tile_px)
	var src := TileSetAtlasSource.new()
	src.texture = load(ATLAS_PATH)
	src.texture_region_size = Vector2i(tile_px, tile_px)
	var created := {}
	for t in registry.terrain_list:
		var coords := JsonData.to_vec2i(t.get("atlas"))
		if created.has(coords):
			continue
		src.create_tile(coords)
		created[coords] = true
		var frames := int(t.get("animation_frames", 1))
		if frames > 1:
			src.set_tile_animation_columns(coords, 0)
			src.set_tile_animation_frames_count(coords, frames)
			src.set_tile_animation_speed(coords, float(t.get("animation_fps", 4.0)))
	ts.add_source(src, SOURCE_ID)
	return ts


static func atlas_for_symbol(registry: DataRegistry, symbol: String) -> Vector2i:
	return JsonData.to_vec2i(registry.terrain_by_symbol.get(symbol, {}).get("atlas"))
