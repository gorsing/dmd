/*
REQUIRED_ARGS: -w
TEST_OUTPUT:
---
---
*/

pragma(lint, unusedParams);

void test(int x, int y)
{
    auto z = x + 1;
}

pragma(lint, none);
void ignored(int a) {}
