class_name CanopyCover
extends RefCounted
## Dense tree canopy as cover from the air (update-police-pursuit 2.2). The helicopter's sight
## ray is tested against the tree crowns of the pack, not physics bodies, so nothing collides
## with leaves. Approach: trees go into a grid of `CELL_M` cells; a ray is sampled every
## `sample_m` over the part low enough to pass through crowns, and the length that lies inside
## a crown ellipsoid counts as cover when the crown's tree stands in a dense group (at least
## `min_trees` trees within `group_m`), so parks and woods hide a player and a single row of
## street trees does not. A ray is blocked once it has gone `min_depth_m` through such crowns.

const CELL_M := 8.0
const DEFAULTS := {
	"group_m": 12.0,
	"min_trees": 5,
	"min_depth_m": 1.5,
	"sample_m": 0.75,
	"crown_mid": 0.62,
	"crown_half_height": 0.28,
}

var config: Dictionary = DEFAULTS.duplicate()
var _trees: Array = []  # rows [x, y, z, archetype, height, crown, seed, source]
var _grid: Dictionary = {}  # Vector2i -> PackedInt32Array of tree indices
var _dense: Dictionary = {}  # tree index -> bool, filled on first use
var _top_m: float = 0.0  # the highest crown top above its tree's base


## From the vegetation rows a pack draws (MapPack.vegetation_chunks, capped like the chunks).
static func from_chunks(chunks: Dictionary, cfg: Dictionary = {}) -> CanopyCover:
	var rows: Array = []
	for coord: Vector2i in chunks:
		rows.append_array(VegetationBuilder.capped(chunks[coord])["trees"])
	return CanopyCover.new(rows, cfg)


func _init(tree_rows: Array = [], cfg: Dictionary = {}) -> void:
	for k: String in cfg:
		config[k] = cfg[k]
	_trees = tree_rows
	for i in range(_trees.size()):
		var row: Array = _trees[i]
		var c := _cell(float(row[0]), float(row[2]))
		var ids: PackedInt32Array = _grid.get(c, PackedInt32Array())  # packed arrays copy: store back
		ids.append(i)
		_grid[c] = ids
		_top_m = maxf(_top_m, float(row[4]) * (_mid() + _half()))


## True when the segment from `from` to `to` passes through `min_depth_m` of dense canopy.
func blocks(from: Vector3, to: Vector3) -> bool:
	if _trees.is_empty():
		return false
	var length := from.distance_to(to)
	if length < 0.001:
		return false
	var dir := (to - from) / length
	var step := float(config["sample_m"])
	var need := float(config["min_depth_m"])
	var depth := 0.0
	# Only the stretch near `to` can be low enough to pass through a crown.
	var rise := maxf(from.y - to.y, 0.0)
	var span := length if rise < 0.01 else minf(length, length * (_top_m + 2.0) / rise)
	var s := 0.0
	while s <= span:
		var p := to - dir * s
		if _in_dense_crown(p):
			depth += step
			if depth >= need:
				return true
		s += step
	return false


## True when `p` lies inside the crown of a tree standing in a dense group.
func _in_dense_crown(p: Vector3) -> bool:
	var c := _cell(p.x, p.z)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var ids: Variant = _grid.get(c + Vector2i(dx, dz))
			if ids == null:
				continue
			for i: int in ids:
				if _inside(_trees[i], p) and _is_dense(i):
					return true
	return false


func _inside(row: Array, p: Vector3) -> bool:
	var h := float(row[4])
	var r := float(row[5])
	var half := maxf(h * _half(), 0.5)
	var cy := float(row[1]) + h * _mid()
	var dx := (p.x - float(row[0])) / r
	var dz := (p.z - float(row[2])) / r
	var dy := (p.y - cy) / half
	return dx * dx + dy * dy + dz * dz <= 1.0


## A tree with at least `min_trees` trees (itself included) within `group_m`.
func _is_dense(i: int) -> bool:
	if _dense.has(i):
		return _dense[i]
	var row: Array = _trees[i]
	var x := float(row[0])
	var z := float(row[2])
	var r := float(config["group_m"])
	var reach := int(ceil(r / CELL_M))
	var c := _cell(x, z)
	var n := 0
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var ids: Variant = _grid.get(c + Vector2i(dx, dz))
			if ids == null:
				continue
			for j: int in ids:
				var o: Array = _trees[j]
				if Vector2(float(o[0]) - x, float(o[2]) - z).length() <= r:
					n += 1
	var dense := n >= int(config["min_trees"])
	_dense[i] = dense
	return dense


func _mid() -> float:
	return float(config["crown_mid"])


func _half() -> float:
	return float(config["crown_half_height"])


static func _cell(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor(x / CELL_M)), int(floor(z / CELL_M)))
