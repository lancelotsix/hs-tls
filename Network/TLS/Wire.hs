{-# LANGUAGE GeneralizedNewtypeDeriving,FlexibleInstances #-}

-- |
-- Module      : Network.TLS.Wire
-- License     : BSD-style
-- Maintainer  : Vincent Hanquez <vincent@snarc.org>
-- Stability   : experimental
-- Portability : unknown
--
-- the Wire module is a specialized Binary package related to the TLS protocol.
-- all multibytes values are written as big endian.
--
module Network.TLS.Wire
	( Get
	, runGet
	, remaining
	, bytesRead
	, getWord8
	, getWords8
	, getWord16
	, getWords16
	, getWord24
	, getBytes
	, processBytes
	, isEmpty
	, Put
	, runPut
	, putWord8
	, putWords8
	, putWord16
	, putWords16
	, putWord24
	, putByteString
	, putLazyByteString
	, encodeWord64
	) where

import qualified Data.Binary.Get as Bin
import Data.Binary.Put
import Data.ByteString (ByteString)
import qualified Data.ByteString.Lazy as L
import Control.Monad.Error
import Data.Word
import Data.Bits
import Network.TLS.Struct

instance Error TLSError where
	noMsg = Error_Misc ""
	strMsg = Error_Misc

newtype Get a = GE { runGE :: ErrorT TLSError Bin.Get a }
	deriving (Monad, MonadError TLSError)

instance Functor Get where
	fmap f = GE . fmap f . runGE

liftGet :: Bin.Get a -> Get a
liftGet = GE . lift

runGet :: Get a -> L.ByteString -> Either TLSError a
runGet f b = Bin.runGet (runErrorT (runGE f)) b

remaining :: Get Int
remaining = fmap fromIntegral $ liftGet Bin.remaining

bytesRead :: Get Int
bytesRead = fmap fromIntegral $ liftGet Bin.bytesRead

getWord8 :: Get Word8
getWord8 = liftGet Bin.getWord8

getWords8 :: Get [Word8]
getWords8 = getWord8 >>= \lenb -> replicateM (fromIntegral lenb) getWord8

getWord16 :: Get Word16
getWord16 = liftGet Bin.getWord16be

getWords16 :: Get [Word16]
getWords16 = getWord16 >>= \lenb -> replicateM (fromIntegral lenb `div` 2) getWord16

getWord24 :: Get Int
getWord24 = do
	a <- fmap fromIntegral getWord8
	b <- fmap fromIntegral getWord8
	c <- fmap fromIntegral getWord8
	return $ (a `shiftL` 16) .|. (b `shiftL` 8) .|. c

getBytes :: Int -> Get ByteString
getBytes i = liftGet $ Bin.getBytes i

processBytes :: Int -> Get a -> Get a
processBytes i f = do
	r1 <- bytesRead
	ret <- f
	r2 <- bytesRead
	if r2 == (r1 + i)
		then return ret
		else throwError (Error_Internal_Packet_ByteProcessed r1 r2 i)
	
isEmpty :: Get Bool
isEmpty = liftGet Bin.isEmpty

putWords8 :: [Word8] -> Put
putWords8 l = do
	putWord8 $ fromIntegral (length l)
	mapM_ putWord8 l

putWord16 :: Word16 -> Put
putWord16 = putWord16be

putWords16 :: [Word16] -> Put
putWords16 l = do
	putWord16 $ 2 * (fromIntegral $ length l)
	mapM_ putWord16 l

putWord24 :: Int -> Put
putWord24 i = do
	let a = fromIntegral ((i `shiftR` 16) .&. 0xff)
	let b = fromIntegral ((i `shiftR` 8) .&. 0xff)
	let c = fromIntegral (i .&. 0xff)
	mapM_ putWord8 [a,b,c]

encodeWord64 :: Word64 -> L.ByteString
encodeWord64 = runPut . putWord64be
