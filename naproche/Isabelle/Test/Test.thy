(*
Authors: Makarius Wenzel (2018)

Some Isabelle/Naproche examples for testing.
*)

section \<open>Naproche-SAD texts within the Isabelle context\<close>

theory Test
  imports Naproche.Naproche
begin

subsection \<open>Inlined text\<close>

forthel \<open>
[synonym subset/-s] [synonym surject/-s]

Let M denote a set.
Axiom. M is setsized.
Let f denote a function.
Let the value of f at x stand for f(x).
Let f is defined on M stand for Dom(f) = M.
Let the domain of f stand for Dom(f).

Axiom. Let x be an element of M. x is setsized.
Axiom. The value of f at any element of the domain of f is a set.

Definition.
A subset of M is a set N such that every element of N is an element of M.

Definition.
The powerset of M is the class of subsets of M.

Axiom. The powerset of M is a set.

Definition.
f surjects onto M iff every element of M is equal to the value of f at some element of the domain of f.

Proposition.
No function that is defined on M surjects onto the powerset of M.
Proof by contradiction.
Assume the contrary. Take a function f that is defined on M and surjects onto the powerset of M.
Define N = { x in M | x is not an element of f(x) }.
Then N is not equal to the value of f at any element of M.
Contradiction. qed.

Theorem. The value of f at any element of the domain of f is a set.
\<close>


subsection \<open>External text file\<close>

context notes [[naproche_prove = false]]
begin

forthel_file \<open>$NAPROCHE_HOME/examples/cantor.ftl\<close>
forthel_file \<open>$NAPROCHE_HOME/examples/cantor.ftl.tex\<close>

end

end
