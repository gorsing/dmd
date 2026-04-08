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
import dmd.init;

// Импортируем "умный" транзитивный обходчик и узлы AST
import dmd.visitor.parsetime : ParseTimeVisitor;
import dmd.astcodegen : ASTCodegen;

import dmd.errors : warning;

extern (D) enum LintFlags : uint
{
    none         = 0,
    constSpecial = 1 << 0,
    unusedParams = 1 << 1,
    all          = ~0
}

private struct TrackedParam
{
    VarDeclaration decl;
    bool used;
}

// Наследуемся от умного визитора, который знает всё об AST
extern(C++) final class LintVisitor : ParseTimeVisitor!ASTCodegen
{
    // Открываем доступ ко всем базовым методам visit, которые мы не переопределили
    alias visit = typeof(super).visit;

    LintFlags[] flagsStack;
    TrackedParam[] activeParams;

    this()
    {
        flagsStack ~= LintFlags.none;
    }

    LintFlags currentFlags()
    {
        return flagsStack.length > 0 ? flagsStack[$ - 1] : LintFlags.none;
    }

    // =========================================================================
    // ПЕРЕХВАТ ПРАГМ
    // =========================================================================

    override void visit(PragmaDeclaration pd)
    {
        if (!pd) return;
        bool pushed = pushLintFlags(pd);

        // Магия: базовый класс сам обойдет pd.decl (внутренние объявления)
        super.visit(pd);

        if (pushed)
            flagsStack.length--;
    }

    override void visit(PragmaStatement ps)
    {
        if (!ps) return;
        bool pushed = false;
        if (ps.ident == Id.lint)
        {
            pushed = true;
            flagsStack ~= parsePragmaArgs(ps.args);
        }

        // Магия: базовый класс сам обойдет ps._body (тело прагмы)
        super.visit(ps);

        if (pushed)
            flagsStack.length--;
    }

    // =========================================================================
    // ПЕРЕХВАТ ФУНКЦИЙ И ПЕРЕМЕННЫХ
    // =========================================================================

    override void visit(FuncDeclaration fd)
    {
        if (!fd) return;

        const flags = currentFlags();

        if (flags & LintFlags.constSpecial)
            checkConstSpecial(fd);

        bool checkUnused = (flags & LintFlags.unusedParams) != 0;

        if (checkUnused)
        {
            import dmd.astenums : LINK;
            if (!fd.fbody ||
                (fd.vtblIndex != -1 && !fd.isFinalFunc()) ||
                (fd.foverrides.length > 0) ||
                (fd._linkage == LINK.c || fd._linkage == LINK.cpp || fd._linkage == LINK.windows))
            {
                checkUnused = false;
            }
        }

        size_t paramStart = activeParams.length;

        if (checkUnused && fd.parameters)
        {
            for (size_t i = 0; i < fd.parameters.length; i++)
            {
                VarDeclaration v = (*fd.parameters)[i];

                if (!v || !v.ident) continue;

                bool isIgnoredName = v.ident.toChars()[0] == '_';

                if (!(v.storage_class & STC.temp) && !isIgnoredName)
                {
                    activeParams ~= TrackedParam(v, false);
                }
            }
        }

        // Магия: мы не пишем `if (fd.fbody) fd.fbody.accept(this);`
        // Транзитивный визитор сам зайдет в параметры, тело функции, лямбды и вложенные классы!
        super.visit(fd);

        if (checkUnused)
        {
            for (size_t i = paramStart; i < activeParams.length; i++)
            {
                if (!activeParams[i].used)
                {
                    warning(activeParams[i].decl.loc, "[unusedParams] function parameter `%s` is never used", activeParams[i].decl.ident.toChars());
                }
            }
        }

        activeParams.length = paramStart;
    }

    override void visit(VarExp ve)
    {
        if (!ve || !ve.var) return;
        
        if (auto vd = ve.var.isVarDeclaration())
        {
            for (size_t i = activeParams.length; i-- > 0; )
            {
                if (activeParams[i].decl == vd)
                {
                    activeParams[i].used = true;
                    break;
                }
            }
        }

        // Пробрасываем обход дальше на случай, если узлу есть что еще показать
        super.visit(ve);
    }

    // =========================================================================
    // ПРИВАТНЫЕ ХЕЛПЕРЫ (Без изменений)
    // =========================================================================

    private void checkConstSpecial(FuncDeclaration fd)
    {
        if (fd.isGenerated() || (fd.storage_class & STC.const_) || (fd.type && fd.type.isConst()))
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
                if (!arg) continue;
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
}

extern(D) void runLinter(Module[] modules)
{
    scope visitor = new LintVisitor();
    foreach (m; modules)
    {
        if (m) m.accept(visitor);
    }
}