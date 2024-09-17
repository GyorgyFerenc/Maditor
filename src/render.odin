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

add_margin_side :: proc(r: Box, margin: f32, side: Box_Side) -> (result: Box, added_side: Box){
    switch side{
    case .Left:   
        result = r;
        result.pos.x  -= margin;
        result.size.x += margin;
        added_side = result;
        added_side.size.x = margin;
        return result, added_side;
    case .Right:  
        result = r;
        result.size.x += margin;
        added_side = r;
        added_side.pos.x += r.size.x;
        added_side.size.x = margin;
        return result, added_side;
    case .Top:
        result = r;
        result.pos.y  -= margin;
        result.size.y += margin;
        added_side = result;
        added_side.size.y = margin;
        return result, added_side;
    case .Bottom:
        result = r;
        result.size.y += margin;
        added_side = r;
        added_side.pos.y += r.size.y
        added_side.size.y = margin;
        return result, added_side;
    }
    return;
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

box_to_rl_rectangle :: proc(b: Box) -> rl.Rectangle{
    return {
        b.pos.x,
        b.pos.y,
        b.size.x,
        b.size.y,
    }
}

draw_box :: proc(b: Box, c: rl.Color){
    rl.DrawRectangleV(b.pos, b.size, c);
}


draw_box_outline :: proc(b: Box, thickness: f32, c: rl.Color){
    rl.DrawRectangleLinesEx(box_to_rl_rectangle(b), thickness, c);
}

Text_Style :: struct{
    font: rl.Font,
    size: f32,
    spacing: f32,
    color: rl.Color,
}
