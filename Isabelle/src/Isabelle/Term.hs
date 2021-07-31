{- generated by Isabelle -}

{-  Title:      Isabelle/Term.hs
    Author:     Makarius
    LICENSE:    BSD 3-clause (Isabelle)

Lambda terms, types, sorts.

See also "$ISABELLE_HOME/src/Pure/term.scala".
-}

{-# LANGUAGE OverloadedStrings #-}

module Isabelle.Term (
  Indexname,

  Sort, dummyS,

  Typ(..), dummyT, is_dummyT, Term(..))
where

import Isabelle.Bytes (Bytes)


type Indexname = (Bytes, Int)


type Sort = [Bytes]

dummyS :: Sort
dummyS = [""]


data Typ =
    Type (Bytes, [Typ])
  | TFree (Bytes, Sort)
  | TVar (Indexname, Sort)
  deriving Show

dummyT :: Typ
dummyT = Type ("dummy", [])

is_dummyT :: Typ -> Bool
is_dummyT (Type ("dummy", [])) = True
is_dummyT _ = False


data Term =
    Const (Bytes, [Typ])
  | Free (Bytes, Typ)
  | Var (Indexname, Typ)
  | Bound Int
  | Abs (Bytes, Typ, Term)
  | App (Term, Term)
  deriving Show
