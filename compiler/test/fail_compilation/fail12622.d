/*
TEST_OUTPUT:
---
fail_compilation/fail12622.d(27): Error: `pure` function `fail12622.foo` cannot call impure function pointer `fp`
fail_compilation/fail12622.d(27): Error: `@nogc` function `fail12622.foo` cannot call non-@nogc function pointer `fp`
fail_compilation/fail12622.d(27): Error: `@safe` function `fail12622.foo` cannot call `@system` function pointer `fp`
fail_compilation/fail12622.d(29): Error: `pure` function `fail12622.foo` cannot call impure function pointer `fp`
fail_compilation/fail12622.d(29): Error: `@nogc` function `fail12622.foo` cannot call non-@nogc function pointer `fp`
fail_compilation/fail12622.d(29): Error: `@safe` function `fail12622.foo` cannot call `@system` function pointer `fp`
fail_compilation/fail12622.d(31): Error: `pure` function `fail12622.foo` cannot call impure function `fail12622.bar`
fail_compilation/fail12622.d(31): Error: `@safe` function `fail12622.foo` cannot call `@system` function `fail12622.bar`
fail_compilation/fail12622.d(21):        `fail12622.bar` is declared here
fail_compilation/fail12622.d(31): Error: `@nogc` function `fail12622.foo` cannot call non-@nogc function `fail12622.bar`
fail_compilation/fail12622.d(21):        `fail12622.bar` is declared here
---
*/
// Note that, today nothrow violation errors are accidentally hidden.



void bar();

pure nothrow @nogc @safe void foo()
{
    auto fp = &bar;

    (*fp)();

    fp();

    bar();
}
