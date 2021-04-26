# Proving in Naproche

Naproche is a proof system that accepts a version of natural language as input and produces proof obligations
from it that is checked by an external automatic theorem prover (ATP) like `eprover`.
It uses [typed first order logic](http://users.cecs.anu.edu.au/~baumgart/publications/TFFArith.pdf) with automatic inference of coercions.
This document describes the structure of a Naproche proof. The syntax is best learned through experience,
examples can be found in the `examples` directory.

## Signatures, Axioms, Theorems

## Type system

Every variable in Naproche as an associated `type`. Possible types are introduced by signatures
or the default type `object`. When you define a term `X(a, b)`, Naproche will consider the types
of the variables `a,b` during definition and check that they match the types of `c,d` when using `X(c,d)`.
Here, we allow *coercions* that were defined before like `Every natural number is a rational number`.
Furthermore, every variable can be coerced to type `object`. 
While you can completely eliminate type checking by using objects
throughout, it helps to be specific since this reduces the search space for the ATP.
Advanced coersions that depend on several conditions to hold (e.g. `Every integer that is non-negative is a natural number`)
can not be inferred automatically (though this may change in the future).

It is also possible to define functions with the same name several times, but this can quickly
lead to ambiguities: For two functions `X : a -> b -> d` and `X : c -> a -> d` and coercions
`a -> c` and `a -> b` it is not possible to find the correct coercions. Thus we require that
whenever for two tuples of coercions `c_1, c_2` such that `type(X \circ c_1) = type(X \circ c_2)` we have
that either `c_1` xor `c_2` consists only of identity functions (that is, one function is strictly
more general than the other and they don't have the same type).

## Set Theory

Naproche uses von Neumann-Bernays-Gödel set theory, which you can access by including `nbg.ftl`.
The axiom of class comprehension is built-in: Any use of the syntax `z = { x | f(x) }` will be 
translated as `∀x in(x, z) iff f(x)`.
Crucially this is also used for induction in the new version. While Naproche had a primitve for
induction built-in for a long time, this version instead champions an approach based on classes:
For example, the induction principle over the natural numbers looks like this:
`∀ [c : class] 0 \in c and (∀ [n : nat] n \in c implies (n + 1) \in c) \implies (∀ [n : nat] n \in c)`.

## Proofs

A theorem with statement (or *goal*) `g` will be directly converted to a proof task for `g` and given to the external prover.
But often the external prover will not succeed and it will be necessary to use a `Proof. ... qed.` block.
In such a situation, you have two choices:

First, you can state a claim `h` which will then by proven by the ATP and afterwards be added as a hypothesis.
This is especially useful if the proof contains several big steps which you would like to guide the ATP through.
It is possible to add a term `(by thm1)` at the end of the claim. Then we will instruct the ATP to consider this
`thm1` as important. That is useful if `thm1` as very dissimilar (in terms of occurring terms in this theorem)
from the claim and will thus likely not be chosen by the heuristics in the ATP. You can often find more information
about the heuristic in the ATPs manual.

Second, you can transform the goal `g` by a *tactic*. There are a few useful tactics implemented in Naproche:

If the goal is of the form `forall x (isXY(x) => y)` you can write `Let x be xy.` to transform the goal into `y`
and add `isXY(x)` as a hypothesis. Since ATPs can do that themselves this is most useful in combination with other tactics.

If the goal is of the form `y` and there is a theorem `thm: x => y` you can write `Use thm.` to transform the goal
into `x`. A typical application of this is to assume an induction principle `induction` and `Use induction.`.

If the goal is a conjunction of terms (e.g.`x and (y => z)`) you can write `Case x.` and a bit later `Case y.` 
to focus on each case seperately.

## Proof objects

Naproche can emit proof objects for each named lemma in a file if you add the `-p` option.
This is in tstp format and can be checked with external tools.
To improve the quality of these objects (and also the translation output) you can give
names to symbols, for example: `[translate_as add_nat]` before a definition of `+ : Nat -> Nat -> Nat`.