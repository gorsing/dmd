// compiler/test/pass_compilation/unused_simple.d

/**********************************
 REQUIRED_ARGS: -check=unused=on
 TEST_OUTPUT:
 ---
 ---
**********************************/

import std.stdio;

void main()
{
    int x = 42;
    writeln(x);    // x используется
}
