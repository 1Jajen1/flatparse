{-# options_ghc -Wno-unused-imports #-}

module Main where

import           Data.ByteString (ByteString)
import qualified Data.ByteString as S
import           Data.Primitive.ByteArray
import qualified Data.Vector.Unboxed as UV
import qualified FlatParse.Basic as F
import           Gauge
import           System.Environment
import           Test.Hspec

import qualified Data.ByteString.Char8 as B

import qualified Attoparsec
import qualified Megaparsec
import qualified Parsec
import qualified FPStateful
import qualified FPBasic
import qualified Bytesmith
import qualified ReadInteger

sexpInp :: B.ByteString
sexpInp =
  B.concat $ "(" : replicate 33333 "(foo (foo (foo ((bar baza)))))" ++ [")"]

longwsInp :: B.ByteString
longwsInp = B.concat $ replicate 55555 "thisisalongkeyword   "

numcsvInp :: B.ByteString
numcsvInp = B.concat ("0" : [B.pack (",  " ++ show n) | n <- [1..100000::Int]])

sexpInp' :: ByteArray
sexpInp' = Bytesmith.strToByteArray $ B.unpack sexpInp

longwsInp' :: ByteArray
longwsInp' = Bytesmith.strToByteArray $ B.unpack longwsInp

numcsvInp' :: ByteArray
numcsvInp' = Bytesmith.strToByteArray $ B.unpack numcsvInp

readIntInp :: B.ByteString
readIntInp = "12345678910"

main :: IO ()
main = do
  withArgs
    mempty
    (hspec
       (do it "empty ok"
              (shouldBe
                 (ReadInteger.readInts " [  ] ")
                 (F.OK (UV.fromList []) "" :: F.Result () (UV.Vector Int)))
           it
             "trailing comma fail"
             (do shouldBe
                   (ReadInteger.readInts "[1,2,3,4,]")
                   (F.Fail :: F.Result () (UV.Vector Int))
                 shouldBe
                   (ReadInteger.checkInts "[1,2,3,4,]")
                   (F.Fail :: F.Result () ()))
           it
             "whitespace ok"
             (do shouldBe
                   (ReadInteger.checkInts " [1, 2,  3,4  ] ")
                   (F.OK () "" :: F.Result () ())
                 shouldBe
                   (ReadInteger.readInts " [1, 2,  3,4  ] ")
                   (F.OK (UV.fromList [1, 2, 3, 4]) "" :: F.Result () (UV.Vector Int)))
           it
             "no whitespace"
             (do shouldBe
                   (ReadInteger.readInts "[ 1,2,3,4]")
                   (F.OK (UV.fromList [1, 2, 3, 4]) "" :: F.Result () (UV.Vector Int))
                 shouldBe
                   (ReadInteger.checkInts "[ 1,2,3,4]")
                   (F.OK () "" :: F.Result () ()))))
  defaultMain
    [ bgroup
        "sexp"
        [ bench "fpbasic" $ whnf FPBasic.runSexp sexpInp
        , bench "fpstateful" $ whnf FPStateful.runSexp sexpInp
        , bench "bytesmith" $ whnf Bytesmith.runSexp sexpInp'
        , bench "attoparsec" $ whnf Attoparsec.runSexp sexpInp
        , bench "megaparsec" $ whnf Megaparsec.runSexp sexpInp
        , bench "parsec" $ whnf Parsec.runSexp sexpInp
        ]
    , bgroup
        "long keyword"
        [ bench "fpbasic" $ whnf FPBasic.runLongws longwsInp
        , bench "fpstateful" $ whnf FPStateful.runLongws longwsInp
        , bench "bytesmith" $ whnf Bytesmith.runLongws longwsInp'
        , bench "attoparsec" $ whnf Attoparsec.runLongws longwsInp
        , bench "megaparsec" $ whnf Megaparsec.runLongws longwsInp
        , bench "parsec" $ whnf Parsec.runLongws longwsInp
        ]
    , bgroup
        "numeral csv"
        [ bench "fpbasic" $ whnf FPBasic.runNumcsv numcsvInp
        , bench "fpstateful" $ whnf FPStateful.runNumcsv numcsvInp
        , bench "bytesmith" $ whnf Bytesmith.runNumcsv numcsvInp'
        , bench "attoparsec" $ whnf Attoparsec.runNumcsv numcsvInp
        , bench "megaparsec" $ whnf Megaparsec.runNumcsv numcsvInp
        , bench "parsec" $ whnf Parsec.runNumcsv numcsvInp
        ]
    , bgroup
        "integer_array"
        [ env
          (pure
             (S.concat
                ["[", S.intercalate "," (replicate size "12345678910"), "]"]))
          (\bs ->
             bgroup
               (show size)
               [ bench "check" (whnf ReadInteger.checkInts bs)
               , bench "parse" (whnf ReadInteger.readInts bs)
               ])
        | size <- [1000, 2000, 4000]
        ]
    ]
