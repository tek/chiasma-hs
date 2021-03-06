module Chiasma.Test.Screenshot where

import Control.Monad.Free.Class (MonadFree)
import qualified Data.ByteString as ByteString (writeFile)
import qualified Data.Text as Text (lines, unlines)
import qualified Data.Text.Encoding as Text (encodeUtf8)
import System.FilePath (takeDirectory, (</>))
import UnliftIO.Directory (createDirectoryIfMissing, doesFileExist)

import Chiasma.Command.Pane (capturePane)
import Chiasma.Data.TmuxId (PaneId(PaneId))
import Chiasma.Data.TmuxThunk (TmuxThunk)

loadScreenshot :: MonadIO m => FilePath -> m (Maybe Text)
loadScreenshot path =
  ifM (doesFileExist path) (Just . toText <$> liftIO (readFile path)) (pure Nothing)

storeScreenshot :: MonadIO m => FilePath -> [Text] -> m ()
storeScreenshot path text = do
  createDirectoryIfMissing True (takeDirectory path)
  liftIO $ ByteString.writeFile path (Text.encodeUtf8 . Text.unlines $ text)

takeScreenshot ::
  MonadFree TmuxThunk m =>
  MonadIO m =>
  Int ->
  m [Text]
takeScreenshot =
  capturePane . PaneId

recordScreenshot ::
  MonadFree TmuxThunk m =>
  MonadIO m =>
  FilePath ->
  Int ->
  m ()
recordScreenshot path paneId = do
  current <- takeScreenshot paneId
  storeScreenshot path current

testScreenshot ::
  MonadFree TmuxThunk m =>
  MonadIO m =>
  FilePath ->
  Int ->
  m (Maybe ([Text], [Text]))
testScreenshot path pane = do
  current <- takeScreenshot pane
  loadScreenshot path >>= check current
  where
    check current (Just existing) =
      return $ Just (current, Text.lines existing)
    check current Nothing =
      Nothing <$ storeScreenshot path current

screenshot ::
  MonadFree TmuxThunk m =>
  MonadIO m =>
  Bool ->
  FilePath ->
  Text ->
  Int ->
  m (Maybe ([Text], [Text]))
screenshot record storage name paneId =
  if record then Nothing <$ recordScreenshot path paneId else testScreenshot path paneId
  where
    path = storage </> toString name
