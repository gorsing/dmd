/**
 * Enforce visibility constraints such as `public` and `private`.
 *
 * Specification: $(LINK2 https://dlang.org/spec/attribute.html#visibility_attributes, Visibility Attributes)
 *
 * Copyright:   Copyright (C) 1999-2026 by The D Language Foundation, All Rights Reserved
 * Authors:     $(LINK2 https://www.digitalmars.com, Walter Bright)
 * License:     $(LINK2 https://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 * Source:      $(LINK2 https://github.com/dlang/dmd/blob/master/compiler/src/dmd/access.d, _access.d)
 * Documentation:  https://dlang.org/phobos/dmd_access.html
 * Coverage:    https://codecov.io/gh/dlang/dmd/src/master/compiler/src/dmd/access.d
 */

module dmd.access;

import dmd.aggregate;
import dmd.astenums;
import dmd.dclass;
import dmd.dmodule;
import dmd.dscope;
import dmd.dstruct;
import dmd.dsymbol;
import dmd.dsymbolsem : toAlias;
import dmd.errors;
import dmd.expression;
import dmd.funcsem : overloadApply;
import dmd.location;
import dmd.tokens;

private enum LOG = false;

/*******************************
 * Do access check for member of this class, this class being the
 * type of the 'this' pointer used to access smember.
 * Returns true if the member is not accessible.
 */
bool checkAccess(AggregateDeclaration ad, Loc loc, Scope* sc, Dsymbol smember)
{
    static if (LOG)
    {
        printf("AggregateDeclaration::checkAccess() for %s.%s\n", ad.toChars(), smember.toChars());
    }

    const p = smember.toParent();
    if (p && p.isTemplateInstance())
        return false; // for backward compatibility

    if (!symbolIsVisible(sc, smember))
    {
        error(loc, "%s `%s` %s `%s` is not accessible", ad.kind(), ad.toPrettyChars(), smember.kind(), smember.toErrMsg());
        return true;
    }

    return false;
}

/****************************************
 * Determine if scope sc has package level access to s.
 */
private bool hasPackageAccess(Scope* sc, Dsymbol s)
{
    return hasPackageAccess(sc._module, s);
}

private bool hasPackageAccess(Module mod, Dsymbol s)
{
    Package pkg = s.visible().pkg;

    if (!pkg)
        pkg = resolvePackageAccess(s);

    static if (LOG)
    {
        printf("hasPackageAccess(s = '%s', mod = '%s', pkg = '%s')\n", 
               s.toChars(), mod.toChars(), pkg ? pkg.toChars() : "NULL");
    }

    if (!pkg)
        return false;

    if (pkg == mod.parent || pkg.isPackageMod() == mod)
    {
        static if (LOG) printf("\tsc is in permitted package for s\n");
        return true;
    }

    for (Dsymbol ancestor = mod.parent; ancestor; ancestor = ancestor.parent)
    {
        if (ancestor == pkg)
        {
            static if (LOG) printf("\tsc is in permitted ancestor package for s\n");
            return true;
        }
    }

    static if (LOG) printf("\tno package access\n");
    return false;
}

/****************************************
 * Helper to infer the most qualified package if no explicit package exists.
 */
private Package resolvePackageAccess(Dsymbol s)
{
    for (; s; s = s.parent)
    {
        if (auto m = s.isModule())
        {
            if (DsymbolTable dst = Package.resolve(m.md ? m.md.packages : null, null, null))
            {
                if (Dsymbol s2 = dst.lookup(m.ident))
                {
                    if (Package p = s2.isPackage())
                    {
                        if (p.isPackageMod())
                            return p;
                    }
                }
            }
        }
        else if (auto p = s.isPackage())
        {
            return p;
        }
    }
    return null;
}

/****************************************
 * Determine if scope sc has protected level access to cd.
 */
private bool hasProtectedAccess(Scope* sc, Dsymbol s)
{
    if (auto cd = s.isClassMember()) // also includes interfaces
    {
        for (auto scx = sc; scx; scx = scx.enclosing)
        {
            if (!scx.scopesym)
                continue;

            if (auto cd2 = scx.scopesym.isClassDeclaration())
            {
                if (cd.isBaseOf(cd2, null))
                    return true;
            }
        }
    }
    return sc._module == s.getAccessModule();
}

/****************************************
 * Check access to d for expression e.d
 * Returns true if the declaration is not accessible.
 */
bool checkAccess(Loc loc, Scope* sc, Expression e, Dsymbol d)
{
    if (sc.noAccessCheck || !e || d.isUnitTestDeclaration())
        return false;

    static if (LOG)
    {
        printf("checkAccess(%s . %s)\n", e.toChars(), d.toChars());
        printf("\te.type = %s\n", e.type.toChars());
    }

    if (auto tc = e.type.isTypeClass())
    {
        ClassDeclaration cd = tc.sym;
        if (e.op == EXP.super_)
        {
            if (auto cd2 = sc.func.toParent().isClassDeclaration())
                cd = cd2;
        }
        return checkAccess(cd, loc, sc, d);
    }

    if (auto ts = e.type.isTypeStruct())
    {
        return checkAccess(ts.sym, loc, sc, d);
    }

    return false;
}

/****************************************
 * Check access to package/module `p` from scope `sc`.
 */
bool checkAccess(Scope* sc, Package p)
{
    if (sc._module == p)
        return false;

    for (; sc; sc = sc.enclosing)
    {
        if (sc.scopesym && sc.scopesym.isPackageAccessible(p, Visibility(Visibility.Kind.private_)))
            return false;
    }

    return true;
}

/**
 * Check whether symbol `s` is visible in `mod`.
 */
bool symbolIsVisible(Module mod, Dsymbol s)
{
    s = mostVisibleOverload(s);
    final switch (s.visible().kind)
    {
        case Visibility.Kind.undefined: return true;
        case Visibility.Kind.none: return false;
        case Visibility.Kind.private_: return s.getAccessModule() == mod;
        case Visibility.Kind.package_: return s.getAccessModule() == mod || hasPackageAccess(mod, s);
        case Visibility.Kind.protected_: return s.getAccessModule() == mod;
        case Visibility.Kind.public_, Visibility.Kind.export_: return true;
    }
}

/**
 * Same as above, but determines the lookup module from symbol's `origin`.
 */
bool symbolIsVisible(Dsymbol origin, Dsymbol s)
{
    return symbolIsVisible(origin.getAccessModule(), s);
}

/**
 * Same as above but also checks for protected symbols visible from scope `sc`.
 */
bool symbolIsVisible(Scope* sc, Dsymbol s)
{
    return checkSymbolAccess(sc, mostVisibleOverload(s));
}

/**
 * Check if a symbol is visible from a given scope without taking
 * into account the most visible overload.
 */
bool checkSymbolAccess(Scope* sc, Dsymbol s)
{
    final switch (s.visible().kind)
    {
        case Visibility.Kind.undefined: return true;
        case Visibility.Kind.none: return false;
        case Visibility.Kind.private_: return sc._module == s.getAccessModule();
        case Visibility.Kind.package_: return sc._module == s.getAccessModule() || hasPackageAccess(sc._module, s);
        case Visibility.Kind.protected_: return hasProtectedAccess(sc, s);
        case Visibility.Kind.public_, Visibility.Kind.export_: return true;
    }
}

/**
 * Return the "effective" visibility attribute of a symbol when accessed in a module.
 */
private Visibility visibilitySeenFromModule(Dsymbol d, Module mod)
{
    Visibility vis = d.visible();
    if (mod && vis.kind == Visibility.Kind.package_)
    {
        return hasPackageAccess(mod, d) ? Visibility(Visibility.Kind.public_) : Visibility(Visibility.Kind.private_);
    }
    return vis;
}

/**
 * Use the most visible overload to check visibility. Later perform an access
 * check on the resolved overload.
 */
public Dsymbol mostVisibleOverload(Dsymbol s, Module mod = null)
{
    if (!s.isOverloadable())
        return s;

    Dsymbol mostVisible = s;

    for (Dsymbol current = s; current; )
    {
        Dsymbol next;

        if (auto fd = current.isFuncDeclaration())
            next = fd.overnext;
        else if (auto td = current.isTemplateDeclaration())
            next = td.overnext;
        else if (auto fa = current.isFuncAliasDeclaration())
            next = fa.overnext;
        else if (auto od = current.isOverDeclaration())
            next = od.overnext;
        else if (auto ad = current.isAliasDeclaration())
        {
            assert(ad.isOverloadable || (ad.type && ad.type.ty == Terror), "Non overloadable Aliasee in overload list");

            if (ad.semanticRun < PASS.semanticdone)
                next = ad.overnext;
            else
            {
                auto aliasee = ad.toAlias();
                if (aliasee.isFuncAliasDeclaration || aliasee.isOverDeclaration)
                    next = aliasee;
                else
                {
                    assert(ad.overnext is null, "Unresolved overload of alias");
                    break;
                }
            }
        }
        else
            break;

        if (next && visibilitySeenFromModule(mostVisible, mod) < visibilitySeenFromModule(next, mod))
            mostVisible = next;

        current = next;
    }

    return mostVisible;
}