package buffer

import "core:mem"
import "core:fmt"
import "core:os"
import s "core:strings"
import "core:unicode/utf8"

// They remain consistent after inserts and deletes
Pos_Id :: distinct int; 

Buffer :: struct{
    path: Maybe(string),
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

load :: proc(path: string, gpa, fa: mem.Allocator) -> (buffer: Buffer, ok: bool){
    content := read_file(path, gpa, fa) or_return;
    buffer = create(gpa);
    buffer.path = path;
    reserve(&buffer.runes, len(content) / 3 + 1);

    for r in content{
        if r != '\r' do append(&buffer.runes, r);
    }

    return buffer, true;

    read_file :: proc(path: string, gpa, fa: mem.Allocator) -> (content: string, ok: bool){
        context.allocator = gpa;
        context.temp_allocator = fa;
        b := os.read_entire_file(path, fa) or_return;
        content = cast(string) b;
        return content, true;
    }
}

save :: proc(b: Buffer, fa: mem.Allocator) -> (ok: bool){
    builder := s.builder_make(fa);
    
    it := iter(b);
    for r in next(&it){
        s.write_rune(&builder, r);
    }

    path := b.path.? or_return;
    return write_file(path, s.to_string(builder), fa);

    write_file :: proc(path: string, str: string, fa: mem.Allocator) -> bool{
        context.allocator = fa;
        context.temp_allocator = fa;
        return os.write_entire_file(path, transmute([]u8) str);
    }
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

remove_rune :: proc(b: ^Buffer, p: Pos_Id){
    remove_rune_i(b, get_pos(b^, p));
}

remove_rune_i :: proc(b: ^Buffer, pos: int){
    for &position in b.positions{
        if position >= pos{
            position -= 1;
        }
    }

    ordered_remove(&b.runes, pos);
}

remove_rune_left :: proc(b: ^Buffer, p: Pos_Id){
    remove_rune_left_i(b, get_pos(b^, p));
}

remove_rune_left_i :: proc(b: ^Buffer, pos: int){
    if pos > 0{
        for &position in b.positions{
            if position >= pos{
                position -= 1;
            }
        }
        ordered_remove(&b.runes, pos - 1);
    }
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

/*
   Counting starts from 1
*/
get_line_number :: proc(b: Buffer, p: Pos_Id) -> int{
    return get_line_number_i(b, get_pos(b, p));
}

get_line_number_i :: proc(b: Buffer, pos: int) -> int{
    count := 1;

    it := iter(b);
    for r, idx in next(&it){
        if idx == pos do break;
        if r == '\n' do count += 1;
    }

    return count;
}

Iter :: struct{
    b: Buffer,
    pos: int,
}

iter :: proc(b: Buffer) -> Iter{
    return {b, 0};
}

next :: proc(it: ^Iter) -> (rune, int, bool){
    r := get_rune_i(it.b, it.pos);
    if r == 0{
        return {}, {}, false;
    }

    idx := it.pos;
    it.pos += 1;

    return r, idx, true;
}
