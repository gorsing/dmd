/*
TEST_OUTPUT:
---
fail_compilation/diag10319.d(30): Error: `pure` function `D main` cannot call impure function `diag10319.foo`
fail_compilation/diag10319.d(30): Error: `@safe` function `D main` cannot call `@system` function `diag10319.foo`
fail_compilation/diag10319.d(19):        `diag10319.foo` is declared here
fail_compilation/diag10319.d(31): Error: `pure` function `D main` cannot call impure function `diag10319.bar!int.bar`
fail_compilation/diag10319.d(23):        contaminated by `accessing mutable static data `g`, so `bar` cannot infer `pure`
fail_compilation/diag10319.d(31): Error: `@safe` function `D main` cannot call `@system` function `diag10319.bar!int.bar`
fail_compilation/diag10319.d(24):        contaminated by `taking the address of stack-allocated local variable `x`, so `bar` cannot infer `@safe`
fail_compilation/diag10319.d(21):        `diag10319.bar!int.bar` is declared here
fail_compilation/diag10319.d(30): Error: function `diag10319.foo` is not `nothrow`
fail_compilation/diag10319.d(31): Error: function `diag10319.bar!int.bar` is not `nothrow`
fail_compilation/diag10319.d(25):        contaminated by `object.Exception` being thrown but not caught`, so `bar` cannot infer `nothrow`
fail_compilation/diag10319.d(28): Error: function `D main` may throw but is marked as `nothrow`
---
*/

void foo() {}

void bar(T)()
{
    static int g; g = 10;       // impure
    int x; auto p = &x;         // system
    throw new Exception("");    // may throw
}

@safe pure nothrow void main()  // L23
{
    foo();      // L25
    bar!int();  // L26
}
