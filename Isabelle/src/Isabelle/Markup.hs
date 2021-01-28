{- generated by Isabelle -}

{-  Title:      Haskell/Tools/Markup.hs
    Author:     Makarius
    LICENSE:    BSD 3-clause (Isabelle)

Quasi-abstract markup elements.

See also "$ISABELLE_HOME/src/Pure/PIDE/markup.ML".
-}

{-# OPTIONS_GHC -fno-warn-missing-signatures #-}

module Isabelle.Markup (
  T, empty, is_empty, properties,

  nameN, name, xnameN, xname, kindN,

  bindingN, binding, entityN, entity, defN, refN,

  completionN, completion, no_completionN, no_completion,

  lineN, end_lineN, offsetN, end_offsetN, fileN, idN, positionN, position,

  expressionN, expression,

  citationN, citation,

  pathN, path, urlN, url, docN, doc,

  markupN, consistentN, unbreakableN, indentN, widthN,
  blockN, block, breakN, break, fbreakN, fbreak, itemN, item,

  wordsN, words,

  tfreeN, tfree, tvarN, tvar, freeN, free, skolemN, skolem, boundN, bound, varN, var,
  numeralN, numeral, literalN, literal, delimiterN, delimiter, inner_stringN, inner_string,
  inner_cartoucheN, inner_cartouche,
  token_rangeN, token_range,
  sortingN, sorting, typingN, typing, class_parameterN, class_parameter,

  antiquotedN, antiquoted, antiquoteN, antiquote,

  paragraphN, paragraph, text_foldN, text_fold,

  keyword1N, keyword1, keyword2N, keyword2, keyword3N, keyword3, quasi_keywordN, quasi_keyword,
  improperN, improper, operatorN, operator, stringN, string, alt_stringN, alt_string,
  verbatimN, verbatim, cartoucheN, cartouche, commentN, comment, comment1N, comment1,
  comment2N, comment2, comment3N, comment3,

  forkedN, forked, joinedN, joined, runningN, running, finishedN, finished,
  failedN, failed, canceledN, canceled, initializedN, initialized, finalizedN, finalized,
  consolidatedN, consolidated,

  writelnN, writeln, stateN, state, informationN, information, tracingN, tracing,
  warningN, warning, legacyN, legacy, errorN, error, reportN, report, no_reportN, no_report,

  intensifyN, intensify,
  Output, no_output)
where

import Prelude hiding (words, error, break)

import Isabelle.Library
import qualified Isabelle.Properties as Properties
import qualified Isabelle.Value as Value


{- basic markup -}

type T = (String, Properties.T)

empty :: T
empty = ("", [])

is_empty :: T -> Bool
is_empty ("", _) = True
is_empty _ = False

properties :: Properties.T -> T -> T
properties more_props (elem, props) =
  (elem, fold_rev Properties.put more_props props)

markup_elem name = (name, (name, []) :: T)
markup_string name prop = (name, \s -> (name, [(prop, s)]) :: T)


{- misc properties -}

nameN :: String
nameN = "name"

name :: String -> T -> T
name a = properties [(nameN, a)]

xnameN :: String
xnameN = "xname"

xname :: String -> T -> T
xname a = properties [(xnameN, a)]

kindN :: String
kindN = "kind"


{- formal entities -}

(bindingN, binding) = markup_elem "binding"

entityN :: String; entity :: String -> String -> T
entityN = "entity"
entity kind name =
  (entityN,
    (if null name then [] else [(nameN, name)]) ++ (if null kind then [] else [(kindN, kind)]))

defN :: String
defN = "def"

refN :: String
refN = "ref"


{- completion -}

(completionN, completion) = markup_elem "completion"

(no_completionN, no_completion) = markup_elem "no_completion"


{- position -}

lineN, end_lineN :: String
lineN = "line"
end_lineN = "end_line"

offsetN, end_offsetN :: String
offsetN = "offset"
end_offsetN = "end_offset"

fileN, idN :: String
fileN = "file"
idN = "id"

(positionN, position) = markup_elem "position"


{- expression -}

expressionN :: String
expressionN = "expression"

expression :: String -> T
expression kind = (expressionN, if kind == "" then [] else [(kindN, kind)])


{- citation -}

(citationN, citation) = markup_string "citation" nameN


{- external resources -}

(pathN, path) = markup_string "path" nameN

(urlN, url) = markup_string "url" nameN

(docN, doc) = markup_string "doc" nameN


{- pretty printing -}

markupN, consistentN, unbreakableN, indentN :: String
markupN = "markup";
consistentN = "consistent";
unbreakableN = "unbreakable";
indentN = "indent";

widthN :: String
widthN = "width"

blockN :: String
blockN = "block"
block :: Bool -> Int -> T
block c i =
  (blockN,
    (if c then [(consistentN, Value.print_bool c)] else []) ++
    (if i /= 0 then [(indentN, Value.print_int i)] else []))

breakN :: String
breakN = "break"
break :: Int -> Int -> T
break w i =
  (breakN,
    (if w /= 0 then [(widthN, Value.print_int w)] else []) ++
    (if i /= 0 then [(indentN, Value.print_int i)] else []))

(fbreakN, fbreak) = markup_elem "fbreak"

(itemN, item) = markup_elem "item"


{- text properties -}

(wordsN, words) = markup_elem "words"


{- inner syntax -}

(tfreeN, tfree) = markup_elem "tfree"

(tvarN, tvar) = markup_elem "tvar"

(freeN, free) = markup_elem "free"

(skolemN, skolem) = markup_elem "skolem"

(boundN, bound) = markup_elem "bound"

(varN, var) = markup_elem "var"

(numeralN, numeral) = markup_elem "numeral"

(literalN, literal) = markup_elem "literal"

(delimiterN, delimiter) = markup_elem "delimiter"

(inner_stringN, inner_string) = markup_elem "inner_string"

(inner_cartoucheN, inner_cartouche) = markup_elem "inner_cartouche"


(token_rangeN, token_range) = markup_elem "token_range"


(sortingN, sorting) = markup_elem "sorting"

(typingN, typing) = markup_elem "typing"

(class_parameterN, class_parameter) = markup_elem "class_parameter"


{- antiquotations -}

(antiquotedN, antiquoted) = markup_elem "antiquoted"

(antiquoteN, antiquote) = markup_elem "antiquote"


{- text structure -}

(paragraphN, paragraph) = markup_elem "paragraph"

(text_foldN, text_fold) = markup_elem "text_fold"


{- outer syntax -}

(keyword1N, keyword1) = markup_elem "keyword1"

(keyword2N, keyword2) = markup_elem "keyword2"

(keyword3N, keyword3) = markup_elem "keyword3"

(quasi_keywordN, quasi_keyword) = markup_elem "quasi_keyword"

(improperN, improper) = markup_elem "improper"

(operatorN, operator) = markup_elem "operator"

(stringN, string) = markup_elem "string"

(alt_stringN, alt_string) = markup_elem "alt_string"

(verbatimN, verbatim) = markup_elem "verbatim"

(cartoucheN, cartouche) = markup_elem "cartouche"

(commentN, comment) = markup_elem "comment"


{- comments -}

(comment1N, comment1) = markup_elem "comment1"

(comment2N, comment2) = markup_elem "comment2"

(comment3N, comment3) = markup_elem "comment3"


{- command status -}

(forkedN, forked) = markup_elem "forked"
(joinedN, joined) = markup_elem "joined"
(runningN, running) = markup_elem "running"
(finishedN, finished) = markup_elem "finished"
(failedN, failed) = markup_elem "failed"
(canceledN, canceled) = markup_elem "canceled"
(initializedN, initialized) = markup_elem "initialized"
(finalizedN, finalized) = markup_elem "finalized"
(consolidatedN, consolidated) = markup_elem "consolidated"


{- messages -}

(writelnN, writeln) = markup_elem "writeln"

(stateN, state) = markup_elem "state"

(informationN, information) = markup_elem "information"

(tracingN, tracing) = markup_elem "tracing"

(warningN, warning) = markup_elem "warning"

(legacyN, legacy) = markup_elem "legacy"

(errorN, error) = markup_elem "error"

(reportN, report) = markup_elem "report"

(no_reportN, no_report) = markup_elem "no_report"

(intensifyN, intensify) = markup_elem "intensify"


{- output -}

type Output = (String, String)

no_output :: Output
no_output = ("", "")
