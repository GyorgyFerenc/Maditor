package main

import "core:fmt"

Harpoon :: struct{
    app: ^App,
    slots: [NUMBER_OF_SLOTS]Harpoon_Slot,
}

Harpoon_Slot :: struct{
    active: bool,
    window: Window_Id,
}

init_harpoon :: proc(self: ^Harpoon, app: ^App){
    self.app = app;
}


update_harpoon :: proc(self: ^Harpoon){
    for key, i in SLOT_KEYS{
        add_to_slot := ADD_TO_SLOT;
        add_to_slot[len(add_to_slot) - 1] = key;
        if match_key_bind(self.app, add_to_slot){
            self.slots[i].active = true;
            self.slots[i].window = get_active(self.app^);
        }

        jump_to_slot := JUMP_TO_SLOT;
        jump_to_slot[len(jump_to_slot) - 1] = key;
        if match_key_bind(self.app, jump_to_slot) && self.slots[i].active{
            set_active(self.slots[i].window, self.app);
        }

    }
}

draw_harpoon :: proc(self: ^Harpoon){
    // Todo(Ferenc): Redisign the whole ui stuff to make it easier to draw slots
}

NUMBER_OF_SLOTS :: 12
SLOT_KEYS :: [NUMBER_OF_SLOTS]Key{
    Key{key = .Q}, Key{key = .W}, Key{key = .E}, Key{key = .R},
    Key{key = .A}, Key{key = .S}, Key{key = .D}, Key{key = .F},
    Key{key = .Z}, Key{key = .X}, Key{key = .C}, Key{key = .V},
}

ADD_TO_SLOT  :: Key_Bind{{key = .SPACE}, {key = .APOSTROPHE}, {}} // Last one needs to be empty to be replaced
JUMP_TO_SLOT :: Key_Bind{{key = .SPACE}, {key = .H}, {}} // Last one needs to be empty to be replaced






