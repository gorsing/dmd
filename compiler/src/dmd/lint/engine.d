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
import dmd.visitor.postorder; // Используем безопасный пост-ордер обход
import dmd.init;

import dmd.errors : warning;

extern (D) enum LintFlags : uint
{
    none         = 0,
    constSpecial = 1 << 0,
    unusedParams = 1 << 1,
    all          = ~0
}

// Посетитель для поиска использованных переменных внутри тела функции
private extern(C++) final class UnusedParamVisitor : StoppableVisitor
{
    alias visit = typeof(super).visit;

    // Ключ - указатель на декларацию параметра, значение - был ли он использован
    bool[void*] usedParams;

    extern(D) this(VarDeclaration[] paramsToTrack)
    {
        foreach (p; paramsToTrack)
            usedParams[cast(void*)p] = false;
    }

    // Заглушки, чтобы избежать fallback'а в базовый класс
    override void visit(Dsymbol s) { }
    override void visit(Statement s) { }
    override void visit(Expression e) { }
    override void visit(Initializer i) { }

    // --- МОСТЫ: Statements -> Expressions ---
    // (Без этого walkPostorder не спустится внутрь выражений)
    override void visit(ExpStatement s) { if (s.exp) walkPostorder(s.exp, this); }
    override void visit(IfStatement s) { if (s.condition) walkPostorder(s.condition, this); }
    override void visit(ReturnStatement s) { if (s.exp) walkPostorder(s.exp, this); }
    override void visit(WhileStatement s) { if (s.condition) walkPostorder(s.condition, this); }
    override void visit(DoStatement s) { if (s.condition) walkPostorder(s.condition, this); }
    override void visit(ForStatement s) {
        if (s.condition) walkPostorder(s.condition, this);
        if (s.increment) walkPostorder(s.increment, this);
    }
    override void visit(ForeachStatement s) { if (s.aggr) walkPostorder(s.aggr, this); }
    override void visit(ForeachRangeStatement s) {
        if (s.lwr) walkPostorder(s.lwr, this);
        if (s.upr) walkPostorder(s.upr, this);
    }
    override void visit(SwitchStatement s) { if (s.condition) walkPostorder(s.condition, this); }
    override void visit(CaseStatement s) { if (s.exp) walkPostorder(s.exp, this); }
    override void visit(GotoCaseStatement s) { if (s.exp) walkPostorder(s.exp, this); }
    override void visit(ThrowStatement s) { if (s.exp) walkPostorder(s.exp, this); }
    override void visit(SynchronizedStatement s) { if (s.exp) walkPostorder(s.exp, this); }
    override void visit(WithStatement s) { if (s.exp) walkPostorder(s.exp, this); }

    // --- МОСТЫ ДЛЯ ИНИЦИАЛИЗАТОРОВ ---
    override void visit(DeclarationExp de)
    {
        if (de.declaration)
        {
            if (auto vd = de.declaration.isVarDeclaration())
            {
                if (vd._init)
                {
                    if (auto ei = vd._init.isExpInitializer())
                    {
                        if (ei.exp) walkPostorder(ei.exp, this);
                    }
                }
            }
        }
    }

    // --- МОСТ ДЛЯ ЛЯМБД И ДЕЛЕГАТОВ ---
    override void visit(FuncExp fe)
    {
        if (fe.fd && fe.fd.fbody)
            walkPostorder(fe.fd.fbody, this); // Ныряем внутрь замыканий!
    }

    // --- САМОЕ ГЛАВНОЕ: ПЕРЕХВАТ ПЕРЕМЕННЫХ ---
    override void visit(VarExp ve)
    {
        if (ve && ve.var)
        {
            auto ptr = cast(void*)ve.var;
            if (auto p = ptr in usedParams)
                *p = true; // Отмечаем как использованную
        }
    }
}

// Главный обходчик AST для линтера
extern(C++) final class LintVisitor : Visitor
{
    alias visit = Visitor.visit;

    LintFlags[] flagsStack;

    extern(D) this()
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

    override void visit(Module m)
    {
        if (!m || !m.members) return;
        foreach (s; *m.members)
            if (s) s.accept(this);
    }

    override void visit(AttribDeclaration ad)
    {
        if (ad && ad.decl)
            foreach (s; *ad.decl)
                if (s) s.accept(this);
    }

    override void visit(AggregateDeclaration ad)
    {
        if (!ad || !ad.members) return;
        foreach (s; *ad.members)
            if (s) s.accept(this);
    }

    override void visit(TemplateInstance ti)
    {
        if (!ti || !ti.members) return;
        foreach (s; *ti.members)
            if (s) s.accept(this);
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
            newFlags |= LintFlags.all;
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

    override void visit(PragmaDeclaration pd)
    {
        if (!pd) return;
        bool pushed = pushLintFlags(pd);

        if (pd.decl)
            foreach (s; *pd.decl)
                if (s) s.accept(this);

        if (pushed)
            flagsStack.length--;
    }

    // --- Линтер для вложенных функций и прагм внутри тел функций ---
    override void visit(CompoundStatement s)
    {
        if (s && s.statements)
            foreach (stmt; *s.statements)
                if (stmt) stmt.accept(this);
    }

    override void visit(ExpStatement s)
    {
        if (s && s.exp) s.exp.accept(this);
    }

    override void visit(DeclarationExp de)
    {
        if (de && de.declaration)
            de.declaration.accept(this);
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

        if (ps._body)
            ps._body.accept(this);

        if (pushed)
            flagsStack.length--;
    }

    // --- Основная логика ---

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

        if (checkUnused && fd.parameters)
        {
            VarDeclaration[] paramsToTrack;

            for (size_t i = 0; i < fd.parameters.length; i++)
            {
                VarDeclaration v = (*fd.parameters)[i];
                if (!v || !v.ident) continue;

                bool isIgnoredName = v.ident.toChars()[0] == '_';

                if (!(v.storage_class & STC.temp) && !isIgnoredName)
                {
                    paramsToTrack ~= v;
                }
            }

            if (paramsToTrack.length > 0 && fd.fbody)
            {
                scope paramVisitor = new UnusedParamVisitor(paramsToTrack);
                walkPostorder(fd.fbody, paramVisitor);

                foreach (p; paramsToTrack)
                {
                    if (!paramVisitor.usedParams[cast(void*)p])
                    {
                        warning(p.loc, "[unusedParams] function parameter `%s` is never used", p.ident.toChars());
                    }
                }
            }
        }

        if (fd.fbody)
            fd.fbody.accept(this);
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