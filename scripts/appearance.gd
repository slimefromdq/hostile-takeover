class_name Appearance
extends RefCounted

# How a fighter looks: body build, skin, eyes, hair, headgear, top, bottoms and shoes, picked in the start menu's LOOK tab
# (Splatoon-style). Cosmetic only: every build shares Fighter's collider and hitbox. Team identity comes from trim the rig
# adds in the team colour (collar or stripe, shoulder bands, shoe stripe), so the player's own colours stay theirs.
# Pure data plus the packing rules; scripts/character_rig.gd draws it. A look travels as one int ("ap" in snapshots).

const BODIES := [
	{"name": "Slim", "width": 0.88, "limb": 0.86},
	{"name": "Standard", "width": 1.0, "limb": 1.0},
	{"name": "Sturdy", "width": 1.14, "limb": 1.18},
]
const SKIN_TONES := [Color("ffe0cc"), Color("f6c9a8"), Color("eab08a"), Color("d39a6e"), Color("b87a50"), Color("9a5f3c"), Color("74452a"), Color("50301f")]
const EYE_COLORS := [Color("2fd3b0"), Color("3a8cff"), Color("7a4a2a"), Color("2c2c34"), Color("57b847"), Color("a35cff"), Color("ff6fa8"), Color("f0a020")]
const HAIR_COLORS := [Color("2a2420"), Color("5a3a22"), Color("a8642c"), Color("e8c66a"), Color("f1ede4"), Color("d84a3a"),
	Color("ff6fb5"), Color("9a5cff"), Color("3f63e0"), Color("2fd8c8"), Color("2a9a5a"), Color("8a9098")]
const CLOTH_COLORS := [Color("f2efe6"), Color("2b2f38"), Color("6e7682"), Color("c9b48a"), Color("4d6b3a"), Color("8c3a3a"),
	Color("e8c53a"), Color("2f5fae"), Color("6db8e8"), Color("e86aa0"), Color("5a3d8c"), Color("e8742e")]
const HAIRSTYLES := ["Bob", "Twin Tails", "Ponytail", "Buzz", "Long", "Spiky"]
const HEADGEAR := ["None", "Cap", "Goggle Helmet", "Headset", "Beanie", "Sunglasses"]
const TOPS := ["Tee", "Hoodie", "Crop Jacket", "Tactical Vest", "Jersey"]
const BOTTOMS := ["Shorts", "Cargo Pants", "Skirt", "Cutoffs"]
const SHOES := ["Sneakers", "Boots", "High-tops"]

# Packing order and bit widths. "style" fields pick a named option, "color" fields a swatch.
const FIELDS := [
	{"key": "body", "label": "BUILD", "kind": "style", "bits": 2},
	{"key": "skin", "label": "SKIN", "kind": "color", "bits": 3},
	{"key": "eyes", "label": "EYES", "kind": "color", "bits": 3},
	{"key": "hair", "label": "HAIR", "kind": "style", "bits": 3},
	{"key": "hair_color", "label": "HAIR COLOUR", "kind": "color", "bits": 4},
	{"key": "headgear", "label": "HEADGEAR", "kind": "style", "bits": 3},
	{"key": "top", "label": "TOP", "kind": "style", "bits": 3},
	{"key": "top_color", "label": "TOP COLOUR", "kind": "color", "bits": 4},
	{"key": "bottom", "label": "BOTTOMS", "kind": "style", "bits": 2},
	{"key": "bottom_color", "label": "BOTTOMS COLOUR", "kind": "color", "bits": 4},
	{"key": "shoes", "label": "SHOES", "kind": "style", "bits": 2},
	{"key": "shoe_color", "label": "SHOES COLOUR", "kind": "color", "bits": 4},
]

const DEFAULT_LOOK := {"body": 1, "skin": 1, "eyes": 0, "hair": 0, "hair_color": 9, "headgear": 3, "top": 2, "top_color": 3,
	"bottom": 0, "bottom_color": 4, "shoes": 0, "shoe_color": 0}

const SETTINGS_PATH := "user://settings.cfg"

static func options(key: String) -> Array:
	match key:
		"body": return BODIES
		"skin": return SKIN_TONES
		"eyes": return EYE_COLORS
		"hair": return HAIRSTYLES
		"hair_color": return HAIR_COLORS
		"headgear": return HEADGEAR
		"top": return TOPS
		"bottom": return BOTTOMS
		"shoes": return SHOES
		_: return CLOTH_COLORS  # top_color, bottom_color, shoe_color

static func option_name(key: String, index: int) -> String:
	var table := options(key)
	var item = table[clampi(index, 0, table.size() - 1)]
	if item is Dictionary:
		return item.name
	if item is Color:
		return "#" + item.to_html(false)
	return item

static func encode(look: Dictionary) -> int:
	var code := 0
	var shift := 0
	for f in FIELDS:
		var size := options(f.key).size()
		code |= clampi(int(look.get(f.key, DEFAULT_LOOK[f.key])), 0, size - 1) << shift
		shift += f.bits
	return code

# Every field clamped into its table, so any int from the network is safe.
static func decode(code: int) -> Dictionary:
	var look := {}
	var shift := 0
	for f in FIELDS:
		var size := options(f.key).size()
		look[f.key] = clampi((code >> shift) & ((1 << f.bits) - 1), 0, size - 1)
		shift += f.bits
	return look

static func sanitize(code: int) -> int:
	return encode(decode(code))

static func default_code() -> int:
	return encode(DEFAULT_LOOK)

static func with_field(code: int, key: String, value: int) -> int:
	var look := decode(code)
	look[key] = value
	return encode(look)

static func random(rng: RandomNumberGenerator) -> int:
	var look := {}
	for f in FIELDS:
		look[f.key] = rng.randi_range(0, options(f.key).size() - 1)
	return encode(look)

# "Standard · Twin Tails · Cap · Hoodie · Shorts · Boots"
static func describe(code: int) -> String:
	var look := decode(code)
	var parts := PackedStringArray()
	for key in ["body", "hair", "headgear", "top", "bottom", "shoes"]:
		parts.append(option_name(key, look[key]))
	return " · ".join(parts)

static func load_saved() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return default_code()
	return sanitize(int(cfg.get_value("player", "look", default_code())))

static func save(code: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # keep the other sections (display, sensitivity, map)
	cfg.set_value("player", "look", sanitize(code))
	cfg.save(SETTINGS_PATH)
