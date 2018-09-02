{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module RON.Data
    ( reduce
    , typeName
    ) where

import           RON.Internal.Prelude

import qualified Data.ByteString.Char8 as BSC
import           Data.Foldable (fold)
import           Data.List (partition)
import qualified Data.List.NonEmpty as NonEmpty
import           Data.Map.Strict (Map, (!?))
import qualified Data.Map.Strict as Map
import           GHC.TypeLits (symbolVal)

import           RON.Data.Internal (RChunk' (..), Reduced (..), Reducer,
                                    Reducible (..))
import           RON.Data.LWW (LwwPerField)
import           RON.Data.ORSet (ORSet)
import           RON.Data.RGA (RGA)
import           RON.Data.VersionVector (VersionVector)
import           RON.Types (Chunk (Query, Raw, Value), Frame, Op (..), Op' (..),
                            RChunk (..), UUID)
import           RON.UUID (pattern Zero)
import qualified RON.UUID as UUID

reducers :: Map UUID Reducer
reducers = Map.fromList
    [ mkReducer @LwwPerField
    , mkReducer @RGA
    , mkReducer @ORSet
    , mkReducer @VersionVector
    ]

reduce :: Frame -> Frame
reduce chunks = values' ++ queries where
    chunkObjectAndType = opObjectAndType . \case
        Raw                              op  -> op
        Value RChunk{rchunkHeader = op} -> op
        Query RChunk{rchunkHeader = op} -> op
    opObjectAndType Op{..} = (opObject, opType)
    (queries, values) = partition isQuery chunks
    values' =
        fold $
        Map.mapWithKey reduceByType $
        NonEmpty.fromList <$>
        Map.fromListWith (++)
            [(chunkObjectAndType value, [value]) | value <- values]

reduceByType :: (UUID, UUID) -> NonEmpty Chunk -> [Chunk]
reduceByType (obj, typ) = case reducers !? typ of
    Nothing   -> toList  -- TODO use generic reducer
    Just rdcr -> rdcr obj

isQuery :: Chunk -> Bool
isQuery = \case
    Query _ -> True
    _       -> False
typeName :: forall a . Reducible a => UUID
typeName =

    fromJust . UUID.mkName . BSC.pack $ symbolVal (Proxy :: Proxy (OpType a))

mkReducer :: forall a . Reducible a => (UUID, Reducer)
mkReducer = (typeName @a, reducer @a)

reducer :: forall a . Reducible a => Reducer
reducer obj chunks = chunks' ++ leftovers where
    chunks' = case mReducedState of
        Nothing -> []
        Just reducedState ->
            [ Value RChunk
                { rchunkHeader = mkOp Op'
                    { opEvent = stateVersion
                    , opRef = Zero
                    , opPayload = []
                    }
                , rchunkBody = map mkOp reducedStateBody
                }
            | not $ null reducedStateBody
            ]
            ++  map (Value . wrapRChunk) reducedPatches
            ++  map (Raw . mkOp) reducedUnappliedOps
          where
            Reduced { reducedStateVersion
                    , reducedStateBody
                    , reducedPatches
                    , reducedUnappliedOps
                    } =
                toChunks reducedState
            stateVersion = case mSeenState of
                Just (MaxOnFst (seenStateVersion, seenState))
                    | reducedStateVersion > seenStateVersion ->
                        reducedStateVersion
                    | sameState reducedState seenState -> seenStateVersion
                    | otherwise -> UUID.succValue seenStateVersion
                Nothing -> reducedStateVersion
    typ = typeName @a
    mkOp = Op typ obj
    (mReducedState, mSeenState, leftovers) = sconcat $ fmap load chunks
    load chunk = fromMaybe (Nothing, Nothing, [chunk]) $ load' chunk
    load' chunk = case chunk of
        Raw op@Op{op'} -> do
            guardSameObject op
            let state = fromRawOp @a op'
            pure (Just state, Nothing, [])
        Value RChunk{rchunkHeader, rchunkBody} -> do
            guardSameObject rchunkHeader
            body <- for rchunkBody $ \op -> do
                guardSameObject op
                pure $ op' op
            let ref = opRef $ op' rchunkHeader
            let state = fromChunk @a ref body
            pure
                ( Just state
                , case ref of
                    Zero ->  -- state
                        Just $ MaxOnFst (opEvent $ op' rchunkHeader, state)
                    _    -> Nothing  -- patch
                , []
                )
        _ -> Nothing
    guardSameObject Op{opType, opObject} =
        guard $ opType == typ && opObject == obj
    wrapRChunk RChunk'{..} = RChunk
        { rchunkHeader = mkOp
            Op'{opEvent = rchunk'Version, opRef = rchunk'Ref, opPayload = []}
        , rchunkBody = map mkOp rchunk'Body
        }
