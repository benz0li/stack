{-# LANGUAGE NoImplicitPrelude   #-}

{-|
Module      : System.Process.Pager
Description : Run external pagers (@$PAGER@, @less@, @more@).
License     : BSD-3-Clause

Run external pagers (@$PAGER@, @less@, @more@).
-}

module System.Process.Pager
  ( pageWriter
  , pageText
  , PagerException (..)
  ) where

import           Control.Monad.Trans.Maybe ( MaybeT (runMaybeT, MaybeT) )
import qualified Data.Text.IO as T
import           Stack.Prelude
import           System.Directory ( findExecutable )
import           System.Environment ( lookupEnv )
import           System.Process
                   ( createProcess, cmdspec, shell, proc, waitForProcess
                   , CmdSpec (ShellCommand, RawCommand)
                   , StdStream (CreatePipe)
                   , CreateProcess (std_in, close_fds, delegate_ctlc)
                   )

-- | Type representing exceptions thrown by functions exported by the
-- "System.Process.Pager" module.
data PagerException
  = PagerExitFailure CmdSpec Int
  deriving (Show, Typeable)

instance Exception PagerException where
  displayException (PagerExitFailure cmd n) =
    let getStr (ShellCommand c) = c
        getStr (RawCommand exePath _) = exePath
    in  concat
          [ "Error: [S-9392]\n"
          , "Pager (`"
          , getStr cmd
          , "') exited with non-zero status: "
          , show n
          ]

-- | Run pager, providing a function that writes to the pager's input.
pageWriter :: (Handle -> IO ()) -> IO ()
pageWriter writer = do
  let alternatives =
            cmdspecFromEnvVar
        <|> cmdspecFromExeName "less"
        <|> cmdspecFromExeName "more"
  runMaybeT alternatives >>= \case
    Just pager -> do
      (Just h,_,_,procHandle) <- createProcess pager
                                   { std_in = CreatePipe
                                   , close_fds = True
                                   , delegate_ctlc = True
                                   }
      (_ :: Either IOException ()) <- try (do writer h; hClose h)
      waitForProcess procHandle >>= \case
        ExitSuccess -> pure ()
        ExitFailure n -> throwIO (PagerExitFailure (cmdspec pager) n)
    Nothing -> writer stdout
 where
  cmdspecFromEnvVar = shell <$> MaybeT (lookupEnv "PAGER")
  cmdspecFromExeName =
    fmap (\command -> proc command []) . MaybeT . findExecutable

-- | Run pager to display a 'Text'
pageText :: Text -> IO ()
pageText = pageWriter . flip T.hPutStr
