{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE DeriveGeneric #-}

module SAD.Core.Typed
 ( InType(..), OutType(..), Type(..)
 , Term(..), Proof, Located(..), Prf(..)
 , PrfBlock(..), ProofBlock
 , Statement, Stmt(..), Operator(..)
 , simp, bindFree, termify, bindExists, desugerClasses
 ) where

import Data.Text (Text)
import qualified Data.Text as Text
import Data.Functor.Identity
import GHC.Generics (Generic)
import Data.Hashable (Hashable)
import Data.Binary (Binary)
import qualified Data.List as L
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.Map as Map
import Data.Functor.Const
import Data.Bifunctor (bimap)
import Control.DeepSeq (NFData)
import SAD.Core.SourcePos (noSourcePos)

import SAD.Data.VarName
import SAD.Data.Terms
import SAD.Core.Pretty (Pretty(..))
import SAD.Core.SourcePos (SourcePos)
import SAD.Helpers (inParens)

-- | Types that can be used as input in a TFF declaration 
newtype InType 
  = Signature TermName -- ^ introduced by signature
  deriving (Eq, Ord, Show, Read, Generic)
instance NFData InType
instance Hashable InType
instance Binary InType

-- | Types that can be used as output in a TFF declaration
-- except $tType since Sorts are handled seperately.
data OutType = Prop | InType InType
  deriving (Eq, Ord, Show, Read, Generic)
instance NFData OutType
instance Hashable OutType
instance Binary OutType

-- | A type for a term in TFF.
data Type = Sort | Pred [InType] OutType
  deriving (Eq, Ord, Show, Read, Generic)
instance NFData Type
instance Hashable Type
instance Binary Type

-- | Operators, both built-in and user-defined.
-- This does not yet include numerical operators with special support
-- in tff like '$sum'. Applications will be checked to have the correct
-- number of correctly typed arguments.
-- Danger: We assume that except for OpTrm all constructors are logical operators
-- in the type checking!
data Operator
  = And | Or | Not | Imp | Iff | Top | Bot | Eq
  | OpTrm TermName
  deriving (Eq, Ord, Show, Read, Generic)
instance NFData Operator
instance Hashable Operator
instance Binary Operator

-- | An AST of typed first order form.
-- During the first parse we will have f = Const (),
-- then we might accumulate type information (f = [] or f = Set)
-- and when all types are resolved we have f = Identity
-- We start out with t = Tag and end up with t = () once all
-- tag information is processed.
data Term f t
  = Forall VarName (f InType) (Term f t)
  | Exists VarName (f InType) (Term f t)
  | Class VarName (f InType) (Term f t)
  | App Operator [Term f t]
  | Tag t (Term f t)
  | Var VarName
deriving instance (Eq (f InType), Eq t) => Eq (Term f t)
deriving instance (Ord (f InType), Ord t) => Ord (Term f t)
deriving instance (Show (f InType), Show t) => Show (Term f t)
deriving instance (Read (f InType), Read t) => Read (Term f t)
deriving instance (Generic (f InType), Generic t) => Generic (Term f t)
instance (Generic (f InType), Generic t, Hashable (f InType), Hashable t) => Hashable (Term f t)
instance (Generic (f InType), Generic t, Binary (f InType), Binary t) => Binary (Term f t)
instance (Generic (f InType), Generic t, NFData (f InType), NFData t) => NFData (Term f t)

-- | Information for the user: Name of a lemma/axiom/sort/.. and position.
data Located a = Located
  { locName :: Text
  , locPos :: SourcePos
  , located :: a
  } deriving (Eq, Ord, Show, Generic)
instance NFData a => NFData (Located a)

-- | A block in Naproche text can contain several statements:
-- The declaration of a notion, a predicate, axiom or claim.
-- For example, defining 'p(x) iff q' will yield a predicate (p : x -> Prop)
-- and an axiom 'p(x) iff q'.
-- Note that we don't check the term of the claim but only the proof block.
data Stmt f t
  = IntroSort TermName
  | Predicate TermName -- ^ symbol declaration
    [InType] -- ^ the types of the arguments
    OutType -- ^ the return type
  | Axiom (Term f t)
  | Claim (Term f t) (PrfBlock f t)
  | Coercion 
    TermName -- ^ name of coercion
    TermName -- ^ from notion
    TermName -- ^ to notion
deriving instance (Eq (f InType), Eq t) => Eq (Stmt f t)
deriving instance (Ord (f InType), Ord t) => Ord (Stmt f t)
deriving instance (Show (f InType), Show t) => Show (Stmt f t)
deriving instance (Generic (f InType), Generic t) => Generic (Stmt f t)
instance (Generic (f InType), Generic t, NFData (f InType), NFData t) => NFData (Stmt f t)

type Statement = Located (Stmt Identity ())

-- | A proof block with the last claim that is to be proven
-- under the tactics given in the list of proofs (the "goal").
-- This will either be a reduction of the claim it belongs to
-- or 'Bot' if we are in a proof by contradiction.
data PrfBlock f t
  = Proving [Located (Prf f t)] (Term f t) 
    [Text] -- ^ links: theorems that may be useful for proving this claim
deriving instance (Eq (f InType), Eq t) => Eq (PrfBlock f t)
deriving instance (Ord (f InType), Ord t) => Ord (PrfBlock f t)
deriving instance (Show (f InType), Show t) => Show (PrfBlock f t)
deriving instance (Generic (f InType), Generic t) => Generic (PrfBlock f t)
instance (Generic (f InType), Generic t, NFData (f InType), NFData t) => NFData (PrfBlock f t)

-- | A proof consists of sub-claims that will be given directly to the ATP
-- and a number of tactics.
-- Danger: If the proof of the subclaim is not empty we will not check
-- the subclaim seperately but assume that the proof contains the subclaim 
-- as its last subclaim (similarly to how we handle claims).
-- Intro, assume and ByContradiction are special, because the modify
-- the goal without needing to be proven.
data Prf f t
  = Subclaim (Term f t) (PrfBlock f t)
  | Intro VarName InType
  | Assume (Term f t)
  | Choose [(VarName, InType)] (Term f t) (PrfBlock f t)
  | Cases [(Term f t, PrfBlock f t)]
  | TerminalCases [(Term f t, PrfBlock f t)]
  | ByContradiction (Term f t) -- ^ contradict the current goal
deriving instance (Eq (f InType), Eq t) => Eq (Prf f t)
deriving instance (Ord (f InType), Ord t) => Ord (Prf f t)
deriving instance (Show (f InType), Show t) => Show (Prf f t)
deriving instance (Generic (f InType), Generic t) => Generic (Prf f t)
instance (Generic (f InType), Generic t, NFData (f InType), NFData t) => NFData (Prf f t)

type ProofBlock = PrfBlock Identity ()
type Proof = Located (Prf Identity ())

-- | Simplify a formula for nicer pretty-printing.
simp :: Term f t -> Term f t
simp = \case
  Forall v t tr -> case simp tr of
    App Top [] -> App Top []
    App Bot [] -> App Bot []
    tr' -> Forall v t tr'
  Exists v t tr -> case simp tr of
    App Top [] -> App Top []
    App Bot [] -> App Bot []
    tr' -> Exists v t tr'
  Class v m tr -> Class v m (simp tr)
  App And [App Top [], b] -> simp b
  App And [a, App Top []] -> simp a
  App And [App Bot [], _] -> App Bot []
  App And [_, App Bot []] -> App Bot []
  App Or  [App Top [], _] -> App Top []
  App Or  [_, App Top []] -> App Top []
  App Or  [App Bot [], b] -> simp b
  App Or  [a, App Bot []] -> simp a
  App Imp [App Top [], b] -> simp b
  App Imp [_, App Top []] -> App Top []
  App Imp [App Bot [], _] -> App Top []
  App Imp [a, App Bot []] -> simp $ App Not [a]
  App Iff [App Top [], b] -> simp b
  App Iff [a, App Top []] -> simp a
  App Iff [App Bot [], b] -> simp $ App Not [b]
  App Iff [a, App Bot []] -> simp $ App Not [a]
  App Not [App Not [a]] -> a
  Tag t a -> Tag t $ simp a
  t -> t

-- | Bind free variables by forall quantifiers
-- and turn all bound variables into 'TermVar's.
bindFree :: Set VarName -> Term (Const ()) t -> Term (Const ()) t
bindFree bound t = bind $ findFree bound t
  where
    bind (vars, tr) = foldr (\v t -> Forall v (Const ()) t) tr $ Set.toList $ fvToVarSet $ vars

-- | Make all the given variables terms.
termify :: Set VarName -> Term f t -> Term f t
termify bound = snd . findFree bound

-- | Find free variables not bound in the given set
-- and turn the bound variables into TermVars.
findFree :: Set VarName -> Term f t -> (FV VarName, Term f t)
findFree bound = free
  where
    free = \case
      Forall v f t -> bimap (bindVar v) (Forall v f) $ free t
      Exists v f t -> bimap (bindVar v) (Exists v f) $ free t
      Class  v f t -> bimap (bindVar v) (Class  v f) $ free t
      App op args -> bimap mconcat (App op) $ unzip $ free <$> args
      Tag tag t -> Tag tag <$> free t
      Var v -> if v `Set.member` bound 
        then (mempty, App (OpTrm (TermVar v)) [])
        else (unitFV v noSourcePos, Var v)

-- | Bind free variables by exists quantifiers.
bindExists :: [VarName] -> Term (Const ()) t -> Term (Const ()) t
bindExists vs tr = foldr (\v -> Exists v (Const ())) tr vs

-- | Given an infinite stream of TermNames,
-- replace each class {x | c} by a new operator cls in a term t and return
-- ((rest of the variables, [∀x x\in cls iff c]), t')
-- If classes are nested, we will return the outermost first.
desugerClasses :: [TermName] -> Term f t -> (([TermName], [(TermName, [f InType], Term f t)]), Term f t)
desugerClasses = go mempty 
  where 
    go typings vars = \case
      Forall v m t -> Forall v m <$> go (Map.insert v m typings) vars t 
      Exists v m t -> Exists v m <$> go (Map.insert v m typings) vars t 
      Class v m t -> 
        let (cls:clss) = vars
            ((clss', stmts), t') = go (Map.insert v m typings) clss t
            free = Map.toList $ Map.fromSet (typings Map.!) $ fvToVarSet $ bindVar v $ fst $ findFree mempty t'
            clsTrm = App (OpTrm cls) $ map (Var . fst) free
            ext = Forall v m $ App Iff [App (OpTrm (TermNotion "ElementOf")) [Var v, clsTrm] , t' ]
            ext' = foldr (\(v, m) -> Forall v m) ext free
        in ((clss', (cls, map snd free, ext'):stmts), clsTrm)
      App op ts ->
        let (st, ts') = L.mapAccumL (\(v, ax) t -> 
              let ((v', ax'), t') = go typings v t in ((v', ax ++ ax'), t'))
              (vars, []) ts
        in (st, App op ts')
      Tag tag t -> Tag tag <$> go typings vars t 
      Var v -> ((vars, []), Var v)

instance Pretty InType where
  pretty (Signature t) = pretty t

instance Pretty OutType where
  pretty (InType t) = pretty t
  pretty Prop = "Prop"

instance Pretty Type where
  pretty Sort = "Sort"
  pretty (Pred [] t) = pretty t
  pretty (Pred is t) = 
    Text.intercalate " → " (map pretty is) <> " → " <> pretty t

-- | TODO: This approach is not nice for nested indentations.
renderLines :: [Text] -> Text
renderLines [] = ""
renderLines xs = Text.unlines ("":map ("  " <>) xs)

instance (Pretty (f InType), Show t, Show (f InType)) 
  => Pretty (Term f t) where
  pretty (Forall v t tr) = "(∀[" <> pretty v <> " : " 
    <> pretty t <> "] " <> pretty tr <> ")"
  pretty (Exists v t tr) = "(∃[" <> pretty v <> " : " 
    <> pretty t <> "] " <> pretty tr <> ")"
  pretty (Class v t tr) = "{ " <> pretty v <> " : "
    <> pretty t <> " | " <> pretty tr <> " }"
  pretty (App And [a, b]) = "(" <> pretty a <> " and " <> pretty b <> ")"
  pretty (App Or  [a, b]) = "(" <> pretty a <> " or " <> pretty b <> ")"
  pretty (App Iff [a, b]) = "(" <> pretty a <> " iff " <> pretty b <> ")"
  pretty (App Imp [a, b]) = "(" <> pretty a <> " implies " <> pretty b <> ")"
  pretty (App Eq  [a, b]) = "(" <> pretty a <> " = " <> pretty b <> ")"
  pretty (App Not [a]) = "(not " <> pretty a <> ")"
  pretty (App Top []) = "true"
  pretty (App Bot []) = "false"
  pretty (App (OpTrm (TermSymbolic s)) args) = 
    decode s $ flip map args $ \a -> case a of
      App (OpTrm (TermSymbolic _)) _ -> "(" <> pretty a <> ")"
      _ -> pretty a
  pretty (App (OpTrm op) args) = pretty op  <> inParens (map pretty args) 
  pretty (Var v) = pretty v
  pretty (Tag t tr) = "(" <> Text.pack (show t) <> " :: " <> pretty tr <> ")"
  pretty t = error $ "Malformed term: " ++ show t

instance (Pretty (f InType), Show t, Show (f InType)) 
  => Pretty (Stmt f t) where
  pretty (IntroSort tm) = "Sort: " <> pretty tm
  pretty (Predicate tm [] t) = pretty tm <> " : " <> pretty t
  pretty (Predicate tm ts t) = pretty tm <> " : "
    <> Text.intercalate " → " (map pretty ts) <> " → " <> pretty t
  pretty (Axiom t) = "Axiom: " <> pretty t
  pretty (Claim t prf) = "Claim: " <> pretty t <> " " <> pretty prf
  pretty (Coercion name from to) = "Coercion: " <> pretty name <> " : " 
    <> pretty from <> " → " <> pretty to

instance (Pretty (f InType), Show t, Show (f InType))
  => Pretty (PrfBlock f t) where
  pretty (Proving [] _ ls) = inParens ls
  pretty (Proving prfs c ls) =
    renderLines (map (pretty . located) prfs) 
    <> "\n" <> pretty c <> inParens ls

instance (Pretty (f InType), Show t, Show (f InType))
  => Pretty (Prf f t) where
  pretty (Subclaim t prfs) = pretty t <> " " <> pretty prfs
  pretty (Intro v t) = "Let " <> pretty v <> " : " <> pretty t 
  pretty (Assume a) = "Assume " <> pretty a
  pretty (Choose vs t prfs) = "Choose: " <> Text.intercalate ", " 
    (map pretty vs) <> " such that " <> pretty t <> pretty prfs
  pretty (Cases cs) = Text.concat $
    map (\(t, p) -> "Case: " <> pretty t <> pretty p) cs
  pretty (TerminalCases cs) = Text.concat $
    map (\(t, p) -> "Case: " <> pretty t <> pretty p) cs
  pretty (ByContradiction goal) = "Assume the contrary: " 
    <> pretty (simp (App Not [goal]))

instance Pretty a => Pretty (Located a) where
  pretty (Located t p a) = "[" <> t  <> "] " 
    <> Text.pack (show p) <> "\n" <> pretty a <> "\n"