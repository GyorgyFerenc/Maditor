package v2

import "core:c"
import "core:mem"
import "core:math"
import "core:unicode/utf8"
import s "core:strings"

import rl "vendor:raylib"

v2 :: [2]f32;

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

Vertical_Align :: enum{
    Top,
    Center,
    Bottom,
}

Horizontal_Align :: enum{
    Left,
    Center,
    Right,
}

Draw_Context :: struct{
    box: Box,
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

box_to_rl_rectangle :: proc(b: Box) -> rl.Rectangle{
    return {
        b.pos.x,
        b.pos.y,
        b.size.x,
        b.size.y,
    }
}

rl_rectangle_to_box :: proc(rect: rl.Rectangle) -> Box{
    return {
        pos = {cast(f32) rect.x, cast(f32) rect.y},
        size = {cast(f32) rect.width, cast(f32) rect.height},
    }
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

fill :: proc(ctx: Draw_Context, color: rl.Color){
    draw_box(ctx, ctx.box, color);
}

draw_box :: proc(ctx: Draw_Context, b: Box, color: rl.Color){
    rl.BeginScissorMode(
        cast(c.int) ctx.box.pos.x,
        cast(c.int) ctx.box.pos.y,
        cast(c.int) ctx.box.size.x,
        cast(c.int) ctx.box.size.y,
    );
    defer rl.EndScissorMode();

    rl.DrawRectangleV(ctx.box.pos + b.pos, b.size, color);
}

draw_box_outline :: proc(ctx: Draw_Context, b: Box, thickness: f32, color: rl.Color){
    rl.BeginScissorMode(
        cast(c.int) ctx.box.pos.x,
        cast(c.int) ctx.box.pos.y,
        cast(c.int) ctx.box.size.x,
        cast(c.int) ctx.box.size.y,
    );
    defer rl.EndScissorMode();

    b := b;
    b.pos += ctx.box.pos;
    rl.DrawRectangleLinesEx(box_to_rl_rectangle(b), thickness, color);
}

measure_rune :: proc(ctx: Draw_Context, r: rune, size: f32, font: rl.Font, pos := v2{}) -> Box{
    info := rl.GetGlyphInfo(font, r);
    rect := rl.GetGlyphAtlasRec(font, r);
    ratio := size / cast(f32) font.baseSize;
    b := rl_rectangle_to_box(rect);
    b.pos = 0;
    b.size *= ratio;
    b.pos += pos;
    b.pos.x += cast(f32) info.offsetX * ratio;
    b.pos.y += cast(f32) info.offsetY * ratio;
    return b;
}

draw_rune :: proc(ctx: Draw_Context, r: rune, size: f32, font: rl.Font, pos: v2, color: rl.Color){
    rl.BeginScissorMode(
        cast(c.int) ctx.box.pos.x,
        cast(c.int) ctx.box.pos.y,
        cast(c.int) ctx.box.size.x,
        cast(c.int) ctx.box.size.y,
    );
    defer rl.EndScissorMode();
    rl.DrawTextCodepoint(font, r, ctx.box.pos + pos, size, color);
}

draw_text :: proc(
    ctx: Draw_Context, 
    text: string, 
    font: rl.Font, 
    size: f32, 
    pos: v2, 
    color: rl.Color,
    hspacing: f32 = 0, 
    vspacing: f32 = 0, 
    tab_size: f32 = 40,
    wrap: Maybe(f32) = nil,
    colors: []Draw_Text_Color_Window = {},
){
    feeder := Draw_Text_Feeder{
        ctx  = ctx,
        text = text,
        font = font,
        size = size,
        pos  = pos,
        color    = color,
        hspacing = hspacing,
        vspacing = vspacing,
        tab_size = tab_size,
        wrap     = wrap,
        colors   = colors,
    };

    for r in text{
        feed_rune(&feeder, r);
    }
}

measure_text :: proc(
    ctx: Draw_Context, 
    text: string, 
    font: rl.Font, 
    size: f32, 
    pos: v2, 
    hspacing: f32 = 0, 
    vspacing: f32 = 0, 
    tab_size: f32 = 40,
    wrap: Maybe(f32) = nil,
) -> Box{
    feeder := Draw_Text_Feeder{
        ctx  = ctx,
        text = text,
        font = font,
        size = size,
        pos  = pos,
        hspacing = hspacing,
        vspacing = vspacing,
        tab_size = tab_size,
        wrap     = wrap,

        dont_draw = true,
    };

    for r in text{
        feed_rune(&feeder, r);
    }

    return feeder.bounding_box;
}

Draw_Text_Color_Window :: struct{
    pos: int,
    len: int,
    color: rl.Color,
}

Draw_Text_Feeder :: struct{
    ctx: Draw_Context, 
    text: string, 
    font: rl.Font, 
    size: f32, 
    pos: v2, 
    color: rl.Color,
    hspacing: f32,
    vspacing: f32,
    tab_size: f32,
    wrap: Maybe(f32),
    colors: []Draw_Text_Color_Window,
    
    color_idx: int,
    rune_position: v2,
    dont_draw: bool,

    line: int,  // starts from 0
    count: int,
    idx: int,
    bounding_box: Box,
}

feed_rune :: proc(self: ^Draw_Text_Feeder, r: rune){
    self.count += 1;
    self.idx = self.count - 1;

    w, has_wrap := self.wrap.?;
    r_box := measure_rune(self.ctx, r, self.size, self.font);
    color := self.color; 
    
    if self.color_idx < len(self.colors){
        window := self.colors[self.color_idx];
        if window.pos <= self.idx && self.idx < window.pos + window.len{
            color = window.color;
        } else{
            for self.color_idx < len(self.colors) && self.colors[self.color_idx].pos < self.idx{
                self.color_idx += 1;
            }
        }
    }
 
    if r == '\n'{
        self.line += 1;
        self.rune_position.y += self.size + self.vspacing;
        self.rune_position.x = 0;
    }else if r == '\t'{
        a := math.floor(self.rune_position.x / self.tab_size + 1);
        if has_wrap && a * self.tab_size > w{
            self.rune_position.x = 0;
            self.rune_position.y += self.size + self.vspacing;
        } else {
            self.rune_position.x = a * self.tab_size;
        }
    } else {
        if has_wrap && self.rune_position.x + r_box.size.x > w{
            self.rune_position.x = 0;
            self.rune_position.y += self.size + self.vspacing;
        }
        if !self.dont_draw {
            draw_rune(self.ctx, r, self.size, self.font, self.pos + self.rune_position, color);
        }
        self.rune_position.x += r_box.pos.x + r_box.size.x + self.hspacing;
    }

    self.bounding_box.pos = self.pos;
    if self.rune_position.x > self.bounding_box.size.x{
        self.bounding_box.size.x = self.rune_position.x;
    }
    self.bounding_box.size.y = self.rune_position.y + self.size;
}
