shader_type canvas_item;
render_mode unshaded;

uniform bool Smooth = true;
uniform float width : hint_range(0.0, 64.0) = 2.0;
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 0.0, 1.0); // Желтый для видимости
uniform int pixel_size : hint_range(1, 10) = 1;
uniform float width_speed : hint_range(0.1, 10.0) = 2.0;

void fragment()
{
    // Пульсация обводки
    float pulse_offset = sin(TIME * width_speed) * 0.5;
    float _width = width + pulse_offset;
    _width = max(0.0, _width);
    
    // Размер пикселя
    vec2 unit = (1.0 / float(pixel_size)) * TEXTURE_PIXEL_SIZE;
    
    vec4 pixel_color = texture(TEXTURE, UV);
    
    if (pixel_color.a == 0.0) {
        pixel_color = outline_color;
        pixel_color.a = 0.0;
        
        for (float x = -ceil(_width); x <= ceil(_width); x++) {
            for (float y = -ceil(_width); y <= ceil(_width); y++) {
                if (texture(TEXTURE, UV + vec2(x*unit.x, y*unit.y)).a == 0.0 || (x==0.0 && y==0.0)) {
                    continue;
                }
                
                if (Smooth) {
                    float distance = sqrt(x*x + y*y);
                    if (distance <= _width) {
                        pixel_color.a += outline_color.a * (1.0 - distance/_width);
                        if (pixel_color.a > 1.0) {
                            pixel_color.a = 1.0;
                        }
                    }
                } else {
                    pixel_color.a = outline_color.a;
                    break;
                }
            }
        }
    }
    COLOR = pixel_color;
}