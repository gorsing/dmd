/**
 * The thread module provides support for thread creation and management.
 *
 * Copyright: Copyright Sean Kelly 2005 - 2012.
 * License: Distributed under the
 *      $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0).
 *    (See accompanying file LICENSE)
 * Authors:   Sean Kelly, Walter Bright, Alex Rønne Petersen, Martin Nowak
 * Source:    $(DRUNTIMESRC core/thread/context.d)
 */

module core.thread.context;

private template isCallable(alias F)
{
    enum isCallable = __traits(compiles, F());
}

private template isSafeFn(alias F)
{
    enum isSafeFn = __traits(compiles, () @safe { F(); });
}

private template isNothrow(alias F)
{
    enum isNothrow = __traits(compiles, () nothrow { F(); });
}

private template isNogc(alias F)
{
    enum isNogc = __traits(compiles, () @nogc { F(); });
}
struct StackContext
{
    void* bstack, tstack;

    /// Slot for the EH implementation to keep some state for each stack
    /// (will be necessary for exception chaining, etc.). Opaque as far as
    /// we are concerned here.
    void* ehContext;
    StackContext* within;
    StackContext* next, prev;
}

struct Callable
{
    void opAssign(void function() fn) pure @trusted
    {
        assignFunctionUnsafe(fn);
    }

    void opAssign(void delegate() dg) pure @trusted
    {
        assignDelegateUnsafe(dg);
    }

    void opAssign(F)(F fn) pure @trusted
        if (isCallable!fn && isSafeFn!fn && isNothrow!fn && isNogc!fn)
    {
        static if (is(F == void function()))
            assignFunctionSafe(fn);
        else static if (is(F == void delegate()))
            assignDelegateSafe(fn);
        else
            static assert(0, "Unsupported callable type");
    }

    void opCall() @trusted nothrow @nogc
    {
        switch (m_type)
        {
            case Call.FN: m_fn(); break;
            case Call.DG: m_dg(); break;
            default: assert(0, "Callable not initialized");
        }
    }

private:
    enum Call { NO, FN, DG }
    Call m_type = Call.NO;

    union
    {
        void function() @safe nothrow @nogc m_fn;
        void delegate() @safe nothrow @nogc m_dg;
    }

    @trusted pure nothrow @nogc
    void assignFunctionSafe(void function() @safe nothrow @nogc fn)
    {
        m_fn = fn;
        m_type = Call.FN;
    }

    @trusted pure nothrow @nogc
    void assignDelegateSafe(void delegate() @safe nothrow @nogc dg)
    {
        m_dg = dg;
        m_type = Call.DG;
    }

    @trusted pure
    void assignFunctionUnsafe(void function() fn)
    {
        m_fn = cast(void function() @safe nothrow @nogc) fn;
        m_type = Call.FN;
    }

    @trusted pure
    void assignDelegateUnsafe(void delegate() dg)
    {
        m_dg = cast(void delegate() @safe nothrow @nogc) dg;
        m_type = Call.DG;
    }
}

