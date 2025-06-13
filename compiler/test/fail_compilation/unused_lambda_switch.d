/**********************************
 REQUIRED_ARGS: -check=unused
 TEST_OUTPUT:
 ---
fail_compilation/unused_lambda_switch.d(16): Error: variable `f` declared but never used
fail_compilation/unused_lambda_switch.d(19): Error: variable `y` declared but never used
fail_compilation/unused_lambda_switch.d(27): Error: variable `z` declared but never used
fail_compilation/unused_lambda_switch.d(28): Error: variable `a` declared but never used

 ---
**********************************/

void main()
{
    int x = 1;
    auto f = () => x + 1;
    f();

    int y = 2;
    switch (y)
    {
        case 1:
        case 2: break;
        default:  break;
    }

    int z = 0;
    try { int a = 1 / (z + 1); }
    catch (Exception e) {}
}
