/*
REQUIRED_ARGS: -w
TEST_OUTPUT:
---
fail_compilation/lint_unused_params.d(12): Lint: [unusedParams] function parameter `y` is never used
---
*/

pragma(lint, unusedParams);

void test(int x, int y)
{
    auto z = x + 1;
}

pragma(lint, none);
void ignored(int a) {}
