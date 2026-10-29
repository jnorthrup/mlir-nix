#!/usr/bin/env python3
"""Compare the guarded JIT with the interpreter, including lazy errors and grace validation.

Run after building mlnix: python3 scripts/check-jit.py [--mlnix PATH].
Every case compares status, stdout and stderr on both eager and demand schedules.
Separate instrumented runs prove native execution, grace checks and guard fallback actually happened.
"""
import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def hot(body, tail="warm", n=12):
    return f"let f = x: {body}; warm = builtins.foldl' builtins.add 0 (builtins.genList f {n}); in {tail}"


def sequence(calls, tail):
    """Force calls in order, so the tail exercises a compiled plan after its grace period."""
    for call in reversed(calls):
        tail = f"builtins.seq ({call}) ({tail})"
    return tail


def pointer_hot(definitions, calls, tail):
    return f"let {definitions} in {sequence(calls, tail)}"


IDENTITY = "f = x: x;"
CAPTURE = "make = captured: ignored: captured;"
SELECTOR = "make = condition: value: if condition then value else {};"
ID_WARM = ['f true', 'f "warm"', 'f null', 'f []']
CAP_WARM = ['make true null', 'make "warm" null', 'make [] null', 'make {} null']
SEL_WARM = ['make true {}', 'make false null', 'make true {}', 'make false null']


MAX = "9223372036854775807"
MIN = "(-9223372036854775807 - 1)"
CASES = {
    "integer arithmetic": hot("((x * 3) - 1) + 7"),
    "shared graph": hot("let y = x * 3; in y + y"),
    "integer identity": hot("x"),
    "negative arithmetic": hot("(x - 6) * (x - 4)"),
    "add overflow": hot("x + 1", f"builtins.seq warm (let n = {MAX}; in builtins.seq n (f n))"),
    "sub overflow": hot("x - 1", f"builtins.seq warm (let n = {MIN}; in builtins.seq n (f n))"),
    "mul overflow": hot("x * 2", f"builtins.seq warm (let n = {MAX}; in builtins.seq n (f n))"),
    "intermediate overflow cannot cancel": hot("(x + 1) - 1", f"builtins.seq warm (let n = {MAX}; in builtins.seq n (f n))"),
    "mul overflow cannot cancel": hot("(x * x) - (x * x)", "builtins.seq warm (let n = 3037000500; in builtins.seq n (f n))"),
    "minimum integer succeeds": hot("x + 0", f"builtins.seq warm (let n = {MIN}; in builtins.seq n (f n))"),
    "maximum integer succeeds": hot("x * 1", f"builtins.seq warm (let n = {MAX}; in builtins.seq n (f n))"),
    "float guard": hot("x * 2", "builtins.seq warm (let n = 1.5; in builtins.seq n (f n))"),
    "type error guard": hot("x * 2", "builtins.seq warm (let n = true; in builtins.seq n (f n))"),
    "unused argument": hot("42", 'builtins.seq warm (f (throw "unused argument"))'),
    "lazy branch": hot('if x == 0 then 1 else x', 'builtins.seq warm (f 0)'),
    "unused binding": hot('let unused = throw "unused binding"; in x + 2'),
    "capture changes between closures": "let make = y: x: x + y; in [ ((make 1) 4) ((make 9) 4) ]",
    "trace remains observable": hot('builtins.trace "observed" (x + 1)', n=4),
    "throw remains observable": hot('throw "observed"', n=4),
    "cyclic graph": "let f = x: let y = y; in y; in f 1",
    "node budget": hot("(" * 80 + "x" + " + 1)" * 80, n=4),
    "generic identity all value kinds": pointer_hot(IDENTITY, ID_WARM,
        '[ (f false) (f null) (f "text") (f 1.5) (f [ 1 2 ]) (f { answer = 42; }) '
        '(builtins.isFunction (f (x: x))) (builtins.length (f [ (throw "lazy element") ])) ]'),
    "generic identity preserves sharing": pointer_hot(IDENTITY +
        ' set = { unused = throw "shared set"; }; list = [ (throw "shared list") ];', ID_WARM,
        '[ (f set == set) (f list == list) ]'),
    "generic identity traces once": pointer_hot(IDENTITY +
        ' shared = builtins.trace "identity once" { answer = 42; };', ID_WARM,
        '[ (f shared).answer (f shared).answer ]'),
    "generic identity tail error": pointer_hot(IDENTITY, ID_WARM, 'f (throw "identity tail")'),
    "generic identity recursive argument": pointer_hot(IDENTITY + ' cycle = cycle;', ID_WARM, 'f cycle'),
    "captured identity changes closures": pointer_hot(CAPTURE, CAP_WARM,
        '[ (make "new" (throw "ignored")) (make [ 9 ] (throw "ignored")) '
        '(make { answer = 42; } (throw "ignored")) (make false (throw "ignored")) ]'),
    "captured identity ignores effects and recursion": pointer_hot(CAPTURE + ' cycle = cycle;', CAP_WARM,
        '[ (make 7 cycle) (make 8 (builtins.trace "must stay lazy" (throw "ignored"))) ]'),
    "captured identity preserves sharing": pointer_hot(CAPTURE +
        ' shared = { unused = throw "shared capture"; };', CAP_WARM,
        'make shared (throw "ignored") == shared'),
    "captured identity tail error": pointer_hot(CAPTURE, CAP_WARM,
        'make (throw "captured tail") (builtins.trace "argument must stay lazy" 1)'),
    "selector changes captures after grace": pointer_hot(SELECTOR, SEL_WARM,
        '[ (make true { a = 1; }) (make false (throw "false branch")) '
        '(make true { b = 2; }) (make false (builtins.trace "unselected" null)) ]'),
    "selector both branches during grace": pointer_hot(SELECTOR,
        ['make false (throw "grace false")', 'make true { a = 1; }',
         'make false (builtins.trace "grace unselected" null)'],
        '[ (make true { b = 2; }) (make false (throw "post grace false")) ]'),
    "selector selected tail stays shallow": pointer_hot(SELECTOR, SEL_WARM,
        'builtins.attrNames (make true { lazy = throw "nested value"; })'),
    "selector selected sharing and trace": pointer_hot(SELECTOR +
        ' shared = builtins.trace "selected once" { lazy = throw "nested shared value"; };', SEL_WARM,
        '[ (make true shared == shared) (make true shared == shared) ]'),
    "selector condition error precedes argument": pointer_hot(SELECTOR, SEL_WARM,
        'make (builtins.trace "condition once" (throw "condition failure")) '
        '(builtins.trace "argument must stay lazy" (throw "argument failure"))'),
    "selector condition error during grace": pointer_hot(SELECTOR, ['make false null'],
        'make (builtins.trace "grace condition once" (throw "grace condition failure")) '
        '(builtins.trace "grace argument must stay lazy" null)'),
    "selector condition type precedes argument": pointer_hot(SELECTOR, SEL_WARM,
        'make 42 (builtins.trace "argument must stay lazy" (throw "argument failure"))'),
    "selector condition recursive": pointer_hot(SELECTOR + ' cycle = cycle;', SEL_WARM,
        'make cycle (builtins.trace "argument must stay lazy" null)'),
    "selector selected tail error": pointer_hot(SELECTOR, SEL_WARM, 'make true (throw "selected tail")'),
    "selector reentrant condition": pointer_hot(SELECTOR, SEL_WARM,
        'make (builtins.attrNames (make false (throw "inner ignored")) == []) { answer = 42; }'),
    "list selector empty branch and lazy elements": pointer_hot(
        'make = condition: value: if condition then value else [];',
        ['make true []', 'make false null', 'make true []', 'make false null'],
        '[ (builtins.length (make true [ (throw "lazy element") ])) '
        '(make false (throw "unused list")) (make true [ 7 8 ]) ]'),
    "string selector changes captures": pointer_hot(
        'make = condition: value: if condition then value else "";',
        ['make true "a"', 'make false null', 'make true "b"', 'make false null'],
        '[ (make true "new") (make false (throw "unused string")) (make true "last") ]'),
    "string selector preserves context": pointer_hot(
        'make = condition: value: if condition then value else ""; '
        'context = { "/nix/store/00000000000000000000000000000000-jit" = { path = true; }; }; '
        'value = builtins.appendContext "retained" context;',
        ['make true "a"', 'make false null', 'make true "b"', 'make false null'],
        '[ (make true value == "retained") (builtins.getContext (make true value) == context) '
        '(builtins.getContext (make false value) == {}) ]'),
    "selector empty then branch": pointer_hot(
        'make = condition: value: if condition then [] else value;',
        ['make true null', 'make false []', 'make true null', 'make false []'],
        '[ (make true (throw "unused then")) (make false [ 1 ]) ]'),
    "pointer candidate budget": "builtins.deepSeq [ " +
        " ".join(f"((x{i}: x{i}) true)" for i in range(300)) +
        ' ] ((late: late) { answer = 42; })',
}
ERRORS = {"add overflow", "sub overflow", "mul overflow", "intermediate overflow cannot cancel",
          "mul overflow cannot cancel", "type error guard", "throw remains observable", "cyclic graph",
          "generic identity tail error", "generic identity recursive argument", "captured identity tail error",
          "selector condition error precedes argument", "selector condition error during grace", "selector condition type precedes argument",
          "selector condition recursive", "selector selected tail error"}

# These Boolean cases have independent output/effect oracles in addition to the
# byte-for-byte interpreter comparison. In particular, silence is an assertion.
BOOLEAN_ORACLES = {}
CASE_FLAGS = {}


def boolean_case(name, expr, output="", *, error=None, traces=()):
    CASES[name] = expr
    BOOLEAN_ORACLES[name] = (output.encode() + (b"\n" if error is None else b""), error, list(traces))
    if error is not None:
        ERRORS.add(name)


BOOL_WARM = ["f true", "f false", "f true", "f false"]
FUNCTION_TEST = "f = x: builtins.isFunction x || (x ? __functor && f (x.__functor x));"
FUNCTION_WARM = ["f true", "f {}", "f null", "f (x: x)"]
TYPE_VALUES = ['null', 'true', '1', '1.5', '"text"', './.', '{}', '[]', '(x: x)',
               'builtins.add', '(builtins.add 1)']
for predicate, matching in (("isNull", {0}), ("isBool", {1}), ("isInt", {2}), ("isFloat", {3}),
                            ("isString", {4}), ("isPath", {5}), ("isAttrs", {6}), ("isList", {7}),
                            ("isFunction", {8, 9, 10})):
    boolean_case("Boolean " + predicate, pointer_hot(f"f = x: builtins.{predicate} x;", BOOL_WARM,
        "[ " + " ".join(f"(f {value})" for value in TYPE_VALUES) + " ]"),
        "[ " + " ".join("true" if i in matching else "false" for i in range(len(TYPE_VALUES))) + " ]")

boolean_case("Boolean false AND skips effect", pointer_hot(
    'f = x: x && (builtins.trace "unused AND" (throw "unused"));', ["f false"] * 4, "f false"), "false")
boolean_case("Boolean true OR skips effect", pointer_hot(
    'f = x: x || (builtins.trace "unused OR" (throw "unused"));', ["f true"] * 4, "f true"), "true")
boolean_case("Boolean false implication skips effect", pointer_hot(
    'f = x: x -> (builtins.trace "unused implication" (throw "unused"));', ["f false"] * 4, "f false"), "true")
boolean_case("Boolean nested conditional", pointer_hot(
    "f = x: if builtins.isBool x then !x else builtins.isNull x;", BOOL_WARM,
    '[ (f true) (f false) (f null) (f 1) (f { lazy = throw "unused field"; }) ]'),
    "[ false true true false false ]")
boolean_case("Boolean needed argument trace once", pointer_hot(
    "f = x: builtins.isBool x && x;", BOOL_WARM, 'f (builtins.trace "needed argument" true)'),
    "true", traces=("needed argument",))
boolean_case("Boolean changing captures", pointer_hot(
    "make = captured: x: builtins.isBool x && captured;",
    ["make true true", "make false true", "make true false", "make false false"],
    "[ (make false true) (make true true) (make false false) (make true false) ]"),
    "[ false true false true ]")
boolean_case("Boolean captured trace once", pointer_hot(
    'make = captured: x: builtins.isBool x && captured; shared = builtins.trace "captured once" true;',
    ["make true true", "make false true", "make true false", "make false false"],
    "[ (make shared true) (make shared false) ]"), "[ true true ]", traces=("captured once",))
boolean_case("Boolean unused capture remains lazy", pointer_hot(
    "make = captured: x: x || captured;", ["make false true"] * 4,
    'make (builtins.trace "unused capture" (throw "unused")) true'), "true")
boolean_case("Boolean predicate throw keeps builtin trace", pointer_hot(
    "f = x: builtins.isInt x;", BOOL_WARM,
    'f (builtins.trace "predicate once" (throw "predicate argument"))'),
    error="while calling the 'isInt' builtin", traces=("predicate once",))
boolean_case("Boolean predicate throw during grace", pointer_hot(
    "f = x: builtins.isFunction x;", ["f true"],
    'f (builtins.trace "grace predicate once" (throw "predicate argument"))'),
    error="while calling the 'isFunction' builtin", traces=("grace predicate once",))
for label, body, context in (
        ("NOT", "!x", "in the argument of the not operator"),
        ("AND left", "x && true", "in the left operand of the AND (&&) operator"),
        ("AND right", "true && x", "in the right operand of the AND (&&) operator"),
        ("OR left", "x || false", "in the left operand of the OR (||) operator"),
        ("OR right", "false || x", "in the right operand of the OR (||) operator"),
        ("IMPL left", "x -> true", "in the left operand of the IMPL (->) operator"),
        ("IMPL right", "true -> x", "in the right operand of the IMPL (->) operator"),
        ("IF condition", "if x then true else false", "while evaluating a branch condition")):
    boolean_case("Boolean type error " + label, pointer_hot(f"f = x: {body};", BOOL_WARM, "f 42"), error=context)
boolean_case("Boolean IF tail remains a value", pointer_hot(
    "f = x: if true then x else false;", BOOL_WARM, "f 42"), "42")
boolean_case("Boolean NOT of IF reports outer context", pointer_hot(
    "f = x: !(if true then x else false);", BOOL_WARM, "f 42"),
    error="in the argument of the not operator")
boolean_case("Boolean IF tail throw retains position", pointer_hot(
    "f = x: !(if true then x else false);", BOOL_WARM,
    'f (builtins.trace "selected tail once" (throw "selected tail"))'),
    error="selected tail", traces=("selected tail once",))
boolean_case("Boolean functor branch deopts after memoization", pointer_hot(FUNCTION_TEST, FUNCTION_WARM,
    'f (builtins.trace "functor base once" { __functor = self: builtins.trace "functor called once" (x: x); })'),
    "true", traces=("functor base once", "functor called once"))
boolean_case("Boolean functor field error after deopt", pointer_hot(FUNCTION_TEST, FUNCTION_WARM,
    'f (builtins.trace "functor base once" { __functor = builtins.trace "functor field once" (throw "functor field"); })'),
    error="functor field", traces=("functor base once", "functor field once"))
boolean_case("Boolean hasAttr does not force final field", pointer_hot(
    "f = x: x ? field;", ["f {}", "f null", "f { field = 1; }", "f []"],
    'f (builtins.trace "hasAttr base once" { field = builtins.trace "unused final field" (throw "unused"); })'),
    "true", traces=("hasAttr base once",))
boolean_case("Boolean layered hasAttr deopt", pointer_hot(
    'f = x: x ? k31; base = builtins.listToAttrs (builtins.genList '
    '(i: { name = "k${toString i}"; value = throw "unused layer value"; }) 64); '
    'layered = base // { top = throw "unused top"; };',
    ["f {}", "f null", "f { k31 = 1; }", "f []"], "f layered"), "true")
boolean_case("Boolean multi-path hasAttr preserves intermediate demand", pointer_hot(
    "f = x: x ? a.b;", ["f {}"] * 4,
    'f { a = builtins.trace "intermediate once" { b = builtins.trace "unused final" (throw "unused"); }; }'),
    "true", traces=("intermediate once",))
boolean_case("Boolean local recursive control", "let f = x: let y = !y; in y; in f true",
    error="infinite recursion encountered")
boolean_case("Boolean recursive argument", pointer_hot("f = x: !x; cycle = cycle;", BOOL_WARM, "f cycle"),
    error="infinite recursion encountered")
leaf_names = [f"c{i}" for i in range(17)]
boolean_case("Boolean leaf budget", "let " +
    " ".join(f'{name} = builtins.trace "leaf {i}" true;' for i, name in enumerate(leaf_names)) +
    " f = x: " + " && ".join(leaf_names + ["x"]) + "; in f true", "true",
    traces=tuple(f"leaf {i}" for i in range(17)))
boolean_case("Boolean shared DAG expansion bound", "let f = x: let b0 = builtins.isBool x; " +
    " ".join(f"b{i} = if b{i-1} then b{i-1} else false;" for i in range(1, 19)) +
    " in b18; in [ (f true) (f 42) ]", "[ true false ]")
boolean_case("Boolean unsupported path retires", pointer_hot(
    'f = x: if builtins.isInt x then false else builtins.trace "deopt" false;',
    ["f 0", "f 1", "f 2", "f 3"] + ['f "unsupported"'] * 80, "f 99"),
    "false", traces=("deopt",) * 80)
NESTED_RETIREMENT = 'f = x: if builtins.isBool x then false else builtins.trace "nested deopt" false;'
NESTED_DEOPTS = ['f "unsupported"'] * 64
boolean_case("Boolean nested retirement pins active continuation", pointer_hot(
    NESTED_RETIREMENT, BOOL_WARM, "f (" + sequence(NESTED_DEOPTS, "true") + ")"),
    "false", traces=("nested deopt",) * 64)
boolean_case("Boolean nested retirement unwinds active demand", pointer_hot(
    NESTED_RETIREMENT, BOOL_WARM,
    "f (" + sequence(NESTED_DEOPTS, 'throw "outer demand failure"') + ")"),
    error="while calling the 'isBool' builtin", traces=("nested deopt",) * 64)
PREFLIGHT = 'f = x: if builtins.isInt x then false else builtins.trace "preflight deopt" false;'
boolean_case("Boolean preflight unsupported never compiles", pointer_hot(
    PREFLIGHT, ['f "unsupported"'] * 80, "f 99"), "false", traces=("preflight deopt",) * 80)
boolean_case("Boolean preflight delayed admission", pointer_hot(
    PREFLIGHT, ['f "unsupported"'] * 3 +
    ['f (builtins.trace "admission once" 0)', "f 1", "f 2", "f 3"], "f 99"),
    "false", traces=("preflight deopt",) * 3 + ("admission once",))
boolean_case("Boolean preflight recursive oracle compiles", pointer_hot(
    "f = x: builtins.isBool x;", [],
    'f (builtins.trace "recursive oracle once" (' + sequence(BOOL_WARM, "true") + "))"),
    "true", traces=("recursive oracle once",))
boolean_case("Boolean preflight recursive oracle refuses", pointer_hot(
    PREFLIGHT, [], "f (" + sequence(['f "unsupported"'] * 64, "99") + ")"),
    "false", traces=("preflight deopt",) * 64)
boolean_case("Boolean preflight recursive oracle retires", pointer_hot(
    PREFLIGHT, [], "f (" + sequence(["f 0", "f 1", "f 2", "f 3"] +
                                    ['f "unsupported"'] * 64, "99") + ")"),
    "false", traces=("preflight deopt",) * 64)
boolean_case("Boolean preflight oracle error", pointer_hot(
    "f = x: builtins.isBool x;", [], 'f (builtins.trace "preflight error once" (throw "preflight argument"))'),
    error="while calling the 'isBool' builtin", traces=("preflight error once",))

# The wrapper and its callee must be compiled as one guarded graph. Warmup
# may also compile the callee independently, so coverage uses inline counters.
CALL_WRAP = "wrap = callee: x: !(callee x);"
CALL_BOOL = "callee = x: builtins.isBool x; f = x: !(callee x);"
boolean_case("Inline call predicate", pointer_hot(
    "callee = x: builtins.isFunction x; f = x: !(callee x);", BOOL_WARM,
    "[ (f null) (f {}) (f (x: x)) (f builtins.add) (f (builtins.add 1)) ]"),
    "[ true true false false false ]")
boolean_case("Inline call current closure captures", pointer_hot(
    CALL_WRAP + " pred = flag: x: flag && builtins.isBool x; yes = pred true; no = pred false; "
    "f = wrap yes; g = wrap no;", BOOL_WARM + ["no"],
    '[ (g (throw "unused changed capture")) (f true) (g false) ]'), "[ true false true ]")
boolean_case("Inline call current capture demand once", pointer_hot(
    CALL_WRAP + ' pred = flag: x: flag && builtins.isBool x; yes = pred true; '
    'no = pred (builtins.trace "current capture once" false); f = wrap yes; g = wrap no;',
    BOOL_WARM + ["no"],
    '[ (g (throw "unused capture argument")) (g (throw "still unused")) (f true) ]'),
    "[ true true false ]", traces=("current capture once",))
boolean_case("Inline call changed target before argument", pointer_hot(
    CALL_WRAP + ' a = x: builtins.isBool x; b = x: false; f = wrap a; g = wrap b;',
    BOOL_WARM + ["b"],
    '[ (g (builtins.trace "unused changed-target argument" (throw "unused"))) (f true) ]'),
    "[ true false ]")
boolean_case("Inline call unready target memoizes once", pointer_hot(
    CALL_WRAP + ' a = x: builtins.isBool x; b = builtins.trace "callee once" (x: false); '
    'f = wrap a; g = wrap b;', BOOL_WARM,
    '[ (g (throw "unused first argument")) (g (throw "unused second argument")) ]'),
    "[ true true ]", traces=("callee once",))
boolean_case("Inline call target error precedes argument", pointer_hot(
    CALL_WRAP + ' a = x: builtins.isBool x; f = wrap a; '
    'g = wrap (builtins.trace "callee failure once" (throw "callee failure"));', BOOL_WARM,
    'g (builtins.trace "unused argument" (throw "argument failure"))'),
    error="callee failure", traces=("callee failure once",))
boolean_case("Inline call non-lambda guards", pointer_hot(
    CALL_WRAP + ' a = x: builtins.isBool x; f = wrap a; prim = wrap builtins.isBool; '
    'functor = { __functor = self: x: false; }; g = wrap functor;', BOOL_WARM + ["functor"],
    '[ (prim 42) (g (throw "unused functor argument")) (f true) ]'), "[ true true false ]")
boolean_case("Inline call predicate demand once", pointer_hot(
    CALL_BOOL + ' shared = builtins.trace "inline argument once" true;', BOOL_WARM,
    "[ (f shared) (f shared) ]"), "[ false false ]", traces=("inline argument once",))
boolean_case("Inline call predicate error context", pointer_hot(CALL_BOOL, BOOL_WARM,
    'f (builtins.trace "inline predicate failure once" (throw "inline predicate failure"))'),
    error="while calling the 'isBool' builtin", traces=("inline predicate failure once",))
boolean_case("Inline call callee Boolean context", pointer_hot(
    "callee = x: !x; f = x: !(callee x);", BOOL_WARM, "f 42"),
    error="in the argument of the not operator")
boolean_case("Inline call non-Boolean result keeps caller context", pointer_hot(
    "callee = x: if builtins.isBool x then x else 42; f = x: !(callee x);", BOOL_WARM, "f 42"),
    error="in the argument of the not operator")
CALL_FUNCTION = "callee = x: builtins.isFunction x || (x ? __functor && callee (x.__functor x)); f = x: !(callee x);"
boolean_case("Inline call fallback after persistent demand", pointer_hot(CALL_FUNCTION, BOOL_WARM,
    'f (builtins.trace "inline functor base once" '
    '{ __functor = self: builtins.trace "inline functor call once" (x: x); })'),
    "false", traces=("inline functor base once", "inline functor call once"))
boolean_case("Inline call fallback field error", pointer_hot(CALL_FUNCTION, BOOL_WARM,
    'f (builtins.trace "inline functor base once" '
    '{ __functor = builtins.trace "inline functor field once" (throw "inline functor failure"); })'),
    error="inline functor failure", traces=("inline functor base once", "inline functor field once"))
boolean_case("Inline call skipped guard stays lazy", pointer_hot(
    'wrap = callee: x: x || !(callee x); a = x: builtins.isBool x; f = wrap a; '
    'g = wrap (builtins.trace "unused callee" (throw "unused callee"));', ["f false"] * 4,
    "g true"), "true")
boolean_case("Inline call formals remain fallback", pointer_hot(
    'callee = { value ? false }: value; f = x: !(callee x);', ["f {}"] * 4,
    '[ (f {}) (f { value = true; unused = throw "unexpected formal"; }) ]'),
    error="called with unexpected argument 'unused'")
boolean_case("Inline call temporary argument effects once per call", pointer_hot(
    'callee = x: builtins.isBool x; f = x: !(callee (builtins.trace "temporary argument" x));',
    BOOL_WARM, "f 42"), "true", traces=("temporary argument",) * 5)
boolean_case("Inline call cyclic edge stays fallback", pointer_hot(
    "callee = x: if builtins.isBool x then x else callee x; f = x: !(callee x);", BOOL_WARM,
    'f (builtins.trace "recursive argument once" 42)'),
    error="max-call-depth exceeded", traces=("recursive argument once",))
CASE_FLAGS["Inline call cyclic edge stays fallback"] = ["--option", "max-call-depth", "16"]
boolean_case("Inline call exception cleanup", pointer_hot(CALL_BOOL, BOOL_WARM +
    ['builtins.tryEval (f (builtins.trace "caught inline error" (throw "caught")))'] * 12, "f true"),
    "false", traces=("caught inline error",) * 12)
CASE_FLAGS["Inline call exception cleanup"] = ["--option", "max-call-depth", "4"]
boolean_case("Inline call fallback depth cleanup", pointer_hot(
    'callee = x: if builtins.isBool x then x else builtins.trace "inline deopt" false; '
    'f = x: !(callee x);', BOOL_WARM + ['f "unsupported"'] * 12, "f true"),
    "false", traces=("inline deopt",) * 12)
CASE_FLAGS["Inline call fallback depth cleanup"] = ["--option", "max-call-depth", "4"]
boolean_case("Inline call depth limit precedes body demand", pointer_hot(
    CALL_BOOL + " deeper = x: f x;", BOOL_WARM,
    'deeper (builtins.trace "unused over-depth argument" true)'), error="max-call-depth exceeded")
CASE_FLAGS["Inline call depth limit precedes body demand"] = ["--option", "max-call-depth", "2"]
boolean_case("Inline call host demand preserves logical depth", pointer_hot(
    CALL_BOOL + ' helper = x: builtins.trace "unused over-depth helper body" x;', BOOL_WARM,
    "f (helper true)"), error="max-call-depth exceeded")
CASE_FLAGS["Inline call host demand preserves logical depth"] = ["--option", "max-call-depth", "2"]
boolean_case("Inline call leave restores caller demand depth", pointer_hot(
    'callee = x: builtins.isNull x; make = flag: x: !(callee x) && flag; '
    'helper = x: builtins.trace "caller demand after leave" x; f = make true; g = make (helper true);',
    BOOL_WARM, "g true"), "true", traces=("caller demand after leave",))
CASE_FLAGS["Inline call leave restores caller demand depth"] = ["--option", "max-call-depth", "2"]
boolean_case("Inline call expansion depth bound", pointer_hot(
    "c0 = x: builtins.isBool x; " +
    " ".join(f"c{i} = x: !(c{i-1} x);" for i in range(1, 7)) + " f = c6;", BOOL_WARM,
    "[ (f true) (f 42) ]"), "[ true false ]")
inline_captures = [f"a{i}" for i in range(9)] + [f"b{i}" for i in range(9)]
boolean_case("Inline call expanded leaf budget", pointer_hot(
    " ".join(f'{name} = builtins.trace "inline leaf {name}" true;' for name in inline_captures) +
    " callee = x: " + " && ".join(inline_captures[:9] + ["builtins.isBool x"]) + ";" +
    " middle = x: " + " && ".join(inline_captures[9:] + ["callee x"]) + "; f = x: !(middle x);",
    BOOL_WARM, "[ (f true) (f 42) ]"), "[ false true ]",
    traces=tuple("inline leaf " + name for name in inline_captures[9:] + inline_captures[:9]))
INLINE_RETIREMENT = (
    'callee = x: if builtins.isBool x then false else builtins.trace "inline nested deopt" false; '
    'f = x: !(callee x); deeper = x: f x; deepest = x: deeper x;')
INLINE_NESTED_DEOPTS = ['f "unsupported"'] * 64
boolean_case("Inline call nested retirement pins expanded continuation", pointer_hot(
    INLINE_RETIREMENT, BOOL_WARM,
    "[ (f (" + sequence(INLINE_NESTED_DEOPTS, "true") + ")) (deepest true) ]"),
    "[ true true ]", traces=("inline nested deopt",) * 64)
boolean_case("Inline call nested retirement unwinds expanded demand", pointer_hot(
    INLINE_RETIREMENT, BOOL_WARM,
    "let caught = builtins.tryEval (f (" +
    sequence(INLINE_NESTED_DEOPTS, 'throw "inline outer demand failure"') +
    ")); in builtins.seq caught [ caught.success (deepest true) ]"),
    "[ false true ]", traces=("inline nested deopt",) * 64)
for name in ("Inline call nested retirement pins expanded continuation",
             "Inline call nested retirement unwinds expanded demand"):
    CASE_FLAGS[name] = ["--option", "max-call-depth", "6"]

# Saturated calls bind all supplied formals to persistent caller cells. Curry
# stages are sequential logical calls, while an inlined callee is nested.
CURRY_WARM = ["f true false", "f false true", "f true true", "f false false"]
CURRY_BOOL = "f = a: b: builtins.isBool a && builtins.isBool b;"
boolean_case("Curried two formal logic", pointer_hot(
    "f = a: b: a || b;", CURRY_WARM,
    "[ (f false false) (f false true) (f true false) ]"), "[ false true true ]")
boolean_case("Curried three formal logic", pointer_hot(
    "f = a: b: c: if a then b else !c;",
    ["f true true false", "f false true true", "f true false true", "f false false false"],
    "[ (f true false true) (f false false false) ]"), "[ false true ]")
boolean_case("Curried four formal logic", pointer_hot(
    "f = a: b: c: d: (a && b) || (c && d);",
    ["f true true false false", "f false true true true", "f true false true false", "f false false false true"],
    "[ (f true true false false) (f false true true false) ]"), "[ true false ]")
boolean_case("Curried unused earlier formal stays lazy", pointer_hot(
    "f = unused: b: builtins.isBool b;", CURRY_WARM,
    'f (builtins.trace "unused earlier formal" (throw "unused")) true'), "true")
boolean_case("Curried unused later formal stays lazy", pointer_hot(
    "f = a: unused: builtins.isBool a;", CURRY_WARM,
    'f true (builtins.trace "unused later formal" (throw "unused"))'), "true")
boolean_case("Curried formal demand order and sharing", pointer_hot(
    CURRY_BOOL + ' first = builtins.trace "first formal once" true; '
    'last = builtins.trace "last formal once" false;', CURRY_WARM,
    "[ (f first last) (f first last) ]"), "[ true true ]",
    traces=("first formal once", "last formal once"))
boolean_case("Curried short circuit skips later formal", pointer_hot(
    "f = a: b: a && b;", CURRY_WARM,
    'f false (builtins.trace "unused short-circuit formal" (throw "unused"))'), "false")
boolean_case("Curried first formal predicate error", pointer_hot(CURRY_BOOL, CURRY_WARM,
    'f (builtins.trace "first formal failure" (throw "formal failure")) '
    '(builtins.trace "unused later failure" (throw "unused"))'),
    error="while calling the 'isBool' builtin", traces=("first formal failure",))
for label, tail, context in (
        ("earlier", 'f 42 (builtins.trace "unused right formal" (throw "unused"))',
         "in the left operand of the AND (&&) operator"),
        ("later", "f true 42", "in the right operand of the AND (&&) operator")):
    boolean_case("Curried Boolean type error " + label,
        pointer_hot("f = a: b: a && b;", CURRY_WARM, tail), error=context)
boolean_case("Curried current ancestor captures", pointer_hot(
    "make = captured: a: b: builtins.isBool a && (captured || b); f = make false; g = make true;",
    CURRY_WARM + ["g"], '[ (g true (throw "unused changed capture argument")) (f true false) ]'),
    "[ true false ]")
boolean_case("Curried changed captured callee", pointer_hot(
    'make = callee: a: b: !(callee a) || b; yes = x: builtins.isBool x; no = x: false; '
    'f = make yes; g = make no;', CURRY_WARM + ["no", "g"],
    'g (builtins.trace "unused changed callee argument" (throw "unused")) (throw "unused later")'), "true")
CURRY_CALLEE = "callee = x: builtins.isBool x; f = ignored: x: !(callee x);"
boolean_case("Curried inline callee nested depth", pointer_hot(
    CURRY_CALLEE, CURRY_WARM, 'f (throw "unused first") (builtins.trace "nested curried demand" true)'),
    "false", traces=("nested curried demand",))
CASE_FLAGS["Curried inline callee nested depth"] = ["--option", "max-call-depth", "2"]
boolean_case("Curried inline callee depth limit", pointer_hot(
    'callee = x: builtins.isBool x; f = skip: x: if skip then false else !(callee x);',
    ["callee true"] + ["f true false"] * 4,
    'f false (builtins.trace "unused over-depth curried formal" true)'), error="max-call-depth exceeded")
CASE_FLAGS["Curried inline callee depth limit"] = ["--option", "max-call-depth", "1"]
for arity in (2, 3, 4):
    formals = [f"a{i}" for i in range(arity)]
    defs = "f = " + ": ".join(formals) + ": " + " && ".join(formals) + ";"
    call = "f " + " ".join(["true"] * arity)
    name = f"Curried sequential depth arity{arity}"
    boolean_case(name, pointer_hot(defs, [call] * 4, call), "true")
    CASE_FLAGS[name] = ["--option", "max-call-depth", "1"]
boolean_case("Curried partial closure behavior", pointer_hot(
    "f = a: b: a && b; partial = f false;", CURRY_WARM,
    '[ (builtins.isFunction partial) (builtins.functionArgs partial == {}) '
    '(partial (throw "unused partial argument")) (f true true) ]'), "[ true true false true ]")
boolean_case("Curried wrong arity does not poison saturation", pointer_hot(
    "f = a: b: c: a || b || c; partial = f false false;",
    ["partial"] + ["f true false false"] * 4,
    "[ (partial true) (f false false false) ]"), "[ true false ]")
boolean_case("Curried escaped deferred descendant retains captures", pointer_hot(
    'f = choose: captured: if choose then (x: captured && x) else builtins.isBool captured; '
    'escaped = f true (builtins.trace "escaped capture once" false);', ["f false true"] * 4,
    'builtins.seq escaped (builtins.trace "after closure escape" '
    '[ (builtins.isFunction escaped) (escaped (throw "unused escaped argument")) ])'),
    "[ true false ]", traces=("after closure escape", "escaped capture once"))
CURRY_ALIAS = (
    'f = flag: choose: pred: x: if choose then (y: flag) else !(pred x); '
    'oldStage = f false true (x: false); old = oldStage 0;')
boolean_case("Curried inline capture shares SSA but not environment", pointer_hot(
    CURRY_ALIAS, ["old"] + ["f true false old true"] * 4,
    "[ (f true false old true) (f false false old true) ]"), "[ true true ]")
boolean_case("Curried outer local computation stays fallback", pointer_hot(
    'f = a: let local = builtins.trace "outer local once" a; in b: if b then !local else false;',
    ["f true false"] * 4, 'f (builtins.trace "local formal once" true) true'),
    "false", traces=("outer local once", "local formal once"))
boolean_case("Curried fallback preserves earlier demand", pointer_hot(
    'f = a: b: if builtins.isBool a then '
    '(if b then builtins.trace "curried fallback once" false else true) else false;',
    ["f true false"] * 4, 'f (builtins.trace "persistent curried formal once" true) true'),
    "false", traces=("persistent curried formal once", "curried fallback once"))
boolean_case("Curried defaults stay interpreted", pointer_hot(
    "f = { flag ? true }: b: flag && b;", ["f {} true"] * 4,
    '[ (f {} false) (f { flag = false; } (throw "unused default argument")) ]'), "[ false false ]")
boolean_case("Curried arity budget", pointer_hot(
    "f = a: b: c: d: e: a && b && c && d && e;", ["f true true true true true"] * 4,
    'f false (throw "unused b") (throw "unused c") (throw "unused d") (throw "unused e")'), "false")
boolean_case("Curried overapplication keeps later argument lazy", pointer_hot(
    CURRY_BOOL, CURRY_WARM,
    'f true false (builtins.trace "unused extra curried argument" (throw "unused"))'),
    error="attempt to call something which is not a function but a Boolean")
boolean_case("Curried recursive oracle admission", pointer_hot(CURRY_BOOL, [],
    'f (builtins.trace "curried oracle once" (' + sequence(CURRY_WARM, "true") + ")) false"),
    "true", traces=("curried oracle once",))
CURRY_RETIREMENT = 'f = a: b: if builtins.isBool a then false else builtins.trace "curried nested deopt" false;'
CURRY_NESTED_DEOPTS = ['f "unsupported" false'] * 64
boolean_case("Curried nested retirement pins active arguments", pointer_hot(
    CURRY_RETIREMENT, CURRY_WARM,
    "f (" + sequence(CURRY_NESTED_DEOPTS, "true") + ") false"),
    "false", traces=("curried nested deopt",) * 64)
boolean_case("Curried nested retirement unwinds argument demand", pointer_hot(
    CURRY_RETIREMENT, CURRY_WARM,
    "let caught = builtins.tryEval (f (" +
    sequence(CURRY_NESTED_DEOPTS, 'throw "curried outer demand failure"') +
    ") false); in builtins.seq caught [ caught.success (f true false) ]"),
    "[ false false ]", traces=("curried nested deopt",) * 64)

# Multi-argument inlining must work independently of virtual Select leaves.
for arity in (2, 3, 4):
    formals = [f"a{i}" for i in range(arity)]
    defs = "pred = " + ": ".join(formals) + ": " + " && ".join(formals) + "; "
    defs += "f = " + ": ".join(formals) + ": !(pred " + " ".join(formals) + ");"
    warm = "f " + " ".join(["true"] * arity)
    name = f"Saturated inline persistent arity{arity}"
    boolean_case(name, pointer_hot(defs, [warm] * 4,
        "f false " + " ".join(['(throw "unused inline formal")'] * (arity - 1))), "true")
    CASE_FLAGS[name] = ["--option", "max-call-depth", "2"]

PROJECT_PRED = "pred = name: value: builtins.isBool value;"
PROJECT_MAKE = "make = set: name: !(pred name set.${name});"
PROJECT_WARM = ['f "field"'] * 4
PROJECT = PROJECT_PRED + PROJECT_MAKE + "f = make { field = true; };"
boolean_case("Projection ignored argument stays lazy", pointer_hot(
    'pred = name: value: false;' + PROJECT_MAKE +
    ' f = make { field = true; }; g = make (builtins.trace "unused base" (throw "unused base"));',
    PROJECT_WARM, 'g (builtins.trace "unused key" (throw "unused key"))'), "true")
boolean_case("Projection name-only predicate skips base and field", pointer_hot(
    'pred = name: value: builtins.isString name;' + PROJECT_MAKE +
    ' f = make { field = true; }; g = make (builtins.trace "unused base" (throw "unused base"));',
    PROJECT_WARM, 'g (builtins.trace "name only" "field")'), "false", traces=("name only",))
boolean_case("Projection current sets and keys", pointer_hot(
    PROJECT_PRED + PROJECT_MAKE +
    ' f = make { a = true; b = 42; }; g = make { a = 42; b = false; };', ['f "a"'] * 4,
    '[ (f "a") (f "b") (g "a") (g "b") ]'), "[ false true true false ]")
boolean_case("Projection dynamic demand order and sharing", pointer_hot(
    PROJECT + ' g = make (builtins.trace "projection base once" '
    '{ field = builtins.trace "projection field once" true; }); '
    'key = builtins.trace "projection key once" "field";', PROJECT_WARM, "[ (g key) (g key) ]"),
    "[ false false ]", traces=("projection key once", "projection base once", "projection field once"))
boolean_case("Projection static demand order", pointer_hot(
    PROJECT_PRED + ' make = set: name: !(pred name set.field); f = make { field = true; }; '
    'g = make (builtins.trace "static base once" { field = builtins.trace "static field once" false; });',
    PROJECT_WARM, 'g (builtins.trace "unused static name" (throw "unused"))'),
    "false", traces=("static base once", "static field once"))
boolean_case("Projection final value stays shallow", pointer_hot(
    PROJECT, PROJECT_WARM, 'make { field = { nested = throw "unused nested field"; }; } "field"'), "true")
boolean_case("Projection Boolean consumer keeps own context", pointer_hot(
    'f = set: !set.field;', ["f { field = true; }"] * 4,
    'f { field = builtins.trace "non-Boolean field once" 42; }'),
    error="in the argument of the not operator", traces=("non-Boolean field once",))
boolean_case("Projection tail remains an arbitrary value", pointer_hot(
    'f = set: set.field;', ["f { field = true; }"] * 4,
    'f { field = builtins.trace "tail field once" 42; }'), "42", traces=("tail field once",))
boolean_case("Projection hasAttr leaves final field lazy", pointer_hot(
    'f = set: (set.field) ? inner;', ["f { field = {}; }"] * 4,
    'f { field = builtins.trace "selected set once" { inner = builtins.trace "unused inner field" (throw "unused"); }; }'),
    "true", traces=("selected set once",))
boolean_case("Projection missing field keeps predicate context", pointer_hot(
    PROJECT + ' g = make (builtins.trace "missing base" {});', PROJECT_WARM,
    'g (builtins.trace "missing key" "absent")'), error="attribute 'absent' missing",
    traces=("missing key", "missing base"))
boolean_case("Projection base type keeps selection context", pointer_hot(
    PROJECT + ' g = make (builtins.trace "bad base" 42);', PROJECT_WARM,
    'g (builtins.trace "base type key" "field")'), error="while selecting an attribute",
    traces=("base type key", "bad base"))
boolean_case("Projection key type precedes base", pointer_hot(
    PROJECT + ' g = make (builtins.trace "unused bad-key base" (throw "unused"));', PROJECT_WARM,
    'g (builtins.trace "bad key" 42)'), error="while evaluating an attribute name", traces=("bad key",))
boolean_case("Projection key throw precedes base", pointer_hot(
    PROJECT + ' g = make (builtins.trace "unused key-error base" (throw "unused"));', PROJECT_WARM,
    'g (builtins.trace "key failure once" (throw "projection key failure"))'),
    error="while calling the 'isBool' builtin", traces=("key failure once",))
boolean_case("Projection contextful key precedes base", pointer_hot(
    PROJECT + ' g = make (builtins.trace "unused contextual-key base" (throw "unused")); '
    'key = builtins.appendContext "field" '
    '{ "/nix/store/00000000000000000000000000000000-jit" = { path = true; }; };',
    PROJECT_WARM, "g key"), error="not allowed to refer to a store path")
boolean_case("Projection field throw happens once", pointer_hot(
    PROJECT + ' g = make (builtins.trace "throwing field base" '
    '{ field = builtins.trace "field failure once" (throw "projection field failure"); });',
    PROJECT_WARM, 'g (builtins.trace "throwing field key" "field")'),
    error="while calling the 'isBool' builtin",
    traces=("throwing field key", "throwing field base", "field failure once"))
boolean_case("Projection changed callee precedes selection", pointer_hot(
    'make = pred: set: name: !(pred name set.${name}); '
    'yes = name: value: builtins.isBool value; no = name: value: false; '
    'f = make yes { field = true; }; '
    'g = make no (builtins.trace "unused changed-callee base" (throw "unused"));',
    PROJECT_WARM + ["no", "g"],
    'g (builtins.trace "unused changed-callee key" (throw "unused"))'), "true")
boolean_case("Projection callee error precedes selection", pointer_hot(
    'make = pred: set: name: !(pred name set.${name}); '
    'yes = name: value: builtins.isBool value; f = make yes { field = true; }; '
    'g = make (builtins.trace "projection callee failure" (throw "callee failure")) '
    '(builtins.trace "unused callee-error base" (throw "unused"));', PROJECT_WARM,
    'g (builtins.trace "unused callee-error key" (throw "unused"))'),
    error="callee failure", traces=("projection callee failure",))
boolean_case("Projection layered shadowing", pointer_hot(
    PROJECT_PRED + PROJECT_MAKE + ' f = make { field = true; }; '
    'base = builtins.listToAttrs (builtins.genList '
    '(i: { name = "k${toString i}"; value = throw "unused shadowed layer value"; }) 64); '
    'layered = base // { k31 = builtins.trace "layer winner once" true; }; g = make layered;',
    PROJECT_WARM, '[ (g "k31") (g "k31") ]'), "[ false false ]", traces=("layer winner once",))
boolean_case("Projection cached flat layer", pointer_hot(
    PROJECT_PRED + PROJECT_MAKE + ' f = make { field = true; }; '
    'base = builtins.listToAttrs (builtins.genList '
    '(i: { name = "k${toString i}"; value = throw "unused cached layer value"; }) 64); '
    'layered = base // { k31 = builtins.trace "cached layer winner once" true; }; g = make layered; '
    'wide = builtins.listToAttrs (builtins.genList '
    '(i: { name = "z${toString i}"; value = throw "unused wide value"; }) 9);',
    PROJECT_WARM + ["layered // wide"], 'g "k31"'),
    "false", traces=("cached layer winner once",))
boolean_case("Projection default stays fallback", pointer_hot(
    PROJECT_PRED + ' make = set: name: !(pred name (set.${name} or false)); f = make {};',
    PROJECT_WARM, 'f "absent"'), "false")
boolean_case("Projection nested base stays fallback", pointer_hot(
    PROJECT_PRED + ' make = set: name: !(pred name set.inner.${name}); '
    'f = make { inner = { field = true; }; }; '
    'g = make { inner = builtins.trace "nested base once" { field = true; }; };',
    PROJECT_WARM, 'g "field"'), "false", traces=("nested base once",))
boolean_case("Projection nested key stays fallback", pointer_hot(
    PROJECT_PRED + ' make = keys: set: !(pred keys.name set.${keys.name}); '
    'f = make { name = "field"; };', ['f { field = true; }'] * 4,
    'make { name = builtins.trace "nested key once" "field"; } { field = false; }'),
    "false", traces=("nested key once",))
boolean_case("Projection selected callee stays fallback", pointer_hot(
    'make = functions: set: name: !((functions.${name}) name set.${name}); '
    'f = make { field = name: value: false; } {};', PROJECT_WARM,
    'f (builtins.trace "callee selection key" "field")'), "true", traces=("callee selection key",))
PROJECTION_FALLBACK = (
    'pred = name: value: if builtins.isBool value then builtins.trace "projection fallback once" false else false; '
    + PROJECT_MAKE + ' f = make { field = 42; }; '
    'g = make (builtins.trace "fallback base once" { field = builtins.trace "fallback field once" true; });')
boolean_case("Projection fallback preserves demands", pointer_hot(PROJECTION_FALLBACK, PROJECT_WARM,
    'g (builtins.trace "fallback key once" "field")'), "true",
    traces=("fallback key once", "fallback base once", "fallback field once", "projection fallback once"))
for part, definitions, tail in (
        ("key", 'g = make { field = true; }; helper = x: builtins.trace "unused key helper" x;', 'g (helper "field")'),
        ("base", 'g = make (helper { field = true; }); helper = x: builtins.trace "unused base helper" x;', 'g "field"'),
        ("field", 'g = make { field = helper true; }; helper = x: builtins.trace "unused field helper" x;', 'g "field"')):
    name = "Projection logical depth during " + part + " demand"
    boolean_case(name, pointer_hot(PROJECT + definitions, PROJECT_WARM, tail), error="max-call-depth exceeded")
    CASE_FLAGS[name] = ["--option", "max-call-depth", "2"]
PROJECTION_ALIAS = (
    'f = key: choose: pred: set: if choose then (name: value: builtins.isBool set.${key}) '
    'else !(pred key set.${key}); factory = f (builtins.trace "old projection key" "old") true (n: v: false); '
    'old = factory (builtins.trace "old projection base" { old = builtins.trace "old projection field" true; }); '
    'currentKey = throw "unused current key"; currentSet = throw "unused current set";')
boolean_case("Projection same SSA uses captured context", pointer_hot(
    PROJECTION_ALIAS, ["old"] + ["f currentKey false old currentSet"] * 4,
    "f currentKey false old currentSet"), "false",
    traces=("old projection key", "old projection base", "old projection field"))
PROJECTION_RETIRE = (
    'pred = name: value: if builtins.isBool value then false else builtins.trace "projection nested deopt" false; '
    + PROJECT_MAKE + ' f = make { field = true; }; g = make { field = "unsupported"; };')
PROJECTION_NESTED = ['g "field"'] * 64
for throwing in (False, True):
    end = 'throw "projection outer field failure"' if throwing else "true"
    definitions = PROJECTION_RETIRE + ' suspended = make { field = builtins.trace "suspended field once" (' + \
        sequence(PROJECTION_NESTED, end) + "); };"
    tail = 'let caught = builtins.tryEval (suspended "field"); in builtins.seq caught [ caught.success (f "field") ]' \
        if throwing else 'suspended "field"'
    boolean_case("Projection nested retirement " + ("unwinds field" if throwing else "pins field"),
        pointer_hot(definitions, PROJECT_WARM, tail), "[ false true ]" if throwing else "true",
        traces=("suspended field once",) + ("projection nested deopt",) * 64)


# Value tails return existing WHNF cells. A Boolean consumer must still reject
# non-Booleans, and no returned set/list/closure may be recursively inspected.
VALUE_STATIC = "f = set: set.field;"
VALUE_WARM = ["f { field = 7; }"] * 4
VALUE_DYNAMIC = "make = set: key: set.${key}; f = make { field = 7; };"
boolean_case("Values static selected kinds", pointer_hot(
    VALUE_STATIC, VALUE_WARM,
    '[ (f { field = null; }) (f { field = false; }) (f { field = 42; }) '
    '(f { field = 1.5; }) (f { field = "text"; }) (builtins.isPath (f { field = ./.; })) '
    '(builtins.attrNames (f { field = { lazy = throw "unused set field"; }; })) '
    '(builtins.length (f { field = [ (throw "unused list item") ]; })) '
    '((f { field = x: x; }) 9) ((f { field = builtins.add; }) 2 3) '
    '((f { field = builtins.add 4; }) 5) ]'),
    '[ null false 42 1.5 "text" true [ "lazy" ] 1 9 5 9 ]')
boolean_case("Values dynamic current sets and keys", pointer_hot(
    VALUE_DYNAMIC + ' g = make { field = "new"; other = [ 9 ]; };', PROJECT_WARM,
    '[ (f "field") (g "field") (g "other") (make { field = null; } "field") ]'),
    '[ 7 "new" [ 9 ] null ]')
boolean_case("Values selected context survives", pointer_hot(
    VALUE_STATIC + ' context = { "/nix/store/00000000000000000000000000000000-jit" = { path = true; }; }; '
    'text = builtins.appendContext "retained" context;', VALUE_WARM,
    '[ (f { field = text; } == "retained") (builtins.getContext (f { field = text; }) == context) ]'),
    "[ true true ]")
boolean_case("Values selected containers retain identity", pointer_hot(
    VALUE_STATIC + ' set = { lazy = throw "unused shared field"; }; list = [ (throw "unused shared item") ];',
    VALUE_WARM, '[ (f { field = set; } == set) (f { field = list; } == list) ]'), "[ true true ]")
boolean_case("Values selected closure escapes with capture", pointer_hot(
    VALUE_STATIC + ' maker = captured: ignored: captured; old = maker (builtins.trace "escaped capture" 37); '
    'escaped = f { field = old; };', VALUE_WARM,
    'builtins.seq escaped (builtins.trace "after value return" '
    '[ (builtins.isFunction escaped) (escaped (throw "unused closure argument")) '
    '((f { field = maker 91; }) null) (escaped null) ])'), "[ true 37 91 37 ]",
    traces=("after value return", "escaped capture"))
boolean_case("Values dynamic demand order and sharing", pointer_hot(
    VALUE_DYNAMIC + ' g = make (builtins.trace "value base" '
    '{ field = builtins.trace "value field" [ (throw "unused returned item") ]; }); '
    'key = builtins.trace "value key" "field";', PROJECT_WARM,
    '[ (builtins.length (g key)) (builtins.length (g key)) ]'), "[ 1 1 ]",
    traces=("value key", "value base", "value field"))
boolean_case("Values tail forces WHNF before returning", pointer_hot(
    VALUE_STATIC, VALUE_WARM,
    'builtins.seq (f { field = builtins.trace "returned WHNF" { nested = throw "unused nested"; }; }) '
    '(builtins.trace "after WHNF" 42)'), "42", traces=("returned WHNF", "after WHNF"))
boolean_case("Values captured conditional changes environments", pointer_hot(
    'make = left: right: condition: if condition then left else right; '
    'f = make 7 "old"; g = make [ 9 ] null;', BOOL_WARM,
    '[ (f true) (g true) (f false) (g false) ]'), '[ 7 [ 9 ] "old" null ]')
boolean_case("Values conditional mixed Boolean and value paths", pointer_hot(
    'f = choose: value: if choose then value else builtins.isBool value;',
    ['f true 7', 'f false 7', 'f true "warm"', 'f false true'],
    '[ (f true "tail") (f false 42) (f false false) '
    '(builtins.attrNames (f true { lazy = throw "unused mixed field"; })) ]'),
    '[ "tail" false true [ "lazy" ] ]')
boolean_case("Values conditional unselected tails stay lazy", pointer_hot(
    'f = choose: left: right: if choose then left else right;',
    ['f true 7 null', 'f false null "warm"'] * 2,
    '[ (f true 42 (builtins.trace "unused right tail" (throw "unused"))) '
    '(builtins.length (f false (builtins.trace "unused left tail" (throw "unused")) [ (throw "unused item") ])) ]'),
    "[ 42 1 ]")
for arity in (2, 3, 4):
    formals = [f"a{i}" for i in range(arity)]
    # Alternate the returned formal, covering both early and late argument cells.
    selected = 0 if arity == 3 else arity - 1
    defs = "f = " + ": ".join(formals) + ": " + formals[selected] + ";"
    warm = "f " + " ".join(["7"] * arity)
    args = ['(builtins.trace "unused value formal" (throw "unused"))'] * arity
    args[selected] = '42'
    name = f"Values curried identity arity{arity}"
    boolean_case(name, pointer_hot(defs, [warm] * 4, "f " + " ".join(args)), "42")
    CASE_FLAGS[name] = ["--option", "max-call-depth", "1"]
boolean_case("Values shared formals preserve original cell", pointer_hot(
    'f = a: b: if builtins.isAttrs a then b else a; '
    'shared = builtins.trace "shared value formal" { lazy = throw "unused shared formal field"; };',
    ["f 7 null"] * 4,
    '[ (f shared shared == shared) (f shared shared == shared) ]'), "[ true true ]",
    traces=("shared value formal",))
VALUE_INLINE = "callee = x: x; middle = x: callee x; f = x: middle x;"
boolean_case("Values inline tail leaves nested contexts", pointer_hot(
    VALUE_INLINE, ["f 7"] * 4,
    '[ (f "tail") (builtins.length (f [ (throw "unused inline item") ])) '
    '(builtins.attrNames (f { lazy = throw "unused inline field"; })) ]'), '[ "tail" 1 [ "lazy" ] ]')
boolean_case("Values inline tail obeys exact nested depth", pointer_hot(
    VALUE_INLINE, ["f 7"] * 4, 'f "tail"'), '"tail"')
CASE_FLAGS["Values inline tail obeys exact nested depth"] = ["--option", "max-call-depth", "3"]
boolean_case("Values inline result feeds strict Boolean consumer", pointer_hot(
    'callee = x: x; middle = x: callee x; f = x: !(middle x);', BOOL_WARM,
    'f (builtins.trace "Boolean inline tail" 42)'), error="in the argument of the not operator",
    traces=("Boolean inline tail",))
boolean_case("Values inline Boolean condition keeps value branches", pointer_hot(
    'callee = x: x; make = left: right: x: if callee x then left else right; f = make 7 "other";',
    BOOL_WARM, '[ (f true) (f false) ]'), '[ 7 "other" ]')
boolean_case("Values inline changed callee skips argument", pointer_hot(
    'make = callee: x: callee x; yes = x: x; no = ignored: "changed"; f = make yes; g = make no;',
    ["f 7"] * 4 + ["no", "g"],
    'g (builtins.trace "unused changed value argument" (throw "unused"))'), '"changed"')
VALUE_ALIAS = (
    'f = captured: choose: pred: arg: if choose then (ignored: captured) else pred arg; '
    'oldStage = f "old" true (x: x); old = oldStage 0;')
boolean_case("Values inline same SSA uses old closure environment", pointer_hot(
    VALUE_ALIAS, ["old"] + ['f "new" false old null'] * 4,
    '[ (f "new" false old null) (f "last" false old (throw "unused old argument")) ]'),
    '[ "old" "old" ]')
boolean_case("Values inline depth checked before returned demand", pointer_hot(
    'callee = x: x; middle = x: callee x; f = skip: x: if skip then x else middle x;',
    ["middle 7"] + ["f true 7"] * 4,
    'f false (builtins.trace "unused deep value" (throw "unused"))'), error="max-call-depth exceeded")
CASE_FLAGS["Values inline depth checked before returned demand"] = ["--option", "max-call-depth", "2"]
for part, definitions, tail, context, traces in (
        ("missing", 'g = make (builtins.trace "value missing base" {});',
         'g (builtins.trace "value missing key" "absent")', "attribute 'absent' missing",
         ("value missing key", "value missing base")),
        ("base type", 'g = make (builtins.trace "value bad base" 42);',
         'g (builtins.trace "value type key" "field")', "while selecting an attribute",
         ("value type key", "value bad base")),
        ("key type", 'g = make (builtins.trace "unused value base" (throw "unused"));',
         'g (builtins.trace "value bad key" 42)', "while evaluating an attribute name", ("value bad key",)),
        ("key throw", 'g = make (builtins.trace "unused value base" (throw "unused"));',
         'g (builtins.trace "value key throw" (throw "value key failure"))', "value key failure", ("value key throw",)),
        ("base throw", 'g = make (builtins.trace "value base throw" (throw "value base failure"));',
         'g (builtins.trace "value ready key" "field")', "value base failure", ("value ready key", "value base throw")),
        ("field throw", 'g = make (builtins.trace "value throwing base" '
         '{ field = builtins.trace "value field throw" (throw "value field failure"); });',
         'g (builtins.trace "value throwing key" "field")', "value field failure",
         ("value throwing key", "value throwing base", "value field throw"))):
    boolean_case("Values selection error " + part,
        pointer_hot(VALUE_DYNAMIC + definitions, PROJECT_WARM, tail), error=context, traces=traces)
boolean_case("Values condition remains strict Boolean", pointer_hot(
    'f = set: if set.condition then set.left else set.right;',
    ['f { condition = true; left = 7; }'] * 4,
    'f { condition = builtins.trace "bad value condition" 42; '
    'left = builtins.trace "unused condition left" (throw "unused"); right = throw "unused"; }'),
    error="while evaluating a branch condition", traces=("bad value condition",))
boolean_case("Values contextful key is rejected before base", pointer_hot(
    VALUE_DYNAMIC + ' g = make (builtins.trace "unused context key base" (throw "unused")); '
    'key = builtins.appendContext "field" '
    '{ "/nix/store/00000000000000000000000000000000-jit" = { path = true; }; };',
    PROJECT_WARM, "g key"), error="not allowed to refer to a store path")
boolean_case("Values recursive oracle keeps result", pointer_hot(VALUE_STATIC, [],
    'f { field = builtins.trace "value oracle once" (' + sequence(VALUE_WARM, '"outer"') + '); }'),
    '"outer"', traces=("value oracle once",))
VALUE_RETIRE = (
    'f = set: if builtins.isAttrs set then set.field else builtins.trace "value nested deopt" null; '
    'old = ignored: "escaped";')
VALUE_NESTED = ['f "unsupported"'] * 64
boolean_case("Values retired plan releases escaped closure safely", pointer_hot(
    VALUE_RETIRE + ' escaped = f { field = builtins.trace "suspended returned closure" (' +
    sequence(VALUE_NESTED, "old") + '); };', VALUE_WARM,
    'builtins.seq escaped [ (builtins.isFunction escaped) (escaped (throw "unused escaped argument")) '
    '(f { field = "after"; }) ]'), '[ true "escaped" "after" ]',
    traces=("suspended returned closure",) + ("value nested deopt",) * 64)
boolean_case("Values retired plan unwinds failed value demand", pointer_hot(
    VALUE_RETIRE, VALUE_WARM,
    'let caught = builtins.tryEval (f { field = builtins.trace "suspended failed value" (' +
    sequence(VALUE_NESTED, 'throw "outer value failure"') + '); }); '
    'in builtins.seq caught [ caught.success (f { field = "after"; }) ]'), '[ false "after" ]',
    traces=("suspended failed value",) + ("value nested deopt",) * 64)
value_leaf_names = [f"v{i}" for i in range(18)]
boolean_case("Values leaf budget keeps untouched alternatives lazy", pointer_hot(
    " ".join(f'{n} = builtins.trace "value leaf {n}" "{n}";' for n in value_leaf_names) +
    ' f = x: ' + " ".join(f"if builtins.isBool x then {n} else" for n in value_leaf_names[:-1]) +
    " " + value_leaf_names[-1] + ";", ["f 7"] * 4, "f true"), '"v0"',
    traces=("value leaf v17", "value leaf v0"))


# Empty recipes are tail results, not persistent cells and not Boolean values.
# They must not evaluate an unused argument or retain a prior string context.
for label, literal, value, inspect in (
        ("attrs", "{}", '{ lazy = throw "unused empty-test field"; }',
         lambda empty, selected: f'[ ({empty} == {{}}) (builtins.attrNames ({selected})) ]'),
        ("list", "[]", '[ (throw "unused empty-test item") ]',
         lambda empty, selected: f'[ (builtins.length ({empty})) (builtins.length ({selected})) ]'),
        ("string", '""', 'text',
         lambda empty, selected: f'[ ({empty}) (builtins.getContext ({selected}) == context) ]')):
    for side in ("then", "else"):
        rhs = f"if condition then {literal} else value" if side == "then" else f"if condition then value else {literal}"
        defs = 'context = { "/nix/store/00000000000000000000000000000000-jit" = { path = true; }; }; '
        defs += 'text = builtins.appendContext "contextual" context; f = condition: value: ' + rhs + ';'
        empty_condition = "true" if side == "then" else "false"
        value_condition = "false" if side == "then" else "true"
        warm = [f"f {empty_condition} null", f"f {value_condition} {literal}"] * 2
        empty_call = f'f {empty_condition} (builtins.trace "unused empty argument" (throw "unused"))'
        selected_call = f"f {value_condition} {value}"
        expected = {'attrs': '[ true [ "lazy" ] ]', 'list': '[ 0 1 ]', 'string': '[ "" true ]'}[label]
        boolean_case(f"Empty curried {label} {side}", pointer_hot(defs, warm,
            inspect(empty_call, selected_call)), expected)
boolean_case("Empty unconditional roots skip arguments", pointer_hot(
    'attrs = x: {}; list = x: []; string = x: "";',
    ["attrs null", "list null", "string null"] * 4,
    '[ (attrs (builtins.trace "unused attrs argument" (throw "unused"))) '
    '(list (builtins.trace "unused list argument" (throw "unused"))) '
    '(string (builtins.trace "unused string argument" (throw "unused"))) ]'), '[ { } [ ] "" ]')
boolean_case("Empty inline leaves restore nested context", pointer_hot(
    'callee = x: []; middle = x: callee x; f = x: middle x;', ["f null"] * 4,
    'f (builtins.trace "unused nested empty argument" (throw "unused"))'), "[ ]")
CASE_FLAGS["Empty inline leaves restore nested context"] = ["--option", "max-call-depth", "3"]
boolean_case("Empty inline skips projected key base and field", pointer_hot(
    'callee = x: {}; make = set: key: callee set.${key}; f = make { field = true; }; '
    'g = make (builtins.trace "unused empty projection base" (throw "unused"));', PROJECT_WARM,
    'g (builtins.trace "unused empty projection key" (throw "unused"))'), "{ }")
boolean_case("Empty captured value remains shallow and current", pointer_hot(
    'make = captured: condition: if condition then {} else captured; '
    'f = make { old = throw "unused old capture"; }; '
    'g = make (builtins.trace "needed empty-test capture" { new = throw "unused new capture"; });', BOOL_WARM,
    '[ (f true == {}) (g true == {}) (builtins.attrNames (g false)) (builtins.attrNames (f false)) ]'),
    '[ true true [ "new" ] [ "old" ] ]', traces=("needed empty-test capture",))
boolean_case("Empty condition error precedes result", pointer_hot(
    'f = condition: value: if condition then {} else value;', ["f true null"] * 4,
    'f (builtins.trace "empty condition failure" (throw "empty condition failed")) '
    '(builtins.trace "unused empty error argument" (throw "unused"))'),
    error="empty condition failed", traces=("empty condition failure",))
boolean_case("Empty condition type stays strict", pointer_hot(
    'f = condition: value: if condition then [] else value;', ["f true null"] * 4,
    'f 42 (builtins.trace "unused empty type argument" (throw "unused"))'),
    error="while evaluating a branch condition")
boolean_case("Empty inline return stays invalid in Boolean context", pointer_hot(
    'callee = condition: if condition then true else {}; f = condition: !(callee condition);',
    ["f true"] * 4, "f false"), error="in the argument of the not operator")


# List recipes retain existing element handles, including unforced thunks and
# productive blackholes. Constructing or validating the list cannot force them.
LIST_RETURN = "f = x: [ x ];"
LIST_WARM = ['f (builtins.trace "unused warm list element" (throw "unused"))'] * 4
boolean_case("List return singleton stays non-strict", pointer_hot(LIST_RETURN, LIST_WARM,
    'builtins.length (f (builtins.trace "unused list element" (throw "unused")))'), "1")
boolean_case("List return duplicate handles force once", pointer_hot(
    'f = x: [ x x x x ]; shared = builtins.trace "shared list element" 7;', LIST_WARM,
    'let xs = f shared; in [ (builtins.length xs) (builtins.elemAt xs 2) (builtins.head xs) (builtins.elemAt xs 3) ]'),
    "[ 4 7 7 7 ]", traces=("shared list element",))
boolean_case("List return late error keeps consumer trace", pointer_hot(LIST_RETURN, LIST_WARM,
    'builtins.head (f (builtins.trace "late list failure" (throw "late element failed")))'),
    error="while calling the 'head' builtin", traces=("late list failure",))
boolean_case("List return cyclic element stays lazy", pointer_hot(
    LIST_RETURN + " cycle = cycle;", LIST_WARM, "builtins.length (f cycle)"), "1")
boolean_case("List return cyclic element fails only when demanded", pointer_hot(
    LIST_RETURN + " cycle = cycle;", LIST_WARM, "builtins.head (f cycle)"), error="infinite recursion encountered")
boolean_case("List return productive blackhole survives", pointer_hot(
    LIST_RETURN + " xs = f xs;", LIST_WARM,
    "[ (builtins.length xs) (builtins.length (builtins.head xs)) ]"), "[ 1 1 ]")
boolean_case("List return deferred closure keeps capture", pointer_hot(
    LIST_RETURN + 'make = captured: ignored: captured; '
    'xs = f (make (builtins.trace "late closure capture" 37));', LIST_WARM,
    'builtins.seq xs (builtins.trace "after list construction" '
    '[ ((builtins.head xs) (throw "unused closure argument")) ((builtins.head xs) null) ])'),
    "[ 37 37 ]", traces=("after list construction", "late closure capture"))
LIST_CAPTURE = (
    'make = seed: let delayed = builtins.trace "fresh list capture" seed; in ignored: [ delayed ]; '
    'f = make 7; g = make 9;')
boolean_case("List return fresh capture resolves without forcing", pointer_hot(
    LIST_CAPTURE, ["f null"] * 4,
    'let xs = g (throw "unused capture argument"); in builtins.seq xs '
    '(builtins.trace "after fresh capture list" [ (builtins.length xs) (builtins.head xs) (builtins.head xs) ])'),
    "[ 1 9 9 ]", traces=("after fresh capture list", "fresh list capture"))
boolean_case("List return captured handles preserve later force order", pointer_hot(
    'make = seed: let a = builtins.trace "capture a" seed; b = builtins.trace "capture b" seed; '
    'in x: [ a b x ]; f = make 7; g = make 9;', ["f null"] * 4,
    'let xs = g (throw "unused third element"); in builtins.seq xs '
    '(builtins.trace "after ordered list" [ (builtins.length xs) (builtins.elemAt xs 1) (builtins.head xs) ])'),
    "[ 3 9 9 ]", traces=("after ordered list", "capture b", "capture a"))
boolean_case("List return current captured environments", pointer_hot(
    'make = left: right: x: [ left x right ]; f = make 7 "old"; g = make 91 "new";',
    ["f null"] * 4, '[ (g false) (f true) ]'), '[ [ 91 false "new" ] [ 7 true "old" ] ]')
for arity in (2, 3, 4):
    formals = [f"a{i}" for i in range(arity)]
    defs = "f = " + ": ".join(formals) + ": [ " + " ".join(reversed(formals)) + " ];"
    call = "f " + " ".join(str(i + 1) for i in range(arity))
    name = f"List return curried order arity{arity}"
    boolean_case(name, pointer_hot(defs, [call] * 4, call),
        "[ " + " ".join(str(i + 1) for i in reversed(range(arity))) + " ]")
    # Strict printing visits the list and its elements at two depths.
    CASE_FLAGS[name] = ["--option", "max-call-depth", "2"]
boolean_case("List return curry stages stay sequential", pointer_hot(
    'f = a: b: c: d: [ a b c d ];', ["f 1 2 3 4"] * 5, "42"), "42")
CASE_FLAGS["List return curry stages stay sequential"] = ["--option", "max-call-depth", "1"]
boolean_case("List return optional both branches", pointer_hot(
    'f = condition: value: if condition then [ value ] else [];',
    ['f true (throw "unused warm optional")', 'f false (throw "unused warm optional")'] * 2,
    '[ (builtins.length (f true (builtins.trace "unused true optional" (throw "unused")))) '
    '(builtins.length (f false (builtins.trace "unused false optional" (throw "unused")))) ]'), "[ 1 0 ]")
LIST_INLINE = "callee = x: [ x ]; middle = x: callee x; f = x: middle x;"
boolean_case("List return inline element forces after Leave", pointer_hot(
    LIST_INLINE + ' helper = x: builtins.trace "element after Leave" x;', ["f 7"] * 4,
    "f (helper 42)"), "[ 42 ]", traces=("element after Leave",))
CASE_FLAGS["List return inline element forces after Leave"] = ["--option", "max-call-depth", "3"]
boolean_case("List return saturated inline preserves order", pointer_hot(
    'callee = a: b: c: [ c a b ]; f = a: b: c: callee a b c;', ["f 1 2 3"] * 4,
    "f 4 5 6"), "[ 6 4 5 ]")
CASE_FLAGS["List return saturated inline preserves order"] = ["--option", "max-call-depth", "2"]
boolean_case("List return changed callee skips argument", pointer_hot(
    'make = callee: x: callee x; singleton = x: [ x ]; empty = ignored: []; '
    'f = make singleton; g = make empty;', ["f 7"] * 4 + ["empty", "g"],
    'g (builtins.trace "unused changed list argument" (throw "unused"))'), "[ ]")
LIST_ALIAS = (
    'f = captured: choose: pred: arg: if choose then (ignored: [ captured ]) else pred arg; '
    'oldStage = f "old" true (x: []); old = oldStage 0;')
boolean_case("List return inline capture uses original environment", pointer_hot(
    LIST_ALIAS, ["old"] + ['f "new" false old null'] * 4,
    'f "last" false old (throw "unused old-list argument")'), '[ "old" ]')
boolean_case("List return local computation remains deferred fallback", pointer_hot(
    'f = x: [ (x + 1) ];', ["f 7"] * 4,
    '[ (builtins.length (f (builtins.trace "unused local list input" (throw "unused")))) '
    '(builtins.head (f 41)) ]'), "[ 1 42 ]")
boolean_case("List return local projection remains deferred fallback", pointer_hot(
    'f = set: [ set.field ];', ["f { field = 7; }"] * 4,
    '[ (builtins.length (f (builtins.trace "unused list projection base" (throw "unused")))) '
    '(builtins.head (f { field = builtins.trace "late projected field" 9; })) ]'),
    "[ 1 9 ]", traces=("late projected field",))
boolean_case("List return virtual inline formal stays deferred", pointer_hot(
    'callee = x: [ x ]; f = set: callee set.field;', ["f { field = 7; }"] * 4,
    'builtins.length (f (builtins.trace "unused virtual list base" (throw "unused")))'), "1")
boolean_case("List return element count cap stays lazy", pointer_hot(
    'f = x: [ x x x x x ];', LIST_WARM,
    'builtins.length (f (builtins.trace "unused oversized list element" (throw "unused")))'), "5")
boolean_case("List return Boolean consumer remains strict", pointer_hot(
    'f = x: if builtins.isBool x then false else ![ x ];', BOOL_WARM, "f 42"),
    error="in the argument of the not operator")
boolean_case("List return condition remains strict", pointer_hot(
    'f = condition: value: if condition then [ value ] else [];', ["f true null"] * 4,
    'f 42 (builtins.trace "unused invalid list condition element" (throw "unused"))'),
    error="while evaluating a branch condition")
boolean_case("List return recursive oracle does not force element", pointer_hot(
    'f = condition: value: if condition then [ value ] else [];', [],
    'builtins.length (f (builtins.trace "list oracle condition" (' +
    sequence(["f true null"] * 4, "true") + ')) (builtins.trace "unused oracle list element" (throw "unused")))'),
    "1", traces=("list oracle condition",))
LIST_RETIRE = 'f = x: if builtins.isAttrs x then [ x ] else builtins.trace "list retirement deopt" [];'
LIST_RETIRE_WARM = ["f {}"] * 4
LIST_RETIRE_NESTED = ['f "unsupported"'] * 64
boolean_case("List return survives active retirement and escapes", pointer_hot(
    LIST_RETIRE + ' old = ignored: "escaped"; xs = f (builtins.trace "suspended list input" (' +
    sequence(LIST_RETIRE_NESTED, '{ closure = old; lazy = throw "unused escaped list field"; }') + '));',
    LIST_RETIRE_WARM,
    'builtins.seq xs [ (builtins.length xs) ((builtins.head xs).closure (throw "unused escaped closure argument")) '
    '(builtins.length (f {})) ]'), '[ 1 "escaped" 1 ]',
    traces=("suspended list input",) + ("list retirement deopt",) * 64)
boolean_case("List return active retirement unwinds failed condition", pointer_hot(
    LIST_RETIRE, LIST_RETIRE_WARM,
    'let caught = builtins.tryEval (f (builtins.trace "failed list input" (' +
    sequence(LIST_RETIRE_NESTED, 'throw "list outer failure"') + '))); '
    'in builtins.seq caught [ caught.success (builtins.length (f {})) ]'), "[ false 1 ]",
    traces=("failed list input",) + ("list retirement deopt",) * 64)
list_leaf_names = [f"l{i}" for i in range(17)]
boolean_case("List return leaf budget preserves lazy alternatives", pointer_hot(
    " ".join(f'{n} = builtins.trace "list leaf {n}" "{n}";' for n in list_leaf_names) +
    ' f = x: ' + " ".join(f"if x then [ {n} ] else" for n in list_leaf_names[:-1]) +
    " [ " + list_leaf_names[-1] + " ];", ["f false"] * 4, "builtins.head (f true)"),
    '"l0"', traces=("list leaf l0",))


# Binary string comparisons have independent byte/effect oracles. String literals
# are operands in the plan; they are not assumed to have persistent Value cells.
STRING_PAIR = 'f = lhs: rhs: lhs == rhs;'
STRING_WARM = ['f "warm" "warm"'] * 4
for operator, equal, different in (("==", "true", "false"), ("!=", "false", "true")):
    for side in ("left", "right"):
        body = f'"needle" {operator} x' if side == "left" else f'x {operator} "needle"'
        boolean_case(f"String {operator} literal {side}", pointer_hot(
            f'f = x: {body};', ['f "needle"'] * 4,
            '[ (f "needle") (f "other") (f "") (f "needlex") ]'),
            f"[ {equal} {different} {different} {different} ]")
boolean_case("String literal pair", pointer_hot('f = ignored: "same" == "same";', ['f null'] * 4,
    'f (builtins.trace "unused literal argument" (throw "unused"))'), "true")
boolean_case("String empty literal comparison", pointer_hot('f = x: x != "";', ['f ""'] * 4,
    '[ (f "") (f "x") (f "\\n") ]'), "[ false true true ]")
boolean_case("String pair demand order and sharing", pointer_hot(
    STRING_PAIR + ' lhs = builtins.trace "string lhs" "same"; rhs = builtins.trace "string rhs" "same";',
    STRING_WARM, '[ (f lhs rhs) (f lhs rhs) ]'), "[ true true ]", traces=("string lhs", "string rhs"))
boolean_case("String same cell forces once", pointer_hot(
    'f = x: x == x; shared = builtins.trace "same string cell" "text";', ['f "warm"'] * 4,
    "f shared"), "true", traces=("same string cell",))
boolean_case("String literal NUL parser rejection", 'let f = x: x == "a\x00b"; in f "a"',
    error="input string contains NUL byte")
boolean_case("String JSON NUL remains rejected", pointer_hot(STRING_PAIR, STRING_WARM,
    'f "a" (builtins.fromJSON \'\'"a\\u0000b"\'\')'), error="contains null bytes")
boolean_case("String literal byte lengths", pointer_hot(
    'f = x: x == "a\\nb";', ['f "a\\nb"'] * 4,
    '[ (f "a\\nb") (f "a\\nc") (f "a") (f "a\\nb\\t") (f "λ") ]'),
    "[ true false false false false ]")
boolean_case("String UTF8 literal bytes", pointer_hot('f = x: x != "λ雪";', ['f "λ雪"'] * 4,
    '[ (f "λ雪") (f "λ") (f "雪λ") ]'), "[ false true true ]")
boolean_case("String context ignored without mutation", pointer_hot(
    STRING_PAIR + ' context = { "/nix/store/00000000000000000000000000000000-jit" = { path = true; }; }; '
    'left = builtins.appendContext "same" context; right = "same";', STRING_WARM,
    '[ (f left right) (f right left) (builtins.getContext left == context) (builtins.getContext right == {}) ]'),
    "[ true true true true ]")
boolean_case("String fresh captured environment", pointer_hot(
    'make = captured: x: x != captured; f = make "old"; '
    'g = make (builtins.trace "new string capture" "new");', ['f "old"'] * 4,
    '[ (g (builtins.trace "new string argument" "new")) (f "new") (g "old") ]'),
    "[ false true true ]", traces=("new string argument", "new string capture"))
boolean_case("String skipped comparison stays lazy", pointer_hot(
    'f = condition: lhs: rhs: if condition then lhs == rhs else false;',
    ['f true "x" "x"'] * 4,
    'f false (builtins.trace "unused string lhs" (throw "unused")) '
    '(builtins.trace "unused string rhs" (throw "unused"))'), "false")
for side, tail, traces in (
        ("lhs", 'f (builtins.trace "failed string lhs" (throw "string lhs failed")) '
         '(builtins.trace "unused failed rhs" (throw "unused"))', ("failed string lhs",)),
        ("rhs", 'f (builtins.trace "ready string lhs" "x") '
         '(builtins.trace "failed string rhs" (throw "string rhs failed"))',
         ("ready string lhs", "failed string rhs"))):
    boolean_case("String error " + side, pointer_hot(STRING_PAIR, STRING_WARM, tail),
        error="string " + side + " failed", traces=traces)
boolean_case("String nonstring lhs still demands rhs", pointer_hot(STRING_PAIR, STRING_WARM,
    'f (builtins.trace "nonstring lhs" false) '
    '(builtins.trace "nonstring demanded rhs" (throw "rhs must fail"))'),
    error="rhs must fail", traces=("nonstring lhs", "nonstring demanded rhs"))
boolean_case("String generic equality fallback remains deep", pointer_hot(
    STRING_PAIR + ' shared = [ (throw "shared list element must stay lazy") ];', STRING_WARM,
    '[ (f 7 7.0) (f false "false") (f null null) (f [ 1 2 ] [ 1 2 ]) '
    '(f { answer = 42; } { answer = 42; }) (f shared shared) (f (x: x) (x: x)) ]'),
    "[ true false true true true true false ]")
boolean_case("String generic equality fallback element error", pointer_hot(STRING_PAIR, STRING_WARM,
    'f [ (builtins.trace "deep equality element" (throw "deep equality failed")) ] [ 1 ]'),
    error="deep equality failed", traces=("deep equality element",))
boolean_case("String static projection order", pointer_hot(
    'f = left: right: left.field == right.field;',
    ['f { field = "x"; } { field = "x"; }'] * 4,
    'f (builtins.trace "compare left base" { field = builtins.trace "compare left field" "x"; }) '
    '(builtins.trace "compare right base" { field = builtins.trace "compare right field" "x"; })'),
    "true", traces=("compare left base", "compare left field", "compare right base", "compare right field"))
boolean_case("String dynamic projection order", pointer_hot(
    'make = set: key: set.${key} != "different"; f = make { field = "x"; }; '
    'g = make (builtins.trace "string projection base" { field = builtins.trace "string projection field" "x"; });',
    ['f "field"'] * 4, 'g (builtins.trace "string projection key" "field")'),
    "true", traces=("string projection key", "string projection base", "string projection field"))
for arity in (3, 4):
    args = ["left", "right"] + [f"unused{i}" for i in range(arity - 2)]
    call = 'f "x" "x"' + ' (throw "unused curried string")' * (arity - 2)
    name = f"String curried sequential depth arity{arity}"
    boolean_case(name, pointer_hot('f = ' + ": ".join(args) + ': left == right;', [call] * 4, call), "true")
    CASE_FLAGS[name] = ["--option", "max-call-depth", "1"]
STRING_INLINE = 'callee = left: right: left != right; middle = left: right: callee left right; f = left: right: middle left right;'
boolean_case("String inline nested Leave", pointer_hot(STRING_INLINE,
    ['f "x" "x"'] * 4, 'f "left" "right"'), "true")
CASE_FLAGS["String inline nested Leave"] = ["--option", "max-call-depth", "3"]
boolean_case("String inline demand keeps logical depth", pointer_hot(
    STRING_INLINE + ' helper = x: x;', ['f "x" "x"'] * 4,
    'f "left" (helper "right")'), error="max-call-depth exceeded")
CASE_FLAGS["String inline demand keeps logical depth"] = ["--option", "max-call-depth", "3"]
STRING_ALIAS = ('f = captured: choose: pred: x: if choose then (value: value == captured) else pred x; '
                'oldStage = f "old" true (x: false); old = oldStage null;')
boolean_case("String inline same SSA different capture", pointer_hot(STRING_ALIAS,
    ["old"] + ['f "new" false old "old"'] * 4, 'f "last" false old "old"'), "true")
boolean_case("String fallback keeps completed demands", pointer_hot(
    'f = left: right: if left == right then builtins.trace "string fallback" false else true; '
    'left = builtins.trace "fallback string left" "same"; right = builtins.trace "fallback string right" "same";',
    ['f "left" "right"'] * 4, 'f left right'), "false",
    traces=("fallback string left", "fallback string right", "string fallback"))
boolean_case("String recursive oracle shared entry", pointer_hot(STRING_PAIR, [],
    'f (builtins.trace "string recursive oracle" (' + sequence(STRING_WARM, '"outer"') + ')) "outer"'),
    "true", traces=("string recursive oracle",))
STRING_RETIRE = 'f = left: right: if left == right then true else builtins.trace "string retirement deopt" false;'
STRING_NESTED = ['f "left" "right"'] * 64
boolean_case("String reentrant retirement preserves comparison", pointer_hot(STRING_RETIRE, STRING_WARM,
    'f (builtins.trace "suspended string lhs" (' + sequence(STRING_NESTED, '"same"') + ')) "same"'),
    "true", traces=("suspended string lhs",) + ("string retirement deopt",) * 64)
boolean_case("String reentrant retirement restores throw", pointer_hot(STRING_RETIRE, STRING_WARM,
    'let caught = builtins.tryEval (f "same" (builtins.trace "suspended string rhs" (' +
    sequence(STRING_NESTED, 'throw "suspended comparison failed"') + '))); '
    'in builtins.seq caught [ caught.success (f "same" "same") ]'), "[ false true ]",
    traces=("suspended string rhs",) + ("string retirement deopt",) * 64)
boolean_case("String local computation remains fallback", pointer_hot(
    'f = x: (builtins.trace "local string expression" x) == "x";', ['f "x"'] * 4, 'f "x"'),
    "true", traces=("local string expression",) * 5)
boolean_case("String literal byte budget", pointer_hot('f = x: x == "' + "a" * 4097 + '";',
    ['f "small"'] * 4, 'f (builtins.trace "large literal input" "small")'),
    "false", traces=("large literal input",))
boolean_case("String literal operand budget", pointer_hot(
    'f = x: ' + " ".join(f'if x == "v{i}" then true else' for i in range(17)) + ' false;',
    ['f "missing"'] * 4, 'f (builtins.trace "literal budget input" "v0")'),
    "true", traces=("literal budget input",))

# Keep path cases separate: the string-only candidate can run every earlier gate
# with --skip-string-paths before multi-key Select lowering is built.
for length in (2, 3, 4):
    path = ".".join(f"k{i}" for i in range(length))
    value = '"match"'
    for i in reversed(range(length)):
        value = '{ k' + str(i) + ' = ' + value + '; }'
    boolean_case(f"String path length{length}", pointer_hot(f'f = set: set.{path} == "match";',
        ["f " + value] * 4, "f " + value), "true")
PATH_COMPARE = 'f = set: set.a.b.c == "match";'
PATH_WARM = ['f { a.b.c = "match"; }'] * 4
boolean_case("String path force order and sharing", pointer_hot(
    PATH_COMPARE + ' set = builtins.trace "path base" { a = builtins.trace "path a" '
    '{ b = builtins.trace "path b" { c = builtins.trace "path c" "match"; unused = throw "unused path field"; }; }; };',
    PATH_WARM, '[ (f set) (f set) ]'), "[ true true ]", traces=("path base", "path a", "path b", "path c"))
boolean_case("String path short circuit skips projection", pointer_hot(
    'f = condition: set: condition && set.a.b == "match";', ['f true { a.b = "match"; }'] * 4,
    'f false (builtins.trace "unused path base" (throw "unused"))'), "false")
for label, value, fragment, traces in (
        ("base", 'builtins.trace "path bad base" 42', "while selecting an attribute", ("path bad base",)),
        ("intermediate", '{ a = builtins.trace "path bad intermediate" []; }',
         "while selecting an attribute", ("path bad intermediate",)),
        ("missing", '{ a.b = {}; }', "attribute 'c' missing", ()),
        ("final", '{ a.b.c = builtins.trace "path final failure" (throw "path field failed"); }',
         "path field failed", ("path final failure",))):
    boolean_case("String path error " + label, pointer_hot(PATH_COMPARE, PATH_WARM, 'f (' + value + ')'),
        error=fragment, traces=traces)
boolean_case("String path current captures", pointer_hot(
    'make = set: x: set.a.b == x; f = make { a.b = "old"; }; g = make { a.b = "new"; };',
    ['f "old"'] * 4, '[ (g "new") (f "new") (g "old") ]'), "[ true false false ]")
boolean_case("String path layered intermediate", pointer_hot(
    'f = set: set.a.b == "new"; base = { b = "old"; lazy = throw "unused layered field"; '
    + " ".join(f'k{i} = {i};' for i in range(40)) + ' }; layered = base // { b = "new"; };',
    ['f { a.b = "new"; }'] * 4, 'f { a = layered; }'), "true")
boolean_case("String path changed callee skips projection", pointer_hot(
    'make = pred: set: pred set.a.b; compare = x: x == "match"; ignore = x: false; '
    'f = make compare; g = make ignore;', ['f { a.b = "match"; }'] * 4 + ['ignore', 'g'],
    'g (builtins.trace "unused changed path input" (throw "unused"))'), "false")
boolean_case("String path nested callee restores Leave", pointer_hot(
    'callee = set: set.a.b == "match"; middle = set: callee set; f = set: middle set;',
    ['f { a.b = "match"; }'] * 4, 'f { a.b = "match"; }'), "true")
CASE_FLAGS["String path nested callee restores Leave"] = ["--option", "max-call-depth", "3"]
boolean_case("String path final field remains lazy for hasAttr", pointer_hot(
    'f = set: set.a.b ? field;', ['f { a.b.field = true; }'] * 4,
    'f { a.b.field = builtins.trace "unused final hasAttr field" (throw "unused"); }'), "true")
boolean_case("String path inline same SSA different environment", pointer_hot(
    'f = captured: choose: pred: arg: if choose then (set: captured.a.b == set.a.b) else pred arg; '
    'oldStage = f { a.b = "old"; } true (x: false); old = oldStage null;',
    ['old'] + ['f { a.b = "new"; } false old { a.b = "old"; }'] * 4,
    'f { a.b = "last"; } false old { a.b = "old"; }'), "true")
boolean_case("String path survives active retirement", pointer_hot(
    'f = set: if set.a.b == "match" then true else builtins.trace "path retirement deopt" false;',
    ['f { a.b = "match"; }'] * 4,
    'f { a = builtins.trace "suspended path intermediate" (' +
    sequence(['f { a.b = "other"; }'] * 64, '{ b = "match"; }') + '); }'),
    "true", traces=("suspended path intermediate",) + ("path retirement deopt",) * 64)
for label, definition, warm, tail, traces in (
        ("length cap", 'f = set: set.a.b.c.d.e == "match";', 'f { a.b.c.d.e = "match"; }',
         'f { a.b.c.d.e = builtins.trace "long path field" "match"; }', ("long path field",)),
        ("dynamic multikey", 'f = key: set: set.a.${key} == "match";', 'f "b" { a.b = "match"; }',
         'f (builtins.trace "multikey dynamic key" "b") { a.b = "match"; }', ("multikey dynamic key",)),
        ("default", 'f = set: (set.a.b or "match") == "match";', 'f { a.b = "match"; }',
         'f {}', ()),
        ("local base", 'f = set: (builtins.trace "local path base" set).a.b == "match";',
         'f { a.b = "match"; }', 'f { a.b = "match"; }', ("local path base",) * 5)):
    boolean_case("String path excluded " + label, pointer_hot(definition, [warm] * 4, tail), "true", traces=traces)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mlnix", default=str(ROOT / "build/bin/mlnix"))
    parser.add_argument("--skip-string-paths", action="store_true", help="stage string comparison checks before static multi-key paths")
    args = parser.parse_args()
    binary = str(Path(args.mlnix).resolve())
    checked = 0
    with tempfile.TemporaryDirectory(prefix="mlnix-jit-check-") as tmp:
        base = {k: v for k, v in os.environ.items() if not k.startswith("MLNIX_JIT")}
        for key in ("MLNIX_DEFER", "MLNIX_STATS", "MLNIX_PRIMS_IRDL", "MLNIX_PIPELINE"):
            base.pop(key, None)
        base.update(MLNIX_STORE_ROOT=tmp + "/root", MLNIX_STATE_DIR=tmp + "/state", NIX_REMOTE="dummy://")

        def run(expr, demand, jit=False, stats=False, dump=None, extra=None, flags=()):
            env = dict(base)
            if demand:
                env["MLNIX_DEFER"] = "1"
            if jit:
                env.update(MLNIX_JIT="1", MLNIX_JIT_THRESHOLD="1")
            if stats:
                env["MLNIX_STATS"] = "1"
            if dump:
                env["MLNIX_JIT_DUMP"] = str(dump)
            env.update(extra or {})
            source = ["-E", expr]
            if "\x00" in expr:
                # argv cannot contain NUL; a source file preserves the parser
                # rejection case, with the same diagnostic path in both arms.
                path = Path(tmp) / "nul-expression.nix"
                path.write_text(expr)
                source = [str(path)]
            return subprocess.run([binary, "instantiate", "--eval", "--strict", "--show-trace", *flags, *source],
                                  cwd=ROOT, env=env, capture_output=True, timeout=60)

        def counters(expr, demand, dump=None, extra=None, expected_rc=0, flags=()):
            p = run(expr, demand, jit=True, stats=True, dump=dump, extra=extra, flags=flags)
            assert p.returncode == expected_rc, f"instrumented run: expected rc={expected_rc}, got {p}"
            line = next((line for line in p.stderr.decode().splitlines() if line.startswith("jit:")), None)
            assert line, f"JIT statistics absent (rc={p.returncode}, stdout={p.stdout!r}): {p.stderr.decode()}"
            fields = {k: int(v) for k, v in re.findall(r"(\w+)=(\d+)", line)}
            assert fields["mismatches"] == fields["compile_failures"] == 0, line
            assert fields["lazy_value_mismatches"] == 0, line
            return fields

        for demand in (False, True):
            for name, expr in CASES.items():
                if args.skip_string_paths and name.startswith("String path "):
                    continue
                oracle = run(expr, demand, flags=CASE_FLAGS.get(name, ()))
                native = run(expr, demand, jit=True, flags=CASE_FLAGS.get(name, ()))
                expected_rc = 1 if name in ERRORS else 0
                assert oracle.returncode == expected_rc, f"interpreter {name}: expected rc={expected_rc}, got {oracle}"
                if name in BOOLEAN_ORACLES:
                    expected_out, fragment, traces = BOOLEAN_ORACLES[name]
                    assert oracle.stdout == expected_out, (name, expected_out, oracle)
                    if fragment:
                        assert fragment.encode() in oracle.stderr, (name, fragment, oracle)
                    actual_traces = [line[7:] for line in oracle.stderr.decode().splitlines() if line.startswith("trace: ")]
                    assert actual_traces == traces, (name, traces, actual_traces)
                assert (native.returncode, native.stdout, native.stderr) == (oracle.returncode, oracle.stdout, oracle.stderr), \
                    f"{'demand' if demand else 'eager'} {name}:\ninterpreter={oracle}\nJIT={native}"
                checked += 1
            dump = Path(tmp) / ("demand-ir" if demand else "eager-ir")
            dump.mkdir()
            counts = counters(CASES["integer arithmetic"], demand, dump)
            assert counts["compiled"] == 1 and counts["grace"] == 3 and counts["executions"] > 3, counts
            assert list(dump.glob("*.typed.mlir")) and list(dump.glob("*.llvm.mlir")) and list(dump.glob("*.ll")), list(dump.iterdir())
            for name in ("add overflow", "sub overflow", "mul overflow", "intermediate overflow cannot cancel", "mul overflow cannot cancel"):
                counts = counters(CASES[name], demand, expected_rc=1)
                assert counts["compiled"] == 1 and counts["overflows"] >= 1, (name, counts)
            counts = counters(CASES["float guard"], demand)
            assert counts["compiled"] == 1 and counts["type_misses"] >= 1, counts
            for name, field in (("generic identity all value kinds", "identity_executions"),
                                ("captured identity changes closures", "capture_executions"),
                                ("selector changes captures after grace", "selector_executions"),
                                ("list selector empty branch and lazy elements", "selector_executions"),
                                ("string selector changes captures", "selector_executions"),
                                ("selector empty then branch", "selector_executions")):
                # Generic saturated value returns can bypass the inner pointer
                # lambda. Keep this legacy tier's independent coverage explicit.
                counts = counters(CASES[name], demand, extra={"MLNIX_JIT_VALUES": "0"})
                assert counts["pointer_compiled"] == 1 and counts[field] > 3, (name, counts)
                assert counts["pointer_grace"] >= 3 and counts["pointer_mismatches"] == 0, (name, counts)
            for name in ["Boolean " + predicate for predicate in
                         ("isNull", "isBool", "isInt", "isFloat", "isString", "isPath", "isAttrs", "isList", "isFunction")] + [
                    "Boolean false AND skips effect", "Boolean true OR skips effect",
                    "Boolean false implication skips effect", "Boolean nested conditional",
                    "Boolean changing captures", "Boolean unused capture remains lazy",
                    "Boolean hasAttr does not force final field"]:
                counts = counters(CASES[name], demand)
                assert counts["boolean_compiled"] >= 1 and counts["boolean_completions"] > 3, (name, counts)
                assert counts["boolean_grace"] >= 3 and counts["boolean_mismatches"] == 0, (name, counts)
            counts = counters(CASES["Boolean needed argument trace once"], demand)
            assert counts["boolean_completions"] > 3 and counts["boolean_demands"] >= 1, counts
            for name in ("Boolean functor branch deopts after memoization", "Boolean layered hasAttr deopt"):
                counts = counters(CASES[name], demand)
                assert counts["boolean_compiled"] >= 1 and counts["boolean_deopts"] >= 1, (name, counts)
            counts = counters(CASES["Boolean IF tail remains a value"], demand)
            assert counts["lazy_value_compiled"] == 1 and counts["lazy_value_completions"] == 5, counts
            assert counts["lazy_value_grace"] == 3 and counts["boolean_deopts"] == 0, counts
            counts = counters(CASES["Boolean leaf budget"], demand)
            assert counts["boolean_compiled"] == 0 and counts["rejected"] >= 1, counts
            counts = counters(CASES["Boolean unsupported path retires"], demand)
            assert counts["boolean_retired"] == 1 and counts["boolean_deopts"] == 64, counts
            assert counts["boolean_completions"] == 4 and counts["boolean_grace"] == 3, counts
            for name, rc, completions in (("Boolean nested retirement pins active continuation", 0, 5),
                                          ("Boolean nested retirement unwinds active demand", 1, 4)):
                counts = counters(CASES[name], demand, expected_rc=rc)
                assert counts["boolean_retired"] == 1 and counts["boolean_deopts"] == 64, (name, counts)
                assert counts["boolean_completions"] == completions, (name, counts)
            for name in ("Boolean preflight unsupported never compiles", "Boolean preflight recursive oracle refuses"):
                counts = counters(CASES[name], demand)
                assert counts["boolean_compiled"] == counts["boolean_executions"] == 0, (name, counts)
                assert counts["boolean_preflight_attempts"] == counts["boolean_preflight_deopts"] == 64, (name, counts)
                assert counts["boolean_preflight_rejections"] == 1, (name, counts)
                assert counts["boolean_deopts"] == counts["boolean_retired"] == 0, (name, counts)
            counts = counters(CASES["Boolean preflight delayed admission"], demand)
            assert counts["boolean_compiled"] == 1 and counts["boolean_grace"] == 3, counts
            assert counts["boolean_preflight_attempts"] == 4 and counts["boolean_preflight_deopts"] == 3, counts
            assert counts["boolean_preflight_rejections"] == 0 and counts["boolean_completions"] == 5, counts
            counts = counters(CASES["Boolean preflight recursive oracle compiles"], demand)
            assert counts["boolean_compiled"] == counts["boolean_preflight_attempts"] == 1, counts
            assert counts["boolean_grace"] == 3 and counts["boolean_completions"] == 4, counts
            counts = counters(CASES["Boolean preflight recursive oracle retires"], demand)
            assert counts["boolean_preflight_attempts"] == counts["boolean_compiled"] == counts["boolean_retired"] == 1, counts
            assert counts["boolean_deopts"] == 64 and counts["boolean_grace"] == 3, counts
            counts = counters(CASES["Boolean preflight oracle error"], demand, expected_rc=1)
            assert counts["boolean_compiled"] == counts["boolean_preflight_attempts"] == 0, counts
            for name in ("Inline call predicate", "Inline call current closure captures",
                         "Inline call current capture demand once", "Inline call predicate demand once",
                         "Inline call exception cleanup", "Inline call fallback depth cleanup",
                         "Inline call leave restores caller demand depth"):
                counts = counters(CASES[name], demand, flags=CASE_FLAGS.get(name, ()))
                assert counts["boolean_inline_compiled"] >= 1 and counts["boolean_inline_calls"] > 3, (name, counts)
                assert counts["boolean_depth_entries"] >= 1 and counts["boolean_grace"] >= 3, (name, counts)
                assert counts["boolean_specializations"] >= 1, (name, counts)
            for name in ("Inline call changed target before argument", "Inline call unready target memoizes once",
                         "Inline call non-lambda guards"):
                counts = counters(CASES[name], demand)
                assert counts["boolean_inline_compiled"] >= 1 and counts["boolean_guard_misses"] >= 1, (name, counts)
            counts = counters(CASES["Inline call predicate demand once"], demand)
            assert counts["boolean_demands"] >= 1, counts
            name = "Inline call leave restores caller demand depth"
            counts = counters(CASES[name], demand, flags=CASE_FLAGS[name])
            assert counts["boolean_demands"] >= 1 and counts["boolean_inline_calls"] >= 5, counts
            name = "Inline call host demand preserves logical depth"
            counts = counters(CASES[name], demand, flags=CASE_FLAGS[name], expected_rc=1)
            assert counts["boolean_inline_compiled"] >= 1 and counts["boolean_inline_calls"] >= 4, counts
            counts = counters(CASES["Inline call fallback after persistent demand"], demand)
            assert counts["boolean_inline_compiled"] >= 1 and counts["boolean_deopts"] >= 1, counts
            for name in ("Inline call nested retirement pins expanded continuation",
                         "Inline call nested retirement unwinds expanded demand"):
                counts = counters(CASES[name], demand, flags=CASE_FLAGS[name])
                assert counts["boolean_inline_compiled"] >= 1 and counts["boolean_inline_calls"] > 64, (name, counts)
                assert counts["boolean_retired"] == 2 and counts["boolean_deopts"] == 128, (name, counts)
            # Disable only inlining: the standalone callee's Boolean tier stays
            # active, and the result/effects must still match the interpreter.
            expr = CASES["Inline call predicate"]
            oracle = run(expr, demand)
            ablated = run(expr, demand, jit=True, extra={"MLNIX_JIT_INLINE": "0"})
            assert (ablated.returncode, ablated.stdout, ablated.stderr) == \
                (oracle.returncode, oracle.stdout, oracle.stderr), (oracle, ablated)
            checked += 1
            counts = counters(expr, demand, extra={"MLNIX_JIT_INLINE": "0"})
            assert counts["boolean_inline_compiled"] == counts["boolean_inline_calls"] == 0, counts
            assert counts["boolean_compiled"] >= 1 and counts["boolean_completions"] > 3, counts
            for arity in (2, 3, 4):
                name = f"Curried sequential depth arity{arity}"
                counts = counters(CASES[name], demand, flags=CASE_FLAGS[name])
                assert counts["curried_compiled"] == 1 and counts["curried_grace"] == 3, (name, counts)
                assert counts["curried_completions"] > 3 and counts["curried_frames_saved"] > 0, (name, counts)
                assert counts["curried_values_saved"] > 0, (name, counts)
                assert counts["curried_frames_saved"] * (arity - 1) == counts["curried_values_saved"] * arity, (name, counts)
            for name in ("Curried current ancestor captures", "Curried formal demand order and sharing",
                         "Curried wrong arity does not poison saturation", "Curried inline callee nested depth",
                         "Curried inline capture shares SSA but not environment"):
                counts = counters(CASES[name], demand, flags=CASE_FLAGS.get(name, ()))
                assert counts["curried_compiled"] >= 1 and counts["curried_completions"] > 3, (name, counts)
                assert counts["curried_grace"] >= 3 and counts["curried_frames_saved"] > 0, (name, counts)
            for name in ("Curried outer local computation stays fallback", "Curried fallback preserves earlier demand",
                         "Curried escaped deferred descendant retains captures", "Curried changed captured callee"):
                counts = counters(CASES[name], demand)
                assert counts["curried_compiled"] >= 1 and counts["curried_deopts"] >= 1, (name, counts)
            counts = counters(CASES["Curried inline capture shares SSA but not environment"], demand)
            assert counts["boolean_inline_calls"] > 3, counts
            counts = counters(CASES["Curried defaults stay interpreted"], demand)
            assert counts["curried_compiled"] == counts["curried_executions"] == 0, counts
            # A five-stage application can interpret its first stage and then
            # enter the supported four-stage suffix, retaining that first frame.
            counts = counters(CASES["Curried arity budget"], demand)
            assert counts["curried_arity4"] > 0 and counts["curried_frames_saved"] > 0, counts
            assert counts["curried_frames_saved"] * 3 == counts["curried_values_saved"] * 4, counts
            counts = counters(CASES["Curried recursive oracle admission"], demand)
            assert counts["curried_compiled"] == 1 and counts["curried_grace"] == 3, counts
            for name in ("Curried nested retirement pins active arguments", "Curried nested retirement unwinds argument demand"):
                counts = counters(CASES[name], demand)
                assert counts["curried_compiled"] == 1 and counts["curried_grace"] == 3, (name, counts)
                assert counts["curried_deopts"] == 64 and counts["curried_frames_saved"] > 0, (name, counts)
            expr = CASES["Curried two formal logic"]
            oracle = run(expr, demand)
            ablated = run(expr, demand, jit=True, extra={"MLNIX_JIT_CURRIED": "0"})
            assert (ablated.returncode, ablated.stdout, ablated.stderr) == \
                (oracle.returncode, oracle.stdout, oracle.stderr), (oracle, ablated)
            checked += 1
            counts = counters(expr, demand, extra={"MLNIX_JIT_CURRIED": "0"})
            assert counts["curried_compiled"] == counts["curried_executions"] == 0, counts
            assert counts["boolean_compiled"] >= 1 and counts["boolean_completions"] > 3, counts
            for arity in (2, 3, 4):
                name = f"Saturated inline persistent arity{arity}"
                counts = counters(CASES[name], demand, flags=CASE_FLAGS[name])
                assert counts["boolean_saturated_inline_compiled"] >= 1, (name, counts)
                assert counts["boolean_saturated_inline_calls"] > 3, (name, counts)
                assert counts["boolean_projection_compiled"] == 0, (name, counts)
            for name in ("Projection current sets and keys", "Projection dynamic demand order and sharing",
                         "Projection static demand order", "Projection same SSA uses captured context"):
                counts = counters(CASES[name], demand)
                assert counts["boolean_projection_compiled"] >= 1 and counts["boolean_projection_requests"] > 3, (name, counts)
                assert counts["boolean_saturated_inline_calls"] > 3, (name, counts)
            counts = counters(CASES["Projection dynamic demand order and sharing"], demand)
            assert counts["boolean_projection_forces"] >= 3 and counts["boolean_projection_flat"] >= 1, counts
            for name in ("Projection tail remains an arbitrary value", "Projection hasAttr leaves final field lazy"):
                counts = counters(CASES[name], demand)
                assert counts["boolean_projection_compiled"] >= 1 and counts["boolean_projection_requests"] > 3, (name, counts)
            for name in ("Projection ignored argument stays lazy", "Projection name-only predicate skips base and field"):
                counts = counters(CASES[name], demand)
                assert counts["boolean_saturated_inline_calls"] > 3 and counts["boolean_projection_requests"] == 0, (name, counts)
            counts = counters(CASES["Projection layered shadowing"], demand)
            assert counts["boolean_projection_layered"] >= 1, counts
            counts = counters(CASES["Projection cached flat layer"], demand)
            assert counts["boolean_projection_cached_flat"] >= 1, counts
            counts = counters(CASES["Projection changed callee precedes selection"], demand)
            assert counts["boolean_projection_compiled"] >= 1 and counts["boolean_guard_misses"] >= 1, counts
            counts = counters(CASES["Projection fallback preserves demands"], demand)
            assert counts["boolean_projection_requests"] > 3 and counts["boolean_deopts"] >= 1, counts
            for name in ("Projection default stays fallback", "Projection nested base stays fallback",
                         "Projection nested key stays fallback", "Projection selected callee stays fallback"):
                counts = counters(CASES[name], demand)
                assert counts["boolean_projection_compiled"] == 0, (name, counts)
            for name in ("Projection nested retirement pins field", "Projection nested retirement unwinds field"):
                counts = counters(CASES[name], demand)
                assert counts["boolean_projection_requests"] > 64 and counts["boolean_retired"] >= 1, (name, counts)
            for name in ("Projection dynamic demand order and sharing", "Saturated inline persistent arity3"):
                expr = CASES[name]
                flags = CASE_FLAGS.get(name, ())
                oracle = run(expr, demand, flags=flags)
                ablated = run(expr, demand, jit=True, flags=flags, extra={"MLNIX_JIT_PROJECTION": "0"})
                assert (ablated.returncode, ablated.stdout, ablated.stderr) == \
                    (oracle.returncode, oracle.stdout, oracle.stderr), (name, oracle, ablated)
                checked += 1
                counts = counters(expr, demand, flags=flags, extra={"MLNIX_JIT_PROJECTION": "0"})
                assert counts["boolean_projection_compiled"] == counts["boolean_projection_requests"] == 0, (name, counts)
                if name.startswith("Saturated"):
                    assert counts["boolean_saturated_inline_calls"] > 3, counts
            for name in ("Values static selected kinds", "Values dynamic current sets and keys",
                         "Values selected context survives", "Values selected containers retain identity",
                         "Values selected closure escapes with capture", "Values dynamic demand order and sharing",
                         "Values captured conditional changes environments", "Values conditional mixed Boolean and value paths",
                         "Values conditional unselected tails stay lazy", "Values shared formals preserve original cell",
                         "Values inline tail leaves nested contexts", "Values inline tail obeys exact nested depth",
                         "Values inline Boolean condition keeps value branches", "Values inline same SSA uses old closure environment"):
                counts = counters(CASES[name], demand, flags=CASE_FLAGS.get(name, ()))
                assert counts["lazy_value_compiled"] >= 1 and counts["lazy_value_completions"] > 3, (name, counts)
                assert counts["lazy_value_grace"] >= 3, (name, counts)
            counts = counters(CASES["Values static selected kinds"], demand)
            assert counts["lazy_value_compiled"] == 1 and counts["lazy_value_grace"] == 3, counts
            assert counts["boolean_deopts"] == 0, counts
            counts = counters(CASES["Values dynamic demand order and sharing"], demand)
            assert counts["boolean_projection_forces"] >= 3, counts
            for arity in (2, 3, 4):
                name = f"Values curried identity arity{arity}"
                counts = counters(CASES[name], demand, flags=CASE_FLAGS[name])
                assert counts["curried_compiled"] == counts["lazy_value_compiled"] == 1, (name, counts)
                assert counts["curried_grace"] == counts["lazy_value_grace"] == 3, (name, counts)
                assert counts["lazy_value_completions"] > 3 and counts["curried_deopts"] == 0, (name, counts)
                assert counts["curried_frames_saved"] * (arity - 1) == counts["curried_values_saved"] * arity, (name, counts)
            for name in ("Values inline tail leaves nested contexts", "Values inline same SSA uses old closure environment"):
                counts = counters(CASES[name], demand)
                assert counts["boolean_inline_compiled"] >= 1 and counts["boolean_inline_calls"] > 3, (name, counts)
            counts = counters(CASES["Values inline changed callee skips argument"], demand)
            assert counts["lazy_value_compiled"] >= 1 and counts["boolean_guard_misses"] >= 1, counts
            counts = counters(CASES["Values recursive oracle keeps result"], demand)
            assert counts["lazy_value_compiled"] == 1 and counts["lazy_value_grace"] == 3, counts
            for name in ("Values retired plan releases escaped closure safely", "Values retired plan unwinds failed value demand"):
                counts = counters(CASES[name], demand)
                assert counts["lazy_value_compiled"] == 1 and counts["lazy_value_grace"] == 3, (name, counts)
                assert counts["boolean_retired"] == 1 and counts["boolean_deopts"] == 64, (name, counts)
            counts = counters(CASES["Values leaf budget keeps untouched alternatives lazy"], demand)
            assert counts["compiled"] == 0 and counts["rejected"] >= 1, counts
            for kind in ("attrs", "list", "string"):
                for side in ("then", "else"):
                    name = f"Empty curried {kind} {side}"
                    counts = counters(CASES[name], demand)
                    assert counts["curried_compiled"] == counts["lazy_value_compiled"] == 1, (name, counts)
                    assert counts["lazy_value_grace"] == 3 and counts["lazy_empty_completions"] >= 3, (name, counts)
                    assert counts["curried_completions"] > 3 and counts["boolean_deopts"] == 0, (name, counts)
            counts = counters(CASES["Empty unconditional roots skip arguments"], demand)
            assert counts["lazy_value_compiled"] == 3 and counts["lazy_value_grace"] == 9, counts
            assert counts["lazy_empty_completions"] == 15 and counts["boolean_deopts"] == 0, counts
            for name in ("Empty inline leaves restore nested context", "Empty inline skips projected key base and field"):
                counts = counters(CASES[name], demand, flags=CASE_FLAGS.get(name, ()))
                assert counts["boolean_inline_compiled"] >= 1 and counts["boolean_inline_calls"] > 3, (name, counts)
                assert counts["lazy_empty_completions"] > 3 and counts["boolean_deopts"] == 0, (name, counts)
                if "projected" in name:
                    assert counts["boolean_projection_requests"] == 0, counts
            counts = counters(CASES["Empty captured value remains shallow and current"], demand)
            assert counts["lazy_value_grace"] >= 3 and counts["lazy_empty_completions"] >= 3, counts
            # The ablation retains the old Boolean-only projection plan and its
            # non-Bool fallback, while arbitrary-value-only admission stays off.
            for name in ("Projection tail remains an arbitrary value", "Boolean IF tail remains a value",
                         "Values curried identity arity3", "Empty curried attrs else",
                         "Empty unconditional roots skip arguments"):
                expr = CASES[name]
                flags = CASE_FLAGS.get(name, ())
                oracle = run(expr, demand, flags=flags)
                ablated = run(expr, demand, jit=True, flags=flags, extra={"MLNIX_JIT_VALUES": "0"})
                assert (ablated.returncode, ablated.stdout, ablated.stderr) == \
                    (oracle.returncode, oracle.stdout, oracle.stderr), (name, oracle, ablated)
                checked += 1
                counts = counters(expr, demand, flags=flags, extra={"MLNIX_JIT_VALUES": "0"})
                assert counts["lazy_value_compiled"] == counts["lazy_value_completions"] == counts["lazy_value_grace"] == 0, (name, counts)
                assert counts["lazy_empty_completions"] == 0, (name, counts)
                if name.startswith(("Projection", "Boolean")):
                    assert counts["boolean_compiled"] == 1 and counts["boolean_deopts"] == 1, counts
                else:
                    assert counts["curried_compiled"] == 0, counts
            for name in ("List return singleton stays non-strict", "List return duplicate handles force once",
                         "List return cyclic element stays lazy", "List return productive blackhole survives",
                         "List return deferred closure keeps capture", "List return fresh capture resolves without forcing",
                         "List return captured handles preserve later force order", "List return current captured environments",
                         "List return inline element forces after Leave", "List return saturated inline preserves order",
                         "List return inline capture uses original environment"):
                counts = counters(CASES[name], demand, flags=CASE_FLAGS.get(name, ()))
                assert counts["lazy_list_compiled"] >= 1 and counts["lazy_list_completions"] > 3, (name, counts)
                assert counts["lazy_value_grace"] >= 3, (name, counts)
            counts = counters(CASES["List return singleton stays non-strict"], demand)
            assert counts["lazy_list_compiled"] == 1 and counts["lazy_list_completions"] == 5, counts
            assert counts["lazy_value_grace"] == 3 and counts["boolean_deopts"] == 0, counts
            assert counts["boolean_demands"] == counts["lazy_list_handle_lookups"] == 0, counts
            counts = counters(CASES["List return fresh capture resolves without forcing"], demand)
            assert counts["lazy_list_handle_lookups"] >= 1 and counts["boolean_demands"] == 0, counts
            for name in [f"List return curried order arity{arity}" for arity in (2, 3, 4)] + [
                    "List return curry stages stay sequential", "List return recursive oracle does not force element"]:
                counts = counters(CASES[name], demand, flags=CASE_FLAGS.get(name, ()))
                assert counts["curried_compiled"] == 1 and counts["curried_completions"] > 3, (name, counts)
                assert counts["curried_grace"] == 3 and counts["lazy_list_completions"] > 3, (name, counts)
                assert counts["curried_deopts"] == 0, (name, counts)
            counts = counters(CASES["List return optional both branches"], demand)
            assert counts["curried_completions"] > 3 and counts["lazy_list_completions"] >= 3, counts
            assert counts["lazy_empty_completions"] >= 3 and counts["boolean_deopts"] == 0, counts
            for name in ("List return inline element forces after Leave", "List return saturated inline preserves order",
                         "List return inline capture uses original environment"):
                counts = counters(CASES[name], demand, flags=CASE_FLAGS.get(name, ()))
                assert counts["boolean_inline_compiled"] >= 1 and counts["boolean_inline_calls"] > 3, (name, counts)
            counts = counters(CASES["List return changed callee skips argument"], demand)
            assert counts["lazy_list_completions"] > 3 and counts["boolean_guard_misses"] >= 1, counts
            counts = counters(CASES["List return virtual inline formal stays deferred"], demand)
            assert counts["lazy_list_compiled"] >= 1 and counts["lazy_list_completions"] > 3, counts
            assert counts["boolean_inline_compiled"] == counts["boolean_projection_requests"] == 0, counts
            for name in ("List return local computation remains deferred fallback", "List return local projection remains deferred fallback",
                         "List return element count cap stays lazy", "List return leaf budget preserves lazy alternatives"):
                counts = counters(CASES[name], demand)
                assert counts["lazy_list_compiled"] == counts["lazy_list_completions"] == 0, (name, counts)
            for name, completions in (("List return survives active retirement and escapes", 5),
                                      ("List return active retirement unwinds failed condition", 4)):
                counts = counters(CASES[name], demand)
                assert counts["lazy_list_compiled"] == 1 and counts["lazy_list_completions"] == completions, (name, counts)
                assert counts["boolean_retired"] == 1 and counts["boolean_deopts"] == 64, (name, counts)
            for name, flag in (("List return singleton stays non-strict", "MLNIX_JIT_LISTS"),
                               ("List return optional both branches", "MLNIX_JIT_LISTS"),
                               ("List return singleton stays non-strict", "MLNIX_JIT_VALUES")):
                expr = CASES[name]
                oracle = run(expr, demand)
                ablated = run(expr, demand, jit=True, extra={flag: "0"})
                assert (ablated.returncode, ablated.stdout, ablated.stderr) == \
                    (oracle.returncode, oracle.stdout, oracle.stderr), (name, flag, oracle, ablated)
                checked += 1
                counts = counters(expr, demand, extra={flag: "0"})
                assert counts["lazy_list_compiled"] == counts["lazy_list_completions"] == counts["lazy_list_handle_lookups"] == 0, (name, counts)
                if "optional" in name:
                    assert counts["lazy_empty_completions"] >= 3 and counts["boolean_deopts"] >= 1, counts
            for name in [f"String {operator} literal {side}" for operator in ("==", "!=") for side in ("left", "right")] + [
                    "String empty literal comparison", "String pair demand order and sharing", "String same cell forces once",
                    "String literal byte lengths", "String UTF8 literal bytes", "String context ignored without mutation",
                    "String fresh captured environment", "String static projection order", "String dynamic projection order",
                    "String inline nested Leave", "String inline same SSA different capture", "String recursive oracle shared entry"]:
                counts = counters(CASES[name], demand, flags=CASE_FLAGS.get(name, ()))
                assert counts["string_compiled"] >= 1 and counts["string_comparisons"] > 3, (name, counts)
                assert counts["boolean_grace"] >= 3 and counts["string_guard_deopts"] == 0, (name, counts)
            counts = counters(CASES["String pair demand order and sharing"], demand)
            # Curried interpreter-first grace admits the inner unary kernel too:
            # six saturated executions plus its three unary oracle comparisons.
            assert counts["string_compiled"] == 2 and counts["string_comparisons"] == 9, counts
            assert counts["curried_compiled"] == 1 and counts["curried_completions"] == 6, counts
            assert counts["curried_grace"] == 3 and counts["boolean_demands"] == 2, counts
            assert counts["boolean_deopts"] == 0, counts
            counts = counters(CASES["String same cell forces once"], demand)
            assert counts["boolean_demands"] == 1, counts
            counts = counters(CASES["String generic equality fallback remains deep"], demand)
            # Each saturated guard fallback reaches the previously warmed unary
            # guard before ordinary deep equality; neither repeats a force.
            assert counts["curried_deopts"] == 7, counts
            assert counts["string_guard_deopts"] == counts["boolean_deopts"] == 14, counts
            counts = counters(CASES["String static projection order"], demand)
            # The fourth warm invocation forces its two fresh base thunks; the
            # final call forces two bases and two traced fields exactly once.
            assert counts["boolean_projection_forces"] == 6, counts
            counts = counters(CASES["String dynamic projection order"], demand)
            assert counts["boolean_projection_forces"] == 3, counts
            for arity in (3, 4):
                name = f"String curried sequential depth arity{arity}"
                counts = counters(CASES[name], demand, flags=CASE_FLAGS[name])
                assert counts["curried_compiled"] == 1 and counts["curried_grace"] == 3, (name, counts)
                assert counts["curried_completions"] == 5 and counts["string_comparisons"] == 8, (name, counts)
            for name in ("String inline nested Leave", "String inline same SSA different capture"):
                counts = counters(CASES[name], demand, flags=CASE_FLAGS.get(name, ()))
                assert counts["boolean_inline_compiled"] >= 1 and counts["boolean_inline_calls"] > 3, (name, counts)
            counts = counters(CASES["String fallback keeps completed demands"], demand)
            assert counts["curried_deopts"] == 1 and counts["boolean_deopts"] == 2, counts
            assert counts["string_comparisons"] == 9 and counts["boolean_demands"] == 2, counts
            for name, comparisons in (("String reentrant retirement preserves comparison", 136),
                                      ("String reentrant retirement restores throw", 135)):
                counts = counters(CASES[name], demand)
                # Both admitted tiers retire after 64 misses. The successful
                # suspended outer comparison adds one; a throwing run does not.
                assert counts["boolean_retired"] == 2 and counts["curried_deopts"] == 64, (name, counts)
                assert counts["boolean_deopts"] == 128, (name, counts)
                assert counts["string_compiled"] == 2 and counts["string_comparisons"] == comparisons, (name, counts)
            for name in ("String local computation remains fallback", "String literal byte budget", "String literal operand budget"):
                counts = counters(CASES[name], demand)
                assert counts["string_compiled"] == counts["string_comparisons"] == 0, (name, counts)
            for name in ("String pair demand order and sharing", "String static projection order"):
                expr = CASES[name]
                oracle = run(expr, demand)
                ablated = run(expr, demand, jit=True, extra={"MLNIX_JIT_STRINGS": "0"})
                assert (ablated.returncode, ablated.stdout, ablated.stderr) == \
                    (oracle.returncode, oracle.stdout, oracle.stderr), (name, oracle, ablated)
                checked += 1
                counts = counters(expr, demand, extra={"MLNIX_JIT_STRINGS": "0"})
                assert counts["string_compiled"] == counts["string_comparisons"] == counts["string_guard_deopts"] == 0, (name, counts)
            if not args.skip_string_paths:
                for name in [f"String path length{length}" for length in (2, 3, 4)] + [
                        "String path force order and sharing", "String path current captures",
                        "String path layered intermediate", "String path nested callee restores Leave",
                        "String path final field remains lazy for hasAttr", "String path inline same SSA different environment"]:
                    counts = counters(CASES[name], demand, flags=CASE_FLAGS.get(name, ()))
                    assert counts["path_projection_compiled"] >= 1 and counts["path_projection_requests"] > 3, (name, counts)
                counts = counters(CASES["String path force order and sharing"], demand)
                # The first native warm call forces its three fresh path thunks; the
                # shared final set then forces base, a, b and c exactly once.
                assert counts["boolean_projection_forces"] == 7 and counts["string_comparisons"] == 6, counts
                counts = counters(CASES["String path layered intermediate"], demand)
                assert counts["boolean_projection_layered"] >= 1, counts
                counts = counters(CASES["String path changed callee skips projection"], demand)
                assert counts["path_projection_compiled"] >= 1 and counts["boolean_guard_misses"] >= 1, counts
                counts = counters(CASES["String path survives active retirement"], demand)
                assert counts["path_projection_requests"] > 64 and counts["boolean_retired"] == 1, counts
                assert counts["boolean_deopts"] == 64, counts
                for name in [n for n in CASES if n.startswith("String path excluded ")]:
                    counts = counters(CASES[name], demand)
                    assert counts["path_projection_compiled"] == counts["path_projection_requests"] == 0, (name, counts)
                for flag in ("MLNIX_JIT_PATHS", "MLNIX_JIT_PROJECTION"):
                    expr = CASES["String path force order and sharing"]
                    oracle = run(expr, demand)
                    ablated = run(expr, demand, jit=True, extra={flag: "0"})
                    assert (ablated.returncode, ablated.stdout, ablated.stderr) == \
                        (oracle.returncode, oracle.stdout, oracle.stderr), (flag, oracle, ablated)
                    checked += 1
                    counts = counters(expr, demand, extra={flag: "0"})
                    assert counts["path_projection_compiled"] == counts["path_projection_requests"] == 0, (flag, counts)
            counts = counters(CASES["node budget"], demand)
            assert counts["compiled"] == 0 and counts["rejected"] >= 1, counts
            counts = counters(CASES["pointer candidate budget"], demand)
            assert counts["pointer_compiled"] == 1 and counts["candidates"] == 256, counts
            assert counts["identity_executions"] == 256, counts
            counts = counters(CASES["integer arithmetic"], demand, extra={"MLNIX_JIT_THRESHOLD": "1024"})
            assert counts["compiled"] == counts["executions"] == 0, counts
            override = run(CASES["integer arithmetic"], demand, jit=True, stats=True,
                           extra={"MLNIX_PRIMS_IRDL": str(ROOT / "include/NixDialect/NixPrims.irdl.mlir")})
            oracle = run(CASES["integer arithmetic"], demand)
            assert override.returncode == oracle.returncode and override.stdout == oracle.stdout, override
            assert b"jit:" not in override.stderr, override.stderr
            bodies = " ".join(f"(builtins.foldl' builtins.add 0 (builtins.genList (x: x * {i + 1}) 5))" for i in range(18))
            counts = counters(f"builtins.foldl' builtins.add 0 [ {bodies} ]", demand)
            assert counts["compiled"] == 16 and counts["candidates"] <= 256, counts
            staged_cases = sum(not (args.skip_string_paths and n.startswith("String path ")) for n in CASES)
            path_label = "" if args.skip_string_paths else "/path"
            print(f"{'demand' if demand else 'eager'}: {staged_cases + (14 if args.skip_string_paths else 16)} exact comparisons; scalar/pointer/Boolean/inline-call/curried/projection/values/empty/list/string{path_label}/ablation/demand/deopt/grace/budget guards verified")
    print(f"JIT: {checked} exact comparisons passed")


if __name__ == "__main__":
    main()
