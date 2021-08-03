{- generated by Isabelle -}

{-  Title:      Isabelle/Name.hs
    Author:     Makarius

Names of basic logical entities (variables etc.).

See also "$ISABELLE_HOME/src/Pure/name.ML".
-}

{-# LANGUAGE OverloadedStrings #-}

module Isabelle.Name (
  Name, clean_index, clean,
  Context, declare, is_declared, context, make_context, variant
)
where

import Data.Word (Word8)
import qualified Data.Set as Set
import Data.Set (Set)
import qualified Isabelle.Bytes as Bytes
import Isabelle.Bytes (Bytes)
import qualified Isabelle.Symbol as Symbol
import Isabelle.Library


type Name = Bytes


{- suffix for internal names -}

underscore :: Word8
underscore = Bytes.byte '_'

clean_index :: Name -> (Name, Int)
clean_index x =
  if Bytes.null x || Bytes.last x /= underscore then (x, 0)
  else
    let
      rev = reverse (Bytes.unpack x)
      n = length (takeWhile (== underscore) rev)
      y = Bytes.pack (reverse (drop n rev))
    in (y, n)

clean :: Name -> Name
clean = fst . clean_index


{- context for used names -}

data Context = Context (Set Name)

declare :: Name -> Context -> Context
declare x (Context names) = Context (Set.insert x names)

is_declared :: Context -> Name -> Bool
is_declared (Context names) x = Set.member x names

context :: Context
context = Context (Set.fromList ["", "'"])

make_context :: [Name] -> Context
make_context used = fold declare used context


{- generating fresh names -}

bump_init :: Name -> Name
bump_init str = str <> "a"

bump_string :: Name -> Name
bump_string str =
  let
    a = Bytes.byte 'a'
    z = Bytes.byte 'z'
    bump (b : bs) | b == z = a : bump bs
    bump (b : bs) | a <= b && b < z = b + 1 : bs
    bump bs = a : bs

    rev = reverse (Bytes.unpack str)
    part2 = reverse (takeWhile (Symbol.is_ascii_quasi . Bytes.char) rev)
    part1 = reverse (bump (drop (length part2) rev))
  in Bytes.pack (part1 <> part2)

variant :: Name -> Context -> (Name, Context)
variant name names =
  let
    vary bump x = if is_declared names x then bump x |> vary bump_string else x
    (x, n) = clean_index name
    x' = x |> vary bump_init
    names' = declare x' names;
  in (x' <> Bytes.pack (replicate n underscore), names')
