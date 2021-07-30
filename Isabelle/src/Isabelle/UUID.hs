{- generated by Isabelle -}

{-  Title:      Isabelle/UUID.hs
    Author:     Makarius
    LICENSE:    BSD 3-clause (Isabelle)

Universally unique identifiers.

See "$ISABELLE_HOME/src/Pure/General/uuid.scala".
-}

module Isabelle.UUID (
    T,
    parse_string, parse_bytes,
    string, bytes,
    random, random_string, random_bytes
  )
where

import Data.UUID (UUID)
import qualified Data.UUID as UUID
import Data.UUID.V4 (nextRandom)

import qualified Isabelle.Bytes as Bytes
import Isabelle.Bytes (Bytes)


type T = UUID


{- parse -}

parse_string :: String -> Maybe T
parse_string = UUID.fromString

parse_bytes :: Bytes -> Maybe T
parse_bytes = UUID.fromASCIIBytes . Bytes.unmake


{- print -}

string :: T -> String
string = UUID.toString

bytes :: T -> Bytes
bytes = Bytes.make . UUID.toASCIIBytes


{- random id -}

random :: IO T
random = nextRandom

random_string :: IO String
random_string = string <$> random

random_bytes :: IO Bytes
random_bytes = bytes <$> random