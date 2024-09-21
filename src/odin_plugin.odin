package main

import "core:fmt"
import t "core:odin/tokenizer"
import p "core:odin/parser"
import "core:odin/ast"
import s "core:strings"
import "src:Buffer"
import "core:path/filepath"

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

    //tokenizer_coloring(self, tw, text, path);
    //parser_coloring(self, tw, text, path);
    tokenizer_coloring(self, tw, text, path);
}

destroy_odin_plugin :: proc(self: ^Odin_Plugin){
}

parser_coloring :: proc(self: ^Odin_Plugin, tw: ^Text_Window, text: string, path: string){
    context.allocator      = self.app.fa;
    context.temp_allocator = self.app.fa;

    //collect_package :: proc(path: string) -> (pkg: ^ast.Package, success: bool) {
    //parse_package_from_path :: proc(path: string, p: ^Parser = nil) -> (pkg: ^ast.Package, ok: bool) {

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
                //add_color(tw, token_to_text_window_color(n.tok, color_scheme.procedure));
                if len(n.names) < 1 do break;
                if len(n.values) < 1 do break;

                id, ok := n.names[0].derived_expr.(^ast.Ident);
//                fmt.printfln("%#v", n.values[0].derived_expr);
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

token_to_text_window_color :: proc(t: t.Token, color: rl.Color) -> Text_Window_Color{
    return Text_Window_Color{
        color = color,
        pos = t.pos.offset,
        len = len(t.text),
    };
}

