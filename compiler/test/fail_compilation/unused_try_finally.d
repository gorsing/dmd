/**********************************
REQUIRED_ARGS: -check=unused=on
TEST_OUTPUT:
---
fail_compilation/unused_try_finally.d(13): Error: variable `t` declared but never used
fail_compilation/unused_try_finally.d(17): Error: variable `f` declared but never used
---
**********************************/
void main()
{
    try
    {
        int t;
    }
    finally
    {
        int f;
    }
}
