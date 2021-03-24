# This module implements the Morse-Kelley (MK) set theory,
# an extension of ZFC. Any lemma that can be proven in ZFC
# also can be proven in MK, but unlike ZFC, MK is finitely axiomatizable,
# that is, we can describe it without using schemata over arbitrary formulas.
# The axiom schema of class formation has been omitted in this presentation
# because it is built into the compiler.

[synonym relation/-s]
[synonym function/-s]
[synonym element/-s]

Let B, C, D, E denote classes.
Let b, c, d, e denote sets.
Let w, x, y, z denote objects.

Axiom. b is a class.
Axiom. b is an object.

Definition. Let x be an object. 
  x is in B iff x is an element of B.

# This axiom is implicitly used in the compiler.
Axiom Ext. If x is an element of C iff x is an element of B then C = B.

Signature. The empty set is a set.
Axiom Empty. x is not an element of the empty set.
Lemma. The empty set is { u | u != u }.

Definition. B is nonempty iff there is a x such that x is in B.
Lemma. If B is nonempty then B is not the empty set.
Definition. B is empty iff B is not nonempty.
Lemma. B is empty iff B is { u | u != u }.

Signature. The pair of x and y is a set.
Axiom Pair. x is in the pair of y and z iff x = y or x = z.
Lemma. The pair of x and y is { u | u = x or u = y }.
Definition. The singleton of x is the pair of x and x.

Definition. The ordered pair of x and y is the pair of x and the pair of x and y.
Definition. (x, y) is the ordered pair of x and y.
Lemma OrdPair. If the ordered pair of x and y is equal to the ordered pair of z and w
  then x = z and y = w.

Signature. The union of b is a set.
Axiom Union. b is the union of d iff (x is in b iff there is a c 
  such that c is in d and x is in c).
Signature. The union of c and b is a set.
Axiom UnionIntro. c is the union of d and b iff c is the union of the pair of d and b.

Signature. A subclass of B is a class.
Axiom SubclassIntro. C is a subclass of B iff
  for all x if x is an element of C then x is an element of B.

Signature. The powerset of b is a set.
Axiom PowerSet. b is the powerset of d iff (c is in b iff c is a subclass of d).

Definition. The successor of b is the pair of b and the singleton of b.
Axiom Inf. There is a set n such that the empty set is in n and for every b
  such that b is in n the successor of b is in n.

Definition. The product of C and B is { (u, v) | u is a object and v is a object and u is in C and v is in B }.
Signature. A relation is a class.
Axiom RelationIntro. C is a relation iff for every x such that x is in C
  there is a y such that there is a z such that x is the ordered pair of y and z.

Let R, S denote relations.
Definition. The domain of R is { u | there is a object v such that (u, v) is in R }.
Definition. The Range  of R is { v | there is a object u such that (u, v) is in R }.
# Definition. The field  of R is the union of the domain of R and the Range of R.
Definition. The restriction of R to B is { (u, v) | u is a object and v is a object and (u, v) is in R and u is in B }.
Definition. The    image of B under R is { v | there is a object u such that u is in B and (u, v) is in R }.
Definition. The preimage of B under R is { u | there is a object v such that v is in B and (u, v) is in R }.
Definition. The composition of S and R is { (x, z) | x is a object and z is a set and there is a object y such that (x, y) is in R and (y, z) is in S }.
Definition. The inverse of R is { (y, x) | x is a object and y is a object and (x, y) is in R }.
Definition. Dom(R) is the domain of R.
Definition. Ran(R) is the range of R.
# Definition. field(R) is the field of R.
Definition. R[B] is the image of B under R.
Definition. R^{-1} is the inverse of R.

# Definition. R is reflexive iff for all x such that x is in the field of R (x, x) is in R.
# Definition. R is irreflexive iff for all x such that x is in the field of R (x, x) is not in R.
Definition. R is symmetric iff for all x, y such that (x, y) is in R (y, x) is in R.
Definition. R is antisymmetric iff for all x, y such that (x, y) is in R and (y, x) is in R x = y.
Definition. R is transitive iff for all x, y, z such that (x, y) is in R and (y, z) is in R (x, z) is in R.
Definition. R is connex iff for all x, y such that x,y are in R
  (x, y) is in R or (y, x) is in R or x = y.

Signature. A function is a relation.
Axiom FunctionIntro. R is a function iff for all x, y, z such that (x, y) is in R and (x, z) is in R y = z.

Let F, G denote functions.
Definition. F at x is a object y such that (x, y) is in F.
Definition. F[x] is F at x.

Axiom Choice. Let c be a set such that for all b such that b is in c b is nonempty.
  There exists a function F such that Dom(F) = c
  and for all x such that x is in c there is a set d such that x is in d and d is F at x.

Axiom Replacement. The restriction of F to c is a set.

Definition. The intersection of B is { v | for every set u such that u is in B v is in u }.
Definition. The intersection of c and b is the intersection of the pair of c and b.
Axiom Restriction. If c is nonempty then there is a b such that b is in c and
  (the intersection of c and b) is empty.