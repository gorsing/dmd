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

private extern(C++) class DeepVisitor : Visitor
{
    alias visit = Visitor.visit;
    bool[void*] visitedSymbols;

    bool visitDsymbol(Dsymbol s)
    {
        if (!s) return false;
        auto ptr = cast(void*)s;
        if (ptr in visitedSymbols) return false;
        visitedSymbols[ptr] = true;
        return true;
    }

    override void visit(Dsymbol s) { }
    override void visit(Statement s) { }
    override void visit(Expression e) { }
    override void visit(Initializer i) { }

    override void visit(Module m) { if (visitDsymbol(m) && m.members) foreach(s; *m.members) if (s) s.accept(this); }
    override void visit(AttribDeclaration ad) { if (visitDsymbol(ad) && ad.decl) foreach(s; *ad.decl) if (s) s.accept(this); }
    override void visit(AggregateDeclaration ad) { if (visitDsymbol(ad) && ad.members) foreach(s; *ad.members) if (s) s.accept(this); }
    override void visit(TemplateInstance ti) { if (visitDsymbol(ti) && ti.members) foreach(s; *ti.members) if (s) s.accept(this); }
    override void visit(TemplateDeclaration td) { if (visitDsymbol(td) && td.members) foreach(s; *td.members) if (s) s.accept(this); }
    override void visit(TemplateMixin tm) { if (visitDsymbol(tm) && tm.members) foreach(s; *tm.members) if (s) s.accept(this); }
    override void visit(AliasDeclaration ad) { if (visitDsymbol(ad) && ad.aliassym) ad.aliassym.accept(this); }
    override void visit(VarDeclaration vd) { if (visitDsymbol(vd) && vd._init) vd._init.accept(this); }

    override void visit(ExpStatement s) { if (s.exp) s.exp.accept(this); }
    override void visit(ReturnStatement s) { if (s.exp) s.exp.accept(this); }
    override void visit(IfStatement s) { if (s.condition) s.condition.accept(this); if (s.ifbody) s.ifbody.accept(this); if (s.elsebody) s.elsebody.accept(this); }
    override void visit(WhileStatement s) { if (s.condition) s.condition.accept(this); if (s._body) s._body.accept(this); }
    override void visit(DoStatement s) { if (s.condition) s.condition.accept(this); if (s._body) s._body.accept(this); }
    override void visit(ForStatement s) { if (s._init) s._init.accept(this); if (s.condition) s.condition.accept(this); if (s.increment) s.increment.accept(this); if (s._body) s._body.accept(this); }
    override void visit(ForeachStatement s) { if (s.aggr) s.aggr.accept(this); if (s._body) s._body.accept(this); }
    override void visit(ForeachRangeStatement s) { if (s.lwr) s.lwr.accept(this); if (s.upr) s.upr.accept(this); if (s._body) s._body.accept(this); }
    override void visit(SwitchStatement s) { if (s.condition) s.condition.accept(this); if (s._body) s._body.accept(this); }
    override void visit(CaseStatement s) { if (s.exp) s.exp.accept(this); if (s.statement) s.statement.accept(this); }
    override void visit(GotoCaseStatement s) { if (s.exp) s.exp.accept(this); }
    override void visit(ThrowStatement s) { if (s.exp) s.exp.accept(this); }
    override void visit(SynchronizedStatement s) { if (s.exp) s.exp.accept(this); if (s._body) s._body.accept(this); }
    override void visit(WithStatement s) { if (s.exp) s.exp.accept(this); if (s._body) s._body.accept(this); }
    override void visit(CompoundStatement s) { if (s.statements) foreach(stmt; *s.statements) if (stmt) stmt.accept(this); }
    override void visit(ScopeStatement s) { if (s.statement) s.statement.accept(this); }
    override void visit(TryCatchStatement s) { if (s._body) s._body.accept(this); if (s.catches) foreach(c; *s.catches) if (c && c.handler) c.handler.accept(this); }
    override void visit(TryFinallyStatement s) { if (s._body) s._body.accept(this); if (s.finalbody) s.finalbody.accept(this); }
    override void visit(LabelStatement s) { if (s.statement) s.statement.accept(this); }

    override void visit(UnaExp e) { if (e.e1) e.e1.accept(this); }
    override void visit(BinExp e) { if (e.e1) e.e1.accept(this); if (e.e2) e.e2.accept(this); }
    override void visit(CallExp e) { if (e.e1) e.e1.accept(this); if (e.arguments) foreach(arg; *e.arguments) if (arg) arg.accept(this); }
    override void visit(ArrayExp e) { if (e.e1) e.e1.accept(this); if (e.arguments) foreach(arg; *e.arguments) if (arg) arg.accept(this); }
    override void visit(SliceExp e) { if (e.e1) e.e1.accept(this); if (e.lwr) e.lwr.accept(this); if (e.upr) e.upr.accept(this); }
    override void visit(ArrayLiteralExp e) { if (e.elements) foreach(el; *e.elements) if (el) el.accept(this); }
    override void visit(AssocArrayLiteralExp e) { if (e.keys) foreach(k; *e.keys) if (k) k.accept(this); if (e.values) foreach(v; *e.values) if (v) v.accept(this); }
    override void visit(StructLiteralExp e) { if (e.elements) foreach(el; *e.elements) if (el) el.accept(this); }
    override void visit(TupleExp e) { if (e.e0) e.e0.accept(this); if (e.exps) foreach(el; *e.exps) if (el) el.accept(this); }
    override void visit(CondExp e) { if (e.econd) e.econd.accept(this); if (e.e1) e.e1.accept(this); if (e.e2) e.e2.accept(this); }
    override void visit(NewExp e) { if (e.thisexp) e.thisexp.accept(this); if (e.arguments) foreach(arg; *e.arguments) if (arg) arg.accept(this); }
    override void visit(DeclarationExp e) { if (e.declaration) e.declaration.accept(this); }
    override void visit(FuncExp fe) { if (fe.fd) fe.fd.accept(this); }
    override void visit(ScopeExp se) { if (se.sds) se.sds.accept(this); }
    override void visit(DotTemplateInstanceExp dti) { if (dti.ti) dti.ti.accept(this); if (dti.e1) dti.e1.accept(this); }

    override void visit(ExpInitializer ei) { if (ei.exp) ei.exp.accept(this); }
    override void visit(StructInitializer si) { foreach(iz; si.value) if (iz) iz.accept(this); }
    override void visit(ArrayInitializer ai) { foreach(iz; ai.value) if (iz) iz.accept(this); }
}

private extern(C++) final class UnusedParamVisitor : DeepVisitor
{
    alias visit = typeof(super).visit;

    bool[void*] usedParams;

    extern(D) this(VarDeclaration[] paramsToTrack)
    {
        foreach (p; paramsToTrack)
            usedParams[cast(void*)p] = false;
    }

    override void visit(VarExp ve)
    {
        if (ve && ve.var)
        {
            auto ptr = cast(void*)ve.var;
            if (auto p = ptr in usedParams)
                *p = true;
        }
        super.visit(ve);
    }

    override void visit(SymOffExp se)
    {
        if (se && se.var)
        {
            auto ptr = cast(void*)se.var;
            if (auto p = ptr in usedParams)
                *p = true;
        }
        super.visit(se);
    }
}

extern(C++) final class LintVisitor : DeepVisitor
{
    alias visit = typeof(super).visit;

    LintFlags[] flagsStack;

    extern(D) this()
    {
        flagsStack ~= LintFlags.none;
    }

    LintFlags currentFlags()
    {
        return flagsStack.length > 0 ? flagsStack[$ - 1] : LintFlags.none;
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

    override void visit(PragmaDeclaration pd)
    {
        if (!visitDsymbol(pd)) return;
        bool pushed = pushLintFlags(pd);

        if (pd.decl)
            foreach (s; *pd.decl)
                if (s) s.accept(this);

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

        if (ps._body)
            ps._body.accept(this);

        if (pushed)
            flagsStack.length--;
    }

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

    private void lintFunc(FuncDeclaration fd)
    {
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
                fd.fbody.accept(paramVisitor);

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

    override void visit(FuncDeclaration fd)
    {
        if (!visitDsymbol(fd)) return;
        lintFunc(fd);
    }

    override void visit(FuncLiteralDeclaration fd)
    {
        if (!visitDsymbol(fd)) return;
        lintFunc(fd);
    }

    override void visit(CtorDeclaration fd)
    {
        if (!visitDsymbol(fd)) return;
        lintFunc(fd);
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