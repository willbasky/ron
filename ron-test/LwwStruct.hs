{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module LwwStruct (prop_lwwStruct) where

import           Control.Monad.Except (runExceptT)
import           Control.Monad.State.Strict (runStateT)
import qualified Data.ByteString.Lazy.Char8 as BSLC
import           Data.String.Interpolate.IsString (i)
import           GHC.Stack (HasCallStack, withFrozenCallStack)
import           Hedgehog (MonadTest, Property, property, (===))
import           Hedgehog.Internal.Property (failWith)

import           RON.Data (getObject, newObject)
import qualified RON.Data.ORSet as ORSet
import qualified RON.Data.RGA as RGA
import           RON.Event (ReplicaId, applicationSpecific)
import           RON.Event.Simulation (runNetworkSim, runReplicaSim)
import           RON.Text (parseObject, serializeObject)

import           LwwStruct.Types (Example1 (..), Example2 (..), int1_assign,
                                  opt5_read, opt6_assign, opt6_read, set4_zoom,
                                  str2_zoom, str3_assign, str3_read)

type ByteStringL = BSLC.ByteString

--------------------------------------------------------------------------------

example0 :: Example1
example0 = Example1
    { int1 = 275
    , str2 = "275"
    , str3 = "190"
    , set4 = mempty
    , opt5 = Nothing
    , opt6 = Just 74
    }

-- | "r3pl1c4"
replica :: ReplicaId
replica = applicationSpecific 0xd83d30067100000

ex1expect :: ByteStringL
ex1expect = [i|
    *lww    #B/000000000y+r3pl1c4   @`          !
                                        :int1   =275
                                        :opt5   >none
                                        :opt6   >some =74
                                        :set4   >)3
                                        :str2   >)T
                                        :str3   '190'

    *rga    #)T                     @)D :0      !
                                    @)B         '2'
                                    @)C         '7'
                                    @)D         '5'

    *set    #)3                     @`          !
    .
    |]

ex4expect :: ByteStringL
ex4expect = [i|
    *lww    #B/000000000y+r3pl1c4   @`]4j           !
                                    @]1K    :int1   =166
                                    @`      :opt5   >none
                                    @]4j    :opt6   >none
                                    @`      :set4   >)3
                                            :str2   >)T
                                    @]36    :str3   '206'

            #]4C                    @`      :0      !
                                            :vv5    >]3g

    *rga    #]0T                    @]2V    :0      !
                                    @]0B    :`]1P   '2'
                                    @)C     :)Z     '7'
                                    @]1s    :0      '1'
                                    @]2V            '4'
                                    @]0D            '5'

    *set    #)3                     @]4a            !
                                    @               >]4C

    *vv     #]3g                    @`              !
    .
    |]

example4expect :: Example1
example4expect = Example1
    { int1 = 166
    , str2 = "145"
    , str3 = "206"
    , set4 = [Example2{vv5 = mempty}]
    , opt5 = Nothing
    , opt6 = Nothing
    }

prop_lwwStruct :: Property
prop_lwwStruct = property $ do
    -- create an object
    let ex1 = runNetworkSim $ runReplicaSim replica $ newObject example0
    let (oid, ex1s) = serializeObject ex1
    prep ex1expect === prep ex1s

    -- parse newly created object
    ex2 <- evalEitherS $ parseObject oid ex1s
    ex1 === ex2

    -- decode newly created object
    example3 <- evalEitherS $ getObject ex2
    example0 === example3

    -- apply operations to the object (frame)
    ((str3Value, opt5Value, opt6Value), ex4) <-
        evalEitherS $
        runNetworkSim $ runReplicaSim replica $ runExceptT $
        (`runStateT` ex2) $ do
            -- plain field
            int1_assign 166
            str2_zoom $ RGA.edit "145"
            str3Value <- str3_read
            str3_assign "206"
            set4_zoom $ ORSet.addNewRef Example2{vv5 = mempty}
            opt5Value <- opt5_read
            opt6Value <- opt6_read
            opt6_assign Nothing
            pure (str3Value, opt5Value, opt6Value)
    str3Value === "190"
    opt5Value === Nothing
    opt6Value === Just 74

    -- decode object after modification
    example4 <- evalEitherS $ getObject ex4
    example4expect === example4

    -- serialize object after modification
    prep ex4expect === prep (snd $ serializeObject ex4)

  where
    prep = filter (not . null) . map BSLC.words . BSLC.lines

evalEitherS :: (MonadTest m, HasCallStack) => Either String a -> m a
evalEitherS = \case
    Left  x -> withFrozenCallStack $ failWith Nothing x
    Right a -> pure a
