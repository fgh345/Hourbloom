shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D base_color : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform int face_row : hint_range(0, 7) = 0;
uniform bool blink = false;

void fragment() {
	vec2 atlas_uv = UV;
	// glTF flips Blender's bottom-origin UVs. Only the neutral facial strip moves.
	if (UV.x >= 0.75 && UV.y >= 0.875) {
		int row = face_row;
		if (blink && UV.x < 0.9375) {
			row = 5;
		}
		atlas_uv.y -= float(row) * 0.125;
	}
	ALBEDO = texture(base_color, atlas_uv).rgb * tint.rgb;
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
	SPECULAR = 0.2;
}
