/**********************************
 REQUIRED_ARGS: -check=unused=on
TEST_OUTPUT:
---
fail_compilation/unused_foreach.d(14): Error: variable `it` declared but never used
---
**********************************/

module unused_foreach;

void loops()
{
    foreach (i; 0 .. 3)
        int it;           // create, but not use.
}
