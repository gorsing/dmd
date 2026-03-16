/*
REQUIRED_ARGS: -w
TEST_OUTPUT:
---
fail_compilation/lint_unused_params.d(15): Lint: [unusedParams] function parameter `y` is never used
fail_compilation/lint_unused_params.d(28): Lint: [unusedParams] function parameter `b` is never used
---
*/

pragma(lint, unusedParams);

void testBasic(int x, int y)
{
    cast(void)x;
}

class Base { void foo(int a) {} }
class Derived : Base
{
    override void foo(int a) {}
}

class Normal
{
    final void bar(int a, int b)
    {
        cast(void)a;
    }
}

pragma(lint, none);

void ignored(int a) {}
