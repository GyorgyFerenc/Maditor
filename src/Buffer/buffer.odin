package buffer

/*
    Todo(Ferenc): Needs a rewrite because Buffer assumes rune pos not byte pos
*/

import "core:mem"
import "core:fmt"
import "core:os"
import s "core:strings"
import "core:unicode/utf8"
import "base:builtin"

// They remain consistent after inserts and deletes
Pos_Id :: distinct int; 

Buffer :: struct{
    path:      Maybe(string),
    runes:     [dynamic]rune,
    positions: [dynamic]int,
    dirty:     bool, // Todo(Ferenc): make a procedure and check with the file on disk
    allocator: mem.Allocator,
}

create :: proc(allocator: mem.Allocator) -> Buffer{
    b := Buffer{
        runes     = make([dynamic]rune, allocator = allocator),
        positions = make([dynamic]int, allocator = allocator),
        allocator = allocator,
    }
    return b;
}

destroy :: proc(b: Buffer) {
    p, ok := b.path.?;
    if ok do delete(p, b.allocator);
    delete(b.runes);
    delete(b.positions);
}

clone :: proc(b: Buffer, allocator: mem.Allocator) -> Buffer{
    new_b := Buffer{};
    new_b.allocator = allocator;
    p, ok := b.path.?;
    if ok {
        set_path(&new_b, p);
    }
    new_b.runes =     clone_dyn_array(b.runes, allocator);
    new_b.positions = clone_dyn_array(b.positions, allocator);
    return new_b;
}

// clones the path
set_path :: proc(b: ^Buffer, path: string){
    b.path = s.clone(path, b.allocator);
}

// clones the path
load :: proc(path: string, gpa, fa: mem.Allocator) -> (buffer: Buffer, ok: bool){
    content := read_file(path, gpa, fa) or_return;
    buffer = create(gpa);
    set_path(&buffer, path);
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

save :: proc(b: ^Buffer, fa: mem.Allocator) -> (ok: bool){
    builder := s.builder_make(fa);
    b.dirty = false;
    
    it := iter(b^);
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
    if value < 0 || value >= length(b^) do return;
    b.positions[p] = value;
}

set_pos_to_pos :: proc(b: ^Buffer, p: Pos_Id, p2: Pos_Id){
    b.positions[p] = get_pos(b^, p2);
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
    b.dirty = true;

    for &position in b.positions{
        if position >= pos{
            if position + 1 < length(b^){
                position += 1;
            }
        }
    }

    inject_at(&b.runes, pos, r);
}

remove_rune :: proc(b: ^Buffer, p: Pos_Id){
    remove_rune_i(b, get_pos(b^, p));
}

remove_rune_i :: proc(b: ^Buffer, pos: int){
    b.dirty = true;

    for &position in b.positions{
        if position >= pos{
            if position - 1 >= 0{
                position -= 1;
            }

        }
    }

    ordered_remove(&b.runes, pos);
}

remove_range :: proc(b: ^Buffer, p: Pos_Id, len: int){
    remove_range_i(b, get_pos(b^, p), len);
}

remove_range_i :: proc(b: ^Buffer, pos, len: int){
    b.dirty = true;

    for _ in 0..<len{
        remove_rune_i(b, pos);
    }
}

remove_rune_left :: proc(b: ^Buffer, p: Pos_Id){
    remove_rune_left_i(b, get_pos(b^, p));
}

remove_rune_left_i :: proc(b: ^Buffer, pos: int){
    b.dirty = true;

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

/*
    Counting of line numbers starts from 1
*/
get_position_of_line :: proc(b: Buffer, line_number: int) -> int{
    line_number := line_number - 1;
    pos := 0;

    it := iter(b);
    for r, idx in next(&it){
        if line_number <= 0 do break;
        if r == '\n' {
            line_number -= 1;
            pos = idx + 1;
        }
    }

    if pos >= length(b){
        pos = length(b) - 1;
    }

    return pos;
}

Iter :: struct{
    b: Buffer,
    pos: int,
}

iter :: proc(b: Buffer) -> Iter{
    return {b, 0};
}

seek :: proc(it: ^Iter, to: int){
    it.pos = to;
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

text_equal :: proc(b1, b2: Buffer) -> bool{
    if length(b1) != length(b2) do return false;

    it := iter(b1);
    for r, idx in next(&it){
        if r != get_rune_i(b2, idx){
            return false;
        }
    }

    return true;
}


clone_dyn_array :: proc(array: $T, allocator: mem.Allocator) -> T{
    new_array := make(T, len(array), len(array), allocator = allocator);
    for el, i in array{
        new_array[i] = el;
    }
    return new_array;
}


