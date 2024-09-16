package main

import "core:c"

import rl "vendor:raylib"

Box :: struct{
    pos:  v2,
    size: v2,
}

Box_Side :: enum{
    Left,
    Right,
    Top,
    Bottom,
}

add_margin :: proc(r: Box, margin: f32) -> Box{
    return {r.pos - margin, r.size + 2 * margin};
}

remove_padding :: proc(r: Box, padding: f32) -> Box{
    return {r.pos + padding, r.size - 2 * padding};
}

remove_padding_side :: proc(r: Box, padding: f32, side: Box_Side) -> (result: Box, removed_side: Box){
    switch side{
    case .Left:   
        result = r;
        result.pos.x  += padding;
        result.size.x -= padding;
        removed_side = r;
        removed_side.size.x = padding;
        return result, removed_side;
    case .Right:  
        result = r;
        result.size.x -= padding;
        removed_side = r;
        removed_side.pos.x += result.size.x;
        removed_side.size.x = padding;
        return result, removed_side;
    case .Top:
        result = r;
        result.pos.y  += padding;
        result.size.y -= padding;
        removed_side = r;
        removed_side.size.y = padding;
        return result, removed_side;
    case .Bottom:
        result = r;
        result.size.y -= padding;
        removed_side = r;
        removed_side.pos.y += result.size.y
        removed_side.size.y = padding;
        return result, removed_side;
    }

    return;
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


