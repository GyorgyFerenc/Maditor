package main

import "core:fmt"
import t "core:odin/tokenizer"
import p "core:odin/parser"
import "core:odin/ast"
import s "core:strings"
import "src:Buffer"
import "core:path/filepath"
import "core:slice"
import "core:unicode/utf8"

import rl "vendor:raylib"


Odin_Plugin :: struct{
    app: ^App,
    tw:  ^Text_Window,
}

init_odin_plugin :: proc(self: ^Odin_Plugin, app: ^App){
    self.app = app;
}

update_odin_plugin :: proc(self: ^Odin_Plugin, app: ^App){
    window, ok := get_active_window(app);
    if !ok do return;

    if window.kind != Text_Window do return;

    tw := cast(^Text_Window) window.data;
    self.tw = tw;
    path, ok2 := tw.buffer.path.?; // Todo(Ferenc): make buffer.path into a string and not a Maybe
    if !ok2 do return;
    
    if !s.ends_with(path, ".odin") do return;
    text := Buffer.to_string(tw.buffer, self.app.fa);

    tokenizer_window_coloring(self, tw, text, path);
}

destroy_odin_plugin :: proc(self: ^Odin_Plugin){
}

parser_coloring :: proc(self: ^Odin_Plugin, tw: ^Text_Window, text: string, path: string){
    context.allocator      = self.app.fa;
    context.temp_allocator = self.app.fa;

    dir := filepath.dir(path, self.app.fa);
    path, abs_ok := filepath.abs(path, self.app.fa);
    if !abs_ok do return;
    

    pkg, ok := p.parse_package_from_path(dir);
    if !ok do return;
    file, ok2 := pkg.files[path];

    visitor := ast.Visitor{
        data  = self,
        visit = proc(v: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor{
            if node == nil do return v;
            self := cast(^Odin_Plugin) v.data;
            tw := cast(^Text_Window) self.tw;
            color_scheme := self.app.settings.color_scheme;

            #partial switch n in node.derived{
            case ^ast.Package_Decl:
                fmt.println("package decl asd");
            case ^ast.Call_Expr:
                id, ok := n.expr.derived_expr.(^ast.Ident); 
                if ok {
                    p1 := id.pos.offset; 
                    p2 := id.end.offset;
                    len := p2 - p1;
                    add_color(tw, Text_Window_Color{
                        color = color_scheme.procedure,
                        pos = p1,
                        len = len,
                    });
                }
            case ^ast.Value_Decl:
                if len(n.names) < 1 do break;
                if len(n.values) < 1 do break;

                id, ok := n.names[0].derived_expr.(^ast.Ident);
                _, ok2 := n.values[0].derived_expr.(^ast.Proc_Lit);
                if ok && ok2 {
                    p1 := id.pos.offset; 
                    p2 := id.end.offset;
                    len := p2 - p1;
                    add_color(tw, Text_Window_Color{
                        color = color_scheme.procedure,
                        pos = p1,
                        len = len,
                    });
                }
            }

            return v;
        } 
    };
    ast.walk(&visitor, file);
}

tokenizer_coloring :: proc(self: ^Odin_Plugin, tw: ^Text_Window, text: string, path: string){
    color_scheme := self.app.settings.color_scheme;

    tokenizer: t.Tokenizer; 
    t.init(&tokenizer, text, path, proc(p: t.Pos, fmt: string, args: ..any){});
    for {
        token := t.scan(&tokenizer);
        if token.kind == .EOF || token.kind == .Invalid do return;
        if token.kind > .B_Keyword_Begin && token.kind < .B_Keyword_End {
            add_color(tw, token_to_text_window_color(token, color_scheme.keyword));
        }
        if token.kind > .B_Operator_Begin && token.kind < .B_Operator_End {
            add_color(tw, token_to_text_window_color(token, color_scheme.operator));
        }
        if token.kind == .Rune || token.kind == .String {
            add_color(tw, token_to_text_window_color(token, color_scheme.string));
        }
        if token.kind == .Integer || token.kind == .Float || token.kind == .Imag {
            add_color(tw, token_to_text_window_color(token, color_scheme.number));
        }
        if token.kind == .Ident { 
            add_color(tw, token_to_text_window_color(token, color_scheme.identifier));
        }
        if token.kind == .Comment { 
            add_color(tw, token_to_text_window_color(token, color_scheme.comment));
        }
    }
}

tokenizer_window_coloring :: proc(self: ^Odin_Plugin, tw: ^Text_Window, text: string, path: string){
    color_scheme := self.app.settings.color_scheme;

    tokenizer: t.Tokenizer; 
    t.init(&tokenizer, text, path, proc(p: t.Pos, fmt: string, args: ..any){});
    t1 := t.Token{};
    t2 := t.scan(&tokenizer);
    t3 := t.scan(&tokenizer);
    t4 := t.scan(&tokenizer);

    import_renames := make(map[string]bool, allocator = self.app.fa);
    
    for {
        shift(&t1, &t2, &t3, &t4, &tokenizer);

        if t1.kind == .EOF || t1.kind == .Invalid do return;
        else if t1.kind > .B_Keyword_Begin && t1.kind < .B_Keyword_End {
            add_color(tw, token_to_text_window_color(t1, color_scheme.keyword));

            if t1.kind == .Import && t2.kind == .Ident{
                import_renames[t2.text] = true;
                shift(&t1, &t2, &t3, &t4, &tokenizer);
                add_color(tw, token_to_text_window_color(t1, color_scheme.namespace));
            }else if t1.kind == .Import && t2.kind == .String{
                path := t2.text[1:][:len(t2.text) - 2];
                import_path := find_id_from_import_path(path);
                import_renames[import_path] = true;
            }
        } else if t1.kind > .B_Operator_Begin && t1.kind < .B_Operator_End {
            add_color(tw, token_to_text_window_color(t1, color_scheme.operator));
        } else if t1.kind == .Rune || t1.kind == .String {
            add_color(tw, token_to_text_window_color(t1, color_scheme.string));
        } else if t1.kind == .Integer || t1.kind == .Float || t1.kind == .Imag {
            add_color(tw, token_to_text_window_color(t1, color_scheme.number));
        } else if t1.kind == .Ident && 
                  t2.kind == .Colon &&
                 (t3.kind == .Colon || t3.kind == .Eq) &&  
                  t4.kind == .Proc {
            add_color(tw, token_to_text_window_color(t1, color_scheme.procedure));
        } else if t1.kind == .Ident && t2.kind == .Period && t3.kind == .Ident { 
            color := color_scheme.identifier;
            if import_renames[t1.text] {
                color = color_scheme.namespace;
            } 
            add_color(tw, token_to_text_window_color(t1, color));
        } else if t1.kind == .Ident && t2.kind == .Open_Paren { 
            add_color(tw, token_to_text_window_color(t1, color_scheme.procedure));
        } else if t1.kind == .Ident && (t1.text == "true" || t1.text == "false"){ 
            add_color(tw, token_to_text_window_color(t1, color_scheme.constant));
        } else if t1.kind == .Ident { 
            color := color_scheme.identifier;
            _, is_type :=  slice.linear_search(TYPES, t1.text);
            if is_type do color = color_scheme.type;
            add_color(tw, token_to_text_window_color(t1, color));
        } else if t1.kind == .Comment { 
            add_color(tw, token_to_text_window_color(t1, color_scheme.comment));
        }
    }

    shift :: proc(t1, t2, t3, t4: ^t.Token, tokenizer: ^t.Tokenizer){
        t1^ = t2^;
        t2^ = t3^;
        t3^ = t4^;
        t4^ = t.scan(tokenizer);
    }

    find_id_from_import_path :: proc(path: string) -> string{
        l := 0;
        #reverse for r, i in path{
            if r == '/' || r == ':' do break;
            _, size := utf8.encode_rune(r);
            l += size;
        }
        return path[len(path) - l:];
    }
}


token_to_text_window_color :: proc(t: t.Token, color: rl.Color) -> Text_Window_Color{
    return Text_Window_Color{
        color = color,
        pos = t.pos.offset,
        len = len(t.text),
    };
}

TYPES :: []string{
"bool", "b8", "b16", "b32", "b64",

"int", "i8", "i16", "i32", "i64", "i128",
"uint", "u8", "u16", "u32", "u64", "u128", "uintptr",

"i16le", "i32le", "i64le", "i128le", "u16le", "u32le", "u64le", "u128le", 
"i16be", "i32be", "i64be", "i128be", "u16be", "u32be", "u64be", "u128be", 

"f16", "f32", "f64", 

"f16le", "f32le", "f64le", 
"f16be", "f32be", "f64be", 

"complex32", "complex64", "complex128", 

"quaternion64", "quaternion128", "quaternion256", 

"rune", 
"string", "cstring",

"rawptr",

"typeid",
"any",
};

