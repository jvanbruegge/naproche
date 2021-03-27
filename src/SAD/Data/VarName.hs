{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE DeriveGeneric #-}

module SAD.Data.VarName
  ( VarName(..)
  , FV, unitFV, bindVar, excludeVars
  , excludeSet
  , IsVar(..)
  , fvToVarSet
  , fvFromVarSet
  , varToText
  , PosVar(..)
  ) where

import Data.Set (Set)
import qualified Data.Set as Set
import GHC.Magic (oneShot)
import Data.Text (Text)
import qualified Data.Text as Text
import Data.Text.Prettyprint.Doc
import SAD.Core.SourcePos
import Data.Function (on)
import GHC.Generics (Generic)
import Data.Hashable (Hashable)
import Data.Binary (Binary)
import Control.DeepSeq (NFData)

-- These names may not reflect what the constructors are used for..
data VarName 
  = VarConstant Text   -- ^ previously starting with x
  | VarHole Text       -- ^ previously starting with ?
  | VarSlot            -- ^ previously !
  | VarHidden Int      -- ^ previously starting with h
  | VarF Int           -- ^ for function outputs
  | VarEmpty           -- ^ previously ""
  | VarDefault Text    -- ^ everything else
  deriving (Eq, Ord, Show, Read, Generic)
instance NFData VarName
instance Hashable VarName
instance Binary VarName

varToText :: VarName -> Text
varToText (VarConstant s) = s
varToText (VarHole s) = "?" <> ( s)
varToText (VarSlot) = "!"
varToText (VarHidden n) = "h" <> (Text.pack (show n))
varToText (VarF s) = "out_" <> (Text.pack (show s))
varToText (VarEmpty) = ""
varToText (VarDefault s) =  s

instance Pretty VarName where
  pretty (VarConstant s) = pretty s
  pretty (VarHole s) = pretty $ "?" <> ( s)
  pretty (VarSlot) = "!"
  pretty (VarHidden n) = "h" <> pretty n
  pretty (VarF s) = "out_" <> pretty s
  pretty (VarEmpty) = ""
  pretty (VarDefault s) = pretty s

data PosVar = PosVar
  { posVarName :: VarName
  , posVarPosition :: SourcePos
  } deriving (Show)

instance Eq PosVar where
  (==) = (==) `on` posVarName

instance Ord PosVar where
  compare = compare `on` posVarName

instance Pretty PosVar where
  pretty (PosVar v p) = "(" <> pretty v <> ", " <> pretty (show p) <> ")"

class (Ord a, Pretty a) => IsVar a where
  buildVar :: VarName -> SourcePos -> a

instance IsVar VarName where
  buildVar = const

instance IsVar PosVar where
  buildVar = PosVar

-- Free variable traversals, see
-- https://www.haskell.org/ghc/blog/20190728-free-variable-traversals.html
-- for explanation

newtype FV a = FV
  { runFV :: Set VarName  -- bound variable set
          -> Set a  -- the accumulator
          -> Set a  -- the result
  }

instance Monoid (FV a) where
  mempty = FV $ oneShot $ \_ acc -> acc

instance Semigroup (FV a) where
  fv1 <> fv2 = FV $ oneShot $ \boundVars -> oneShot $ \acc ->
    runFV fv1 boundVars (runFV fv2 boundVars acc)

unitFV :: IsVar a => VarName -> SourcePos -> FV a
unitFV v s = FV $ oneShot $ \boundVars -> oneShot $ \acc ->
  if Set.member v boundVars
  then acc
  else Set.insert (buildVar v s) acc

bindVar :: Ord a => VarName -> FV a -> FV a
bindVar v fv = FV $ oneShot $ \boundVars -> oneShot $ \acc ->
  runFV fv (Set.insert v boundVars) acc

excludeVars :: Ord a => FV VarName -> FV a -> FV a
excludeVars fv1 fv2 = FV $ oneShot $ \boundVars -> oneShot $ \acc ->
  runFV fv2 (runFV fv1 mempty boundVars) acc

excludeSet :: IsVar a => FV a -> Set VarName -> FV a
excludeSet fs vs = excludeVars (fvFromVarSet id vs) fs

fvFromVarSet :: Ord a => (a -> VarName) -> Set a -> FV a
fvFromVarSet f vs = FV $ oneShot $ \boundVars -> oneShot $ \acc ->
  acc `Set.union` (Set.filter (\a -> Set.notMember (f a) boundVars) vs)

fvToVarSet :: Ord a => FV a -> Set a
fvToVarSet fv = runFV fv mempty mempty