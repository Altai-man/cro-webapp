use Cro::WebApp::Template::AST;

class Cro::WebApp::Template::ASTBuilder {
    method TOP($/) {
        my @prelude;
        unless $*COMPILING-PRELUDE {
            my $loaded-prelude = await $*TEMPLATE-REPOSITORY.resolve-prelude();
            @prelude[0] = Prelude.new:
                    exported-subs => $loaded-prelude.exports<sub>.keys,
                    exported-macros => $loaded-prelude.exports<macro>.keys;
        }
        make Template.new(children => [|@prelude, |flatten-literals($<sequence-element>.map(*.ast))]);
    }

    method sequence-element:sym<sigil-tag>($/) {
        make $<sigil-tag>.ast;
    }

    method sequence-element:sym<literal-text>($/) {
        make Literal.new(text => ~$/);
    }

    method sequence-element:sym<literal-open-tag>($/) {
        my @elements = flatten-literals flat
            Literal.new(text => '<'),
            $<tag-element>.map(*.ast),
            Literal.new(text => '>');
        make @elements == 1 ?? @elements[0] !! Sequence.new(children => @elements);
    }

    method sequence-element:sym<literal-close-tag>($/) {
        make Literal.new(text => ~$/);
    }

    method tag-element:sym<sigil-tag>($/) {
        make $<sigil-tag>.ast;
    }

    method tag-element:sym<literal>($/) {
        make Literal.new(text => ~$/);
    }

    method sigil-tag:sym<topic>($/) {
        my $derefer = $<deref>.ast;
        make escape($derefer(VariableAccess.new(name => '$_')));
    }

    method sigil-tag:sym<variable>($/) {
        my $derefer = $<deref> ?? $<deref>.ast !! { $_ };
        make escape($derefer(VariableAccess.new(name => '$' ~ $<identifier>)));
    }

    method sigil-tag:sym<iteration>($/) {
        my $derefer = $<deref>.ast;
        my $iteration-variable = $<iteration-variable>.ast;
        make Iteration.new:
            target => $derefer(VariableAccess.new(name => '$_')),
            :$iteration-variable,
            children => flatten-literals($<sequence-element>.map(*.ast),
                :trim-trailing-horizontal($*lone-end-line)),
            trim-trailing-horizontal-before => $*lone-start-line;
    }

    method sigil-tag:sym<condition>($/) {
        my $condition = do if $<deref> {
            my $derefer = $<deref>.ast;
            $derefer(VariableAccess.new(name => $<identifier> ?? '$' ~ $<identifier> !! '$_'))
        }
        elsif $<identifier> {
            VariableAccess.new(name => '$' ~ $<identifier>)
        }
        else {
            $<expression>.ast
        }
        make Condition.new:
            negated => $<negate> eq '!',
            condition => $condition,
            children => flatten-literals($<sequence-element>.map(*.ast),
                :trim-trailing-horizontal($*lone-end-line)),
            trim-trailing-horizontal-before => $*lone-start-line;
    }

    method sigil-tag:sym<sub>($/) {
        make TemplateSub.new:
                name => ~$<name>,
                parameters => $<signature> ?? $<signature>.ast !! (),
                children => flatten-literals($<sequence-element>.map(*.ast),
                        :trim-trailing-horizontal($*lone-end-line)),
                trim-trailing-horizontal-before => $*lone-start-line;
    }

    method sigil-tag:sym<call>($/) {
        make Call.new:
                target => ~$<target>,
                arguments => $<arglist> ?? $<arglist>.ast !! ();
    }

    method sigil-tag:sym<macro>($/) {
        make TemplateMacro.new:
                name => ~$<name>,
                parameters => $<signature> ?? $<signature>.ast !! (),
                children => flatten-literals($<sequence-element>.map(*.ast),
                        :trim-trailing-horizontal($*lone-end-line)),
                trim-trailing-horizontal-before => $*lone-start-line;
    }

    method sigil-tag:sym<apply>($/) {
        make MacroApplication.new:
                target => ~$<target>,
                arguments => $<arglist> ?? $<arglist>.ast !! (),
                children => flatten-literals($<sequence-element>.map(*.ast),
                        :trim-trailing-horizontal($*lone-end-line)),
                trim-trailing-horizontal-before => $*lone-start-line;
    }

    method sigil-tag:sym<body>($/) {
        make MacroBody.new;
    }

    method sigil-tag:sym<use>($/) {
        with $<file> {
            my $template-name = .ast;
            my $used = await $*TEMPLATE-REPOSITORY.resolve($template-name);
            make UseFile.new: :$template-name,
                    exported-subs => $used.exports<sub>.keys,
                    exported-macros => $used.exports<macro>.keys;
        }
        orwith $<library> {
            my $module-name = .ast;
            make UseModule.new: :$module-name;
        }
    }

    method module-name($/) {
        make ~$/;
    }

    method signature($/) {
        make $<parameter>.map(*.ast).list;
    }

    method parameter($/) {
        make TemplateParameter.new:
                name => ~$<name>,
                named => ?$<named>,
                default => $<default> ?? $<default>.ast !! Nil;
    }

    method arglist($/) {
        make $<arg>.map(*.ast);
    }

    method arg:by-pos ($/) {
        make ByPosArgument.new(argument => $<expression>.ast);
    }

    method arg:by-name ($/) {
        my $argument;
        with $<var-name> {
            $argument = VariableAccess.new(name => ~$_);
        }
        orwith $<expression> {
            $argument = .ast;
        }
        else {
            $argument = BoolLiteral.new(value => !$<negated>);
        }
        make ByNameArgument.new(name => ~$<identifier>, :$argument);
    }

    method term:sym<single-quote-string>($/) {
        make Literal.new(text => $<single-quote-string>.ast);
    }

    method term:sym<integer>($/) {
        make IntLiteral.new(value => +$/);
    }

    method term:sym<rational>($/) {
        make RatLiteral.new(value => +$/);
    }

    method term:sym<num>($/) {
        make NumLiteral.new(value => +$/);
    }

    method term:sym<bool>($/) {
        make BoolLiteral.new(value => $/ eq 'True');
    }

    method term:sym<variable>($/) {
        my $var = VariableAccess.new(name => ~$<name>);
        make $<deref>
                ?? $<deref>.ast()($var)
                !! $var;
    }

    method term:sym<deref>($/) {
        my $derefer = $<deref>.ast;
        make $derefer(VariableAccess.new(name => '$_'));
    }

    method expression($/) {
        make Expression.new:
                terms => $<term>.map(*.ast),
                infixes => $<infix>.map(~*);
    }

    method term:sym<argument>($/) {
        make $<argument>.ast;
    }

    method term:sym<parens>($/) {
        make $<expression>.ast;
    }

    method deref($/) {
        make -> $initial {
            my $target = $initial;
            for @<deref-item> {
                $target = .ast()($target);
            }
            $target
        }
    }

    method deref-item:sym<method>($/) {
        make -> $target {
            LiteralMethodDeref.new: :$target, symbol => ~$<identifier>
        }
    }

    method deref-item:sym<smart>($/) {
        make -> $target {
            SmartDeref.new: :$target, symbol => ~$/
        }
    }

    method deref-item:sym<hash-literal>($/) {
        make -> $target {
            HashKeyDeref.new: :$target, key => Literal.new(text => ~$/)
        }
    }

    method deref-item:sym<array>($/) {
        make -> $target {
            ArrayIndexDeref.new: :$target, index => $<index>.ast
        }
    }

    method deref-item:sym<hash>($/) {
        make -> $target {
            make HashKeyDeref.new: :$target, key => $<key>.ast
        }
    }

    method single-quote-string($/) {
        make ~$/;
    }

    sub flatten-literals(@children, :$trim-trailing-horizontal) {
        my @squashed;
        my $last-lit = '';
        for @children {
            when Literal {
                $last-lit ~= .text;
            }
            default {
                if $last-lit {
                    push @squashed, Literal.new:
                        text => .trim-trailing-horizontal-before
                            ?? $last-lit.subst(/\h+$/, '')
                            !! $last-lit;
                    $last-lit = '';
                }
                push @squashed, $_;
            }
        }
        if $last-lit {
            push @squashed, Literal.new:
                text => $trim-trailing-horizontal
                    ?? $last-lit.subst(/\h+$/, '')
                    !! $last-lit;
        }
        return @squashed;
    }

    sub escape($target) {
        $*IN-ATTRIBUTE
            ?? EscapeAttribute.new(:$target)
            !! EscapeText.new(:$target)
    }
}
