{-# OPTIONS_GHC -F -pgmF htfpp #-}

module BufferedSpec(
  htf_thisModulesTests
) where

import Data.Either (isLeft)
import Test.Framework
import UnliftIO (try)
import Chiasma.Api (TmuxNative(..))
import Chiasma.Data.TmuxThunk (TmuxCommandFailed)
import Chiasma.Monad.Buffered (runTmux)
import Chiasma.Monad.Tmux (TmuxProg)
import qualified Chiasma.Monad.Tmux as Tmux (read, write)
import Chiasma.Test.Tmux (tmuxSpec)

number :: TmuxProg a String
number = return "1"

prog :: TmuxProg a [String]
prog = do
  a <- number
  out <- Tmux.read "list-panes" ["-t", "%" ++ a]
  Tmux.write "new-windowXXX" []
  return out

runProg :: TmuxNative -> IO [String]
runProg api = runTmux api prog

test_buffered :: IO ()
test_buffered = do
  result <- tmuxSpec (try . runProg)
  assertEqual True (isLeft (result :: Either TmuxCommandFailed [String]))
