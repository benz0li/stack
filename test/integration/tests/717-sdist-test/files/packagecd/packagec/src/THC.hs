{-# LANGUAGE TemplateHaskell #-}
module THC (thFuncC) where

import Language.Haskell.TH

thFuncC :: Q Exp
thFuncC = runIO $ do
  readFile "files/file.txt"
  return $ LitE (IntegerL 5)
