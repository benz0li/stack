{-# LANGUAGE NoImplicitPrelude #-}

{-|
Module      : Path.Find
Description : Finding files.
License     : BSD-3-Clause

Finding files.
-}

module Path.Find
  ( findFileUp
  , findDirUp
  , findFiles
  , findInParents
  ) where

import qualified Data.List as L
import           Path ( Abs, Dir, File, Path, parent, toFilePath )
import           Path.IO ( listDir )
import           RIO
import           System.IO.Error ( isPermissionError )
import           System.PosixCompat.Files
                   ( getSymbolicLinkStatus, isSymbolicLink )

-- | Find the location of a file matching the given predicate.
findFileUp ::
     (MonadIO m, MonadThrow m)
  => Path Abs Dir              -- ^ Start here.
  -> (Path Abs File -> Bool)   -- ^ Predicate to match the file.
  -> Maybe (Path Abs Dir)      -- ^ Do not ascend above this directory.
  -> m (Maybe (Path Abs File)) -- ^ Absolute file path.
findFileUp = findPathUp snd

-- | Find the location of a directory matching the given predicate.
findDirUp ::
     (MonadIO m,MonadThrow m)
  => Path Abs Dir               -- ^ Start here.
  -> (Path Abs Dir -> Bool)     -- ^ Predicate to match the directory.
  -> Maybe (Path Abs Dir)       -- ^ Do not ascend above this directory.
  -> m (Maybe (Path Abs Dir))   -- ^ Absolute directory path.
findDirUp = findPathUp fst

-- | Find the location of a path matching the given predicate.
findPathUp ::
     (MonadIO m,MonadThrow m)
  => (([Path Abs Dir],[Path Abs File]) -> [Path Abs t])
     -- ^ Choose path type from pair.
  -> Path Abs Dir
     -- ^ Start here.
  -> (Path Abs t -> Bool)
     -- ^ Predicate to match the path.
  -> Maybe (Path Abs Dir)
     -- ^ Do not ascend above this directory.
  -> m (Maybe (Path Abs t))
     -- ^ Absolute path.
findPathUp pathType dir p upperBound = do
  entries <- listDir dir
  case L.find p (pathType entries) of
    Just path -> pure (Just path)
    Nothing | Just dir == upperBound -> pure Nothing
            | parent dir == dir -> pure Nothing
            | otherwise -> findPathUp pathType (parent dir) p upperBound

-- | Find files matching predicate below a root directory.
--
-- NOTE: this skips symbolic directory links, to avoid loops. This may
-- not make sense for all uses of file finding.
--
-- TODO: write one of these that traverses symbolic links but
-- efficiently ignores loops.
findFiles ::
     Path Abs Dir
     -- ^ Root directory to begin with.
  -> (Path Abs File -> Bool)
     -- ^ Predicate to match files.
  -> (Path Abs Dir -> Bool)
     -- ^ Predicate for which directories to traverse.
  -> IO [Path Abs File]
     -- ^ List of matching files.
findFiles dir p traversep = do
  (dirs,files) <- catchJust (\ e -> if isPermissionError e
                                      then Just ()
                                      else Nothing)
                            (listDir dir)
                            (\ _ -> pure ([], []))
  filteredFiles <- evaluate $ force (filter p files)
  filteredDirs <- filterM (fmap not . isSymLink) dirs
  subResults <-
    forM filteredDirs
         (\entry ->
            if traversep entry
               then findFiles entry p traversep
               else pure [])
  pure (concat (filteredFiles : subResults))

isSymLink :: Path Abs t -> IO Bool
isSymLink = fmap isSymbolicLink . getSymbolicLinkStatus . toFilePath

-- | @findInParents f path@ applies @f@ to @path@ and its 'parent's until
-- it finds a 'Just' or reaches the root directory.
findInParents ::
     MonadIO m
  => (Path Abs Dir -> m (Maybe a))
  -> Path Abs Dir -> m (Maybe a)
findInParents f path = f path >>= \case
  Just res -> pure (Just res)
  Nothing -> do
    let next = parent path
    if next == path
      then pure Nothing
      else findInParents f next
