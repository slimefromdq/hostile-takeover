class_name Visuals
extends RefCounted

# Shared visual language: team palette, role-based surface materials, silhouette outlines,
# and the city environment. Authored textures (assets/textures/<role>_albedo.*) override the
# procedural look for a role.

const HELIX := Color("3fd0ff")
const MONARCH := Color("ff8a4c")
const NEUTRAL := Color("d8d6c0")
# Art direction palette: bright day, white masses, one hot accent, cobalt secondary, yellow guidance.
const PAL := {
	"white": Color("eceef0"),
	"grey": Color("b7bcc2"),
	"dark": Color("3a4250"),
	"accent": Color("ff6a2b"),
	"cobalt": Color("2a5bd7"),
	"guide": Color("ffc928"),
	"sky_top": Color("2f63d8"),
	"sky_horizon": Color("a9cdff"),
}

const ENEMY_OUTLINE := Color("ff3b3b")
const ALLY_OUTLINE := Color("8fe3ff")

# role -> [surface base multiplier, line colour, grid cell metres, line width, emission]
const ROLES := {
	"walk": [1.0, Color("c9cfd2"), 4.0, 0.05, 0.0, 1.0],
	"wall": [1.0, Color("ffd36b"), 2.0, 0.06, 0.6, 0.0],
	"tower": [0.7, Color("cfc8b4"), 3.0, 0.45, 0.1, 0.0],
	"cover": [1.0, Color("ffffff"), 1.0, 0.04, 0.0, 0.0],
	"accent": [1.0, Color("ffffff"), 2.0, 0.2, 1.4, 1.0],
	"hazard": [1.0, Color("ffcc00"), 1.0, 0.25, 0.8, 1.0],
	"glass": [1.0, Color("bfe9ff"), 2.0, 0.05, 0.2, 1.0],
}

const SURFACE_SHADER := """
shader_type spatial;
uniform vec4 base_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float cell = 2.0;
uniform float line_width = 0.05;
uniform float emission_strength = 0.0;
uniform float top_lines = 1.0;
varying vec3 world_pos;
varying vec3 world_normal;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 n = abs(world_normal);
	vec2 uv = world_pos.xy;
	if (n.y > 0.7) {
		uv = world_pos.xz;
	} else if (n.x > n.z) {
		uv = world_pos.zy;
	}
	vec2 g = abs(fract(uv / cell - 0.5) - 0.5) * cell;
	float line = 1.0 - step(line_width, min(g.x, g.y));
	if (n.y > 0.7) {
		line *= top_lines;
	}
	ALBEDO = mix(base_color.rgb, line_color.rgb, line * 0.55);
	ROUGHNESS = 0.85;
	EMISSION = line_color.rgb * line * emission_strength;
}
"""

const OUTLINE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front;
uniform vec4 outline_color : source_color = vec4(1.0, 0.2, 0.2, 1.0);
uniform float width = 0.03;
void vertex() {
	VERTEX += NORMAL * width;
}
void fragment() {
	ALBEDO = outline_color.rgb;
}
"""

static var _surface_shader: Shader
static var _outline_shader: Shader
static var _materials: Dictionary = {}

const HELIX_CB := Color("0072b2")
const MONARCH_CB := Color("e69f00")
const SETTINGS_PATH := "user://settings.cfg"
static var colorblind := false

static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		colorblind = cfg.get_value("display", "colorblind", false)

static func set_colorblind(value: bool) -> void:
	colorblind = value
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("display", "colorblind", value)
	cfg.save(SETTINGS_PATH)

static func team_color(side: int) -> Color:
	if colorblind:
		return HELIX_CB if side == 0 else MONARCH_CB
	return HELIX if side == 0 else MONARCH

# Role-based world material. Shared per (role, colour) so the map stays cheap to draw.
static func surface(role: String, color: Color) -> Material:
	var key := "%s:%s" % [role, color.to_html()]
	if _materials.has(key):
		return _materials[key]
	var mat: Material
	if role == "glass":
		# Writing ALPHA in the opaque surface shader would push every map mesh into the transparent
		# pipeline (no depth writes, per-mesh sorting), so walls draw over each other. Glass is separate.
		var glass := StandardMaterial3D.new()
		glass.albedo_color = Color(color, 0.35)
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.roughness = 0.1
		_materials[key] = glass
		return glass
	var tex := AssetLibrary.texture(role + "_albedo")
	if tex != null:
		var std := StandardMaterial3D.new()
		std.albedo_color = color
		std.albedo_texture = tex
		std.uv1_triplanar = true
		std.uv1_world_triplanar = true
		std.roughness = 0.85
		mat = std
	else:
		var params: Array = ROLES.get(role, ROLES.walk)
		if _surface_shader == null:
			_surface_shader = Shader.new()
			_surface_shader.code = SURFACE_SHADER
		var sm := ShaderMaterial.new()
		sm.shader = _surface_shader
		sm.set_shader_parameter("base_color", color * params[0])
		sm.set_shader_parameter("line_color", params[1])
		sm.set_shader_parameter("cell", params[2])
		sm.set_shader_parameter("line_width", params[3])
		sm.set_shader_parameter("emission_strength", params[4])
		sm.set_shader_parameter("top_lines", params[5])
		mat = sm
	_materials[key] = mat
	return mat

# Plain lit material used for characters and props.
static func solid(color: Color, rough: float = 0.8) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	return mat

static func glow(color: Color, energy: float = 1.5) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat

# Inverted-hull silhouette: returns the ShaderMaterial so callers can recolour it later.
static func add_outline(material: BaseMaterial3D, color: Color, width: float = 0.03) -> ShaderMaterial:
	if _outline_shader == null:
		_outline_shader = Shader.new()
		_outline_shader.code = OUTLINE_SHADER
	var outline := ShaderMaterial.new()
	outline.shader = _outline_shader
	outline.set_shader_parameter("outline_color", color)
	outline.set_shader_parameter("width", width)
	material.next_pass = outline
	return outline

static func outline_color_for(side: int, local_side: int) -> Color:
	return ALLY_OUTLINE if side == local_side else ENEMY_OUTLINE

# Bright day: saturated blue sky, hard sun, bloomed whites. Forward+ adds SSAO/SSIL for contact shading;
# on Compatibility those effects are skipped and the look falls back to flat ambient.
static func build_environment(root: Node3D) -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = PAL.sky_top
	sky_material.sky_horizon_color = PAL.sky_horizon
	sky_material.ground_horizon_color = PAL.sky_horizon
	sky_material.ground_bottom_color = Color("6f7f94")
	sky_material.sun_angle_max = 18.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.9
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_white = 6.0
	environment.fog_enabled = true
	environment.fog_light_color = Color("bcd4ff")
	environment.fog_density = 0.0025
	environment.glow_enabled = true
	environment.glow_intensity = 0.8
	environment.glow_bloom = 0.12
	environment.glow_hdr_threshold = 1.0
	var forward := RenderingServer.get_current_rendering_method() == "forward_plus"
	if forward:
		environment.ssao_enabled = true
		environment.ssao_radius = 1.6
		environment.ssao_intensity = 2.0
		environment.ssil_enabled = true
		environment.ssil_intensity = 0.8
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	root.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -40, 0)
	sun.light_color = Color("fff3e0")
	sun.light_energy = 1.7
	sun.shadow_enabled = true
	if forward:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = 140.0
	else:
		# One orthogonal cascade covers the arena view and keeps shadow-pass draw calls low.
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 110.0
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 145, 0)
	fill.light_color = Color("9cc0ff")
	fill.light_energy = 0.3
	root.add_child(fill)
