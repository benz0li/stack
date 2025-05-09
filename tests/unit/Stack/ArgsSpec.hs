{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE OverloadedLists   #-}

-- | Args parser test suite.

module Stack.ArgsSpec
  ( spec
  , argsSpec
  , argsInputOutput
  , interpreterArgsSpec
  ) where

import           Data.Attoparsec.Args ( EscapingMode (..), parseArgsFromString )
import           Data.Attoparsec.Interpreter ( interpreterArgsParser )
import qualified Data.Attoparsec.Text as P
import qualified Data.List.NonEmpty as NE
import           Data.Text ( pack )
import           Stack.Constants ( stackProgName )
import           Stack.Prelude
import           Test.Hspec ( Spec, describe, it )

-- | Test spec.
spec :: Spec
spec = do
    argsSpec
    interpreterArgsSpec

argsSpec :: Spec
argsSpec = forM_ argsInputOutput
    (\(input,output) -> it input (parseArgsFromString Escaping input == output))

-- | Fairly comprehensive checks.
argsInputOutput :: [(String, Either String [String])]
argsInputOutput =
    [ ("x", Right ["x"])
    , ("x y z", Right ["x", "y", "z"])
    , ("aaa bbb ccc", Right ["aaa", "bbb", "ccc"])
    , ("    aaa    bbb    ccc   ", Right ["aaa", "bbb", "ccc"])
    , ("aaa\"", Left "unterminated string: endOfInput")
    , ("\"", Left "unterminated string: endOfInput")
    , ("\"\"", Right [""])
    , ("\"aaa", Left "unterminated string: endOfInput")
    , ("\"aaa\" bbb ccc \"ddd\"", Right ["aaa", "bbb", "ccc", "ddd"])
    , ("\"aa\\\"a\" bbb ccc \"ddd\"", Right ["aa\"a", "bbb", "ccc", "ddd"])
    , ("\"aa\\\"a\" bb\\b ccc \"ddd\"", Right ["aa\"a", "bb\\b", "ccc", "ddd"])
    , ("\"\" \"\" c", Right ["","","c"])]

interpreterArgsSpec :: Spec
interpreterArgsSpec =
    describe "Script interpreter parser" $ do
      describe "Success cases" $ do
        describe "Line comments" $ do
          checkLines ""
          checkLines " --x"
          checkLines " --x --y"
        describe "Literate line comments" $ do
          checkLiterateLines ""
          checkLiterateLines " --x"
          checkLiterateLines " --x --y"
        describe "Block comments" $ do
          checkBlocks ""
          checkBlocks "\n"
          checkBlocks " --x"
          checkBlocks "\n--x"
          checkBlocks " --x --y"
          checkBlocks "\n--x\n--y"
          checkBlocks "\n\t--x\n\t--y"
        describe "Literate block comments" $ do
          checkLiterateBlocks "" ""
          checkLiterateBlocks "\n>" ""
          checkLiterateBlocks " --x" " --x"
          checkLiterateBlocks "\n>--x" "--x"
          checkLiterateBlocks " --x --y " "--x --y"
          checkLiterateBlocks "\n>--x\n>--y" "--x --y"
          checkLiterateBlocks "\n>\t--x\n>\t--y" "--x --y"
      describe "Failure cases" $ do
        checkFailures
        describe "Bare directives in literate files" $ do
          forM_ (interpreterGenValid lineComment "") $
            testAndCheck (acceptFailure True) ""
          forM_ (interpreterGenValid blockComment "") $
            testAndCheck (acceptFailure True) ""
    where
      parse isLiterate s =
        P.parseOnly (interpreterArgsParser isLiterate stackProgName) (pack s)

      acceptSuccess :: Bool -> String -> String -> Bool
      acceptSuccess isLiterate args s = case parse isLiterate s of
                               Right x | words x == words args -> True
                               _ -> False

      acceptFailure isLiterate _ s =  case parse isLiterate s of
                           Left _ -> True
                           Right _ -> False

      testAndCheck checker out inp = it (show inp) $ checker out inp

      checkLines args = forM_
        (interpreterGenValid lineComment args)
        (testAndCheck (acceptSuccess False) args)

      checkLiterateLines args = forM_
        (interpreterGenValid literateLineComment args)
        (testAndCheck (acceptSuccess True) args)

      checkBlocks args = forM_
        (interpreterGenValid blockComment args)
        (testAndCheck (acceptSuccess False) args)

      checkLiterateBlocks inp args = forM_
        (interpreterGenValid literateBlockComment inp)
        (testAndCheck (acceptSuccess True) args)

      checkFailures = forM_
        interpreterGenInvalid
        (testAndCheck (acceptFailure False) "unused")

      -- Generate a set of acceptable inputs for given format and args
      interpreterGenValid ::
           (String -> NonEmpty String)
        -> String
        -> NonEmpty String
      interpreterGenValid fmt args = shebang <++> newLine <++> fmt args

      interpreterGenInvalid :: NonEmpty String
      -- Generate a set of Invalid inputs
      interpreterGenInvalid =
        ["-stack\n"] -- random input
        -- just the shebang
        <> shebang <++> ["\n"]
        -- invalid shebang
        <> blockSpace <++> [NE.head (interpreterGenValid lineComment args)]
        -- something between shebang and Stack comment
        <> shebang
            <++> newLine
            <++> blockSpace
            <++> ([NE.head (lineComment args)] <> [NE.head (blockComment args)])
        -- unterminated block comment
        -- just chop the closing chars from a valid block comment
        <> shebang
            <++> ["\n"]
            <++> let c = NE.head (blockComment args)
                     l = length c - 2
                 in  [assert (drop l c == "-}") (take l c)]
        -- nested block comment
        <> shebang
            <++> ["\n"]
            <++> [NE.head (blockComment "--x {- nested -} --y")]
       where
        args = " --x --y"
      (<++>) = liftA2 (<>)

      -- Generative grammar for the interpreter comments
      shebang :: NonEmpty String
      shebang = ["#!/usr/bin/env stack"]

      newLine :: NonEmpty String
      newLine = ["\n"] <> ["\r\n"]

      -- A comment may be the last line or followed by something else
      postComment :: NonEmpty String
      postComment = [""] <> newLine

      -- A command starts with zero or more whitespace followed by "stack"
      makeComment ::
           (String -> String)
        -> NonEmpty String
        -> String
        -> NonEmpty String
      makeComment maker space args =
        let makePrefix :: NonEmpty String -> NonEmpty String
            makePrefix s = (s <> [""]) <++> [stackProgName]
        in  (maker <$> (makePrefix space <&> (++ args))) <++> postComment

      lineSpace :: NonEmpty String
      lineSpace = [" "] <> ["\t"]

      lineComment :: String -> NonEmpty String
      lineComment = makeComment makeLine lineSpace
       where
        makeLine s = "--" ++ s

      literateLineComment :: String -> NonEmpty String
      literateLineComment = makeComment ("> --" ++) lineSpace

      blockSpace :: NonEmpty String
      blockSpace = lineSpace <> newLine

      blockComment :: String -> NonEmpty String
      blockComment = makeComment makeBlock blockSpace
       where
        makeBlock s = "{-" ++ s ++ "-}"

      literateBlockComment :: String -> NonEmpty String
      literateBlockComment = makeComment
        (\s -> "> {-" ++ s ++ "-}")
        (lineSpace <> NE.map (++ ">") newLine)
