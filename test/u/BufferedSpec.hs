{-# OPTIONS_GHC -F -pgmF htfpp #-}

module BufferedSpec(
  htf_thisModulesTests
) where

import Data.Either (isLeft)
import Test.Framework
import Chiasma.Native.Api (TmuxNative(..))
import Chiasma.Data.Window (Window)
import Chiasma.Data.Pane (Pane)
import Chiasma.Data.TmuxThunk (TmuxError)
import Chiasma.Monad.Buffered (runTmux)
import Chiasma.Monad.Tmux (TmuxProg)
import qualified Chiasma.Monad.Tmux as Tmux (read, write)
import Chiasma.Test.Tmux (tmuxSpec)

prog :: TmuxProg ([Pane], [Pane], [Window])
prog = do
  panes1 <- Tmux.read "list-panes" ["-t", "%0"]
  Tmux.write "new-window" []
  Tmux.write "new-window" []
  wins <- Tmux.read @Window "list-windows" []
  panes <- Tmux.read "list-panes" ["-a"]
  return (panes1, panes, wins)

runProg :: TmuxNative -> IO (Either TmuxError ([Pane], [Pane], [Window]))
runProg api = runTmux api prog

test_buffered :: IO ()
test_buffered = do
  result <- tmuxSpec runProg
  print result
  assertEqual True (isLeft result)
