/**********************************
 REQUIRED_ARGS: -check=unused=on
TEST_OUTPUT:
---
fail_compilation/unused_switch.d(18): Error: variable `u0` declared but never used
fail_compilation/unused_switch.d(22): Error: variable `ok` declared but never used
fail_compilation/unused_switch.d(26): Error: variable `defV` declared but never used
---
**********************************/

module unused_switch;

void qux(int s)
{
    switch (s)
    {
        case 0:
            int u0;
            break;

        case 1:
            int ok = 42;
            break;

        default:
            int defV;
    }
}
