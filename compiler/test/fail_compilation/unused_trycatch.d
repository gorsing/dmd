/**********************************
 REQUIRED_ARGS: -check=unused=on
 TEST_OUTPUT:
 ---
fail_compilation/unused_trycatch.d(8): Error: variable `b` declared but never used
fail_compilation/unused_trycatch.d(10): Error: variable `e` declared but never used
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
