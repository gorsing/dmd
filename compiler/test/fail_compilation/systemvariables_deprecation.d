/*
REQUIRED_ARGS: -de
TEST_OUTPUT:
---
fail_compilation/systemvariables_deprecation.d(15): Deprecation: `@safe` function `main` calling `middle`
fail_compilation/systemvariables_deprecation.d(20):        `middle` cannot use `@safe` because it calls `inferred`
fail_compilation/systemvariables_deprecation.d(26):        contaminated by `access `@system` variable `x0`, so `inferred` cannot infer `@safe`
---
*/

// test deprecation messages before -preview=systemVariables becomes default

void main() @safe
{
    middle(); // nested deprecation
}

auto middle()
{
    return inferred(); // no deprecation, inferredC is not explicit `@safe`
}

auto inferred()
{
    @system int* x0;
    x0 = null;
}
