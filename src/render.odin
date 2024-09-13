package main

import "core:c"

import rl "vendor:raylib"

Box :: struct{
    pos:  v2,
    size: v2,
}

add_margin :: proc(r: Box, margin: f32) -> Box{
    return {r.pos - margin, r.size + 2 * margin};
}

remove_padding :: proc(r: Box, padding: f32) -> Box{
    return {r.pos + padding, r.size - 2 * padding};
}

begin_box_draw_mode :: proc(b: Box){
    rl.BeginScissorMode(
        cast(c.int) b.pos.x,
        cast(c.int) b.pos.y,
        cast(c.int) b.size.x,
        cast(c.int) b.size.y,
    );
}

end_box_draw_mode :: proc(){
    rl.EndScissorMode();
}


