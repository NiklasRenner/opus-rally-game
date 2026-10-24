class_name RetroLook
extends Node
## The arcade look for a race, switched with F2: sunlight falls off across a
## surface in a few soft steps instead of a smooth ramp (Saturn / PS1 era
## shading), the sun casts hard-edged shadows, the car's windows reflect a
## flat fake sky, and the fog is a depth fog that closes in on the distance.
## It works by swapping every lit StandardMaterial3D in the scene for a shader
## copy with its own light(), and swapping them back when it's switched off.
## Unshaded, see-through and billboard materials are left alone.
##
## Only the angle between a face and the sun is stepped. Anything that changes
## with distance (shadows, headlight falloff, fog, reflections on the road)
## stays smooth, because stepping those draws rings round the camera and car.

const BANDS := 4.0  # lit steps between the ambient-only side and full sun
const BAND_SOFTNESS := 0.2  # 0 = hard cel edges, 0.5 = smooth ramp again

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
// the car's windows reflect a three-band fake sky instead of the real one,
// like the environment maps of the time
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
	if (LIGHT_IS_DIRECTIONAL) {
		// the sun: step the facing only (wrapped a little so faces just past
		// side-on still catch the lowest step), then shadow it as usual; a bit
		// brighter to make up for the specular sheen rough surfaces no longer get
		float facing = stepped(clamp((dot(NORMAL, LIGHT) + wrap) / (1.0 + wrap), 0.0, 1.0));
		DIFFUSE_LIGHT += LIGHT_COLOR * facing * ATTENUATION * 1.1 / PI;
		// one hard-edged highlight on the car's paint and glass
		if (gloss > 0.0) {
			float h = max(dot(NORMAL, normalize(LIGHT + VIEW)), 0.0);
			float shine = pow(h, exp2(10.0 * (1.0 - roughness_v) + 1.0));
			SPECULAR_LIGHT += LIGHT_COLOR * gloss * smoothstep(0.45, 0.55, shine) * ATTENUATION;
		}
	} else {
		// headlights: plain Lambert, stepping their falloff would draw rings
		DIFFUSE_LIGHT += LIGHT_COLOR * clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION / PI;
	}
}
"""

static var _shaders := {}

var env: Environment
var sun: DirectionalLight3D
var car: Node  # its glass gets the fake sky
var enabled := false
var sky_colors: Array = [Color(0.3, 0.5, 0.9), Color(0.6, 0.78, 0.98), Color(0.4, 0.5, 0.45)]  # top, horizon, ground

var _root: Node
var _copies := {}  # [StandardMaterial3D, on the car] -> ShaderMaterial
var _swaps: Array = []  # [object, slot, index, original material]
var _modern := {}  # environment and sun settings to put back


## Start watching `root` (the race scene) and switch the look on or off.
func setup(root: Node, on: bool) -> void:
	_root = root
	_modern = {"fog_mode": env.fog_mode, "fog_density": env.fog_density, "shadow_blur": sun.shadow_blur,
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


func _exit_tree() -> void:
	# meshes are cached across races (trees), so never leave them swapped
	_restore()
	RenderingServer.directional_soft_shadow_filter_set_quality(_modern.get("shadow_quality", 2))


func _on_node_added(node: Node) -> void:
	if enabled and node is GeometryInstance3D:
		# the mesh and materials are often set right after add_child
		_convert_node.call_deferred(node)


# --------------------------------------------------------------------------- shadows and fog

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
		# same shadow maps and range as before, just no blur or soft filter
		sun.shadow_blur = 0.0
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
	else:
		env.fog_mode = _modern["fog_mode"]
		env.fog_density = _modern["fog_density"]
		sun.shadow_blur = _modern["shadow_blur"]
		RenderingServer.directional_soft_shadow_filter_set_quality(_modern["shadow_quality"])


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
		_swap_mesh(gi, mesh, s)


func _swap(obj: Object, slot: String, idx: int, mat: Material) -> void:
	var on_car := car != null and is_instance_valid(car) and car.is_ancestor_of(obj as Node)
	var copy := _copy(mat, on_car)
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


## A material that lives on the mesh resource itself.
func _swap_mesh(gi: GeometryInstance3D, mesh: Mesh, s: int) -> void:
	var mat := mesh.surface_get_material(s)
	var on_car := car != null and is_instance_valid(car) and car.is_ancestor_of(gi)
	var copy := _copy(mat, on_car)
	if copy == null:
		return
	mesh.surface_set_material(s, copy)
	_swaps.append([mesh, "mesh", s, mat])


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
func _copy(mat: Material, on_car: bool) -> ShaderMaterial:
	if not mat is BaseMaterial3D:
		return null
	var m := mat as BaseMaterial3D
	var key := [m, on_car]
	if _copies.has(key):
		return _copies[key]
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
	if on_car:  # a hard highlight on a whole road would be a hard-edged blob
		sm.set_shader_parameter("gloss", clampf((0.6 - m.roughness) * m.metallic_specular, 0.0, 0.5))
	# only the car's glass: on the road the band edges would sit at a fixed
	# distance from the camera and draw a ring round it
	if on_car and m.roughness < 0.2:
		sm.set_shader_parameter("mirror", 0.3)
		sm.set_shader_parameter("sky_hi", sky_colors[0])
		sm.set_shader_parameter("sky_lo", sky_colors[1])
		sm.set_shader_parameter("ground_col", sky_colors[2])
	if m.emission_enabled:
		sm.set_shader_parameter("emission", m.emission * m.emission_energy_multiplier)
	sm.set_shader_parameter("alpha_scissor", m.alpha_scissor_threshold)
	sm.set_shader_parameter("bands", BANDS)
	sm.set_shader_parameter("softness", BAND_SOFTNESS)
	sm.render_priority = m.render_priority
	_copies[key] = sm
	return sm


static func _shader(cull: String, nearest: bool, scissor: bool) -> Shader:
	var key := "%s|%s|%s" % [cull, nearest, scissor]
	if not _shaders.has(key):
		var sh := Shader.new()
		sh.code = SHADER % [cull, "filter_nearest_mipmap" if nearest else "filter_linear_mipmap",
			"ALPHA = c.a;\n\tALPHA_SCISSOR_THRESHOLD = alpha_scissor;" if scissor else ""]
		_shaders[key] = sh
	return _shaders[key]
