{-# LANGUAGE TypeOperators #-}

module Chiasma.Codec.Decode where

import qualified Data.Text as Text (null, unpack)
import Data.Text.Read (decimal)
import GHC.Generics (K1(..), M1(..), (:*:)(..))
import Prelude hiding (many)
import Text.Parsec.Char (char, digit)
import Text.ParserCombinators.Parsec (
  GenParser,
  ParseError,
  many,
  parse,
  )

import Chiasma.Data.TmuxId (PaneId(..), SessionId(..), WindowId(..), panePrefix, sessionPrefix, windowPrefix)

data TmuxDecodeError =
  ParseFailure Text ParseError
  |
  IntParsingFailure Text
  |
  BoolParsingFailure Text
  |
  TooFewFields
  |
  TooManyFields [Text]
  deriving (Eq, Show)

class TmuxPrimDecode a where
  primDecode :: Text -> Either TmuxDecodeError a

class TmuxDataDecode f where
  decode' :: [Text] -> Either TmuxDecodeError ([Text], f a)

instance (TmuxDataDecode f, TmuxDataDecode g) => TmuxDataDecode (f :*: g) where
  decode' fields = do
    (rest, left) <- decode' fields
    (rest1, right) <- decode' rest
    return (rest1, left :*: right)

instance TmuxDataDecode f => (TmuxDataDecode (M1 i c f)) where
  decode' fields =
    second M1 <$> decode' fields

instance TmuxPrimDecode a => (TmuxDataDecode (K1 c a)) where
  decode' (a:as) = do
    prim <- primDecode a
    return (as, K1 prim)
  decode' [] = Left TooFewFields

readInt :: Text -> Text -> Either TmuxDecodeError Int
readInt input num =
  first (const $ IntParsingFailure input) parsed
  where
    parsed = do
      (num', rest) <- decimal num
      if Text.null rest then Right num' else Left ""

instance TmuxPrimDecode Int where
  primDecode field = readInt field field

instance TmuxPrimDecode Bool where
  primDecode field =
    convert =<< readInt field field
    where
      convert 0 =
        Right False
      convert 1 =
        Right True
      convert _ =
        Left (BoolParsingFailure $ "got non-bool `" <> show field <> "`")

idParser :: Char -> GenParser Char st Text
idParser sym =
  char sym *> (toText <$> many digit)

parseId :: (Int -> a) -> Char -> Text -> Either TmuxDecodeError a
parseId cons sym input = do
  num <- first (ParseFailure "id") $ parse (idParser sym) "none" (Text.unpack input)
  i <- readInt input num
  return $ cons i

instance TmuxPrimDecode SessionId where
  primDecode = parseId SessionId sessionPrefix

instance TmuxPrimDecode WindowId where
  primDecode = parseId WindowId windowPrefix

instance TmuxPrimDecode PaneId where
  primDecode = parseId PaneId panePrefix

instance TmuxPrimDecode [Char] where
  primDecode = Right . toString

instance TmuxPrimDecode Text where
  primDecode = Right
