{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE ViewPatterns #-}

-- | Transform the blocks from a parsed text to TFF form.
-- This code is a bit fragile since it was written mainly
-- by checking that a ton of examples work and not focussing
-- on correctness by design. Therefore we made the concious
-- decision to add many calls to 'error'. This ensures that
-- this transformation is indeed faithful to the Naproche text.

-- TODO: Introduce an error monad for errors that are strictly
-- user errors and not a fault of the translation like duplicate 
-- variables, etc. This also allows us to bubble up errors without
-- evaluating the entire generated proof text.

module SAD.Core.Transform
 ( convert, convertBlock
 ) where

import Data.Text (Text)
import Data.Char (toLower)
import qualified Data.Text as Text
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Functor.Const
import Data.Functor.Identity
import qualified Data.List as List
import Data.Maybe (fromMaybe)
import Control.Applicative

import SAD.Data.Formula (Formula, Tag(..), Decl(..))
import qualified SAD.Data.Formula as F
import SAD.Data.VarName
import SAD.Data.Terms
import SAD.Data.Text.Block (ProofText(..), Block(..), position)
import qualified SAD.Data.Text.Block as Block
import SAD.Core.Pretty (Pretty(..))
import SAD.Helpers (setMapMaybe)

import SAD.Core.Typed
import SAD.Core.Coerce

import GHC.Stack
import Debug.Trace

-- | If you encounter a weird error, this may help
-- with debugging it. You need to import Debug.Trace
traceReprId :: Pretty a => a -> a
traceReprId a = a -- trace (Text.unpack (pretty a)) a

data Context = Context
  { typings :: Map TermName (Maybe Type)
    -- ^ a type for each resolved name
  , resolved :: Map TermName (Set TermName)
    -- ^ resolve functions into names, e.g. + into add_nat 
    -- and and_rat if + was defined twice.
  , nextName :: Maybe Text
    -- ^ the resolved name of the next definition,
    -- if given by an instruction
  , coercions :: Coercions TermName TermName
  , preBoundVars :: Map VarName InType
    -- ^ variables bound by a previous choose statement or in the claim.
  } deriving (Eq, Ord, Show)

-- | Danger: Costly in second argument due to coercions
instance Semigroup Context where
  (<>) (Context t1 r1 n1 c1 p1) (Context t2 r2 n2 c2 p2) = Context (t1 <> t2) (r1 <> r2) (n1 <> n2) (c1 <> c2) (p1 <> p2)

-- | This should be kept in sync with SAD.ForTheL.Base.initFS
predefinedTypes :: Map TermName (Maybe Type)
predefinedTypes = Map.fromList
  [ (termSet, Just Sort)
  , (termClass, Just Sort)
  , (termObject, Just Sort)
  , (termElement, Just $ Pred [Signature termObject, Signature termClass] Prop)
  ]

predefinedNames :: Map TermName (Set TermName)
predefinedNames = Map.fromList
  [ (termElement, Set.singleton termElement) ]

instance Monoid Context where
  mempty = Context predefinedTypes predefinedNames mempty mempty mempty

-- | Parse a formula into a term while ignoring all type information.
-- This will only check that no variable overlap and that all de-bruijn
-- indices have a binder. We will subsequently use the variable names at
-- the binders instead of indices since this leads to nicer output.
parseFormula :: Formula -> Term (Const ()) Tag
parseFormula = go []
  where 
    go vars = \case
      F.All (Decl v _ _) f -> Forall v (Const ()) $ go (addVar v vars) f
      F.Exi (Decl v _ _) f -> Exists v (Const ()) $ go (addVar v vars) f
      F.Class (Decl v _ _) f -> Class v (Const ()) $ go (addVar v vars) f
      F.Iff f1 f2 -> App Iff [go vars f1, go vars f2]
      F.Imp f1 f2 -> App Imp [go vars f1, go vars f2]
      F.And f1 f2 -> App And [go vars f1, go vars f2]
      F.Or  f1 f2 -> App Or  [go vars f1, go vars f2]
      F.Tag t f   -> Tag t $ go vars f
      F.Not f -> App Not [go vars f]
      F.Top -> App Top []
      F.Bot -> App Bot []
      F.Trm TermEquality [f1, f2] _ _ -> App Eq [go vars f1, go vars f2]
      F.Trm name args _ _ -> App (OpTrm name) $ map (go vars) args
      F.Var v _ _ -> Var v
      F.Ind i _ ->
        if length vars > i then Var $ vars !! i
        else error $ "Unbound index: " ++ show i
      f -> error $  "Unexpected formula: " ++ show f

    addVar v vars = v:vars

-- | Given a list of defined sorts and a TermName,
-- decide if this is a sort.
parseType :: Context -> TermName -> Maybe InType
parseType ctx = \case 
  t@(TermNotion _) -> case Map.lookup t (typings ctx) of
    Just (Just Sort) -> Just $ Signature t
    _ -> Nothing
  _ -> Nothing

-- | Transform type predicates into types.
-- This needs to be seperate from finding types, since
-- the type predicates need to be deleted from the terms
-- and it is not allowed for a variable to have more than
-- one sort (which we check here).
extractGivenTypes :: Context -> Term (Const ()) Tag -> Term Maybe Tag
extractGivenTypes ctx = snd . go
  where
    duplicateType a b =
      if coercibleInto' a b (coercions ctx) /= Nothing then a else
      if coercibleInto' b a (coercions ctx) /= Nothing then b else
      error $ "A variable has been defined with multiple types: " ++ show a ++ " and " ++ show b

    -- TODO: The hack below is fragile. It would be better to do the following:
    -- We say a term is in negative position if it occurs negated in the DNF
    -- and else say in positive position. For example: "negative => positive".
    -- Then we should use type predicates in negative position for types
    -- and in positive position for coercions.
    -- We need to split "x iff y" into two statements for this to work.
    -- A statement like 'x is an A iff x is a B and P' should be translated to
    -- '(∀[x : A] ∃[y : B] x = y & P(x)) & (∀[x : B] P(x) => ∃[y : A] x = y)'
    -- (with coercions inserted later...)
    go :: Term (Const ()) Tag -> (Map VarName InType, Term Maybe Tag)
    go = \case
      Forall v (Const ()) t ->
        let (typings, t') = go t
        in (typings, Forall v (Map.lookup v typings) t')
      Exists v (Const ()) t ->
        let (typings, t') = go t
        in (typings, Exists v (Map.lookup v typings) t')
      Class v (Const ()) t ->
        let (typings, t') = go t
        in (typings, Class v (Just $ Map.findWithDefault (Signature termObject) v typings) t')
      -- this hack allows for new coercions in a lemma or axiom
      -- if it is of the form "Let s be a from. Then s is a to."
      App Imp [App (OpTrm (parseType ctx -> Just from)) [Var v0], App (OpTrm name@(parseType ctx -> Just _)) [Var v1]]
        | v0 == v1 -> (Map.singleton v0 from, Tag CoercionTag $ App (OpTrm name) [Var v0])
      App (OpTrm name) [Var v] -> case parseType ctx name of
        Just t -> (Map.singleton v t, App Top [])
        Nothing -> (mempty, App (OpTrm name) [Var v])
      App op args ->
        let res = map go args
            typings = Map.unionsWith duplicateType $ map fst res
            args' = map snd res
        in (typings, App op args')
      Tag tag t -> Tag tag <$> go t
      Var v -> (mempty, Var v)

coercionsToTerm :: [TermName] -> (Term f t -> Term f t)
coercionsToTerm = go . reverse
  where
    go [] = id
    go (x:xs) = go xs . App (OpTrm x) . (:[])

-- | Like <> for maybe, but prefers Nothing
(<+>) :: Semigroup a => Maybe a -> Maybe a -> Maybe a
(<+>) (Just a) (Just b) = Just (a <> b)
(<+>) _ _ = Nothing

-- | Find the coercions for two 'Type's.
-- If both are Sorts we return just the empty list and if both
-- are predicates, we return the coercions for each argument in order.
coercibleInto :: Type -> Type -> Coercions TermName TermName -> Maybe [[TermName]]
coercibleInto smaller bigger coe = case (smaller, bigger) of
  (Sort, Sort) -> Just []
  (Pred is o, Pred is' o') ->
    let outOk = case (o, o') of
          (Prop, Prop) -> Just [] 
          (InType i, InType i') -> 
            const [] <$> coercibleInto' i' i coe -- contravariant
          _ -> Nothing
        inOk = sequence $ zipWith (\a b -> coercibleInto' a b coe) is is'
    in if length is == length is' then inOk <+> outOk else Nothing
  _ -> Nothing

-- | Find the coercions for two 'InType's.
-- We handle 'TermNotKnown' specially, see 'resolve' below.
coercibleInto' :: InType -> InType -> Coercions TermName TermName -> Maybe [TermName]
coercibleInto' _ (Signature TermNotKnown) _ = Just []
coercibleInto' (Signature smaller) (Signature bigger) coe = coerce (smaller, bigger) coe

data ReturnValue = Value | Proposition
  deriving (Eq, Ord, Show)

resolve :: HasCallStack => Context -> TermName -> [InType] -> ReturnValue -> ((TermName, [[TermName]]), Type)
resolve (Context idents res _ coe _) name intypes ret =
  leastGeneral $ Set.toList feasibleNames
  where
    resolvedNames = setMapMaybe (\a -> (\b->(a,b)) <$> (idents Map.! a) ) $ res Map.! name

    feasibleNames = Set.map (\((t, Just a), typ) -> ((t, a), typ)) $ Set.filter (\a -> snd (fst a) /= Nothing) 
        $ Set.map (\t -> ((fst t, coercibleInto typ (snd t) coe), snd t)) resolvedNames

    typ = case ret of
      Proposition -> Pred intypes Prop
      Value -> Pred intypes $ InType $ Signature TermNotKnown

    leastGeneral [] = error $ Text.unpack $ "Resolve failed: " <> pretty name <> " of type " <> pretty typ
    leastGeneral [x] = x
    leastGeneral (x:y:xs) = if coercibleInto (snd x) (snd y) coe /= Nothing then leastGeneral (x:xs) else
      if coercibleInto (snd y) (snd x) coe /= Nothing then leastGeneral (y:xs) else
        error $ Text.unpack $ "Resolve ambigous: " <> pretty name <> " of type " <> pretty typ
          <> " can be resolved as " <> pretty (snd x) <> " or " <> pretty (snd y) <> "\n"
          <> "and none of them is more general than the other."

-- | Type check applications and insert coercions.
gatherTypes :: Context -> Term Maybe Tag -> Term Maybe Tag
gatherTypes c = snd . go Proposition (Map.map Just $ preBoundVars c) 0
  where
    -- The context is the type that the surrounding context expects.
    -- When we expect some InType, we use 'Signature "Object"'.
    -- We need to insert special variables for type predicates,
    -- numbered by d
    go context typings d = \case
      Forall v1 Nothing (App Iff [t1, App Eq [Var v2, t2]])
        | v1 == v2 ->
          let (InType tt2, t2') = go Value typings d t2
              (_, t1') = go Proposition (Map.insert v1 (Just tt2) typings) d t1
          in (Prop, Forall v1 (Just $ tt2) (App Iff [t1', App Eq [Var v2, t2']]))
      Forall v m t -> case context of
        Proposition -> Forall v m <$> go Proposition (Map.insert v m typings) d t
        _ -> error $ "Found a forall term where an object was expected"
      Exists v m t -> case context of
        Proposition -> Exists v m <$> go Proposition (Map.insert v m typings) d t
        _ -> error $ "Found an exists term where an object was expected"
      Class v m t -> case context of
        Value -> (InType $ Signature (TermNotion "Class"), Class v m 
          $ snd $ go Proposition (Map.insert v m typings) d t)
        Proposition -> error $ "Found a class where a proposition was expected."
      -- If we use a sort as a predicate aSort(x), we instead use ∃[v : aSort] v = x.
      App (OpTrm name@(TermNotion _)) [arg] -> 
        let (tb, arg') = go Value typings (d+1) arg
            ia = Signature name
            a = Var (VarF d)
            eq = case tb of
              InType ib -> case (coercibleInto' ia ib (coercions c), coercibleInto' ib ia (coercions c)) of
                (Just ts, _) -> App Eq [coercionsToTerm ts a, arg']
                (_, Just ts) -> App Eq [a, coercionsToTerm ts arg']

                -- This may happen when a coercion is newly introduced.
                -- When the coercion is not in a CoercionTag, this should
                -- throw an error (because otherwise the prover will complain).
                (Nothing, Nothing) -> App Eq [a, arg']
              _ -> error $ "Proposition was used in coercion: " ++ show arg
        in (Prop, (Exists (VarF d) (Just $ Signature name) eq))
      App (OpTrm name@(TermVar v)) args -> case (Map.lookup v typings, args) of
        (Just (Just t), []) -> (InType t, App (OpTrm name) [])
        (_, (_:_)) -> error "Internal: Variable bound as term can't be applied."
        (_, _) -> error "Internal: Variable bound as term in a proof was not registered."
      App (OpTrm name) args ->
        let (argtypes, args') = unzip $ map (go Value typings d) args
            argintypes = flip map argtypes $ \t -> case t of
              Prop -> error "A truth value cannot be passed to a function!"
              InType t' -> t'
        in case resolve c name argintypes context of
              ((name', _), Sort) -> 
                error $ "Illegal use of sort as predicate: " ++ show (App (OpTrm name') args') 
                  ++ " where a value was expected."
              ((name', coe), Pred _ t) -> (t, App (OpTrm name') $ zipWith coercionsToTerm coe args')
      App Eq [a, b] -> let [(ta, a'), (tb, b')] = map (go Value typings d) [a, b] 
        in case (ta, tb) of
          (InType ia, InType ib) -> case (coercibleInto' ia ib (coercions c), coercibleInto' ib ia (coercions c)) of
            (Just ts, _) -> (Prop, App Eq [coercionsToTerm ts a', b'])
            (_, Just ts) -> (Prop, App Eq [a', coercionsToTerm ts b'])
            (Nothing, Nothing) -> error $ "Can't coerce one side of equality into the other: " ++ show (App Eq [a', b']) 
          _ -> error $ "Prop in equality: " ++ show (App Eq [a', b'])
      App op args -> let res = map (go Proposition typings d) args
        in (Prop, App op $ map snd res)
      -- predicate defintions: check that all args are variables
      Tag HeadTerm (App (OpTrm name) args) ->
        (Prop, Tag HeadTerm $ App (OpTrm name) 
          (map (\case Var v -> Var v; x -> error $ "Expected variable in definition but got: " ++ show x) args))
      -- function definitions; check that all args are variables
      Tag HeadTerm (App Eq [Var v0, App (OpTrm name) args]) ->
        (Prop, Tag HeadTerm $ App Eq [Var v0, App (OpTrm name) 
          (map (\case Var v -> Var v; x -> error $ "Expected variable in definition but got: " ++ show x) args)])
      Tag tag t -> Tag tag <$> go context typings d t
      Var v -> case context of
        Proposition -> error $ "A variable " ++ show v ++ " may not appear as a proposition."
        Value -> case Map.lookup v typings of
          Just (Just t) -> (InType t, Var v)
          _ -> error $ "Unbound variable: " ++ show v

coercionName :: TermName -> TermName -> TermName
coercionName (TermNotion n1) (TermNotion n2) = TermName $ beginLower n1 <> "To" <> n2
  where beginLower t = case Text.uncons t of
          Just (c, t') -> Text.cons (toLower c) t'
          Nothing -> t
coercionName _ _ = error $ "Coercions only between notions"

-- | Extract definitions from a typed term.
-- This will find HeadTerms and add them as definitions,
-- as well as delete all HeadTerm Tags.
extractDefinitions :: HasCallStack => Term Maybe Tag -> ([Stmt Identity ()], Term Maybe Tag)
extractDefinitions = go mempty
  where
    extractType :: TermName -> Map VarName (Maybe p) -> Term Maybe Tag -> p
    extractType name types (Var v) = case Map.lookup v types of
      Just (Just t) -> t
      Just Nothing -> error $ Text.unpack $ "In a definition for " <> pretty name <> ", the type of variable "
        <> pretty v <> " could not be guessed. Please provide its type."
      Nothing -> error $ Text.unpack $ "In a definition for " <> pretty name <> ", the variable "
        <> pretty v <> " was found to be unbound."
    extractType name _ e = error $ Text.unpack $ "In a definition for " <> pretty name <> ", I expected a variable, but got:\n" <> pretty e

    go types = \case
      Forall v m t -> simp <$> Forall v m <$> go (Map.insert v m types) t
      Exists v m t -> simp <$> Exists v m <$> go (Map.insert v m types) t
      Class v m t -> simp <$> Class v m <$> go (Map.insert v m types) t
      App op args -> let res = map (go types) args
        in (concatMap fst res, simp $ App op $ map snd res)
      -- coercion definitions
      -- TODO: This case does not match when the coercion already exists and thus an error
      -- 'Remaining tag: CoercionTag' is thrown!
      Tag CoercionTag trm@(Exists _ (Just (Signature to)) (App Eq [_, Var v0])) -> case Map.lookup v0 types of
        (Just (Just (Signature from))) -> ([Coercion (coercionName from to) from (Signature to)], App Top [])
        _ -> ([], trm)
      -- sorts and predicate definitions
      Tag HeadTerm trm@(App (OpTrm name) args) -> case (name, args) of
        (TermNotion _, [Var v]) ->
          let t = case Map.lookup v types of
                (Just (Just (Signature t'))) -> [Coercion (coercionName name t') name (Signature t')]
                _ -> []
          in ([IntroSort name] ++ t, App Top [])
        _ -> let ts = map (extractType name types) args
          in ([Predicate name ts Prop], simp $ trm)
      -- function definitions
      Tag HeadTerm trm@(App Eq [Var v0, App (OpTrm name) args]) ->
        let ts = map (extractType name types) args
        in ([Predicate name ts (InType $ extractType name types (Var v0))], trm)
      Tag tag t -> Tag tag <$> simp <$> go types t
      Var v -> ([], Var v)

-- | Make sure that there are no tags left.
noTags :: Term Identity Tag -> Term Identity ()
noTags = go
  where
    go = \case
      Forall v m t -> Forall v m (go t)
      Exists v m t -> Exists v m (go t)
      Class v m t -> Class v m (go t)
      App op args -> App op (go <$> args)
      Tag Replacement t -> go t
      Tag EqualityChain t -> go t
      Tag tag _ -> error $ "Remaining tag: " ++ show tag
      Var v -> Var v

-- | The full pipeline from formula to a terms.
typecheck :: Context -> Term (Const ()) Tag -> Term Maybe Tag
typecheck ctx
  = traceReprId . gatherTypes ctx 
  . traceReprId . extractGivenTypes ctx 

-- | Fail if the type of binds could not be inferred.
noUntypedBinds :: Term Maybe t -> Term Identity t
noUntypedBinds = \case
  Forall v (Just m) t -> Forall v (Identity m) (noUntypedBinds t)
  Exists v (Just m) t -> Exists v (Identity m) (noUntypedBinds t)
  Class v (Just m) t -> Class v (Identity m) (noUntypedBinds t)
  Forall v Nothing _ -> error $ "Untyped bind: " ++ show v
  Exists v Nothing _ -> error $ "Untyped bind: " ++ show v
  Class v Nothing _ -> error $ "Untyped bind: " ++ show v
  App op args -> App op (noUntypedBinds <$> args)
  Tag tag t -> Tag tag $ noUntypedBinds t
  Var v -> Var v

-- | A tactic takes the goal, the current context and a number of proof lines (Block)
-- and may translate some lines and give a new goal.
type Tactic = (Term Identity (), Context, [Block]) -> Maybe (Proof, (Term Identity (), Context, [Block]))

preBind :: Map VarName InType -> Context -> Context
preBind vs ctx = ctx { preBoundVars = vs <> preBoundVars ctx }

-- | Introduce top-level forall-bound variables in the term
-- and the conditions of if-terms as a tactic.
autoIntroAssume :: Tactic
autoIntroAssume (_, _, []) = Nothing
autoIntroAssume (goal, ctx, (b:bs)) = case goal of
    Forall v (Identity typ) t -> Just ((Located "intro" (position b) (Intro v typ)), (t, preBind (Map.singleton v typ) ctx, b:bs))
    App Imp [ass, goal'] -> Just ((Located "intro" (position b) (Assume $ termify (Map.keysSet $ preBoundVars ctx) ass)), (goal', ctx, b:bs))
    _ -> Nothing

-- | Convert a single line of a proof.
subClaim :: Context -> Block -> Proof
subClaim ctx bl@(Block f b _ _ n l _) = Located n (position bl) $
  let mainF = noTags $ noUntypedBinds
        $ typecheck ctx $ bindFree (Map.keysSet $ preBoundVars ctx) $ parseFormula f
  in Subclaim mainF (convertProof mainF l ctx b)

subClaims :: Tactic
subClaims (_, _, []) = Nothing
subClaims (goal, ctx, (b:bs)) = Just (subClaim ctx b, (goal, ctx, bs))

byContradiction :: Tactic
byContradiction (_, _, []) = Nothing
byContradiction (goal, ctx, (b:bs)) = case formula b of
  F.Not (F.Trm TermThesis [] _ _) ->
    Just (Located (name b) (position b) (ByContradiction goal), (App Bot [], ctx, bs))
  _ -> Nothing

chooses :: Tactic
chooses (_, _, []) = Nothing
chooses (goal, ctx, (b:bs)) = case kind b of
  Block.Selection ->
    let l = position b; n = name b
        vs = Set.map declName $ declaredVariables b
        f = noTags $ noUntypedBinds
          $ typecheck ctx $ bindFree (Map.keysSet $ preBoundVars ctx)
          $ bindExists (Set.toList vs) $ parseFormula (formula b)
        boundVs = Map.fromList $ concat $ flip List.unfoldr f $ \case
            Forall _ (Identity _) t -> Just ([], t)
            Exists v (Identity typ) t
              | v `Set.member` vs -> Just ([(v, typ)], t)
              | otherwise -> Just ([], t)
            _ -> Nothing
        p = convertProof f (link b) ctx (body b)
        ctx' = preBind boundVs ctx
    in Just $ (Located n l $ Choose (Map.toList boundVs) f p, (goal, ctx', bs))
  _ -> Nothing

cases :: Tactic
cases (goal, ctx, bs) = go Nothing bs
  where
    parseCase c b =
      let c' = noTags $ noUntypedBinds
             $ typecheck ctx $ bindFree (Map.keysSet $ preBoundVars ctx) $ parseFormula c
          p' = convertProof goal (link b) ctx (body b)
          l' = (position b)
      in (l', (c', p'))

    go Nothing [] = Nothing
    go (Just (l, ms)) [] = Just (Located "cases" l $ TerminalCases ms, (goal, ctx, []))
    go m (b:bs) = case formula b of
      F.Imp (F.Tag CaseHypothesisTag c) (F.Trm TermThesis [] _ _) ->
        let (l', (c', p')) = parseCase c b
        in case m of
          Nothing -> go (Just (l', [(c', p')])) bs
          Just (l, ms) -> go (Just (l, (c', p'):ms)) bs
      _ -> case m of
        Nothing -> Nothing
        Just (l, ms) -> Just (Located "cases" l $ Cases ms, (goal, ctx, b:bs))

-- | Convert a Proof. ... end. part
convertProof :: Term Identity () -> [Text] -> Context -> [ProofText] -> ProofBlock
convertProof goal links ctx pts =
  let ((goal', ctx', _), ps) = go $ concatMap (\case ProofTextBlock b -> [b]; _ -> []) pts
  in Proving ps (termify (Map.keysSet $ preBoundVars ctx') goal') links
  where
    go bs = unfold (goal, ctx, bs) $ \st ->
      autoIntroAssume st <|> cases st <|> chooses st
      <|> byContradiction st <|> subClaims st

    unfold b f = case f b of
      Just (a, b') -> (a:) <$> unfold b' f
      Nothing -> (b, [])

-- | Get the blocks in a Prooftext.
getBlocks :: ProofText -> [Block]
getBlocks (ProofTextBlock b) = [b]
getBlocks (ProofTextRoot ts) = concatMap getBlocks ts
getBlocks p = error $ "Internal error: getBlocks received: " ++ show p

-- | Convert a block into a statement.
convertBlock :: Context -> Block -> [Statement]
convertBlock ctx bl@(Block f b _ _ n l _) = Located n (position bl) <$>
  case f of
    -- top-level blocks:
    (F.Var (VarHole _) _ _) ->
      let (main:assms) = reverse $ concatMap getBlocks b
          mainF = foldr (F.Imp) (formula main) (formula <$> assms)
          (defs, mainT) = traceReprId $ extractDefinitions 
            $ typecheck ctx $ bindFree mempty $ parseFormula mainF
          mainT' = noTags $ noUntypedBinds mainT
      in case Block.needsProof bl of
        True -> if not (null defs)
          then error $ "Definitions in claim!"
          else [Claim mainT' $ (convertProof mainT' l ctx (body main))]
        False -> defs ++ 
          if mainT == App Top [] then [] else [Axiom mainT']
    _ -> error "convertBlock should not be applied to proofs!"

-- TODO: There may be lazy parse errors in here and we sometimes do not force them.
convert :: [ProofText] -> [Statement]
convert = go mempty . concatMap (\case ProofTextBlock bl -> [bl]; _ -> [])
  where
    go _ [] = []
    go c (b:bs) =
      let stmts = convertBlock c b
      in stmts ++ go (List.foldl' updateCtx c stmts) bs

    updateCtx (Context idents res nn coe pbv) (Located _ _ s) = case s of
      IntroSort n ->
        let n' = newName n res_n 
            res_n = Map.lookup n res
            res_n' = fromMaybe mempty res_n
        in Context (Map.insert n' (Just Sort) idents) (Map.insert n (Set.insert n' res_n') res) nn coe pbv
      Predicate n is o ->
        let n' = newName n res_n 
            res_n = Map.lookup n res
            res_n' = fromMaybe mempty res_n
        in Context (Map.insert n' (Just (Pred is o)) idents) (Map.insert n (Set.insert n' res_n') res) nn coe pbv
      Coercion n from (Signature to) -> Context idents res nn (add (from, to) n coe) pbv
      _ -> Context idents res nn coe pbv