package buffer

import "core:mem"
import "core:fmt"
import "core:unicode/utf8"

// They remain consistent after inserts and deletes
Pos_Id :: distinct int; 

Buffer :: struct{
    file_path: Maybe(string),
    runes:     [dynamic]rune,
    positions: [dynamic]int,
}

create :: proc(allocator: mem.Allocator) -> Buffer{
    b := Buffer{
        runes     = make([dynamic]rune, allocator = allocator),
        positions = make([dynamic]int, allocator = allocator),
    }
    return b;
}

destroy :: proc(b: Buffer) {
    delete(b.runes);
    delete(b.positions);
}

new_pos :: proc(b: ^Buffer) -> Pos_Id{
    l := len(b.positions);
    append(&b.positions, 0);
    return cast(Pos_Id) l;
}

delete_pos :: proc(b: ^Buffer){
    /* Currently cannot delete */
}

set_pos :: proc(b: ^Buffer, p: Pos_Id, value: int){
    b.positions[p] = value;
}

get_pos :: proc(b: Buffer, p: Pos_Id) -> int{
    return b.positions[p];
}

Move_Direction :: enum{
    Up,
    Down,
    Left,
    Right,
}

move_pos :: proc(b: ^Buffer, p: Pos_Id, direction: Move_Direction) -> bool{
    position := get_pos(b^, p);

    switch direction{
    case .Up:   
        line_begin := find_line_begin_i(b^, position);
        pos_from_begin := position - line_begin;
        if line_begin == 0 do return false;
        pos := line_begin - 1; 
        line_begin = find_line_begin_i(b^, pos);
        line_end  := find_line_end_i(b^, pos);
        new_position := clamp(line_begin + pos_from_begin, line_begin, line_end);
        set_pos(b, p, new_position);
        return true;
    case .Down: 
        line_end := find_line_end_i(b^, position);
        line_begin := find_line_begin_i(b^, position);
        pos_from_begin := position - line_begin;
        if line_end >= length(b^) do return false;
        pos := line_end + 1;
        line_begin    = find_line_begin_i(b^, pos);
        line_end      = find_line_end_i(b^, pos);
        new_position := clamp(line_begin + pos_from_begin, line_begin, line_end);
        set_pos(b, p, new_position);
        return true;
    case .Left: 
        new_position := position - 1;
        r := get_rune_i(b^, new_position);
        if r != 0 && r != '\n'{
            set_pos(b, p, new_position);
            return true;
        }
        return false;
    case .Right:
        new_position := position + 1;
        r := get_rune_i(b^, new_position);
        if r != 0 && r != '\n'{
            set_pos(b, p, new_position);
            return true;
        }
        return false;
    }

    return false;
}

find_line_begin :: proc(b: Buffer, p: Pos_Id) -> int{
    return find_line_begin_i(b, get_pos(b, p));
}

find_line_begin_i :: proc(b: Buffer, pos: int) -> int{
    line_begin := 0;

    #reverse for r, i in b.runes[:pos]{
        if r == '\n' {
            line_begin = i + 1;
            break;
        }
    }

    return line_begin;
}

find_line_end :: proc(b: Buffer, p: Pos_Id) -> int{
    return find_line_end_i(b, get_pos(b, p));
}

find_line_end_i :: proc(b: Buffer, pos: int) -> int{
    line_end := len(b.runes);

    for r, i in b.runes[pos:]{
        if r == '\n' {
            line_end = pos + i;
            break;
        }
    }

    return line_end;
}

find_line_len :: proc(b: Buffer, p: Pos_Id) -> int{
    return find_line_len_i(b, get_pos(b, p));
}

find_line_len_i :: proc(b: Buffer, pos: int) -> int{
    return find_line_end_i(b, pos) - find_line_begin_i(b, pos) + 1;
}


get_rune :: proc(b: Buffer, p: Pos_Id) -> rune{
    return get_rune_i(b, get_pos(b, p));
}

get_rune_i :: proc(b: Buffer, pos: int) -> rune{
    if pos < 0 || pos >= len(b.runes) do return 0;
    return b.runes[pos];
}

insert_rune :: proc(b: ^Buffer, p: Pos_Id, r: rune){
    insert_rune_i(b, get_pos(b^, p), r);
}

insert_rune_i :: proc(b: ^Buffer, pos: int, r: rune){
    for &position in b.positions{
        if position >= pos{
            position += 1;
        }
    }

    inject_at(&b.runes, pos, r);
}

insert_string :: proc(b: ^Buffer, p: Pos_Id, str: string){
    //insert_string_i(b, get_pos(b^, p), str);
    for r in str{
        insert_rune(b, p, r);
    }
}

insert_string_i :: proc(b: ^Buffer, pos: int, str: string){
    for r, i in str{
        insert_rune_i(b, pos + i, r);
    }
}

to_string :: proc(b: Buffer, allocator: mem.Allocator) -> string{
    data := make([dynamic]u8, allocator = allocator);
    for r in b.runes{
        bytes, size := utf8.encode_rune(r);
        for i in 0..<size{
            append(&data, bytes[i]);
        }
    }

    return cast(string) data[:];
}

length :: proc(b: Buffer) -> int{
    return len(b.runes);
}

Iter :: struct{
    b: ^Buffer,
    pos: int,
}

iter :: proc(b: ^Buffer) -> Iter{
    return {b, 0};
}

next :: proc(it: ^Iter) -> (rune, int, bool){
    r := get_rune_i(it.b^, it.pos);
    if r == 0{
        return {}, {}, false;
    }

    idx := it.pos;
    it.pos += 1;

    return r, idx, true;
}
