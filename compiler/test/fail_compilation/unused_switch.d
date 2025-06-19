/**********************************
 REQUIRED_ARGS: -check=unused=on
 TEST_OUTPUT:
 ---
 ---
**********************************/

void main()
{
    int y = 2;
    switch (y)
    {
        case 1:
        case 2:
            break;
        default:
            break;
    }
}
