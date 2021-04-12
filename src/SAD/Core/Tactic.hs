{-# LANGUAGE OverloadedStrings #-}

-- | Create proof tasks from statements.
-- This will evaluate tactics and create the necessary
-- statements for the prover.
-- Is a statement like $1 / 0 = 1 / 0$ true?
-- An ATP would say yes, but a mathematician would say no.
-- Therefore we check preconditions of definitions when they are used.
-- This is called ontological checking.

module SAD.Core.Tactic (proofTasks, ontologicalTasks) where

import Prelude hiding (error)
import qualified Prelude
import Control.Monad.Identity
import Data.List
import Data.Text (Text)

import SAD.Core.Typed
import SAD.Core.SourcePos (SourcePos)
import SAD.Core.Task
import SAD.Data.Identifier

proofTasksFromTactic :: Bool -> Term Identity () -> [Hypothesis] -> Located (Prf Identity ()) -> [Task]
proofTasksFromTactic isContra goal hypo (Located n p tactic) = case tactic of
  Intro _ _ -> []
  Assume _ -> []
  Suffices t prf -> proofTasksFromPrfBlock n p isContra hypo (App Imp [t, goal]) prf
  ByContradiction _ -> []
  Subclaim t prf -> proofTasksFromPrfBlock n p isContra hypo (termFromNF t) prf
  Choose vs t prf ->
    let ex = foldl' (\e (i, t) -> Exists i t e) t vs
    in proofTasksFromPrfBlock n p isContra hypo ex prf
  Cases cs -> flip concatMap cs $ \(c, t, prf) -> 
    proofTasksFromPrfBlock "case" p isContra (Given "case" c:hypo) t prf
  TerminalCases [] -> [] -- see use of foldl1 below
  TerminalCases cs ->
    let cases = flip concatMap cs $ \(c, prf) -> 
          proofTasksFromPrfBlock "case" p isContra (Given "case" c:hypo) goal prf
        final = foldl1 (\a b -> App Or [a, b]) (map fst cs)
    in cases ++ [Task hypo final [] n isContra p]

ontoTasksFromTactic :: [Hypothesis] -> Located (Prf Identity ()) -> [Task]
ontoTasksFromTactic hypo (Located _ p tactic) = case tactic of
  Intro _ _ -> []
  Assume a -> nftermToOntoTasks p hypo (termToNF a)
  Suffices t prf -> nftermToOntoTasks p hypo (termToNF t)
    ++ ontoTasksFromPrfBlock hypo prf
  ByContradiction _ -> []
  Subclaim t prf -> nftermToOntoTasks p hypo t
    ++ ontoTasksFromPrfBlock hypo prf
  Choose vs t prf ->
    let ex = foldl' (\e (i, t) -> Exists i t e) t vs
    in nftermToOntoTasks p hypo (termToNF ex) ++ ontoTasksFromPrfBlock hypo prf
  Cases cs -> flip concatMap cs $ \(c, t, prf) -> 
    nftermToOntoTasks p hypo (termToNF c) ++
    nftermToOntoTasks p hypo (termToNF t) ++
    ontoTasksFromPrfBlock (Given "case" c:hypo) prf
  TerminalCases cs -> flip concatMap cs $ \(c, prf) -> 
    nftermToOntoTasks p hypo (termToNF c) ++
    ontoTasksFromPrfBlock (Given "case" c:hypo) prf

-- | Generate tasks from the given proofs under the hypothesis that were assumed at this point.
proofTasksFromPrfBlock :: Text -> SourcePos -> Bool -> [Hypothesis] -> Term Identity () -> PrfBlock Identity () -> [Task]
proofTasksFromPrfBlock topname topPos isContra hypo topclaim = \case
  ProofByHints tophints -> [Task hypo topclaim tophints topname isContra topPos]
  ProofByTactics _ -> Prelude.error "Internal error: Tactics to be generated were not type-checked!"
  ProofByTCTactics ts -> go isContra topclaim hypo ts
  where
    go isContra goal hypo [] = [Task hypo goal [] topname isContra topPos]
    go isContra goal hypo ((tactic, newGoal, newHypos):ts) = 
      let ts' = proofTasksFromTactic isContra goal hypo tactic
          isContra' = case tactic of
            Located _ _ (ByContradiction _) -> True
            _ -> isContra
      in ts' ++ go isContra' newGoal (newHypos ++ hypo) ts

wfToOntoTasks :: Ident -> SourcePos -> [Hypothesis] -> WfBlock Identity () -> [Task]
wfToOntoTasks op p hypo (WfBlock im prf) =
  concatMap (\(_, t) -> nftermToOntoTasks p hypo $ termToNF t) im ++
  case prf of
    Nothing -> []
    Just (goal, prf) ->
      let op' = identAsTerm op
      in proofTasksFromPrfBlock op' p True hypo (termFromNF goal) prf

ontoTasksFromPrfBlock :: [Hypothesis] -> PrfBlock Identity () -> [Task]
ontoTasksFromPrfBlock hypo = \case
  ProofByHints _ -> []
  ProofByTactics _ -> Prelude.error "Internal error: Tactics to be generated were not type-checked!"
  ProofByTCTactics ts -> go hypo ts
  where
    go _ [] = []
    go hypo ((tactic, _, newHypos):ts) = 
      let ts' = ontoTasksFromTactic hypo tactic
      in ts' ++ go (newHypos ++ hypo) ts

statementToHypos :: Located (Stmt Identity ()) -> [Hypothesis]
statementToHypos (Located n _ term) = case term of
  IntroSort t -> [Typing t Sort]
  IntroAtom t _ ex _ -> [Typing t (Pred (map (\(_, Identity b) -> b) ex) Prop)]
  IntroSignature t (Identity o) _ ex _ -> [Typing t (Pred (map (\(_, Identity b) -> b) ex) (InType o))]
  Axiom t -> [Given n (termFromNF t)]
  Predicate i (NFTerm im ex as b) ->
    let ts = map (\(_, Identity t) -> t) ex
        ax = termFromNF (NFTerm im ex as (App Iff [AppWf i (map (\(v, _) -> AppWf v [] noWf) ex) noWf, b]))
    in [Given "" ax, Typing i (Pred ts Prop)]
  Function i (Identity o) (NFTerm im ex as b) ->
    let ts = map (\(_, Identity t) -> t) ex
        ax = termFromNF (NFTerm im ex as (App Eq [AppWf i (map (\(v, _) -> AppWf v [] noWf) ex) noWf, b]))
    in [Given "" ax, Typing i (Pred ts (InType o))]
  Claim t _ -> [Given n (termFromNF t)]
  Coercion n f t -> [Typing n (Pred [Signature f] (InType (Signature t)))]

statementToProofTasks :: [Hypothesis] -> Located (Stmt Identity ()) -> [Task]
statementToProofTasks hypo (Located n pos term) = case term of
  IntroSort _ -> []
  IntroAtom _ _ _ _ -> []
  IntroSignature _ _ _ _ _ -> []
  Axiom _ -> []
  Predicate _ _ -> []
  Function _ _ _ -> []
  Claim t prf -> proofTasksFromPrfBlock n pos False hypo (termFromNF t) prf
  Coercion _ _ _ -> []

nftermToOntoTasks :: SourcePos -> [Hypothesis] -> NFTerm Identity () -> [Task]
nftermToOntoTasks p hypo = go hypo . termFromNF
  where
    mkTyp = Pred [] . InType

    go hypo = \case
      Forall i (Identity typ) t -> go ((Typing i $ mkTyp typ):hypo) t
      Exists i (Identity typ) t -> go ((Typing i $ mkTyp typ):hypo) t
      Class  i (Identity typ) t -> go ((Typing i $ mkTyp typ):hypo) t
      -- this rule allows "Exists x: x in Dom(f) and f(x) = y":
      App And [a, b] -> go hypo a ++ go ((Given "" a):hypo) b
      App Imp [a, b] -> go hypo a ++ go ((Given "" a):hypo) b
      App _ args -> concatMap (go hypo) args
      AppWf op args wf -> 
        wfToOntoTasks op p hypo wf ++ concatMap (go hypo) args
      Tag _ t -> go hypo t

statementToOntoTasks :: [Hypothesis] -> Located (Stmt Identity ()) -> [Task]
statementToOntoTasks hypo (Located _ pos term) = case term of
  IntroSort _ -> []
  IntroAtom _ _ _ _ -> []
  IntroSignature _ _ _ _ _ -> []
  Axiom nf -> nftermToOntoTasks pos hypo nf
  Predicate _ nf -> nftermToOntoTasks pos hypo nf
  Function _ _ nf -> nftermToOntoTasks pos hypo nf
  Claim t prf -> nftermToOntoTasks pos hypo t ++ ontoTasksFromPrfBlock hypo prf
  Coercion _ _ _ -> []

ontologicalTasks :: [Located (Stmt Identity ())] -> [Task]
ontologicalTasks = concat . snd . mapAccumL go []
  where
    go hypo stmt = (statementToHypos stmt ++ hypo, statementToOntoTasks hypo stmt)

proofTasks :: [Located (Stmt Identity ())] -> [Task]
proofTasks = concat . snd . mapAccumL go []
  where
    go hypo stmt = (statementToHypos stmt ++ hypo, statementToProofTasks hypo stmt)