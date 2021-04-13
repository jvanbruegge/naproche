{-
Authors: Andrei Paskevich (2001 - 2008), Steffen Frerix (2017 - 2018)

Syntax of ForThel statements.
-}

{-# LANGUAGE OverloadedStrings #-}

module SAD.ForTheL.Statement
  ( statement
  , sTerm
  , anotion
  , dig
  , selection
  , classNotion
  ) where


import SAD.Data.Formula
import SAD.ForTheL.Base
import SAD.ForTheL.Reports (markupToken, markupTokenOf)
import SAD.Parser.Combinators
import SAD.Parser.Primitives (token, token', symbol, tokenOf')

import qualified SAD.ForTheL.Reports as Reports

import Data.Set (Set)
import Control.Applicative (liftA2, (<**>), Alternative(..))
import Control.Monad (guard)

import qualified Data.Set as Set


statement :: FTL Formula
statement = headed <|> chained

headed :: FTL Formula
headed = quantifiedStatement <|> ifThenStatement <|> wrongStatement
  where
    quantifiedStatement = quantifierChain <*> statement
    ifThenStatement = liftA2 Imp
      (markupToken Reports.ifThen "if" >> statement)
      (markupToken Reports.ifThen "then" >> statement)
    wrongStatement =
      mapM_ token' ["it", "is", "wrong", "that"] >> fmap Not statement


chained :: FTL Formula
chained = label "chained statement" $ (andOr <|> neitherNor) >>= chainEnd
  where
    andOr = atomic >>= \f -> opt f (andChain f <|> orChain f)
    andChain f =
      fmap (foldl And f) $ and >> atomic `sepBy` and
    -- we take sepBy here instead of sepByLLx since we do not  know if the
    -- and/or token' binds to this statement or to an ambient one
    orChain f = fmap (foldl Or f) $ or >> atomic `sepBy`or
    and = markupToken Reports.conjunctiveAnd "and"
    or = markupToken Reports.or "or"

    neitherNor = do
      markupToken Reports.neitherNor "neither"; f <- atomic
      markupToken Reports.neitherNor "nor"
      fs <- atomic `sepBy` markupToken Reports.neitherNor "nor"
      return $ foldl1 And $ map Not (f:fs)


chainEnd :: Formula -> FTL Formula
chainEnd f = optLL1 f $ and_st <|> or_st <|> iff_st <|> where_st
  where
    and_st = fmap (And f) $ markupToken Reports.conjunctiveAnd "and" >> headed
    or_st = fmap (Or f) $ markupToken Reports.or "or" >> headed
    iff_st = fmap (Iff f) $ iff >> statement
    where_st = do
      markupTokenOf Reports.whenWhere ["when", "where"]; y <- statement
      return $ foldr mkAll (Imp y f) (declNames mempty y)


atomic :: FTL Formula
atomic = label "atomic statement"
  thereIs <|> (simple </> (weHave >> symbolicStatement <|> thesis))
  where
    weHave = optLL1 () $ token' "we" >> token' "have"

thesis :: FTL Formula
thesis = art >> (thes <|> contrary <|> contradiction)
  where
    thes = token' "thesis" >> return mkThesis
    contrary = token' "contrary" >> return (Not mkThesis)
    contradiction = token' "contradiction" >> return Bot

thereIs :: FTL Formula
thereIs = label "there-is statement" $ there >> (noNotion -|- notions)
  where
    noNotion = label "no-notion" $ do
      token' "no"; (q, f, vs) <- declared =<< notion;
      return $ Not $ foldr dExi (q f) vs
    notions = fmap multExi $ art >> (declared =<< notion) `sepBy` comma


simple :: FTL Formula
simple = label "simple statement" $ do
  (q, ts) <- terms
  p  <- conjChain doesPredicate
  q' <- lateQuantifiers
  --    ^^^^^^^^^^^^^^^
  --
  --    Late quantification is not part of language description from 2007.
  --
  --    Example: x = y for every real number x.
  --                   ^^^^^^^^^^^^^^^^^^^^^^^
  --
  q . q' <$> dig p ts

-- |
-- A symbolic statement is either a symbolic formula or the assertion that two class
-- terms are equal, followed by optional later quantifiers. If no quantifiers are present
-- the statement is returned as-is, otherwise the quantifiers are applied to the statement.
--
symbolicStatement :: FTL Formula
symbolicStatement = (symbolicFormula -|- classEquality) <**> lateQuantifiers

-- |
-- Parse late quantifiers yielding a quantifying function.
-- Defaults to @id@ when there are no quantifiers.
--
lateQuantifiers :: FTL (Formula -> Formula)
lateQuantifiers = optLL1 id quantifierChain


--- predicates


doesPredicate :: FTL Formula
doesPredicate = label "does predicate" $
  (does >> (doP -|- multiDoP)) <|> hasP <|> isChain
  where
    doP = predicate primVer
    multiDoP = multiPredicate primMultiVer
    hasP = has >> hasPredicate
    isChain = is  >> conjChain (isAPredicate -|- isPredicate)


isPredicate :: FTL Formula
isPredicate = label "is predicate" $
  pAdj -|- pMultiAdj -|- (with >> hasPredicate)
  where
    pAdj = predicate primAdj
    pMultiAdj = multiPredicate primMultiAdj


isAPredicate :: FTL Formula
isAPredicate = label "isA predicate" $ notNotion <|> notion
  -- Unlike the language description, we distinguish positive and negative
  -- rather than notions and fixed terms.
  where
    notion = fmap (uncurry ($)) anotion
    notNotion = do
      token' "not"; (q, f) <- anotion
      let unfinished = dig f [(mkVar (VarHole ""))]
      optLLx (q $ Not f) $ fmap (q. Tag Dig . Not) unfinished

hasPredicate :: FTL Formula
hasPredicate = label "has predicate" $ noPossessive <|> possessive
  where
    possessive = art >> common <|> nonbinary
    nonbinary = fmap (Tag Dig . multExi) $ (declared =<< possess) `sepBy` (comma >> art)
    common = token' "common" >>
      fmap multExi (fmap digadd (declared =<< possess) `sepBy` comma)

    noPossessive = nUnary -|- nCommon
    nUnary = do
      token' "no"; (q, f, v) <- declared =<< possess;
      return $ q . Tag Dig . Not $ foldr dExi f v
    nCommon = do
      token' "no"; token' "common"; (q, f, v) <- declared =<< possess
      return $ q . Not $ foldr dExi (Tag Dig f) v
      -- take a closer look at this later.. why is (Tag Dig) *inside* important?


--- predicate parsing

predicate :: (FTL UTerm -> FTL UTerm) -> FTL Formula
predicate p = (token' "not" >> negative) <|> positive
  where
    positive = do (q, f) <- p term; return $ q . Tag Dig $ f
    negative = do (q, f) <- p term; return $ q . Tag Dig . Not $ f

multiPredicate :: (FTL UTerm -> FTL UTerm) -> FTL Formula
multiPredicate p = (token' "not" >> mNegative) <|> mPositive
  where
    mPositive = (token' "pairwise" >> pPositive) <|> sPositive
    -- we distinguish between *separate* and *pairwise*
    sPositive = do (q, f) <- p term; return $ q . Tag DigMultiSubject $ f
    pPositive = do (q, f) <- p term; return $ q . Tag DigMultiPairwise $ f

    mNegative = (token' "pairwise" >> pNegative) <|> sNegative
    sNegative = do (q, f) <- p term; return $ q . Tag DigMultiSubject . Not $ f
    pNegative = do (q, f) <- p term; return $ q . Tag DigMultiPairwise . Not $ f




--- Notions

baseNotion :: FTL (Formula -> Formula, Formula, Set PosVar)
baseNotion = fmap digadd $ cm <|> symEqnt <|> (clss </> primNotion term)
  where
    cm = token' "common" >> primCommonNotion term terms
    symEqnt = do
      t <- lexicalCheck isTrm sTerm
      v <- hidden;
      pure (id, mkEquality (mkVar (VarHole "")) t, Set.singleton v)

symNotion :: FTL (Formula -> Formula, Formula, Set PosVar)
symNotion = do
  x <- paren (primSnt sTerm) </> primTypedVar
  digNotion (digadd x)


gnotion :: FTL (Formula -> Formula, Formula, Set PosVar)
  -> FTL Formula -> FTL (Formula -> Formula, Formula, Set PosVar)
gnotion nt ra = do
  ls <- fmap reverse la; (q, f, vs) <- nt;
  rs <- opt [] $ fmap (:[]) $ ra <|> rc
  -- we can use <|> here because every ra in use begins with "such"
  return (q, foldr1 And $ f : ls ++ rs, vs)
  where
    la = opt [] $ liftA2 (:) lc la
    lc = predicate primUnAdj </> multiPredicate primMultiUnAdj
    rc = (that >> conjChain doesPredicate <?> "that clause") <|>
      conjChain isPredicate


anotion :: FTL (Formula -> Formula, Formula)
anotion = label "notion (at most one name)" $
  art >> gnotion baseNotion rat >>= single >>= hole
  where
    hole (q, f, v) = return (q, subst (mkVar (VarHole "")) (posVarName v) f)
    rat = fmap (Tag Dig) suchThatAttr

notion :: FTL (Formula -> Formula, Formula, Set PosVar)
notion = label "notion" $ gnotion (baseNotion </> symNotion) suchThatAttr >>= digNotion

possess :: FTL (Formula -> Formula, Formula, Set PosVar)
possess = label "possesive notion" $ gnotion (primOfNotion term) suchThatAttr >>= digNotion


suchThatAttr :: FTL Formula
suchThatAttr = label "such-that attribute" $ such >> that >> statement

digadd :: (a, Formula, c) -> (a, Formula, c)
digadd (q, f, v) = (q, Tag Dig f, v)

digNotion :: (a, Formula, Set PosVar) -> FTL (a, Formula, Set PosVar)
digNotion (q, f, v) = dig f (map pVar $ Set.toList v) >>= \ g -> return (q, g, v)

single :: (a, b, Set c) -> FTL (a, b, c)
single (q, f, vs) = case Set.elems vs of
  [v] -> return (q, f, v)
  _   -> fail "inadmissible multinamed notion"

--- terms

terms :: FTL (Formula -> Formula, [Formula])
terms = label "terms" $
  foldl1 alg <$> (subTerm `sepBy` comma)
  where
    subTerm = quantifiedNotion -|- fmap toMulti definiteTerm
    toMulti (q, t) = (q, [t])
    alg (q, ts) (r, ss) = (q . r, ts ++ ss)

term :: FTL UTerm
term = label "a term" $ (quantifiedNotion >>= toSing) -|- definiteTerm
  where
    toSing (q, [t]) = return (q, t)
    toSing _ = fail "inadmissible multinamed notion"

-- Returns a quantifying function and a list of variables as expression
quantifiedNotion :: FTL (Formula -> Formula, [Formula])
quantifiedNotion = label "quantified notion" $
  paren (universal <|> existential <|> no)
  where
    universal = do
      tokenOf' ["every", "each", "all", "any"]; (q, f, v) <- notion
      vDecl <- makeDecls v
      return (q . flip (foldr dAll) vDecl . blImp f, pVar <$> Set.toList v)

    existential = do
      token' "some"; (q, f, v) <- notion
      vDecl <- makeDecls v
      return (q . flip (foldr dExi) vDecl . blAnd f, pVar <$> Set.toList v)

    no = do
      token' "no"; (q, f, v) <- notion
      vDecl<- makeDecls v
      return (q . flip (foldr dAll) vDecl . blImp f . Not, pVar <$> Set.toList v)


definiteTerm :: FTL (Formula -> Formula, Formula)
definiteTerm = label "definiteTerm" $  symbolicTerm -|- definiteNoun
  where
    definiteNoun = label "definiteNoun" $ paren (art >> primFun term)

symbolicTerm :: FTL (a -> a, Formula)
symbolicTerm = fmap ((,) id) sTerm


--- symbolic notation


symbolicFormula :: FTL Formula
symbolicFormula  = biimplication
  where
    biimplication = implication >>= binary Iff (symbol "<=>" >> implication)
    implication   = disjunction >>= binary Imp (symbol "=>"  >> implication)
    disjunction   = conjunction >>= binary Or  (symbol "\\/" >> disjunction)
    conjunction   = nonbinary   >>= binary And (symbol "/\\" >> conjunction)
    universal     = liftA2 (quantified dAll Imp) (token' "forall" >> (declared =<< symNotion)) nonbinary
    existential   = liftA2 (quantified dExi And) (token' "exists" >> (declared =<<symNotion)) nonbinary
    nonbinary     = universal -|- existential -|- negation -|- separated -|- atomic
    negation      = Not <$> (token' "not" >> nonbinary)
    separated     = token' ":" >> symbolicFormula

    quantified quant op (_, f, v) = flip (foldr quant) v . op f

    binary op p f = optLL1 f $ fmap (op f) p

    atomic = relation -|- parenthesised statement
      where
        relation = sChain </> primCpr sTerm

        sChain = fmap (foldl1 And . concat) sHd

        -- TODO: Rename with slightly more obvious names.
        -- First guess at the meaning of the naming:
        -- s = symbolic
        -- Hd = head
        -- l = left
        -- i = infix
        -- r = right
        --
        -- Combining of the two sides could probably be made
        -- clearer by using list comprehensions.

        sHd = lHd -|- (termChain >>= sTl)
        lHd = do
          pr <- primLpr sTerm
          rs <- termChain
          fmap (map pr rs :) $ opt [] $ sTl rs

        sTl ls = iTl ls -|- rTl ls
        iTl ls = do
          pr <- primIpr sTerm; rs <- termChain
          fmap (liftA2 pr ls rs :) $ opt [] $ sTl rs
        rTl ls = do pr <- primRpr sTerm; return [map pr ls]

        termChain = sTerm `sepBy` token' ","


sTerm :: FTL Formula
sTerm = iTerm
  where
    iTerm = lTerm >>= iTl
    iTl t = opt t $ (primIfn sTerm <*> return t <*> iTerm) >>= iTl

    lTerm = rTerm -|- label "symbolic term" (primLfn sTerm <*> lTerm)

    rTerm = cTerm >>= rTl
    rTl t = opt t $ (primRfn sTerm <*> return t) >>= rTl

    cTerm = label "symbolic term" $ sVar -|- parenthesised sTerm -|- primCfn sTerm

sVar :: FTL Formula
sVar = fmap pVar var

-- class term equations

classEquality :: FTL Formula
classEquality = twoClassTerms </> oneClassTerm
  where
    twoClassTerms = do
      (clss1, _) <- symbClassNotation; token "="
      (clss2, _) <- symbClassNotation;
      pure $ mkEquality clss1 clss2

    oneClassTerm = left </> right
    left = do
      (clss, _) <- symbClassNotation; token "="
      t <- sTerm
      pure $ mkEquality clss t
    right = do
      t <- sTerm; token "="
      (clss, _) <- symbClassNotation
      pure $ mkEquality t clss


-- selection

selection :: FTL Formula
selection = fmap (foldl1 And) $ (art >> takeLongest namedNotion) `sepByLL1` comma
  where
    namedNotion = label "named notion" $ do
      (q, f, vs) <- notion; guard (all isExplicitName $ map posVarName $ Set.toList vs); return $ q f
    isExplicitName (VarConstant _) = True; isExplicitName _ = False


-- function and class syntax

-- -- class

classNotion :: FTL Formula
classNotion = do
  v <- var; token "="; (_, f, _) <- clss
  dig (Tag Dig f) [pVar v]

clss :: FTL MNotion
clss = label "class definition" $ symbSet <|> classOf
  where
    classOf = do
      tokenOf' ["class", "classes"]; nm <- var -|- hidden; token' "of";
      nmDecl <- makeDecl nm
      (q, f, u) <- notion >>= single; vnm <- hidden
      return (id, classFormula $ Class nmDecl $ subst (pVar vnm) (posVarName u) $ q f, Set.singleton nm)
    symbSet = do
      (clss, nm) <- symbClassNotation
      return (id, classFormula clss, Set.singleton nm)
    classFormula = mkEquality (mkVar (VarHole ""))

symbClassNotation :: FTL (Formula, PosVar)
symbClassNotation = cndSet </> finSet
  where
    finSet = braced $ do
      ts <- sTerm `sepByLL1` token ","
      h <- hidden
      hDecl <- makeDecl h
      pure (Class hDecl $ foldr1 Or $ map (mkEquality $ pVar h) ts, h)
    cndSet = braced $ do
      (c, t) <- sepFrom
      st <- token "|" >> statement;
      vs <- freeVars t
      vsDecl <- makeDecls $ fvToVarSet vs;
      nm <- if isVar t then pure $ PosVar (varName t) (varPosition t) else hidden
      nmDecl <- makeDecl nm
      let nmVar = pVar nm
      pure (Class nmDecl $ bind (declName nmDecl) $ c nmVar `blAnd` mbEqu vsDecl nmVar t st, nm)

    -- | If we quantify over a variable v then vs = {v} and we can just substitute
    -- the new variable 'nmVar' for 'v'. Else we quantify over a term (say (x, y))
    -- and have to add exists quantifiers.
    mbEqu _ tr Var{varName = v} = subst tr v
    mbEqu vs tr t = \st -> foldr dExi (st `And` mkEquality tr t) vs

    -- | Split into a constraint and a term.
    -- For example: '(x, y) in Z^2' becomes (_ in Z^2, (x, y))
    sepFrom :: FTL (Formula -> Formula, Formula)
    sepFrom = notionSep -|- classSep -|- noSep
      where
        notionSep = do
          (q, f, v) <- notion >>= single
          guard (case f of Trm n _ _ _ -> n /= TermEquality; _ -> False)
          return (\tr -> subst tr (posVarName v) $ q f, pVar v)
        classSep = do
          t <- sTerm; cnd <- token' "in" >> elementCnd
          return (cnd, t)
        noSep  = do
          t <- sTerm; return (const Top, t)

    elementCnd :: FTL (Formula -> Formula)
    elementCnd = flip mkElem <$> (sTerm </> fmap fst symbClassNotation)


---- chain tools

multExi :: Foldable t1 =>
           [(t2 -> Formula, t2, t1 Decl)] -> Formula
multExi ((q, f, vs):ns) = foldr dExi (q f `blAnd` multExi ns) vs
multExi [] = Top

conjChain :: FTL Formula -> FTL Formula
conjChain = fmap (foldl1 And) . flip sepBy (token' "and")

quantifierChain :: FTL (Formula -> Formula)
quantifierChain = fmap (foldl fld id) $ token' "for" >> quantifiedNotion `sepByLL1` comma
-- we can use LL1 here, since there must always follow a parser belonging to the
-- same non-terminal
  where
    fld x (y, _) = x . y


-- Digger

dig :: Formula -> [Formula] -> FTL Formula
dig f [_] | occursS f = fail "too few subjects for an m-predicate"
dig f ts = return (dive f)
  where
    dive :: Formula -> Formula
    dive (Tag Dig f) = down digS f
    dive (Tag DigMultiSubject f) = down (digM $ zip ts $ tail ts) f
    dive (Tag DigMultiPairwise f) = down (digM $ pairs ts) f
    dive f | isTrm f = f
    dive f = mapF dive f

    down :: (Formula -> [Formula]) -> Formula -> Formula
    down fn (And f g) = And (down fn f) (down fn g)
    down fn f = foldl1 And (fn f)

    digS :: Formula -> [Formula]
    digS f
      | occursH f = map (\t -> subst t (VarHole "") f) ts
      | otherwise = [f]

    digM :: [(Formula, Formula)] -> Formula -> [Formula]
    digM ps f
      | not (occursS f) = digS f
      | not (occursH f) = map (\t -> subst t VarSlot f) $ tail ts
      | otherwise = map (\ (x,y) -> subst y VarSlot $ subst x (VarHole "") f) ps

-- Example:
-- pairs [1,2,3,4]
-- [(1,2),(1,3),(1,4),(2,3),(2,4),(3,4)]
pairs :: [a] -> [(a, a)]
pairs (t:ts) = [ (t, s) | s <- ts ] ++ pairs ts
pairs _ = []
