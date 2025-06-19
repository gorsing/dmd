/**********************************
 REQUIRED_ARGS: -check=unused=on
 TEST_OUTPUT:
 ---
fail_compilation/unused_trycatch.d(13): Error: variable `z` declared but never used
fail_compilation/unused_trycatch.d(15): Error: variable `a` declared but never used
fail_compilation/unused_trycatch.d(16): Error: variable `b` declared but never used
---
**********************************/

void main()
{
    int z = 0;
    try {
        int a = 1 / (z + 1);    // z и a — используются
        auto b = a;             // b — не используется
    }
    catch (Exception e) {}      // e — не используется
}
