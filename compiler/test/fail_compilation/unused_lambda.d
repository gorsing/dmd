/**********************************
 REQUIRED_ARGS: -check=unused=on
 TEST_OUTPUT:
 ---
 ---
**********************************/

void main()
{
    int x = 1;
    auto f = () => x + 1;
    f();
}
