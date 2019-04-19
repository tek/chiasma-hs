{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveAnyClass #-}

module Chiasma.Ui.Data.ViewGeometry(
  ViewGeometry(..),
) where

import Data.Data (Data)
import Data.Default.Class (Default)
import Data.Text.Prettyprint.Doc (Doc, Pretty(..), emptyDoc, nest, space, vsep, (<+>))
import GHC.Generics (Generic)

data ViewGeometry =
  ViewGeometry {
    minSize :: Maybe Float,
    maxSize :: Maybe Float,
    fixedSize :: Maybe Float,
    minimizedSize :: Maybe Float,
    weight :: Maybe Float,
    position :: Maybe Float
  }
  deriving (Eq, Show, Data, Generic, Default)

mayPretty :: String -> Maybe Float -> Doc a
mayPretty prefix (Just a) =
  space <> pretty prefix <> ":" <+> pretty a
mayPretty _ Nothing =
  emptyDoc

instance Pretty ViewGeometry where
  pretty (ViewGeometry minSize maxSize fixedSize _ _ _) =
    foldl (<>) emptyDoc (uncurry mayPretty <$> [("min", minSize), ("max", maxSize), ("fixed", fixedSize)])
