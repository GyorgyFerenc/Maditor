package main

import "core:c"
import "core:math"
import "core:mem"
import "core:fmt"



v2  :: [2]f32;
v2i :: [2]int;
v2ci:: [2]c.int;

v2_to_v2ci :: proc(v: v2) -> v2ci{
    return {cast(c.int) v.x, cast(c.int) v.y};
}

// Todo(Ferenc): add rest
to_v2ci :: proc{
    v2_to_v2ci,
}

v2i_to_v2 :: proc(v: v2i) -> v2{
    return v2{cast(f32) v.x, cast(f32) v.y};
}

to_v2 :: proc{
    v2i_to_v2,
}

floor_v2 :: proc(p: v2) -> v2{
    return {
        math.floor(p.x),
        math.floor(p.y),
    }
}

ALIGN :: mem.DEFAULT_ALIGNMENT;

Growth_Allocator :: struct{
    allocator: mem.Allocator,
    size: uint,
    mems:   [dynamic][]byte,
    buddies: [dynamic]mem.Buddy_Allocator,
}

create_growth_allocator :: proc(allocator: mem.Allocator, size: uint) -> Growth_Allocator{
    return {
        allocator = allocator,
        size = size,
        mems = make([dynamic][]byte, allocator = allocator),
        buddies = make([dynamic]mem.Buddy_Allocator, allocator = allocator),

    };
}

destroy_growth_allocator :: proc(self: Growth_Allocator){
    for m in self.mems{
        delete(m, allocator = self.allocator);
    }
    delete(self.mems);
    delete(self.buddies);
}

growth_allocator :: proc(self: ^Growth_Allocator) -> mem.Allocator{
	return mem.Allocator{
		data = self,
		procedure = growth_allocator_proc,
	}
}

growth_allocator_alloc_bytes_non_zeroed :: proc(self: ^Growth_Allocator, size: uint) -> ([]byte, mem.Allocator_Error){
    if size > self.size{
        growth_size := size;
        if !mem.is_power_of_two(cast(uintptr) growth_size) do growth_size = round_up_to_power_of_two(size);

        l, err := growth(self, growth_size);
        if err != .None do return {}, err;

        return mem.buddy_allocator_alloc_bytes_non_zeroed(&self.buddies[l], size);
    }
    
    for &buddy in self.buddies{
        ptr, err := mem.buddy_allocator_alloc_bytes_non_zeroed(&buddy, size);
        if err == .None do return ptr, err;
    }
 
    l, err := growth(self, self.size);
    if err != .None do return {}, err;
    return mem.buddy_allocator_alloc_bytes_non_zeroed(&self.buddies[l], size);
    
    growth :: proc(self: ^Growth_Allocator, size: uint) -> (int, mem.Allocator_Error){
        l := len(self.buddies);
        
        bytes, err := mem.alloc_bytes(cast(int) size, ALIGN, self.allocator);
        if err != .None do return {}, err;
        
        append(&self.mems, bytes);
        append(&self.buddies, mem.Buddy_Allocator{});

        mem.buddy_allocator_init(&self.buddies[l], self.mems[l], ALIGN);
        return l, .None;
    }
}

growth_allocator_alloc_bytes :: proc(self: ^Growth_Allocator, size: uint) -> ([]byte, mem.Allocator_Error){
	bytes, err := growth_allocator_alloc_bytes_non_zeroed(self, size);
	if bytes != nil {
		mem.zero_slice(bytes);
	}
	return bytes, err;
}

growth_allocator_alloc_non_zeroed :: proc(self: ^Growth_Allocator, size: uint) -> (rawptr, mem.Allocator_Error){
	bytes, err := growth_allocator_alloc_bytes_non_zeroed(self, size);
	return raw_data(bytes), err;
}

growth_allocator_alloc :: proc(self: ^Growth_Allocator, size: uint) -> (rawptr, mem.Allocator_Error){
	bytes, err := growth_allocator_alloc_bytes(self, size);
	return raw_data(bytes), err;
}

growth_allocator_free :: proc(self: ^Growth_Allocator, ptr: rawptr) -> mem.Allocator_Error{
    if ptr == nil do return nil;
    for &buddy in self.buddies{
        err := mem.buddy_allocator_free(&buddy, ptr);
        if err == nil do break;
    }
    
    return nil;
}

growth_allocator_free_all :: proc(self: ^Growth_Allocator){
    for &buddy in self.buddies{
        mem.buddy_allocator_free_all(&buddy);
    }
}

growth_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> ([]byte, mem.Allocator_Error) {
	self := (^Growth_Allocator)(allocator_data)
	switch mode {
	case .Alloc:
		return growth_allocator_alloc_bytes(self, uint(size))
	case .Alloc_Non_Zeroed:
		return growth_allocator_alloc_bytes_non_zeroed(self, uint(size))
	case .Resize:
        i := 0;
        for mem, idx in self.mems{
            first := raw_data(mem);
            last  := raw_data(mem[len(mem) - 1:]);
            if first <= old_memory && old_memory <= last{
                i = idx;
                break;
            }
        }
		return mem.resize_bytes(mem.byte_slice(old_memory, old_size), size, alignment, mem.buddy_allocator(&self.buddies[i]));
	case .Resize_Non_Zeroed:
        i := 0;
        for mem, idx in self.mems{
            first := raw_data(mem);
            last  := raw_data(mem[len(mem) - 1:]);
            if first <= old_memory && old_memory <= last{
                i = idx;
                break;
            }
        }
		return mem.resize_bytes_non_zeroed(mem.byte_slice(old_memory, old_size), size, alignment, mem.buddy_allocator(&self.buddies[i]));
	case .Free:
		return nil, growth_allocator_free(self, old_memory);
	case .Free_All:
		growth_allocator_free_all(self);
	case .Query_Features:
		set := (^mem.Allocator_Mode_Set)(old_memory);
		if set != nil {
			set^ = {.Query_Features, .Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed, .Free, .Free_All, .Query_Info};
		}
		return nil, nil;
	case .Query_Info:
/*
		info := (^Allocator_Query_Info)(old_memory)
		if info != nil && info.pointer != nil {
			ptr := info.pointer
			if !(b.head <= ptr && ptr <= b.tail) {
				return nil, .Invalid_Pointer
			}
			block := (^Buddy_Block)(([^]byte)(ptr)[-b.alignment:])
			info.size = int(block.size)
			info.alignment = int(b.alignment)
			return byte_slice(info, size_of(info^)), nil
		}
		return nil, nil
*/
	}
	return nil, nil

}


//buddy_allocator_alloc :: proc(b: ^Buddy_Allocator, size: uint) -> (rawptr, Allocator_Error) {

/*
buddy_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	loc := #caller_location,
) -> ([]byte, Allocator_Error) {
	b := (^Buddy_Allocator)(allocator_data)
	switch mode {
	case .Alloc:
		return buddy_allocator_alloc_bytes(b, uint(size))
	case .Alloc_Non_Zeroed:
		return buddy_allocator_alloc_bytes_non_zeroed(b, uint(size))
	case .Resize:
		return default_resize_bytes_align(byte_slice(old_memory, old_size), size, alignment, buddy_allocator(b), loc)
	case .Resize_Non_Zeroed:
		return default_resize_bytes_align_non_zeroed(byte_slice(old_memory, old_size), size, alignment, buddy_allocator(b), loc)
	case .Free:
		return nil, buddy_allocator_free(b, old_memory)
	case .Free_All:
		buddy_allocator_free_all(b)
	case .Query_Features:
		set := (^Allocator_Mode_Set)(old_memory)
		if set != nil {
			set^ = {.Query_Features, .Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed, .Free, .Free_All, .Query_Info}
		}
		return nil, nil
	case .Query_Info:
		info := (^Allocator_Query_Info)(old_memory)
		if info != nil && info.pointer != nil {
			ptr := info.pointer
			if !(b.head <= ptr && ptr <= b.tail) {
				return nil, .Invalid_Pointer
			}
			block := (^Buddy_Block)(([^]byte)(ptr)[-b.alignment:])
			info.size = int(block.size)
			info.alignment = int(b.alignment)
			return byte_slice(info, size_of(info^)), nil
		}
		return nil, nil
	}
	return nil, nil
}
*/


round_up_to_power_of_two :: proc(n: uint) -> uint{
    for i in POWERS_OF_TWO{
        if n < cast(uint) i do return cast(uint) i;
    }
    return 0;
}

POWERS_OF_TWO :: [?]u128{
1 << 0,
1 << 1,
1 << 2,
1 << 3,
1 << 4,
1 << 5,
1 << 6,
1 << 7,
1 << 8,
1 << 9,
1 << 10,
1 << 11,
1 << 12,
1 << 13,
1 << 14,
1 << 15,
1 << 16,
1 << 17,
1 << 18,
1 << 19,
1 << 20,
1 << 21,
1 << 22,
1 << 23,
1 << 24,
1 << 25,
1 << 26,
1 << 27,
1 << 28,
1 << 29,
1 << 30,
1 << 31,
1 << 32,
1 << 33,
1 << 34,
1 << 35,
1 << 36,
1 << 37,
1 << 38,
1 << 39,
1 << 40,
1 << 41,
1 << 42,
1 << 43,
1 << 44,
1 << 45,
1 << 46,
1 << 47,
1 << 48,
1 << 49,
1 << 50,
1 << 51,
1 << 52,
1 << 53,
1 << 54,
1 << 55,
1 << 56,
1 << 57,
1 << 58,
1 << 59,
1 << 60,
1 << 61,
1 << 62,
1 << 63,
1 << 64,
1 << 65,
1 << 66,
1 << 67,
1 << 68,
1 << 69,
1 << 70,
1 << 71,
1 << 72,
1 << 73,
1 << 74,
1 << 75,
1 << 76,
1 << 77,
1 << 78,
1 << 79,
1 << 80,
1 << 81,
1 << 82,
1 << 83,
1 << 84,
1 << 85,
1 << 86,
1 << 87,
1 << 88,
1 << 89,
1 << 90,
1 << 91,
1 << 92,
1 << 93,
1 << 94,
1 << 95,
1 << 96,
1 << 97,
1 << 98,
1 << 99,
1 << 100,
1 << 101,
1 << 102,
1 << 103,
1 << 104,
1 << 105,
1 << 106,
1 << 107,
1 << 108,
1 << 109,
1 << 110,
1 << 111,
1 << 112,
1 << 113,
1 << 114,
1 << 115,
1 << 116,
1 << 117,
1 << 118,
1 << 119,
1 << 120,
1 << 121,
1 << 122,
1 << 123,
1 << 124,
1 << 125,
1 << 126,
1 << 127,
//1 << 128,
};


