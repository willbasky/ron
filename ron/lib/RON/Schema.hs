{-# LANGUAGE NamedFieldPuns #-}

module RON.Schema (
    CaseTransform (..),
    Declaration (..),
    Field (..),
    Opaque (..),
    OpaqueAnnotations (..),
    RonType (..),
    Schema,
    StructAnnotations (..),
    StructLww (..),
    TAtom (..),
    TEnum (..),
    TComposite (..),
    TObject (..),
    defaultOpaqueAnnotations,
    defaultStructAnnotations,
    opaqueAtoms,
    opaqueAtoms_,
    opaqueObject,
) where

import           RON.Internal.Prelude

import qualified Data.Text as Text

data TAtom = TAInteger | TAString
    deriving (Show)

data RonType
    = TAtom      TAtom
    | TComposite TComposite
    | TObject    TObject
    | TOpaque    Opaque
    deriving (Show)

data TComposite
    = TOption RonType
    | TEnum   TEnum
    deriving (Show)

data TEnum = Enum {enumName :: Text, enumItems :: [Text]}
    deriving (Show)

data TObject
    = TORSet     RonType
    | TRga       RonType
    | TStructLww StructLww
    | TVersionVector
    deriving (Show)

data StructLww = StructLww
    { structName        :: Text
    , structFields      :: Map Text Field
    , structAnnotations :: StructAnnotations
    }
    deriving (Show)

data StructAnnotations = StructAnnotations
    { saHaskellFieldPrefix        :: Text
    , saHaskellFieldCaseTransform :: Maybe CaseTransform
    }
    deriving (Show)

defaultStructAnnotations :: StructAnnotations
defaultStructAnnotations = StructAnnotations
    {saHaskellFieldPrefix = Text.empty, saHaskellFieldCaseTransform = Nothing}

data CaseTransform = TitleCase
    deriving (Show)

newtype Field = Field{fieldType :: RonType}
    deriving (Show)

data Declaration = DEnum TEnum | DOpaque Opaque | DStructLww StructLww

type Schema = [Declaration]

newtype OpaqueAnnotations = OpaqueAnnotations{oaHaskellType :: Maybe Text}
    deriving (Show)

defaultOpaqueAnnotations :: OpaqueAnnotations
defaultOpaqueAnnotations = OpaqueAnnotations{oaHaskellType = Nothing}

data Opaque = Opaque
    { opaqueIsObject    :: Bool
    , opaqueName        :: Text
    , opaqueAnnotations :: OpaqueAnnotations
    }
    deriving (Show)

opaqueObject :: Text -> OpaqueAnnotations -> RonType
opaqueObject name = TOpaque . Opaque True name

opaqueAtoms :: Text -> OpaqueAnnotations -> RonType
opaqueAtoms name = TOpaque . Opaque False name

opaqueAtoms_ :: Text -> RonType
opaqueAtoms_ name = TOpaque $ Opaque False name defaultOpaqueAnnotations
