class_name RetroLook
extends Node
## The arcade look for a race, switched with F2: light falls off in a few
## soft steps instead of a smooth ramp (Saturn / PS1 era Gouraud), the sun
## casts hard-edged shadows, colours are rounded to 15-bit like the consoles
## had, and the fog is a depth fog that closes in on the distance.
## It works by swapping every lit StandardMaterial3D in the scene for a shader
## copy with a banded light(), and swapping them back when it's switched off.
## Unshaded, see-through and billboard materials are left alone.

const BANDS := 4.0  # lit steps between the ambient-only side and full sun
const BAND_SOFTNESS := 0.2  # 0 = hard cel edges, 0.5 = smooth ramp again
const COLOR_LEVELS := 32.0  # per channel, 5 bits like the 15-bit consoles

const SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_%s, diffuse_lambert, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, %s, repeat_enable;
uniform bool use_tex = false;
uniform bool use_vcol = false;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
uniform float roughness_v = 1.0;
uniform float spec = 0.5;
uniform float gloss = 0.0;
uniform vec3 emission : source_color = vec3(0.0);
uniform float alpha_scissor = 0.5;
uniform float bands = 3.0;
uniform float softness = 0.2;
uniform float wrap = 0.25;
// glossy things (glass, paint, wet roads) reflect a three-band fake sky
// instead of the real one, like the environment maps of the time
uniform float mirror = 0.0;
uniform vec3 sky_hi : source_color = vec3(0.5, 0.6, 0.8);
uniform vec3 sky_lo : source_color = vec3(0.7, 0.8, 0.9);
uniform vec3 ground_col : source_color = vec3(0.3, 0.3, 0.3);

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
}

void fragment() {
	vec4 c = albedo;
	if (use_tex) {
		c *= texture(albedo_tex, UV);
	}
	if (use_vcol) {
		c *= COLOR;
	}
	ALBEDO = c.rgb;
	%s
	ROUGHNESS = roughness_v;
	METALLIC = 0.0;
	SPECULAR = mirror > 0.0 ? 0.0 : spec;
	EMISSION = emission;
	if (mirror > 0.0) {
		vec3 r = (INV_VIEW_MATRIX * vec4(reflect(-VIEW, NORMAL), 0.0)).xyz;
		vec3 env = r.y > 0.3 ? sky_hi : (r.y > -0.05 ? sky_lo : ground_col);
		ALBEDO *= 1.0 - mirror * 0.5;
		EMISSION += env * mirror;
	}
}

// Round to the nearest of a few steps, with a short ramp between them.
float stepped(float v) {
	float q = v * bands;
	return (floor(q) + smoothstep(0.5 - softness, 0.5 + softness, fract(q))) / bands;
}

void light() {
	// wrapped a little so faces just past side-on still catch the lowest step
	float lit = stepped(clamp((dot(NORMAL, LIGHT) + wrap) / (1.0 + wrap), 0.0, 1.0) * ATTENUATION);
	DIFFUSE_LIGHT += LIGHT_COLOR * lit / PI;
	// the sun's sheen on rough ground seen edge-on (the road ahead), smooth not
	// stepped; glossy things get their fake sky instead
	if (LIGHT_IS_DIRECTIONAL && mirror == 0.0) {
		float edge = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
		SPECULAR_LIGHT += LIGHT_COLOR * spec * 0.22 * edge * lit;
	}
	// one hard-edged highlight for the glossy stuff (car paint)
	if (gloss > 0.0) {
		float h = max(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0);
		float shine = pow(h, exp2(10.0 * (1.0 - roughness_v) + 1.0));
		SPECULAR_LIGHT += LIGHT_COLOR * gloss * smoothstep(0.45, 0.55, shine) * step(0.5, ATTENUATION);
	}
}
"""

const POST_SHADER := """
shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform float levels = 32.0;

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	COLOR = vec4(floor(c * (levels - 1.0) + 0.5) / (levels - 1.0), 1.0);
}
"""

static var _shaders := {}

var env: Environment
var sun: DirectionalLight3D
var enabled := false
var sky_colors: Array = [Color(0.3, 0.5, 0.9), Color(0.6, 0.78, 0.98), Color(0.4, 0.5, 0.45)]  # top, horizon, ground

var _root: Node
var _post: CanvasLayer
var _copies := {}  # StandardMaterial3D -> ShaderMaterial
var _swaps: Array = []  # [object, slot, index, original material]
var _modern := {}  # environment and sun settings to put back


## Start watching `root` (the race scene) and switch the look on or off.
func setup(root: Node, on: bool) -> void:
	_root = root
	_modern = {"fog_mode": env.fog_mode, "fog_density": env.fog_density,
		"shadow_mode": sun.directional_shadow_mode, "shadow_distance": sun.directional_shadow_max_distance,
		"shadow_blur": sun.shadow_blur,
		"shadow_quality": ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 2)}
	get_tree().node_added.connect(_on_node_added)
	set_enabled(on)


func set_enabled(on: bool) -> void:
	if on == enabled:
		return
	enabled = on
	if on:
		_convert_tree(_root)
	else:
		_restore()
	_set_environment(on)
	_set_post(on)


func _exit_tree() -> void:
	# meshes are cached across races (trees), so never leave them swapped
	_restore()
	RenderingServer.directional_soft_shadow_filter_set_quality(_modern.get("shadow_quality", 2))


func _on_node_added(node: Node) -> void:
	if enabled and node is GeometryInstance3D:
		# the mesh and materials are often set right after add_child
		_convert_node.call_deferred(node)


# --------------------------------------------------------------------------- lighting, fog, palette

func _set_environment(on: bool) -> void:
	if on:
		# depth fog: clear up close, closing in to a wall of colour far off;
		# the thicker the stage's own fog, the nearer the wall
		var density: float = _modern["fog_density"]
		var end := clampf(1.5 / maxf(density, 0.0001), 340.0, 1300.0)
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_depth_begin = 0.0
		env.fog_depth_end = end
		env.fog_depth_curve = 0.75
		env.fog_density = 1.0
		# one shadow map over a short range, no blur: hard, crisp shadows
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = 70.0
		sun.shadow_blur = 0.0
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
	else:
		env.fog_mode = _modern["fog_mode"]
		env.fog_density = _modern["fog_density"]
		sun.directional_shadow_mode = _modern["shadow_mode"]
		sun.directional_shadow_max_distance = _modern["shadow_distance"]
		sun.shadow_blur = _modern["shadow_blur"]
		RenderingServer.directional_soft_shadow_filter_set_quality(_modern["shadow_quality"])


## 15-bit colour over the 3D view (under the HUD, which is on layer 1).
func _set_post(on: bool) -> void:
	if not on:
		if _post:
			_post.queue_free()
			_post = null
		return
	_post = CanvasLayer.new()
	_post.layer = 0
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = POST_SHADER
	mat.shader = sh
	mat.set_shader_parameter("levels", COLOR_LEVELS)
	rect.material = mat
	_post.add_child(rect)
	add_child(_post)


# --------------------------------------------------------------------------- material swapping

func _convert_tree(node: Node) -> void:
	if node is GeometryInstance3D:
		_convert_node(node)
	for c in node.get_children():
		_convert_tree(c)


func _convert_node(node: Node) -> void:
	if not enabled or not is_instance_valid(node) or not node.is_inside_tree():
		return
	var gi := node as GeometryInstance3D
	if gi.material_override:
		_swap(gi, "override", 0, gi.material_override)
		return
	var mesh: Mesh = null
	if gi is MeshInstance3D:
		mesh = (gi as MeshInstance3D).mesh
	elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh:
		mesh = (gi as MultiMeshInstance3D).multimesh.mesh
	if mesh == null:
		return
	for s in mesh.get_surface_count():
		if gi is MeshInstance3D:
			var mi := gi as MeshInstance3D
			var m := mi.get_surface_override_material(s)
			if m:
				_swap(mi, "surface", s, m)
				continue
		_swap(mesh, "mesh", s, mesh.surface_get_material(s))


func _swap(obj: Object, slot: String, idx: int, mat: Material) -> void:
	var copy := _copy(mat)
	if copy == null:
		return
	match slot:
		"override":
			(obj as GeometryInstance3D).material_override = copy
		"surface":
			(obj as MeshInstance3D).set_surface_override_material(idx, copy)
		"mesh":
			(obj as Mesh).surface_set_material(idx, copy)
	_swaps.append([obj, slot, idx, mat])


func _restore() -> void:
	for sw in _swaps:
		var obj: Object = sw[0]
		if not is_instance_valid(obj):
			continue
		match sw[1]:
			"override":
				(obj as GeometryInstance3D).material_override = sw[3]
			"surface":
				(obj as MeshInstance3D).set_surface_override_material(sw[2], sw[3])
			"mesh":
				(obj as Mesh).surface_set_material(sw[2], sw[3])
	_swaps.clear()


## The shader copy of a material, or null if it should stay as it is.
func _copy(mat: Material) -> ShaderMaterial:
	if not mat is BaseMaterial3D:
		return null
	var m := mat as BaseMaterial3D
	if _copies.has(m):
		return _copies[m]
	if m.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL or m.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED \
			or m.uv1_triplanar or m.next_pass != null or m.normal_enabled \
			or m.transparency not in [BaseMaterial3D.TRANSPARENCY_DISABLED, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR]:
		return null
	var scissor := m.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var nearest := m.texture_filter in [BaseMaterial3D.TEXTURE_FILTER_NEAREST, BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS,
		BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC]
	var sm := ShaderMaterial.new()
	sm.shader = _shader(["back", "front", "disabled"][m.cull_mode], nearest, scissor)
	sm.set_shader_parameter("albedo", m.albedo_color)
	sm.set_shader_parameter("use_tex", m.albedo_texture != null)
	if m.albedo_texture:
		sm.set_shader_parameter("albedo_tex", m.albedo_texture)
	sm.set_shader_parameter("use_vcol", m.vertex_color_use_as_albedo)
	sm.set_shader_parameter("uv1_scale", m.uv1_scale)
	sm.set_shader_parameter("uv1_offset", m.uv1_offset)
	sm.set_shader_parameter("roughness_v", m.roughness)
	sm.set_shader_parameter("spec", m.metallic_specular)
	sm.set_shader_parameter("gloss", clampf((0.6 - m.roughness) * m.metallic_specular, 0.0, 0.5))
	var mirror := clampf((0.45 - m.roughness) * m.metallic_specular * 1.2, 0.0, 0.35)
	sm.set_shader_parameter("mirror", mirror)
	if mirror > 0.0:
		sm.set_shader_parameter("sky_hi", sky_colors[0])
		sm.set_shader_parameter("sky_lo", sky_colors[1])
		sm.set_shader_parameter("ground_col", sky_colors[2])
	if m.emission_enabled:
		sm.set_shader_parameter("emission", m.emission * m.emission_energy_multiplier)
	sm.set_shader_parameter("alpha_scissor", m.alpha_scissor_threshold)
	sm.set_shader_parameter("bands", BANDS)
	sm.set_shader_parameter("softness", BAND_SOFTNESS)
	sm.render_priority = m.render_priority
	_copies[m] = sm
	return sm


static func _shader(cull: String, nearest: bool, scissor: bool) -> Shader:
	var key := "%s|%s|%s" % [cull, nearest, scissor]
	if not _shaders.has(key):
		var sh := Shader.new()
		sh.code = SHADER % [cull, "filter_nearest_mipmap" if nearest else "filter_linear_mipmap",
			"ALPHA = c.a;\n\tALPHA_SCISSOR_THRESHOLD = alpha_scissor;" if scissor else ""]
		_shaders[key] = sh
	return _shaders[key]
