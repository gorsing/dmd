/**********************************
 REQUIRED_ARGS: -check=unused=on
TEST_OUTPUT:
---
fail_compilation/unused_simple.d(13): Error: variable `x` declared but never used
---
**********************************/

module unused_simple;

void foo()
{
    int x;        // var-unused
}
