#!/usr/bin/env python3
"""Apply Hoarbound's Godot 4.8-dev6 directional-shadow sampler patch.

This deliberately uses exact source replacements instead of a unified diff.
Every replacement is checked once against the pinned upstream commit, so a
source drift fails loudly before any build begins.
"""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

UPSTREAM_COMMIT = "8898c2b3db32adf6f92c694ffb6dac19af672e5f"


def run(*args: str, cwd: Path) -> str:
    result = subprocess.run(
        list(args),
        cwd=cwd,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    return result.stdout.strip()


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(
            f"{label}: expected exactly one source anchor in {path}, found {count}"
        )
    path.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot-dir", required=True)
    args = parser.parse_args()

    root = Path(args.godot_dir).resolve()
    head = run("git", "rev-parse", "HEAD", cwd=root)
    if head != UPSTREAM_COMMIT:
        raise RuntimeError(
            f"Godot HEAD is {head}, expected pinned 4.8-dev6 {UPSTREAM_COMMIT}"
        )

    shader_language = root / "servers/rendering/shader_language.cpp"
    replace_once(
        shader_language,
        '''\t{ "frexp", TYPE_VEC4, { TYPE_VEC4, TYPE_IVEC4, TYPE_VOID }, { "x", "exp" }, TAG_GLOBAL, true },

\t{ nullptr, TYPE_VOID, { TYPE_VOID }, { "" }, TAG_GLOBAL, false }''',
        '''\t{ "frexp", TYPE_VEC4, { TYPE_VEC4, TYPE_IVEC4, TYPE_VOID }, { "x", "exp" }, TAG_GLOBAL, true },

\t// Hoarbound: sample a directional shadow map at an arbitrary view-space position.
\t{ "sample_directional_shadow", TYPE_FLOAT, { TYPE_UINT, TYPE_VEC3, TYPE_VOID }, { "light_index", "vertex" }, TAG_GLOBAL, true },

\t{ nullptr, TYPE_VOID, { TYPE_VOID }, { "" }, TAG_GLOBAL, false }''',
        "register sample_directional_shadow builtin",
    )

    shader_types = root / "servers/rendering/shader_types.cpp"
    replace_once(
        shader_types,
        '''\tshader_modes[RSE::SHADER_SPATIAL].functions["light"].built_ins["LIGHT_COLOR"] = constt(ShaderLanguage::TYPE_VEC3);
\tshader_modes[RSE::SHADER_SPATIAL].functions["light"].built_ins["LIGHT_IS_DIRECTIONAL"] = constt(ShaderLanguage::TYPE_BOOL);
\tshader_modes[RSE::SHADER_SPATIAL].functions["light"].built_ins["LIGHT_IS_AREA"] = constt(ShaderLanguage::TYPE_BOOL);''',
        '''\tshader_modes[RSE::SHADER_SPATIAL].functions["light"].built_ins["LIGHT_COLOR"] = constt(ShaderLanguage::TYPE_VEC3);
\tshader_modes[RSE::SHADER_SPATIAL].functions["light"].built_ins["LIGHT_IS_DIRECTIONAL"] = constt(ShaderLanguage::TYPE_BOOL);
\tshader_modes[RSE::SHADER_SPATIAL].functions["light"].built_ins["LIGHT_INDEX"] = constt(ShaderLanguage::TYPE_UINT);
\tshader_modes[RSE::SHADER_SPATIAL].functions["light"].built_ins["LIGHT_IS_AREA"] = constt(ShaderLanguage::TYPE_BOOL);''',
        "register LIGHT_INDEX builtin",
    )

    for rel in (
        "servers/rendering/renderer_rd/forward_clustered/scene_shader_forward_clustered.cpp",
        "servers/rendering/renderer_rd/forward_mobile/scene_shader_forward_mobile.cpp",
    ):
        path = root / rel
        replace_once(
            path,
            '''\t\tactions.renames["LIGHT_COLOR"] = "light_color_highp";
\t\tactions.renames["LIGHT_IS_DIRECTIONAL"] = "is_directional";
\t\tactions.renames["LIGHT_IS_AREA"] = "is_area";''',
            '''\t\tactions.renames["LIGHT_COLOR"] = "light_color_highp";
\t\tactions.renames["LIGHT_IS_DIRECTIONAL"] = "is_directional";
\t\tactions.renames["LIGHT_INDEX"] = "light_index_highp";
\t\tactions.renames["LIGHT_IS_AREA"] = "is_area";''',
            f"map LIGHT_INDEX in {rel}",
        )

    lights = root / "servers/rendering/renderer_rd/shaders/scene_forward_lights_inc.glsl"
    replace_once(
        lights,
        "void light_compute(hvec3 N, hvec3 L, hvec3 V, half A, hvec3 light_color, bool is_directional, half attenuation, hvec3 f0, half roughness, half metallic, half specular_amount, hvec3 albedo, inout half alpha, vec2 screen_uv, hvec3 energy_compensation,",
        """// Hoarbound custom GDSL builtin. Full implementation is below the shadow helpers.
float sample_directional_shadow(uint idx, vec3 vertex);

void light_compute(uint light_index, hvec3 N, hvec3 L, hvec3 V, half A, hvec3 light_color, bool is_directional, half attenuation, hvec3 f0, half roughness, half metallic, half specular_amount, hvec3 albedo, inout half alpha, vec2 screen_uv, hvec3 energy_compensation,""",
        "extend light_compute with light index",
    )
    replace_once(
        lights,
        """\tvec3 light_color_highp = vec3(light_color);
\tfloat attenuation_highp = float(attenuation);
\tvec3 diffuse_light_highp = vec3(diffuse_light);""",
        """\tvec3 light_color_highp = vec3(light_color);
\tfloat attenuation_highp = float(attenuation);
\tuint light_index_highp = light_index;
\tvec3 diffuse_light_highp = vec3(diffuse_light);""",
        "expose light_index_highp to generated light code",
    )

    sampler_impl = r'''
float sample_directional_shadow(uint idx, vec3 vertex) {
#ifdef USING_MOBILE_RENDERER
	// Hoarbound production uses Forward+. Keep Forward Mobile buildable.
	return 1.0;
#else
	if (idx >= scene_data_block.data.directional_light_count) {
		return 1.0;
	}
	if (directional_lights.data[idx].shadow_opacity <= 0.001) {
		return 1.0;
	}

	float depth_z = -vertex.z;
	vec4 pssm_coord;
	float blur_factor;
	vec3 light_dir = directional_lights.data[idx].direction;

	if (depth_z < directional_lights.data[idx].shadow_split_offsets.x) {
		vec4 v = vec4(vertex, 1.0);
		v.xyz += light_dir * directional_lights.data[idx].shadow_bias.x;
		pssm_coord = directional_lights.data[idx].shadow_matrix1 * v;
		blur_factor = 1.0;
	} else if (depth_z < directional_lights.data[idx].shadow_split_offsets.y) {
		vec4 v = vec4(vertex, 1.0);
		v.xyz += light_dir * directional_lights.data[idx].shadow_bias.y;
		pssm_coord = directional_lights.data[idx].shadow_matrix2 * v;
		blur_factor = directional_lights.data[idx].shadow_split_offsets.x / directional_lights.data[idx].shadow_split_offsets.y;
	} else if (depth_z < directional_lights.data[idx].shadow_split_offsets.z) {
		vec4 v = vec4(vertex, 1.0);
		v.xyz += light_dir * directional_lights.data[idx].shadow_bias.z;
		pssm_coord = directional_lights.data[idx].shadow_matrix3 * v;
		blur_factor = directional_lights.data[idx].shadow_split_offsets.x / directional_lights.data[idx].shadow_split_offsets.z;
	} else {
		vec4 v = vec4(vertex, 1.0);
		v.xyz += light_dir * directional_lights.data[idx].shadow_bias.w;
		pssm_coord = directional_lights.data[idx].shadow_matrix4 * v;
		blur_factor = directional_lights.data[idx].shadow_split_offsets.x / directional_lights.data[idx].shadow_split_offsets.w;
	}

	pssm_coord /= pssm_coord.w;
	float shadow = float(sample_directional_pcf_shadow(
			directional_shadow_atlas,
			scene_data_block.data.directional_shadow_pixel_size
				* directional_lights.data[idx].soft_shadow_scale
				* (blur_factor + (1.0 - blur_factor) * float(directional_lights.data[idx].blend_splits)),
			pssm_coord,
			scene_data_block.data.taa_frame_count));

	if (directional_lights.data[idx].blend_splits) {
		float pssm_blend = 0.0;
		float blur_factor2 = 1.0;
		vec4 coord2 = pssm_coord;

		if (depth_z < directional_lights.data[idx].shadow_split_offsets.x) {
			vec4 v = vec4(vertex, 1.0);
			v.xyz += light_dir * directional_lights.data[idx].shadow_bias.y;
			coord2 = directional_lights.data[idx].shadow_matrix2 * v;
			pssm_blend = smoothstep(directional_lights.data[idx].shadow_split_offsets.x * 0.9, directional_lights.data[idx].shadow_split_offsets.x, depth_z);
			blur_factor2 = directional_lights.data[idx].shadow_split_offsets.x / directional_lights.data[idx].shadow_split_offsets.y;
		} else if (depth_z < directional_lights.data[idx].shadow_split_offsets.y) {
			vec4 v = vec4(vertex, 1.0);
			v.xyz += light_dir * directional_lights.data[idx].shadow_bias.z;
			coord2 = directional_lights.data[idx].shadow_matrix3 * v;
			pssm_blend = smoothstep(directional_lights.data[idx].shadow_split_offsets.y * 0.9, directional_lights.data[idx].shadow_split_offsets.y, depth_z);
			blur_factor2 = directional_lights.data[idx].shadow_split_offsets.x / directional_lights.data[idx].shadow_split_offsets.z;
		} else if (depth_z < directional_lights.data[idx].shadow_split_offsets.z) {
			vec4 v = vec4(vertex, 1.0);
			v.xyz += light_dir * directional_lights.data[idx].shadow_bias.w;
			coord2 = directional_lights.data[idx].shadow_matrix4 * v;
			pssm_blend = smoothstep(directional_lights.data[idx].shadow_split_offsets.z * 0.9, directional_lights.data[idx].shadow_split_offsets.z, depth_z);
			blur_factor2 = directional_lights.data[idx].shadow_split_offsets.x / directional_lights.data[idx].shadow_split_offsets.w;
		}

		if (pssm_blend > 0.0) {
			coord2 /= coord2.w;
			float shadow2 = float(sample_directional_pcf_shadow(
					directional_shadow_atlas,
					scene_data_block.data.directional_shadow_pixel_size * directional_lights.data[idx].soft_shadow_scale * blur_factor2,
					coord2,
					scene_data_block.data.taa_frame_count));
			shadow = mix(shadow, shadow2, pssm_blend);
		}
	}

	shadow = mix(shadow, 1.0, smoothstep(directional_lights.data[idx].fade_from, directional_lights.data[idx].fade_to, vertex.z));
	return mix(1.0, shadow, directional_lights.data[idx].shadow_opacity);
#endif
}
'''

    replace_once(
        lights,
        """\t} else {
\t\t//no blockers found, so no shadow
\t\treturn half(1.0);
\t}
}

#endif // SHADOWS_DISABLED

half get_omni_attenuation""",
        """\t} else {
\t\t//no blockers found, so no shadow
\t\treturn half(1.0);
\t}
}

""" + sampler_impl + """
#endif // SHADOWS_DISABLED

#ifdef SHADOWS_DISABLED
float sample_directional_shadow(uint idx, vec3 vertex) {
\treturn 1.0;
}
#endif

half get_omni_attenuation""",
        "insert Forward+ directional shadow sampler",
    )

    replace_once(
        lights,
        "light_compute(normal, hvec3(light_rel_vec_norm), eye_vec, size, hvec3(color), false, omni_attenuation * shadow,",
        "light_compute(idx, normal, hvec3(light_rel_vec_norm), eye_vec, size, hvec3(color), false, omni_attenuation * shadow,",
        "pass omni light index",
    )
    replace_once(
        lights,
        "light_compute(normal, hvec3(light_rel_vec_norm), eye_vec, size, hvec3(color), false, spot_attenuation * shadow,",
        "light_compute(idx, normal, hvec3(light_rel_vec_norm), eye_vec, size, hvec3(color), false, spot_attenuation * shadow,",
        "pass spot light index",
    )

    clustered = root / "servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl"
    replace_once(
        clustered,
        "light_compute(normal, L_view, view, 0.0, specular_light_color, true, 1.0,",
        "light_compute(0xFFFFFFFFu, normal, L_view, view, 0.0, specular_light_color, true, 1.0,",
        "mark fake lightmap directional light",
    )
    replace_once(
        clustered,
        "light_compute(normal, directional_lights.data[i].direction, normalize(view), size_A,",
        "light_compute(i, normal, directional_lights.data[i].direction, normalize(view), size_A,",
        "pass Forward+ directional light index",
    )

    mobile = root / "servers/rendering/renderer_rd/shaders/forward_mobile/scene_forward_mobile.glsl"
    replace_once(
        mobile,
        "light_compute(normal, hvec3(L_view_highp), view, saturateHalf(0.0), specular_light_color, true, half(1.0),",
        "light_compute(0xFFFFFFFFu, normal, hvec3(L_view_highp), view, saturateHalf(0.0), specular_light_color, true, half(1.0),",
        "mark mobile fake lightmap directional light",
    )
    replace_once(
        mobile,
        "light_compute(normal, hvec3(directional_lights.data[i].direction), view, saturateHalf(size_A),",
        "light_compute(i, normal, hvec3(directional_lights.data[i].direction), view, saturateHalf(size_A),",
        "pass mobile directional light index",
    )

    changed = run("git", "diff", "--name-only", cwd=root).splitlines()
    expected = {
        "servers/rendering/shader_language.cpp",
        "servers/rendering/shader_types.cpp",
        "servers/rendering/renderer_rd/forward_clustered/scene_shader_forward_clustered.cpp",
        "servers/rendering/renderer_rd/forward_mobile/scene_shader_forward_mobile.cpp",
        "servers/rendering/renderer_rd/shaders/scene_forward_lights_inc.glsl",
        "servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl",
        "servers/rendering/renderer_rd/shaders/forward_mobile/scene_forward_mobile.glsl",
    }
    if set(changed) != expected:
        raise RuntimeError(
            "Unexpected patched file set:\n"
            + "\n".join(changed)
            + "\nExpected:\n"
            + "\n".join(sorted(expected))
        )

    print("HFN directional-shadow engine source patch applied successfully.")
    for path in sorted(expected):
        print(f"  {path}")


if __name__ == "__main__":
    main()
