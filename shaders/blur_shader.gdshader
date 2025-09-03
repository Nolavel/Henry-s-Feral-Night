shader_type canvas_item;

uniform float blur_amount : hint_range(0, 5.5);

void fragment() {
    vec4 color = texture(TEXTURE, UV);
    color += texture(TEXTURE, UV + vec2(blur_amount, 0.0) * TEXTURE_PIXEL_SIZE);
    color += texture(TEXTURE, UV - vec2(blur_amount, 0.0) * TEXTURE_PIXEL_SIZE);
    color += texture(TEXTURE, UV + vec2(0.0, blur_amount) * TEXTURE_PIXEL_SIZE);
    color += texture(TEXTURE, UV - vec2(0.0, blur_amount) * TEXTURE_PIXEL_SIZE);
    COLOR = color / 5.0;
}