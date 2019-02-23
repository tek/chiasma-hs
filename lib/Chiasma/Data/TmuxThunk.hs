{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE StandaloneDeriving #-}

module Chiasma.Data.TmuxThunk(
  CmdName(..),
  CmdArgs(..),
  TmuxThunk(..),
  TmuxError(..),
  Cmd(..),
  Cmds(..),
  cmd,
) where

import Data.Text (Text)

import Chiasma.Codec.Decode (TmuxDecodeError)
import Chiasma.Data.Cmd (CmdName(..), CmdArgs(..), Cmd(..), Cmds(..), cmd)
import Chiasma.Data.TmuxError (TmuxError(..))

data TmuxThunk next =
  ∀ a . Read Cmd ([Text] -> Either TmuxDecodeError a) ([a] -> next)
  |
  Write Cmd (() -> next)
  |
  Failed TmuxError

deriving instance Functor TmuxThunk
