package pool_array

import "core:mem"

// Todo(Ferenc): Add generational id

Id :: distinct int;
Null_Id :: Id(-1);

Elem :: struct ($T: typeid){
    el: T,
    next: Id,
    free: bool,
}

Pool_Array :: struct ($T: typeid){
    array: [dynamic]Elem(T),
    free: Id,
    len: int,
}

create :: proc($T: typeid, allocator: mem.Allocator, len := 1) -> Pool_Array(T){
    pool := Pool_Array(T){
        array = make([dynamic]Elem(T), len, allocator = allocator),
        free  = Null_Id,
        len   = 0,
    };

    free_all(&pool);
    return pool;
}

destroy :: proc(self: Pool_Array($T)){
    delete(self.array);
}

get :: proc(self: Pool_Array($T), id: Id) -> (T, bool){
    if 0 <= id && cast(int) id < len(self.array) {
        if !self.array[id].free{
            return self.array[id].el, true;
        }
    }

    return {}, false;
}

get_ptr :: proc(self: Pool_Array($T), id: Id) -> (^T, bool){
    if 0 <= id && cast(int) id < len(self.array) {
        if !self.array[id].free{
            return &self.array[id].el, true;
        }
    }
    return {}, false;
}

get_unsafe :: proc(self: Pool_Array($T), id: Id) -> T{
    return self.array[id].el;
}

get_ptr_unsafe :: proc(self: Pool_Array($T), id: Id) -> ^T{
    return &self.array[id].el;
}

set :: proc(self: ^Pool_Array($T), id: Id, el: T){
    if 0 <= id && cast(int) id < len(self.array) do self.array[id].el = el;
}

alloc :: proc(self: ^Pool_Array($T), el: T) -> Id{
    id: Id = Null_Id;

    if self.free != Null_Id{
        id = self.free;
    } else {
        id = cast(Id) len(self.array);
        append(&self.array, Elem(T){});
        self.array[id].next = Null_Id;
    }

    self.free = self.array[id].next;
    self.array[id].el = el;
    self.array[id].free = false;
    self.len += 1;
    return id;
}

free_all :: proc(self: ^Pool_Array($T)){
    self.free = Null_Id;
    self.len  = 0;

    for &el, id in self.array{
        el.next = self.free;
        el.free = true;
        self.free = cast(Id) id;
    }
}

free :: proc(self: ^Pool_Array($T), id: Id){
    if !self.array[id].free do self.len -= 1;

    self.array[id].next = self.free;
    self.array[id].free = true;
    self.free = id;
}

length :: proc(self: Pool_Array($T), count_frees := false) -> int{
    if count_frees{ return len(self.array); }
    return self.len;
}

Iter :: struct($T: typeid){
    array: Pool_Array(T),
    pos: int,
    count: int,
}

Iter_Value :: struct($T: typeid){
    value:     T,
    value_ptr: ^T,
    id:    int,
    count: int,
}

next :: proc(it: ^Iter($T)) -> (Iter_Value(T), bool){
    for {
        if it.pos >= len(it.array.array) do return {}, false;
        elem := &it.array.array[it.pos];
        if !elem.free{
            it_value := Iter_Value(T){};
            it_value.value     = elem.el;
            it_value.value_ptr = &elem.el;
            it_value.id = it.pos;
            it.pos += 1;
            it.count += 1;
            it_value.count = it.count;
            return it_value, true;
        }
        it.pos += 1;
    }
}

iter :: proc(self: Pool_Array($T)) -> Iter(T){
    return Iter(T){self, 0, 0};
}

