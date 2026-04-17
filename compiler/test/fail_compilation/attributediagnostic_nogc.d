/*
TEST_OUTPUT:
---
fail_compilation/attributediagnostic_nogc.d(21): Error: `@nogc` function `attributediagnostic_nogc.layer2` cannot call non-@nogc function `attributediagnostic_nogc.layer1`
fail_compilation/attributediagnostic_nogc.d(22):        `layer1` cannot use `@nogc` because it calls `layer0`
fail_compilation/attributediagnostic_nogc.d(23):        `layer0` cannot use `@nogc` because it calls `gc`
fail_compilation/attributediagnostic_nogc.d(27):        contaminated by `executing an `asm` statement without `@nogc` annotation`, so `gc` cannot infer `@nogc`
fail_compilation/attributediagnostic_nogc.d(22):        `attributediagnostic_nogc.layer1` is declared here
fail_compilation/attributediagnostic_nogc.d(43): Error: `@nogc` function `D main` cannot call non-@nogc function `attributediagnostic_nogc.gc1`
fail_compilation/attributediagnostic_nogc.d(32):        contaminated by `allocating with `new`, so `gc1` cannot infer `@nogc`
fail_compilation/attributediagnostic_nogc.d(30):        `attributediagnostic_nogc.gc1` is declared here
fail_compilation/attributediagnostic_nogc.d(44): Error: `@nogc` function `D main` cannot call non-@nogc function `attributediagnostic_nogc.gc2`
fail_compilation/attributediagnostic_nogc.d(38):        contaminated by `calling non-@nogc `fgc`, so `gc2` cannot infer `@nogc`
fail_compilation/attributediagnostic_nogc.d(36):        `attributediagnostic_nogc.gc2` is declared here
fail_compilation/attributediagnostic_nogc.d(45): Error: `@nogc` function `D main` cannot call non-@nogc function `attributediagnostic_nogc.gcClosure`
fail_compilation/attributediagnostic_nogc.d(48):        contaminated by `allocating a closure for `gcClosure()`, so `gcClosure` cannot infer `@nogc`
fail_compilation/attributediagnostic_nogc.d(48):        `attributediagnostic_nogc.gcClosure` is declared here
---
*/
#line 18
// Issue 17374 - Improve inferred attribute error message
// https://issues.dlang.org/show_bug.cgi?id=17374

auto layer2() @nogc { layer1(); }
auto layer1() { layer0(); }
auto layer0() { gc(); }

auto gc()
{
    asm {}
}

auto gc1()
{
    int* x = new int;
}

auto fgc = function void() {new int[10];};
auto gc2()
{
    fgc();
}

void main() @nogc
{
    gc1();
    gc2();
    gcClosure();
}

auto gcClosure()
{
    int x;
    int bar() { return x; }
    return &bar;
}
