/**********************************
 REQUIRED_ARGS: -check=unused=on
TEST_OUTPUT:
---
fail_compilation/unused_params_globals.d(15): Error: variable `loc` declared but never used
---
**********************************/

module unused_params_globals;

int g;                       // global value not check

void f(int p)                // parameters not check
{
    int loc;                 // must be warning
    ++p;
    ++g;
}
