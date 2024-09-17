package parser

import "core:mem"
import "core:os"
import "core:fmt"
import "core:strconv"
import s "core:strings"
import "core:unicode/utf8"
import "core:unicode"


print :: proc(node: Node){
    switch n in node{
    case ^Atomic:
        fmt.print(n^, sep = "");
    case ^Symbol:
        fmt.print(n^);
    case ^Operator:
        fmt.print(n^);
    case ^Sexpr:
        fmt.print("(");
        print(n.lhs);
        fmt.print(" . ");
        print(n.rhs);
        fmt.print(")");
    case nil:
        fmt.print("nil");
    }
}


Boolean  :: bool;
Integer  :: i64;
Float    :: f64;
String   :: string;
Atomic   :: union #no_nil{
    Boolean,
    Integer,
    Float,
    String,
}
Symbol   :: string;
Operator :: enum{
    Add, // +
    Sub, // -
    Mul, // *
    Div, // /

    // Todo(Ferenc): add more operators
}
Sexpr    :: struct{
    lhs: Node,
    rhs: Node,
}

Node :: union{ 
    ^Atomic,
    ^Symbol,
    ^Operator,
    ^Sexpr,
    // nil, you can check for it
}

parse :: proc(source: string, allocator: mem.Allocator) -> (Node, bool){
    p := Parser{source = source, allocator = allocator}; 

    return parse_node(&p);
}

parse_maybe_naked_sexpr :: proc(source: string, allocator: mem.Allocator) -> (sexpr: ^Sexpr, ok: bool){
    p := Parser{source = source, allocator = allocator}; 
    
    // parse a normal sexpr
    if current(&p) == '(' do return parse_sexpr(&p);

    // parse list like sexprs but without the ( and )
    sexpr = new(Sexpr, allocator);
    if empty(p) do return {}, false;

    sexpr.lhs = parse_node(&p) or_return;

    current_sexpr := sexpr;
    for !empty(p){
        new_sexpr := new(Sexpr, p.allocator);
        new_sexpr.lhs = parse_node(&p) or_return;
        current_sexpr.rhs = new_sexpr;
        current_sexpr = new_sexpr;
    }

    return sexpr, true;
}

parse_node :: proc(p: ^Parser) -> (Node, bool){
    if current(p) == '(' do return parse_sexpr(p);

    if current(p) == '"'{
        next(p);
        start := p.pos;
        length := 0;
        for current_raw(p) != '"'{
            length += next(p);
            if empty(p^) do return {}, false;
        }
        next(p);
        inside := p.source[start:][:length];
        return new_atomic(inside, p.allocator), true;
    }

    start := p.pos;
    length := 0;
    for !separator(current_raw(p)){
        length += next(p);
    }
    possible_symbol := p.source[start:][:length];
    if possible_symbol == "" do return {}, false;


    switch possible_symbol{
    case "null":  return nil, true;
    case "true":  return new_atomic(true, p.allocator), true;
    case "false": return new_atomic(false, p.allocator), true;
    case "+":     return new_operator(.Add, p.allocator), true;
    case "-":     return new_operator(.Sub, p.allocator), true;
    case "*":     return new_operator(.Mul, p.allocator), true;
    case "/":     return new_operator(.Div, p.allocator), true;
    }

    i64_value, ok_i64 := strconv.parse_i64(possible_symbol);
    if ok_i64 do return new_atomic(i64_value, p.allocator), true;
    f64_value, ok_f64 := strconv.parse_f64(possible_symbol);
    if ok_f64 do return new_atomic(f64_value, p.allocator), true;

    node := new(Symbol, p.allocator);
    node^ = cast(Symbol) possible_symbol;
    return node, true;

    separator :: proc(r: rune) -> bool{
        switch r{
        case 0: return true;
        case '(': return true;
        case ')': return true;
        }
        return unicode.is_space(r);
    }

    new_operator :: proc(op: Operator, alloc: mem.Allocator) -> ^Operator{
        a := new(Operator, alloc);
        a^ = op;
        return a;
    }

    new_atomic :: proc(value: $T, alloc: mem.Allocator) -> ^Atomic{
        atomic := new(Atomic, alloc);
        atomic^ = value;
        return atomic;
    }
}

parse_sexpr :: proc(p: ^Parser) -> (sexpr: ^Sexpr, ok: bool){
    sexpr = new(Sexpr, p.allocator);
    if current(p) != '(' do return {}, false;
    next(p);

    if current(p) == ')' {
        next(p);
        return sexpr, true;
    }

    sexpr.lhs = parse_node(p) or_return;

    if current(p) == '.' {
        next(p);
        sexpr.rhs = parse_node(p) or_return;
        assert(current(p) == ')');
        next(p);
        return sexpr, true;
    }

    current_sexpr := sexpr;
    for current(p) != ')'{
        new_sexpr := new(Sexpr, p.allocator);
        new_sexpr.lhs = parse_node(p) or_return;
        current_sexpr.rhs = new_sexpr;
        current_sexpr = new_sexpr;
    }
    next(p);

    return sexpr, true;
}


Parser :: struct{
    source: string,
    pos: int,
    allocator: mem.Allocator,
}

current :: proc(p: ^Parser) -> rune{
    skip_whitespace(p);   

    return current_raw(p);
}

current_raw :: proc(p: ^Parser) -> rune{
    if p.pos >= len(p.source) do return 0;
    return utf8.rune_at(p.source, p.pos);
}

next :: proc(p: ^Parser) -> int{
    if p.pos >= len(p.source) do return 0;

    _, size := utf8.decode_rune(p.source[p.pos:]);
    p.pos += size;
    return size;
}

empty :: proc(p: Parser) -> bool{
    return p.pos >= len(p.source);
}

skip_whitespace :: proc(p: ^Parser){
    for !empty(p^) && unicode.is_space(current_raw(p)){
        next(p);
    }
}
