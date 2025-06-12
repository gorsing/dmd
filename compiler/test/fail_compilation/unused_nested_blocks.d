/**********************************
 REQUIRED_ARGS: -check=unused=on
TEST_OUTPUT:
---
fail_compilation/unused_nested_blocks.d(14): Error: variable `inner` declared but never used
---
**********************************/

module unused_nested_blocks;

void baz()
{
    {
        { int inner; }   // warning
    }
}
