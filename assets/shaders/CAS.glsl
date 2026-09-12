// FidelityFX Contrast Adaptive Sharpening (CAS) for MPV
//!DESC AMD FidelityFX Contrast Adaptive Sharpening (CAS)
//!HOOK MAIN
//!BIND HOOKED

#define SHARPENING 0.8

vec4 hook() {
    vec2 pos = HOOKED_pos;
    vec2 pt = HOOKED_pt;

    vec3 a = HOOKED_tex(pos + vec2(-pt.x, -pt.y)).rgb;
    vec3 b = HOOKED_tex(pos + vec2(0.0, -pt.y)).rgb;
    vec3 c = HOOKED_tex(pos + vec2(pt.x, -pt.y)).rgb;
    vec3 d = HOOKED_tex(pos + vec2(-pt.x, 0.0)).rgb;
    vec3 e = HOOKED_tex(pos).rgb;
    vec3 f = HOOKED_tex(pos + vec2(pt.x, 0.0)).rgb;
    vec3 g = HOOKED_tex(pos + vec2(-pt.x, pt.y)).rgb;
    vec3 h = HOOKED_tex(pos + vec2(0.0, pt.y)).rgb;
    vec3 i = HOOKED_tex(pos + vec2(pt.x, pt.y)).rgb;

    // Min and max of 3x3 cross
    vec3 min_rgb = min(min(min(d, e), min(f, b)), h);
    vec3 min_rgb2 = min(min(min(min_rgb, a), min(c, g)), i);
    min_rgb += min_rgb2;

    vec3 max_rgb = max(max(max(d, e), max(f, b)), h);
    vec3 max_rgb2 = max(max(max(max_rgb, a), max(c, g)), i);
    max_rgb += max_rgb2;

    // Smooth filter ratio
    vec3 rcp_max_rgb = vec3(1.0) / max_rgb;
    vec3 amp_rgb = clamp(min(min_rgb, 2.0 - max_rgb) * rcp_max_rgb, 0.0, 1.0);
    amp_rgb = inversesqrt(amp_rgb);

    float peak = -3.0 * SHARPENING + 8.0;
    vec3 w_rgb = -vec3(1.0) / (amp_rgb * peak);
    vec3 rcp_weight = vec3(1.0) / (1.0 + 4.0 * w_rgb);

    vec3 window = (b + d) + (f + h);
    vec3 out_rgb = clamp((window * w_rgb + e) * rcp_weight, 0.0, 1.0);

    return vec4(out_rgb, HOOKED_tex(pos).a);
}
