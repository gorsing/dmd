/**
 * Does semantic analysis for attributes.
 *
 * The term 'attribute' refers to things that can apply to a larger scope than a single declaration.
 */
module dmd.attribsem;

import dmd.arraytypes;
import dmd.attrib;
import dmd.dscope;
import dmd.dsymbol;
import dmd.expression;
import dmd.expressionsem;
import dmd.location;
import dmd.root.array; // for each

/**
 * Retrieves the attributes associated with a UserAttributeDeclaration.
 * * Returns:
 * A pointer to Expressions containing the attributes, or null if none exist.
 */
Expressions* getAttributes(UserAttributeDeclaration a)
{
    // Optimization: check if there is any data to process
    if (!a.userAttribDecl && (!a.atts || !a.atts.length))
        return null;

    if (auto sc = a._scope)
    {
        a._scope = null;
        if (a.atts) // Safe semantic call
            arrayExpressionSemantic(a.atts.peekSlice(), sc);
    }

    auto exps = new Expressions();

    // Recursively collect attributes from parent blocks
    if (a.userAttribDecl && a.userAttribDecl !is a)
    {
        if (auto parentAtts = a.userAttribDecl.getAttributes())
            exps.push(new TupleExp(Loc.initial, parentAtts));
    }

    if (a.atts && a.atts.length)
        exps.push(new TupleExp(Loc.initial, a.atts));

    return exps;
}

/**
 * Iterates the UDAs attached to the given symbol.
 *
 * Params:
 * sym = the symbol to get the UDAs from
 * sc = scope to use for semantic analysis of UDAs
 * dg = called once for each UDA
 *
 * Returns:
 * If `dg` returns `!= 0`, stops the iteration and returns that value.
 * Otherwise, returns 0.
 */
int foreachUda(Dsymbol sym, Scope* sc, int delegate(Expression) dg)
{
    if (!sym.userAttribDecl)
        return 0;

    auto udas = sym.userAttribDecl.getAttributes();
    if (!udas) // PROTECTION: prevent null pointer dereference
        return 0;

    arrayExpressionSemantic(udas.peekSlice(), sc, true);

    return udas.each!((uda) {
        if (!uda) return 0;

        // If it's a tuple (group of UDAs), iterate through its elements
        if (auto te = uda.isTupleExp())
        {
            return te.exps.each!((e) => dg(e));
        }

        // Handle single UDA expression
        return dg(uda);
    });
}