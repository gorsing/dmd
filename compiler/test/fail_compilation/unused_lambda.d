/**********************************
 REQUIRED_ARGS: -check=unused=on
 TEST_OUTPUT:
 ---
 fail_compilation/unused_lambda.d(12): Error: variable `f` declared but never used
 ---
**********************************/

void main()
{
    int x = 1;
    auto f = () => x + 1;
    f();
}
