/*
REQUIRED_ARGS: -verrors=spec
TEST_OUTPUT:
---
(spec:1) fail_compilation/diag_nogc_traits.d(13): Error: allocating with `new` is not allowed in `@nogc` function `test_nogc_traits`
(spec:1) fail_compilation/diag_nogc_traits.d(13): Error: allocating with `new` causes a GC allocation in `@nogc` function `test_nogc_traits`
fail_compilation/diag_nogc_traits.d(14): Error: static assert:  `0` is false
---
*/

void test_nogc_traits() @nogc
{
    enum b = __traits(compiles, new int);
    static assert(0);
}
