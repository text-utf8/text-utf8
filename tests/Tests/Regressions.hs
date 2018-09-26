-- | Regression tests for specific bugs.
--
{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
module Tests.Regressions
    (
      tests
    ) where

import Control.Exception (SomeException, handle)
import Data.Char (isLetter)
import System.IO
import Test.HUnit (assertBool, assertEqual, assertFailure)
import qualified Data.ByteString as B
import Data.ByteString.Char8 ()
import qualified Data.ByteString.Lazy as LB
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.IO as T
import qualified Data.Text.Lazy as LT
import qualified Data.Text.Lazy.Encoding as LE
import qualified Data.Text.Unsafe as T
import qualified Test.Framework as F
import qualified Test.Framework.Providers.HUnit as F

import Tests.Utils (withTempFile)

-- Reported by Michael Snoyman: UTF-8 encoding a large lazy bytestring
-- caused either a segfault or attempt to allocate a negative number
-- of bytes.
lazy_encode_crash :: IO ()
lazy_encode_crash = withTempFile $ \ _ h ->
   LB.hPut h . LE.encodeUtf8 . LT.pack . replicate 100000 $ 'a'

-- Reported by Pieter Laeremans: attempting to read an incorrectly
-- encoded file can result in a crash in the RTS (i.e. not merely an
-- exception).
hGetContents_crash :: IO ()
hGetContents_crash = withTempFile $ \ path h -> do
  B.hPut h (B.pack [0x78, 0xc4 ,0x0a]) >> hClose h
  h' <- openFile path ReadMode
  hSetEncoding h' utf8
  handle (\(_::SomeException) -> return ()) $
    T.hGetContents h' >> assertFailure "T.hGetContents should crash"

-- Reported by Ian Lynagh: attempting to allocate a sufficiently large
-- string (via either Array.new or Text.replicate) could result in an
-- integer overflow.
replicate_crash :: IO ()
replicate_crash = handle (\(_::SomeException) -> return ()) $
                  T.replicate (2^power) "0123456789abcdef" `seq`
                  assertFailure "T.replicate should crash"
  where
    power | maxBound == (2147483647::Int) = 28
          | otherwise                     = 60 :: Int

-- Reported by John Millikin: a UTF-8 decode error handler could
-- return a bogus substitution character, which we would write without
-- checking.
utf8_decode_unsafe :: IO ()
utf8_decode_unsafe = do
  let t = TE.decodeUtf8With (\_ _ -> Just '\xdc00') "\x80"
  assertBool "broken error recovery shouldn't break us" (t == "\xfffd")

-- Reported by Eric Seidel: we mishandled mapping Chars that fit in a
-- single byte to Chars that require multiple bytes.
mapAccumL_resize :: IO ()
mapAccumL_resize = do
  let f a _ = (a, '\65536') -- bytes in utf8 representation: "\240\144\128\128"
      count = 5
      val   = T.mapAccumL f (0::Int) (T.replicate count "a")
  assertEqual "mapAccumL should correctly fill buffers for 4-byte results"
             (0, T.replicate count "\65536") val
  assertEqual "mapAccumL should correctly size buffers for 4-byte results"
             (count * 4) (T.lengthWord8 (snd val))

-- See GitHub #197
t197 :: IO ()
t197 =
    assertBool "length (filter (==',') \"0,00\") should be 1" (currencyParser "0,00")
  where
    currencyParser x = cond == 1
      where
        cond = length fltr
        fltr = filter (== ',') x

t221 :: IO ()
t221 =
    assertEqual "toLower of large input shouldn't crash"
                (T.toLower (T.replicate 200000 "0") `seq` ())
                ()

t227 :: IO ()
t227 =
    assertEqual "take (-3) shouldn't crash with overflow"
                (T.length $ T.filter isLetter $ T.take (-3) "Hello! How are you doing today?")
                0

tests :: F.Test
tests = F.testGroup "Regressions"
    [ F.testCase "hGetContents_crash" hGetContents_crash
    , F.testCase "lazy_encode_crash" lazy_encode_crash
    , F.testCase "mapAccumL_resize" mapAccumL_resize
    , F.testCase "replicate_crash" replicate_crash
    , F.testCase "utf8_decode_unsafe" utf8_decode_unsafe
    , F.testCase "t197" t197
    , F.testCase "t221" t221
    , F.testCase "t227" t227
    ]
