{-
Authors: Makarius Wenzel (2021)

The Naproche logic within Isabelle/HOL.
-}

{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NamedFieldPuns #-}

module SAD.Data.Formula.HOL (
  base_type, prop_type, export_formula,
  type_terms, type_term, print_terms, print_term
)
where

import SAD.Data.VarName (VariableName (..))
import SAD.Data.Text.Decl (Decl (..))
import SAD.Data.Terms
import SAD.Data.Formula.Base

import Isabelle.Bytes (Bytes)
import qualified Isabelle.Value as Value
import qualified Isabelle.Name as Isabelle
import qualified Isabelle.Term as Isabelle
import Isabelle.Term ((--->))
import qualified Isabelle.HOL as Isabelle
import qualified Isabelle.Naproche as Isabelle
import Isabelle.Library
import qualified Naproche.Program as Program
import qualified Isabelle.YXML as YXML
import qualified Isabelle.Term_XML.Encode as Encode
import qualified Isabelle.Term_XML.Decode as Decode


{- export formula -}

base_type, prop_type :: Isabelle.Typ
base_type = Isabelle.iT
prop_type = Isabelle.boolT

variable_name :: VariableName -> Isabelle.Name
variable_name (VarConstant s) = "x" <> make_bytes s
variable_name (VarHole s) = Isabelle.internal ("HOLE_" <> make_bytes s)
variable_name VarSlot = Isabelle.internal "SLOT"
variable_name (VarU s) = "u" <> make_bytes s
variable_name (VarHidden n) = "h" <> Value.print_int n
variable_name (VarAssume n) = "i" <> Value.print_int n
variable_name (VarSkolem n) = "o" <> Value.print_int n
variable_name (VarTask s) = "c" <> variable_name s
variable_name (VarZ s) = "z" <> make_bytes s
variable_name (VarW s) = "w" <> make_bytes s
variable_name VarEmpty = Isabelle.uu_
variable_name (VarDefault s) = make_bytes s

term_name :: TermName -> Isabelle.Name
term_name (TermName t) = make_bytes t
term_name (TermSymbolic t) = "s" <> make_bytes t
term_name (TermNotion t) = "a" <> make_bytes t
term_name (TermThe t) = "the" <> make_bytes t
term_name (TermUnaryAdjective t) = "is" <> make_bytes t
term_name (TermMultiAdjective t) = "mis" <> make_bytes t
term_name (TermUnaryVerb t) = "do" <> make_bytes t
term_name (TermMultiVerb t) = "mdo" <> make_bytes t
term_name (TermTask n) = "tsk " <> Value.print_int n
term_name TermEquality = "="
term_name TermLess  = "iLess"
term_name TermSmall = "isSetSized"
term_name TermThesis = "#TH#"
term_name TermEmpty = ""

export_formula :: Formula -> Isabelle.Term
export_formula = Isabelle.mk_trueprop . form
  where
    form :: Formula -> Isabelle.Term
    form (All Decl{declName = x} b) = Isabelle.mk_all_op base_type (abs x (form b))
    form (Exi Decl{declName = x} b) = Isabelle.mk_ex_op base_type (abs x (form b))
    form (Iff a b) = Isabelle.mk_iff (form a) (form b)
    form (Imp a b) = Isabelle.mk_imp (form a) (form b)
    form (Or a b) = Isabelle.mk_disj (form a) (form b)
    form (And a b) = Isabelle.mk_conj (form a) (form b)
    form (Tag _ a) = form a
    form (Not a) = Isabelle.mk_not (form a)
    form Top = Isabelle.true
    form Bot = Isabelle.false
    form Trm{trmName = TermEquality, trmArgs = [a, b]} = Isabelle.mk_eq base_type (term a) (term b)
    form Trm{trmName = name, trmArgs = args} = app name (map term args) prop_type
    form Var{varName = x} = free x prop_type
    form Ind{indIndex = i} = Isabelle.Bound i
    form ThisT = Isabelle.mk_this prop_type

    term :: Formula -> Isabelle.Term
    term Trm{trmName = name, trmArgs = args} = app name (map term args) base_type
    term Var{varName = x} = free x base_type
    term Ind{indIndex = i} = Isabelle.Bound i
    term ThisT = Isabelle.mk_this base_type
    term (Tag _ a) = term a
    term _ = error "Bad formula as term"

    free :: VariableName -> Isabelle.Typ -> Isabelle.Term
    free x ty = Isabelle.Free (variable_name x, ty)

    abs :: VariableName -> Isabelle.Term -> Isabelle.Term
    abs x body = Isabelle.Abs (variable_name x, base_type, body)

    app :: TermName -> [Isabelle.Term] -> Isabelle.Typ -> Isabelle.Term
    app name args res_type = Isabelle.list_comb op args
      where
        op = Isabelle.Free (term_name name, ty)
        ty = replicate (length args) base_type ---> res_type


{- Isabelle term operations -}

type_terms :: Program.Context -> [Isabelle.Term] -> IO [Isabelle.Typ]
type_terms = Program.yxml_pide_command Encode.term Decode.typ Isabelle.type_terms_command

type_term :: Program.Context -> Isabelle.Term -> IO Isabelle.Typ
type_term = singletonM . type_terms

print_terms :: Program.Context -> [Isabelle.Term] -> IO [Bytes]
print_terms = Program.yxml_pide_command Encode.term YXML.string_of_body Isabelle.print_terms_command

print_term :: Program.Context -> Isabelle.Term -> IO Bytes
print_term = singletonM . print_terms
