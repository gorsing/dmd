module dmd.linter;

import dmd.func;
import dmd.id;
import dmd.declaration;
import dmd.aggregate;
import dmd.dscope;
import dmd.errors;
import dmd.astenums;
import dmd.expression;
import dmd.visitor.transitive;
import dmd.astcodegen;

struct LintContext
{
    uint usedParameters;

    bool isUsed(size_t index) { return (usedParameters & (1 << index)) != 0; }
    void markUsed(size_t index) { usedParameters |= (1 << index); }
}

private extern (C++) final class UsageScanner : TransitiveVisitor!ASTCodegen
{
    alias visit = TransitiveVisitor!ASTCodegen.visit;
    FuncDeclaration fd;
    LintContext* ctx;

    override void visit(VarExp e)
    {
        if (auto v = e.var.isVarDeclaration())
        {
            if (v.storage_class & STC.parameter)
            {
                if (fd.parameters)
                {
                    foreach (i, p; *fd.parameters)
                    {
                        if (v == p)
                        {
                            ctx.markUsed(i);
                            break;
                        }
                    }
                }
            }
        }
    }

    override void visit(FuncExp e) {}
    override void visit(DeclarationExp e) {}
}

private bool isIgnored(VarDeclaration v)
{
    if (!v.ident)
        return true;
    const(char)* s = v.ident.toChars();
    return s[0] == '_';
}

void lintFunction(FuncDeclaration funcdecl)
{
    if (!funcdecl || !funcdecl._scope)
        return;

    lintConstSpecial(funcdecl);
    lintUnusedParams(funcdecl);
}

void lintConstSpecial(FuncDeclaration fd, bool isKnownStructMember = false)
{
    if (!fd || !fd._scope || !(fd._scope.lintFlags & LintFlags.constSpecial))
        return;

    if (fd.isGenerated() || (fd.storage_class & STC.const_) || fd.type.isConst())
        return;

    if (!isKnownStructMember)
    {
        if (fd.ident != Id.opEquals && fd.ident != Id.opCmp &&
            fd.ident != Id.tohash && fd.ident != Id.tostring)
            return;

        if (!fd.toParent2() || !fd.toParent2().isStructDeclaration())
            return;
    }

    lint(fd.loc, "constSpecial".ptr, "special method `%s` should be marked as `const`".ptr, fd.ident ? fd.ident.toChars() : fd.toChars());
}

private void lintUnusedParams(FuncDeclaration fd)
{
    if (!fd.fbody || !fd.parameters || fd.parameters.length == 0)
        return;

    if (!fd._scope || !(fd._scope.lintFlags & LintFlags.unusedParams))
        return;

    auto ad = fd.isMember2();
    bool isClassMethod = ad && ad.isClassDeclaration();
    bool isVirtual = isClassMethod && !fd.isStatic() && !(fd.storage_class & STC.final_);
    bool isOverride = (fd.storage_class & STC.override_) || (fd.foverrides.length > 0);

    if (isVirtual || isOverride)
        return;

    LintContext ctx;
    scope scanner = new UsageScanner();
    scanner.fd = fd;
    scanner.ctx = &ctx;

    fd.fbody.accept(scanner);

    foreach (i, v; *fd.parameters)
    {
        if (!ctx.isUsed(i) && !isIgnored(v))
        {
            lint(v.loc, "unusedParams", "parameter `%s` is never used", v.ident.toChars());
        }
    }
}