package main

import "core:c"
import "core:mem"
import "core:unicode/utf8"
import s "core:strings"
//import "core:unicode/utf8"

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

Vertical_Align :: enum{
    Top,
    Center,
    Bottom,
}
align_vertical :: proc(b: Box, to: Box, b_align: Vertical_Align, to_align: Vertical_Align) -> Box{
    result := b;
    switch to_align{
    case .Top:
        switch b_align{
        case .Top:    result.pos.y = to.pos.y;
        case .Center: result.pos.y = to.pos.y - b.size.y / 2;
        case .Bottom: result.pos.y = to.pos.y - b.size.y;
        }
    case .Center:
        switch b_align{
        case .Top:    result.pos.y = to.pos.y + to.size.y / 2;
        case .Center: result.pos.y = to.pos.y + to.size.y / 2 - b.size.y / 2;
        case .Bottom: result.pos.y = to.pos.y + to.size.y / 2 - b.size.y;
        }
    case .Bottom:
        switch b_align{
        case .Top:    result.pos.y = to.pos.y + to.size.y;
        case .Center: result.pos.y = to.pos.y + to.size.y - b.size.y / 2;
        case .Bottom: result.pos.y = to.pos.y + to.size.y - b.size.y;
        }
    }
    return result;
}

Horizontal_Align :: enum{
    Left,
    Center,
    Right,
}
align_horizontal :: proc(b: Box, to: Box, b_align: Horizontal_Align, to_align: Horizontal_Align) -> Box{
    result := b;
    switch to_align{
    case .Left:
        switch b_align{
        case .Left:   result.pos.x = to.pos.x;
        case .Center: result.pos.x = to.pos.x - b.size.x / 2;
        case .Right:  result.pos.x = to.pos.x - b.size.x;
        }
    case .Center:
        switch b_align{
        case .Left:   result.pos.x = to.pos.x + to.size.x / 2;
        case .Center: result.pos.x = to.pos.x + to.size.x / 2 - b.size.x / 2;
        case .Right:  result.pos.x = to.pos.x + to.size.x / 2 - b.size.x;
        }
    case .Right:
        switch b_align{
        case .Left:   result.pos.x = to.pos.x + to.size.x;
        case .Center: result.pos.x = to.pos.x + to.size.x - b.size.x / 2;
        case .Right:  result.pos.x = to.pos.x + to.size.x - b.size.x;
        }
    }
    return result;
}


// Todo(Ferenc): do a custom draw text

// This is janky do better lol
measure_rune_size :: proc(r: rune, style: Text_Style) -> v2{
    str: [5]u8;
    encoded, size := utf8.encode_rune(r);
    for i in 0..<size{
        str[i] = encoded[i];
    }

    ptr := transmute(cstring) &str;
    return rl.MeasureTextEx(style.font, ptr, style.size, style.spacing);

    //    let scale = size / cast(f32) font.baseSize;
    //    let rect = GetGlyphAtlasRec(font, rune);
    //    return rect.width * scale;
}

measure_text :: proc(str: string, style: Text_Style, fa: mem.Allocator) -> v2{
    cstr := s.clone_to_cstring(str, fa);
    return rl.MeasureTextEx(style.font, cstr, style.size, style.spacing);
}
