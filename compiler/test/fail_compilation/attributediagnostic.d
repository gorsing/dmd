/*
TEST_OUTPUT:
---
fail_compilation/attributediagnostic.d(21): Error: `@safe` function `attributediagnostic.layer2` cannot call `@system` function `attributediagnostic.layer1`
fail_compilation/attributediagnostic.d(23):        `layer1` cannot use `@safe` because it calls `layer0`
fail_compilation/attributediagnostic.d(25):        `layer0` cannot use `@safe` because it calls `system`
fail_compilation/attributediagnostic.d(27):        contaminated by `executing an `asm` statement without `@trusted` annotation`, so `system` cannot infer `@safe`
fail_compilation/attributediagnostic.d(22):        `attributediagnostic.layer1` is declared here
fail_compilation/attributediagnostic.d(43): Error: `@safe` function `D main` cannot call `@system` function `attributediagnostic.system1`
fail_compilation/attributediagnostic.d(32):        contaminated by `cast from `uint` to `int*`, so `system1` cannot infer `@safe`
fail_compilation/attributediagnostic.d(30):        `attributediagnostic.system1` is declared here
fail_compilation/attributediagnostic.d(44): Error: `@safe` function `D main` cannot call `@system` function `attributediagnostic.system2`
fail_compilation/attributediagnostic.d(38):        contaminated by `calling `@system` `fsys`, so `system2` cannot infer `@safe`
fail_compilation/attributediagnostic.d(36):        `attributediagnostic.system2` is declared here
---
*/

// Issue 17374 - Improve inferred attribute error message
// https://issues.dlang.org/show_bug.cgi?id=17374

auto layer2() @safe { layer1(); }
auto layer1() { layer0(); }
auto layer0() { system(); }

auto system()
{
    asm {}
}

auto system1()
{
    int* x = cast(int*) 0xDEADBEEF;
}

auto fsys = function void() @system {};
auto system2()
{
    fsys();
}

void main() @safe
{
    system1();
    system2();
}
