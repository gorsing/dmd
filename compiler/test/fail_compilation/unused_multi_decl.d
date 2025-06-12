/**********************************
 REQUIRED_ARGS: -check=unused=on
TEST_OUTPUT:
---
fail_compilation/unused_multi_decl.d(14): Error: variable `a` declared but never used
fail_compilation/unused_multi_decl.d(14): Error: variable `b` declared but never used
---
**********************************/

module unused_multi_decl;

void bar()
{
    int a, b;     // two values warnings
}
