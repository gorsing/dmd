/**
 * Copyright:   Copyright (C) 1999-2026 by The D Language Foundation, All Rights Reserved
 * Authors:     $(LINK2 https://www.digitalmars.com, Walter Bright)
 * License:     $(LINK2 https://www.boost.org/LICENSE_1_0.txt, Boost License 1.0)
 */

module dmd.lint.engine;

import dmd.astenums;
import dmd.attrib;
import dmd.declaration;
import dmd.dsymbol;
import dmd.expression;
import dmd.func;
import dmd.id;
import dmd.statement;
import dmd.visitor;
import dmd.errors : lint;

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

    // Стек для лексического отслеживания pragma(lint, ...)
    LintFlags[] flagsStack;

    // Изолированное состояние для отслеживания (вместо void* lintInfo и wasUsed)
    bool[VarDeclaration] unusedTrack;

    this()
    {
        // Инициализируем стек базовым состоянием.
        flagsStack ~= LintFlags.none;
    }

    LintFlags currentFlags()
    {
        return flagsStack.length > 0 ? flagsStack[$ - 1] : LintFlags.none;
    }

    // ------------------------------------------------------------------------
    // Обход дерева и управление лексическим контекстом (pragma)
    // ------------------------------------------------------------------------

    override void visit(Dsymbol s) { }
    override void visit(Statement s) { }
    override void visit(Expression e) { }

    override void visit(Module m)
    {
        if (!m.members) return;
        foreach (s; *m.members)
            if (s) s.accept(this);
    }

    // Обработка pragma(lint) на уровне объявлений
    override void visit(AttribDeclaration ad)
    {
        PragmaDeclaration pd = ad.isPragmaDeclaration();
        bool pushed = pushLintFlags(pd);

        Dsymbols* decls = ad.include(null);
        if (decls)
        {
            foreach (s; *decls)
                if (s) s.accept(this);
        }

        if (pushed)
            flagsStack.length--;
    }

    // Обработка pragma(lint) на уровне инструкций внутри тела функции
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

    // ------------------------------------------------------------------------
    // Анализ функций (применение правил)
    // ------------------------------------------------------------------------

    override void visit(FuncDeclaration fd)
    {
        const flags = currentFlags();

        if (flags & LintFlags.constSpecial)
            checkConstSpecial(fd);

        bool checkUnused = (flags & LintFlags.unusedParams) != 0;

        // Сохраняем состояние для корректной работы с вложенными функциями
        bool[VarDeclaration] oldTrack = unusedTrack; 
        unusedTrack = null;

        if (checkUnused && fd.fbody && fd.parameters)
        {
            const bool isRequiredByInterface = fd.isOverride() || (fd.isVirtual() && !fd.isFinal());
            if (!isRequiredByInterface)
            {
                foreach (v; *fd.parameters)
                {
                    bool isIgnoredName = v.ident && v.ident.toChars()[0] == '_';
                    if (v.ident && !(v.storage_class & STC.temp) && !isIgnoredName)
                    {
                        unusedTrack[v] = false; // Добавляем параметр в трекер как неиспользованный
                    }
                }
            }
        }

        // Запускаем рекурсивный обход AST-дерева тела функции
        if (fd.fbody)
            fd.fbody.accept(this);

        if (checkUnused)
        {
            foreach (v, used; unusedTrack)
            {
                if (!used)
                {
                    lint(v.loc, "unusedParams".ptr, "function parameter `%s` is never used".ptr, v.ident.toChars());
                }
            }
        }

        unusedTrack = oldTrack; // Восстанавливаем родительский трекер
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

        lint(fd.loc, "constSpecial".ptr, "special method `%s` should be marked as `const`".ptr, fd.ident ? fd.ident.toChars() : fd.toChars());
    }

    // ------------------------------------------------------------------------
    // Вспомогательные методы прагм
    // ------------------------------------------------------------------------

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

    // ------------------------------------------------------------------------
    // Рекурсивный обход Statements и Expressions (для unusedParams)
    // ------------------------------------------------------------------------

    // Отмечаем использование переменной при обходе
    override void visit(VarExp ve)
    {
        if (auto vd = ve.var.isVarDeclaration())
        {
            if (vd in unusedTrack)
                unusedTrack[vd] = true;
        }
    }

    // Проброс визитора сквозь Statements
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

    // Проброс визитора сквозь Expressions
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
}

// Точка входа для запуска линтера после семантики
extern(D) void runLinter(Module[] modules)
{
    scope visitor = new LintVisitor();
    foreach (m; modules)
    {
        m.accept(visitor);
    }
}