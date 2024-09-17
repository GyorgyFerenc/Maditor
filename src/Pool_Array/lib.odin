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
}

create :: proc($T: typeid, allocator: mem.Allocator, len := 1) -> Pool_Array(T){
    pool := Pool_Array(T){
        array = make([dynamic]Elem(T), len, allocator = allocator),
        free = Null_Id,
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
    return id;
}

free_all :: proc(self: ^Pool_Array($T)){
    self.free = Null_Id;

    for &el, id in self.array{
        el.next = self.free;
        el.free = true;
        self.free = cast(Id) id;
    }
}

free :: proc(self: ^Pool_Array($T), id: Id){
    self.array[id].next = self.free;
    self.array[id].free = true;
    self.free = id;
}
