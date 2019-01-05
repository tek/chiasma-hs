module Chiasma.Test.Tmux(
  withTestTmux,
  tmuxSpec,
) where

import GHC.Real (fromIntegral)
import GHC.IO.Handle (Handle)
import System.FilePath ((</>))
import System.Posix.Pty (Pty, resizePty, createPty)
import System.Posix.Terminal (openPseudoTerminal)
import System.Posix.IO (fdToHandle)
import qualified System.Posix.Signals as Signal (signalProcess, killProcess)
import System.Process (getPid)
import System.Process.Typed (
  ProcessConfig,
  Process,
  withProcess,
  proc,
  setStdin,
  setStdout,
  setStderr,
  useHandleClose,
  unsafeProcessHandle,
  )
import UnliftIO (finally)
import UnliftIO.Temporary (withSystemTempDirectory)
import Chiasma.Native.Api (TmuxNative(..))
import Chiasma.Test.File (fixture)

data Terminal = Terminal Handle Pty

unsafeTerminal :: IO Terminal
unsafeTerminal = do
  (_, slave) <- openPseudoTerminal
  mayPty <- createPty slave
  handle <- fdToHandle slave
  pty <- maybe (error "couldn't spawn pty") return mayPty
  return $ Terminal handle pty

testTmuxProcessConfig :: FilePath -> FilePath -> Terminal -> IO (ProcessConfig () () ())
testTmuxProcessConfig socket confFile (Terminal handle pty) = do
  resizePty pty (1000, 1000)
  let stream = useHandleClose handle
  let stdio = setStdin stream . setStdout stream . setStderr stream
  return $ stdio $ proc "tmux" ["-S", socket, "-f", confFile]

killPid :: Integral a => a -> IO ()
killPid pid =
  Signal.signalProcess Signal.killProcess (fromIntegral pid)

killProcess :: Process () () () -> IO ()
killProcess prc = do
  let handle = unsafeProcessHandle prc
  mayPid <- getPid handle
  maybe (return ()) killPid mayPid

runAndKillTmux :: (TmuxNative -> IO a) -> TmuxNative -> Process () () () -> IO a
runAndKillTmux thunk api prc =
  finally (thunk api) (killProcess prc)

withTestTmux :: (TmuxNative -> IO a) -> FilePath -> IO a
withTestTmux thunk tempDir = do
  let socket = tempDir </> "tmux_socket"
  conf <- fixture "u" "tmux.conf"
  terminal <- unsafeTerminal
  pc <- testTmuxProcessConfig socket conf terminal
  withProcess pc $ runAndKillTmux thunk (TmuxNative socket)

tmuxSpec :: (TmuxNative -> IO a) -> IO a
tmuxSpec thunk =
  withSystemTempDirectory "chiasma-test" $ withTestTmux thunk
