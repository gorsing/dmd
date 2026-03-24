module dmd.lint.engine;

import dmd.aggregate;
import dmd.arraytypes;
import dmd.astenums;
import dmd.attrib;
import dmd.declaration;
import dmd.dmodule;
import dmd.dsymbol;
import dmd.dtemplate;
import dmd.expression;
import dmd.func;
import dmd.id;
import dmd.statement;
import dmd.visitor;
import dmd.init;

import dmd.errors : warning;

extern (D) enum LintFlags : uint
{
    none         = 0,
    constSpecial = 1 << 0,
    unusedParams = 1 << 1,
    all          = ~0
}

extern(C++) final class LintVisitor : Visitor
{
    alias visit = Visitor.visit;

    LintFlags[] flagsStack;
    
    // Надежный стек вместо ломающегося ассоциативного массива
    VarDeclaration[] activeParams;
    bool[] activeUsed;

    this()
    {
        flagsStack ~= LintFlags.none;
    }

    LintFlags currentFlags()
    {
        return flagsStack.length > 0 ? flagsStack[$ - 1] : LintFlags.none;
    }

    override void visit(Dsymbol s) { }
    override void visit(Statement s) { }
    override void visit(Expression e) { }
    override void visit(Initializer i) { }

    override void visit(TemplateDeclaration td)
    {
        if (!td.members) return;
        foreach (s; *td.members)
            if (s) s.accept(this);
    }

    override void visit(DeclarationExp de)
    {
        if (de.declaration)
            de.declaration.accept(this);
    }

    override void visit(AliasDeclaration ad)
    {
        if (ad.aliassym)
            ad.aliassym.accept(this);
    }

    override void visit(Module m)
    {
        if (!m.members) return;
        foreach (s; *m.members)
            if (s) s.accept(this);
    }

    override void visit(AttribDeclaration ad)
    {
        if (ad.decl)
        {
            foreach (s; *ad.decl)
                if (s) s.accept(this);
        }
    }

    override void visit(PragmaDeclaration pd)
    {
        bool pushed = pushLintFlags(pd);

        if (pd.decl)
        {
            foreach (s; *pd.decl)
                if (s) s.accept(this);
        }

        if (pushed)
            flagsStack.length--;
    }

    override void visit(PragmaStatement ps)
    {
        bool pushed = false;
        if (ps.ident == Id.lint)
        {
            pushed = true;
            flagsStack ~= parsePragmaArgs(ps.args);
        }

        if (ps._body)
            ps._body.accept(this);

        if (pushed)
            flagsStack.length--;
    }

    override void visit(AggregateDeclaration ad)
    {
        if (!ad.members) return;
        foreach (s; *ad.members)
            if (s) s.accept(this);
    }

    override void visit(TemplateInstance ti)
    {
        if (!ti.members) return;
        foreach (s; *ti.members)
            if (s) s.accept(this);
    }

    override void visit(FuncDeclaration fd)
    {
        const flags = currentFlags();

        if (flags & LintFlags.constSpecial)
            checkConstSpecial(fd);

        bool checkUnused = (flags & LintFlags.unusedParams) != 0;

        if (checkUnused)
        {
            if (!fd.fbody)
                checkUnused = false;
            else if (fd.vtblIndex != -1 && !fd.isFinalFunc())
                checkUnused = false;
            else if (fd.foverrides.length > 0)
                checkUnused = false;
            else
            {
                import dmd.astenums : LINK;
                if (fd._linkage == LINK.c || fd._linkage == LINK.cpp || fd._linkage == LINK.windows)
                    checkUnused = false;
            }
        }

        // Запоминаем текущий размер стека, чтобы поддержать вложенные функции/лямбды
        size_t paramStart = activeParams.length;

        if (checkUnused && fd.parameters)
        {
            for (size_t i = 0; i < fd.parameters.length; i++)
            {
                activeParams ~= (*fd.parameters)[i];
                activeUsed ~= false;
            }
        }

        if (fd.fbody)
            fd.fbody.accept(this);

        if (checkUnused && fd.parameters)
        {
            for (size_t i = 0; i < fd.parameters.length; i++)
            {
                size_t stackIdx = paramStart + i;
                if (!activeUsed[stackIdx])
                {
                    VarDeclaration v = (*fd.parameters)[i];
                    bool isIgnoredName = v.ident && v.ident.toChars()[0] == '_';
                    if (v.ident && !(v.storage_class & STC.temp) && !isIgnoredName)
                    {
                        warning(v.loc, "[unusedParams] function parameter `%s` is never used", v.ident.toChars());
                    }
                }
            }
        }

        // Восстанавливаем стек
        activeParams.length = paramStart;
        activeUsed.length = paramStart;
    }

    private void checkConstSpecial(FuncDeclaration fd)
    {
        if (fd.isGenerated() || (fd.storage_class & STC.const_) || fd.type.isConst())
            return;

        if (fd.ident != Id.opEquals && fd.ident != Id.opCmp &&
            fd.ident != Id.tohash && fd.ident != Id.tostring)
            return;

        if (!fd.toParent2() || !fd.toParent2().isStructDeclaration())
            return;

        warning(fd.loc, "[constSpecial] special method `%s` should be marked as `const`", fd.ident ? fd.ident.toChars() : fd.toChars());
    }

    private bool pushLintFlags(PragmaDeclaration pd)
    {
        if (pd && pd.ident == Id.lint)
        {
            flagsStack ~= parsePragmaArgs(pd.args);
            return true;
        }
        return false;
    }

    private LintFlags parsePragmaArgs(Expressions* args)
    {
        LintFlags newFlags = currentFlags();
        if (!args || args.length == 0)
        {
            newFlags |= LintFlags.all;
        }
        else
        {
            foreach (arg; *args)
            {
                auto id = arg.isIdentifierExp();
                if (!id) continue;

                if (id.ident == Id.constSpecial)
                    newFlags |= LintFlags.constSpecial;
                else if (id.ident == Id.unusedParams)
                    newFlags |= LintFlags.unusedParams;
                else if (id.ident == Id.none)
                    newFlags = LintFlags.none;
                else if (id.ident == Id.all)
                    newFlags |= LintFlags.all;
            }
        }
        return newFlags;
    }

    override void visit(VarExp ve)
    {
        if (auto vd = ve.var.isVarDeclaration())
        {
            // Ищем переменную в нашем надежном плоском стеке
            for (size_t i = 0; i < activeParams.length; i++)
            {
                if (activeParams[i] == vd)
                {
                    activeUsed[i] = true;
                    break;
                }
            }
        }
    }

    override void visit(CompoundStatement s)
    {
        if (s.statements)
            foreach (stmt; *s.statements)
                if (stmt) stmt.accept(this);
    }

    override void visit(ExpStatement s)
    {
        if (s.exp) s.exp.accept(this);
    }

    override void visit(IfStatement s)
    {
        if (s.condition) s.condition.accept(this);
        if (s.ifbody) s.ifbody.accept(this);
        if (s.elsebody) s.elsebody.accept(this);
    }

    override void visit(ReturnStatement s)
    {
        if (s.exp) s.exp.accept(this);
    }

    override void visit(ForStatement s)
    {
        if (s._init) s._init.accept(this);
        if (s.condition) s.condition.accept(this);
        if (s.increment) s.increment.accept(this);
        if (s._body) s._body.accept(this);
    }

    override void visit(BinExp e)
    {
        if (e.e1) e.e1.accept(this);
        if (e.e2) e.e2.accept(this);
    }

    override void visit(UnaExp e)
    {
        if (e.e1) e.e1.accept(this);
    }

    override void visit(CallExp e)
    {
        if (e.e1) e.e1.accept(this);
        if (e.arguments)
            foreach (arg; *e.arguments)
                if (arg) arg.accept(this);
    }

    override void visit(VarDeclaration vd)
    {
        if (vd._init)
            vd._init.accept(this);
    }

    override void visit(ExpInitializer ei)
    {
        if (ei.exp)
            ei.exp.accept(this);
    }

    override void visit(FuncExp fe)
    {
        if (fe.fd)
            fe.fd.accept(this);
    }
}

extern(D) void runLinter(Module[] modules)
{
    scope visitor = new LintVisitor();
    foreach (m; modules)
    {
        m.accept(visitor);
    }
}