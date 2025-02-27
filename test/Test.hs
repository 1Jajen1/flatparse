{-# LANGUAGE ScopedTypeVariables #-}

module Main where

import Numeric (showHex)
import Data.ByteString (ByteString)
import qualified Data.ByteString as B
import qualified Data.Char
import qualified FlatParse.Basic as FB
-- import qualified FlatParse.Stateful as FS
import Test.HUnit
import Test.Hspec
import Test.Hspec.QuickCheck
import Test.QuickCheck hiding ( (.&.) )
import Data.Word
import Data.Int
import Data.Bits
import Test.QuickCheck.Instances.ByteString()

main :: IO ()
main = hspec $ do
  basicSpec

-- | The spec for FlatParse.Basic.
basicSpec :: SpecWith ()
basicSpec = describe "FlatParse.Basic" $ do
  describe "Errors and failures" $ do
    describe "FB.empty" $
      it "always fails" $ FB.empty `shouldParseFail` ""

    describe "err" $
      it "throws an error" $ FB.err "nope" `shouldParseErr` ""

    describe "lookahead" $
      it "restores state" $ do
        let p = FB.lookahead $(FB.string "fun") *> $(FB.string "function")
        p `shouldParse` "function"

    describe "fails" $ do
      it "expects child to fail" $ FB.fails FB.empty `shouldParse` ""
      it "fails when child succeeds" $ FB.fails (pure ()) `shouldParseFail` ""
      it "propagates errors" $ FB.fails (FB.err "nope") `shouldParseErr` ""

    describe "try" $
      it "turns error into failure" $ FB.try (FB.err "nope") `shouldParseFail` ""

    describe "optional" $ do
      it "can succeed" $ FB.optional (pure ()) `shouldParseWith` ("", Just ())
      it "can succeed when argument missing" $
        FB.optional FB.empty `shouldParseWith` ("", Nothing)
      it "propagates errors" $ FB.optional (FB.err "nope") `shouldParseErr` ""

    describe "optional_" $ do
      it "can succeed" $ FB.optional (pure ()) `shouldParse` ""
      it "can succeed when argument missing" $ FB.optional FB.empty `shouldParse` ""
      it "propagates errors" $ FB.optional (FB.err "nope") `shouldParseErr` ""

    describe "withOption" $ do
      let opt p = FB.withOption p (pure . reverse) (pure "bar")
      it "handles success" $ opt (pure "foo") `shouldParseWith` ("", "oof")
      it "handles failure" $ opt FB.empty `shouldParseWith` ("", "bar")
      it "handles error" $ opt (FB.err "nope") `shouldParseErr` ""

    describe "cut" $ do
      it "turns failure into error" $ FB.empty `FB.cut` "nope" `shouldParseErr` ""
      it "leaves success alone" $ pure () `FB.cut` "nope" `shouldParse` ""
      it "propagates error" $
        FB.err "inner" `FB.cut` "outer" `shouldParseErrWith` ("", "inner")

    describe "cutting" $ do
      it "turns failure into error" $
        FB.cutting FB.empty "nope" (++) `shouldParseErrWith` ("", "nope")
      it "leaves success alone" $ do
        FB.cutting (pure ()) "nope" (++) `shouldParse` ""
      it "combines errors" $
        FB.cutting (FB.err "!!!") "nope" (++) `shouldParseErrWith` ("", "!!!nope")

  describe "Basic lexing and parsing" $ do
    describe "FB.eof" $ do
      it "succeeds at end of file" $ FB.eof `shouldParse` ""
      it "fails with more input" $ FB.eof `shouldParseFail` "more"

    describe "skip" $ do
      prop "skips to the end of input" $
        \(bs :: ByteString) ->
          (FB.skip (B.length bs) >> FB.eof) `shouldParse` bs

    describe "char" $ do
      it "succeeds on that char" $ $(FB.char 'a') `shouldParse` "a"
      it "succeeds on multibyte char" $ $(FB.char 'ȩ') `shouldParse` FB.packUTF8 "ȩ"
      it "fails on the wrong char" $ $(FB.char 'a') `shouldParseFail` "b"
      it "fails at end of file" $ $(FB.char 'a') `shouldParseFail` ""

    describe "byte" $ do
      it "succeeds on that byte" $ FB.byte 0x61 `shouldParse` "\x61"
      it "succeeds on high bytes" $ FB.byte 0xfe `shouldParse` "\xfe"
      it "fails on the wrong byte" $ FB.byte 0x61 `shouldParseFail` "\x62"
      it "fails on end of file" $ FB.byte 0x61 `shouldParseFail` ""

    describe "bytes" $ do
      it "succeeds on those bytes" $
        $(FB.bytes [1, 2, 3, 4]) `shouldParse` "\x01\x02\x03\x04"
      it "succeeds on high bytes" $
        $(FB.bytes [0xf1, 0xf2, 0xf3, 0xf4]) `shouldParse` "\xf1\xf2\xf3\xf4"
      it "fails on wrong bytes" $
        $(FB.bytes [1, 2, 5, 4]) `shouldParseFail` "\x01\x02\x03\x04"
      it "fails when out of space" $
        $(FB.bytes [1, 2, 3, 4]) `shouldParseFail` "\x01\x02\x03"

    describe "byteString" $ do
      it "succeeds on those bytes" $
        FB.byteString (B.pack [1, 2, 3, 4]) `shouldParse` "\x01\x02\x03\x04"
      it "succeeds on high bytestring" $
        FB.byteString (B.pack [0xf1, 0xf2, 0xf3, 0xf4]) `shouldParse` "\xf1\xf2\xf3\xf4"
      it "fails on wrong bytestring" $
        FB.byteString (B.pack [1, 2, 5, 4]) `shouldParseFail` "\x01\x02\x03\x04"
      it "fails when out of space" $
        FB.byteString (B.pack [1, 2, 3, 4]) `shouldParseFail` "\x01\x02\x03"


    describe "string" $ do
      it "succeeds on the right string" $ $(FB.string "foo") `shouldParse` "foo"
      it "succeeds with multibyte chars" $
        $(FB.string "foȩ") `shouldParse` FB.packUTF8 "foȩ"
      it "fails on the wrong string" $ $(FB.string "foo") `shouldParseFail` "bar"
      it "fails when out of space" $ $(FB.string "foo") `shouldParseFail` "fo"

    describe "switch" $ do
      it "parses simple words" $
        $( FB.switch
             [|
               case _ of
                 "foo" -> pure 1
                 "bar" -> pure 2
               |]
         )
          `shouldParseWith` ("foo", 1)

      it "matches the default" $
        $( FB.switch
             [|
               case _ of
                 "foo" -> pure 1
                 "bar" -> pure 2
                 _ -> pure 0
               |]
         )
          `shouldParsePartialWith` ("fez", 0)

      it "fails with no default" $
        $( FB.switch
             [|
               case _ of
                 "foo" -> pure 1
                 "bar" -> pure 2
               |]
         )
          `shouldParseFail` "fez"

      it "prefers longest match" $
        $( FB.switch
             [|
               case _ of
                 "foo" -> pure 1
                 "foobar" -> pure 2
               |]
         )
          `shouldParseWith` ("foobar", 2)

      it "doesn't reproduce bug #12" $
        $( FB.switch
             [|
               case _ of
                 "Eac" -> pure ()
                 "EAc" -> pure ()
                 "E" -> pure ()
               |]
         )
          `shouldParse` "E"

    describe "switchWithPost" $ do
      it "applies post after match" $
        $( FB.switchWithPost
             (Just [|$(FB.string "bar")|])
             [|
               case _ of
                 "foo" -> pure ()
               |]
         )
          `shouldParse` "foobar"

      it "doesn't apply post after default" $
        $( FB.switchWithPost
             (Just [|$(FB.string "bar")|])
             [|
               case _ of
                 "foo" -> pure ()
                 _ -> pure ()
               |]
         )
          `shouldParse` ""

      it "requires the post must match" $
        $( FB.switchWithPost
             (Just [|$(FB.string "bar")|])
             [|
               case _ of
                 "foo" -> pure ()
               |]
         )
          `shouldParseFail` "foo"

    describe "rawSwitchWithPost" $ do
      it "parses simple words" $
        $( FB.rawSwitchWithPost
             Nothing
             [ ("foo", [|pure 1|]),
               ("bar", [|pure 2|])
             ]
             Nothing
         )
          `shouldParseWith` ("foo", 1)

      it "matches the default" $
        $( FB.rawSwitchWithPost
             Nothing
             [ ("foo", [|pure 1|]),
               ("bar", [|pure 2|])
             ]
             (Just [|pure 0|])
         )
          `shouldParsePartialWith` ("fez", 0)

      it "fails with no default" $
        $( FB.rawSwitchWithPost
             Nothing
             [ ("foo", [|pure 1|]),
               ("bar", [|pure 2|])
             ]
             Nothing
         )
          `shouldParseFail` "fez"

      it "prefers longest match" $
        $( FB.rawSwitchWithPost
             Nothing
             [ ("foo", [|pure 1|]),
               ("foobar", [|pure 2|])
             ]
             Nothing
         )
          `shouldParseWith` ("foobar", 2)

      it "applies post after match" $
        $( FB.rawSwitchWithPost
             (Just [|$(FB.string "bar")|])
             [("foo", [|pure ()|])]
             Nothing
         )
          `shouldParse` "foobar"

      it "doesn't apply post after default" $
        $( FB.rawSwitchWithPost
             (Just [|$(FB.string "bar")|])
             [("foo", [|pure ()|])]
             (Just [|pure ()|])
         )
          `shouldParse` ""

      it "requires the post must match" $
        $( FB.rawSwitchWithPost
             (Just [|$(FB.string "bar")|])
             [("foo", [|pure ()|])]
             Nothing
         )
          `shouldParseFail` "foo"

    describe "satisfy" $ do
      it "succeeds on the right char" $
        FB.satisfy (== 'a') `shouldParseWith` ("a", 'a')

      it "succeeds on multi-byte chars" $ do
        let chars = "$¢€𐍈" :: [Char]
        sequence_
          [ if a == b
              then FB.satisfy (== a) `shouldParseWith` (FB.packUTF8 (pure b), b)
              else FB.satisfy (== a) `shouldParseFail` FB.packUTF8 (pure b)
            | a <- chars,
              b <- chars
          ]

      it "fails on the wrong char" $
        FB.satisfy (== 'a') `shouldParseFail` "b"
      it "fails at end of file" $
        FB.satisfy (== 'a') `shouldParseFail` ""

    describe "satisfyASCII" $ do
      it "succeeds on the right char" $
        FB.satisfyASCII (== 'a') `shouldParseWith` ("a", 'a')
      it "fails on the wrong char" $
        FB.satisfyASCII (== 'a') `shouldParseFail` "b"

      it "fails on the wrong multi-byte char" $
        -- The specification for FB.satisfyASCII requires that the predicate
        -- return False for non-ASCII characters, but multi-byte chars are
        -- still allowed in the input.
        FB.satisfyASCII (== 'a') `shouldParseFail` FB.packUTF8 "ȩ"

      it "fails at end of file" $
        FB.satisfyASCII (== 'a') `shouldParseFail` ""

    describe "satisfyASCII_" $ do
      it "succeeds on the right char" $
        FB.satisfyASCII_ (== 'a') `shouldParseWith` ("a", ())
      it "fails on the wrong char" $
        FB.satisfyASCII_ (== 'a') `shouldParseFail` "b"
      it "fails on the wrong multi-byte char" $
        FB.satisfyASCII_ (== 'a') `shouldParseFail` FB.packUTF8 "ȩ"
      it "fails at end of file" $
        FB.satisfyASCII_ (== 'a') `shouldParseFail` ""

    describe "fusedSatisfy" $ do
      it "correctly routes chars based on length" $ do
        FB.fusedSatisfy (== '$') (const False) (const False) (const False)
          `shouldParse` FB.packUTF8 "$"
        FB.fusedSatisfy (const False) (== '¢') (const False) (const False)
          `shouldParse` FB.packUTF8 "¢"
        FB.fusedSatisfy (const False) (const False) (== '€') (const False)
          `shouldParse` FB.packUTF8 "€"
        FB.fusedSatisfy (const False) (const False) (const False) (== '𐍈')
          `shouldParse` FB.packUTF8 "𐍈"

      it "fails on FB.empty input" $
        FB.fusedSatisfy (const True) (const True) (const True) (const True)
          `shouldParseFail` ""

    describe "anyWord8" $ do
      it "reads a byte" $ FB.anyWord8 `shouldParseWith` ("\xef", 0xef)
      it "fails on FB.empty input" $ FB.anyWord8 `shouldParseFail` ""

    describe "anyWord16" $ do
      -- Byte order is unspecified, so just assert that it succeeds.
      it "succeeds" $ FB.anyWord16 `shouldParse` "\xef\xbe"

      it "fails on FB.empty input" $ FB.anyWord16 `shouldParseFail` ""
      it "fails on insufficient input" $ FB.anyWord16 `shouldParseFail` "\xff"

    describe "anyWord32" $ do
      -- Byte order is unspecified, so just assert that it succeeds.
      it "succeeds" $ FB.anyWord32 `shouldParse` "\xef\xbe\xae\x7e"

      it "fails on empty input" $ FB.anyWord32 `shouldParseFail` ""
      it "fails on insufficient input" $
        FB.anyWord32 `shouldParseFail` "\xff\xff\xff"

    describe "anyWord" $ do
      -- This combinator is inherently non-portable, but we know a Word is at
      -- least some bytes.
      it "fails on FB.empty input" $ FB.anyWord `shouldParseFail` ""

    describe "anyChar" $ do
      it "reads 1-byte char" $ FB.anyChar `shouldParseWith` (FB.packUTF8 "$", '$')
      it "reads 2-byte char" $ FB.anyChar `shouldParseWith` (FB.packUTF8 "¢", '¢')
      it "reads 3-byte char" $ FB.anyChar `shouldParseWith` (FB.packUTF8 "€", '€')
      it "reads 4-byte char" $ FB.anyChar `shouldParseWith` (FB.packUTF8 "𐍈", '𐍈')
      it "fails on FB.empty input" $ FB.anyChar `shouldParseFail` ""

    describe "anyChar_" $ do
      it "reads 1-byte char" $ FB.anyChar_ `shouldParseWith` (FB.packUTF8 "$", ())
      it "reads 2-byte char" $ FB.anyChar_ `shouldParseWith` (FB.packUTF8 "¢", ())
      it "reads 3-byte char" $ FB.anyChar_ `shouldParseWith` (FB.packUTF8 "€", ())
      it "reads 4-byte char" $ FB.anyChar_ `shouldParseWith` (FB.packUTF8 "𐍈", ())
      it "fails on empty input" $ FB.anyChar_ `shouldParseFail` ""

    describe "anyCharASCII" $ do
      it "reads ASCII char" $ FB.anyCharASCII `shouldParseWith` (FB.packUTF8 "$", '$')
      it "fails on non-ASCII char" $ FB.anyCharASCII `shouldParseFail` FB.packUTF8 "¢"
      it "fails on empty input" $ FB.anyCharASCII `shouldParseFail` ""

    describe "anyCharASCII_" $ do
      it "reads ASCII char" $ FB.anyCharASCII_ `shouldParseWith` (FB.packUTF8 "$", ())
      it "fails on non-ASCII char" $
        FB.anyCharASCII_ `shouldParseFail` FB.packUTF8 "¢"
      it "fails on empty input" $ FB.anyCharASCII_ `shouldParseFail` ""

    describe "isDigit" $ do
      it "agrees with Data.Char" $
        property $
          \c -> FB.isDigit c === Data.Char.isDigit c

    describe "isLatinLetter" $ do
      it "agrees with Data.Char" $
        property $
          \c ->
            FB.isLatinLetter c
              === (Data.Char.isAsciiUpper c || Data.Char.isAsciiLower c)

    describe "readInt" $ do
      it "round-trips on non-negative Ints" $
        property $
          \(NonNegative i) -> FB.readInt `shouldParseWith` (FB.packUTF8 (show i), i)

      it "fails on non-integers" $ FB.readInt `shouldParseFail` "foo"
      it "fails on negative integers" $ FB.readInt `shouldParseFail` "-5"
      it "fails on FB.empty input" $ FB.readInt `shouldParseFail` ""

    describe "readIntHex" $ do
      it "round-trips on non-negative Ints, lowercase" $
        property $
          \(NonNegative i) -> FB.readIntHex `shouldParseWith` (FB.packUTF8 (showHex i ""), i)

      it "round-trips on non-negative Ints, uppercase" $
        property $
          \(NonNegative i) -> FB.readIntHex `shouldParseWith` (FB.packUTF8 (Data.Char.toUpper <$> showHex i ""), i)

      it "fails on non-integers" $ FB.readIntHex `shouldParseFail` "quux"
      it "fails on negative integers" $ FB.readIntHex `shouldParseFail` "-5"
      it "fails on FB.empty input" $ FB.readIntHex `shouldParseFail` ""

    describe "readInteger" $ do
      it "round-trips on non-negative Integers" $
        property $
          \(NonNegative i) ->
            FB.readInteger `shouldParseWith` (FB.packUTF8 (show i), i)

      it "fails on non-integers" $ FB.readInteger `shouldParseFail` "foo"
      it "fails on negative integers" $ FB.readInteger `shouldParseFail` "-5"
      it "fails on FB.empty input" $ FB.readInteger `shouldParseFail` ""

    describe "anyCString" $ do
      prop "parses arbitrary null-terminated bytestrings" $
        \(bs :: ByteString) ->
          let bs' = B.snoc bs 0x00
              expected = B.takeWhile (/= 0x00) bs'
          in  FB.anyCString `shouldParsePartialWith` (bs', expected)

    describe "Explicit-endianness machine integers" $ do
      describe "Unsigned" $ do
        prop "parses Word8s" $ do
          \(w :: Word8)  -> FB.anyWord8    `shouldParseWith` (w8AsByteString w, w)
        prop "parses Word16s (LE)" $ do
          \(w :: Word16) -> FB.anyWord16le `shouldParseWith` (w16leAsByteString w, w)
        prop "parses Word16s (BE)" $ do
          \(w :: Word16) -> FB.anyWord16be `shouldParseWith` (B.reverse (w16leAsByteString w), w)
        prop "parses Word32s (LE)" $ do
          \(w :: Word32) -> FB.anyWord32le `shouldParseWith` (w32leAsByteString w, w)
        prop "parses Word32s (BE)" $ do
          \(w :: Word32) -> FB.anyWord32be `shouldParseWith` (B.reverse (w32leAsByteString w), w)
        prop "parses Word64s (LE)" $ do
          \(w :: Word64) -> FB.anyWord64le `shouldParseWith` (w64leAsByteString w, w)
        prop "parses Word64s (BE)" $ do
          \(w :: Word64) -> FB.anyWord64be `shouldParseWith` (B.reverse (w64leAsByteString w), w)

      describe "Signed" $ do
        prop "parses Int8s" $ do
          \(i :: Int8)   -> FB.anyInt8     `shouldParseWith` (w8AsByteString i, i)
        prop "parses Int16s (LE)" $ do
          \(i :: Int16)  -> FB.anyInt16le  `shouldParseWith` (w16leAsByteString i, i)
        prop "parses Int16s (BE)" $ do
          \(i :: Int16)  -> FB.anyInt16be  `shouldParseWith` (B.reverse (w16leAsByteString i), i)
        prop "parses Int32s (LE)" $ do
          \(i :: Int32)  -> FB.anyInt32le  `shouldParseWith` (w32leAsByteString i, i)
        prop "parses Int32s (BE)" $ do
          \(i :: Int32)  -> FB.anyInt32be  `shouldParseWith` (B.reverse (w32leAsByteString i), i)
        prop "parses Int64s (LE)" $ do
          \(i :: Int64)  -> FB.anyInt64le  `shouldParseWith` (w64leAsByteString i, i)
        prop "parses Int64s (BE)" $ do
          \(i :: Int64)  -> FB.anyInt64be  `shouldParseWith` (B.reverse (w64leAsByteString i), i)

  describe "Combinators" $ do
    describe "Functor instance" $ do
      it "fmaps over the result" $
        ((+ 2) <$> FB.readInt) `shouldParseWith` ("2", 4)

    describe "Applicative instance" $ do
      it "combines using <*>" $
        ((+) <$> FB.readInt <* $(FB.string "+") <*> FB.readInt)
          `shouldParseWith` ("2+3", 5)

    describe "Monad instance" $ do
      it "combines with a do block" $ do
        let parser = do
              i <- FB.readInt
              $(FB.string "+")
              j <- FB.readInt
              pure (i + j)
        parser `shouldParseWith` ("2+3", 5)

    describe "(<|>)" $ do
      it "chooses first option on success" $
        (("A" <$ $(FB.string "foo")) FB.<|> ("B" <$ $(FB.string "foo")))
          `shouldParseWith` ("foo", "A")

      it "chooses second option when first fails" $
        (("A" <$ $(FB.string "bar")) FB.<|> ("B" <$ $(FB.string "foo")))
          `shouldParseWith` ("foo", "B")

    describe "branch" $ do
      it "chooses the first FB.branch on success" $
        FB.branch (pure ()) (pure "A") (pure "B") `shouldParseWith` ("", "A")
      it "does not backtrack from first FB.branch" $
        FB.branch (pure ()) FB.empty (pure "B") `shouldParseFail` ""
      it "chooses the second FB.branch on failure" $
        FB.branch FB.empty (pure "A") (pure "B") `shouldParseWith` ("", "B")

    describe "chainl" $ do
      it "parses a chain of numbers" $
        FB.chainl (+) FB.readInt ($(FB.char '+') *> FB.readInt)
          `shouldParseWith` ("1+2+3", 6)

      it "allows the right chain to be FB.empty" $
        FB.chainl (+) FB.readInt ($(FB.char '+') *> FB.readInt)
          `shouldParseWith` ("1", 1)

      it "requires at least the leftmost parser to match" $
        FB.chainl (+) FB.readInt ($(FB.char '+') *> FB.readInt)
          `shouldParseFail` ""

    describe "chainr" $ do
      it "parses a chain of numbers" $
        FB.chainr (+) (FB.readInt <* $(FB.char '+')) FB.readInt
          `shouldParseWith` ("1+2+3", 6)

      it "allows the left chain to be FB.empty" $
        FB.chainr (+) (FB.readInt <* $(FB.char '+')) FB.readInt
          `shouldParseWith` ("1", 1)

      it "requires at least the rightmost parser to match" $
        FB.chainr (+) (FB.readInt <* $(FB.char '+')) FB.readInt
          `shouldParseFail` ""

    describe "many" $ do
      it "parses many chars" $
        FB.many (FB.satisfy FB.isLatinLetter) `shouldParseWith` ("abc", "abc")
      it "accepts FB.empty input" $
        FB.many (FB.satisfy FB.isLatinLetter) `shouldParseWith` ("", "")
      it "is greedy" $
        (FB.many (FB.satisfy FB.isDigit) *> FB.satisfy FB.isDigit) `shouldParseFail` "123"

    describe "many_" $ do
      it "parses many chars" $
        FB.many_ (FB.satisfy FB.isLatinLetter) `shouldParseWith` ("abc", ())
      it "accepts FB.empty input" $
        FB.many_ (FB.satisfy FB.isLatinLetter) `shouldParseWith` ("", ())
      it "is greedy" $
        (FB.many_ (FB.satisfy FB.isDigit) *> FB.satisfy FB.isDigit) `shouldParseFail` "123"

    describe "some" $ do
      it "parses some chars" $
        FB.some (FB.satisfy FB.isLatinLetter) `shouldParseWith` ("abc", "abc")
      it "rejects FB.empty input" $
        FB.some (FB.satisfy FB.isLatinLetter) `shouldParseFail` ""
      it "is greedy" $
        (FB.some (FB.satisfy FB.isDigit) *> FB.satisfy FB.isDigit) `shouldParseFail` "123"

    describe "some_" $ do
      it "parses some chars" $
        FB.some_ (FB.satisfy FB.isLatinLetter) `shouldParseWith` ("abc", ())
      it "rejects FB.empty input" $
        FB.some_ (FB.satisfy FB.isLatinLetter) `shouldParseFail` ""
      it "is greedy" $
        (FB.some_ (FB.satisfy FB.isDigit) *> FB.satisfy FB.isDigit) `shouldParseFail` "123"

    describe "notFollowedBy" $ do
      it "succeeds when it should" $
        FB.readInt `FB.notFollowedBy` $(FB.char '.') `shouldParsePartial` "123+5"
      it "fails when first parser doesn't match" $
        FB.readInt `FB.notFollowedBy` $(FB.char '.') `shouldParseFail` "a"
      it "fails when followed by the wrong thing" $
        FB.readInt `FB.notFollowedBy` $(FB.char '.') `shouldParseFail` "123.0"

    describe "isolate" $ do
      prop "isolate takeRestBs is identity" $ do
        \(bs :: ByteString) ->
          FB.isolate (B.length bs) FB.takeRestBs `shouldParseWith` (bs, bs)
      prop "isolate takeBs length is identity" $ do
        \(bs :: ByteString) ->
          FB.isolate (B.length bs) (FB.takeBs (B.length bs)) `shouldParseWith` (bs, bs)

  describe "Positions and spans" $ do
    describe "Pos Ord instance" $ do
      pure ()

    describe "getPos" $ do
      pure ()

    describe "setPos" $ do
      pure ()

    describe "endPos" $ do
      pure ()

    describe "spanOf" $ do
      pure ()

    describe "spanned" $ do
      pure ()

    describe "byteStringOf" $ do
      pure ()

    describe "byteStringed" $ do
      pure ()

    describe "inSpan" $ do
      pure ()

  describe "Positions and span conversions" $ do
    describe "validPos" $ do
      pure ()

    describe "posLineCols" $ do
      pure ()

    describe "unsafeSpanToByteString" $ do
      pure ()

    describe "unsafeSlice" $ do
      pure ()

    describe "mkPos" $ do
      pure ()

    describe "lines" $ do
      pure ()

  describe "Getting the rest of the input as a String" $ do
    describe "takeLine" $ do
      pure ()

    describe "traceLine" $ do
      pure ()

    describe "takeRest" $ do
      pure ()

    describe "traceRest" $ do
      pure ()

  describe "String conversions" $ do
    describe "packUTF8" $ do
      pure ()

    describe "unpackUTF8" $ do
      pure ()

  describe "Location & address primitives" $ do
    it "valid lookaheadFromAddr# usage succeeds" $ do
      -- use Int#/Int64# directly because Word8# -> Int# is annoying on old GHCs
      let bs = B.pack [ 0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
                      , 0xFF, 0x31, 0x32, 0x33, 0x00, 0xFF]
          p = FB.withAddr# $ \addr# -> FB.withAnyInt64# $ \os# ->
                  FB.lookaheadFromAddr# addr# $ FB.atSkip# os# $ FB.anyCString
      p `shouldParsePartialWith` (bs, "123")

--------------------------------------------------------------------------------

w8AsByteString :: (Bits w, Num w, Integral w) => w -> ByteString
w8AsByteString w = B.pack [b1]
  where
    b1 = fromIntegral $  w .&. 0x00FF

w16leAsByteString :: (Bits w, Num w, Integral w) => w -> ByteString
w16leAsByteString w = B.pack [b1, b2]
  where
    b1 = fromIntegral $  w .&. 0x00FF
    b2 = fromIntegral $ (w .&. 0xFF00) `shiftR` 8

w32leAsByteString :: (Bits w, Num w, Integral w) => w -> ByteString
w32leAsByteString w = B.pack [b1, b2, b3, b4]
  where
    b1 = fromIntegral $  w .&. 0x000000FF
    b2 = fromIntegral $ (w .&. 0x0000FF00) `shiftR` 8
    b3 = fromIntegral $ (w .&. 0x00FF0000) `shiftR` 16
    b4 = fromIntegral $ (w .&. 0xFF000000) `shiftR` 24

w64leAsByteString :: (Bits w, Num w, Integral w) => w -> ByteString
w64leAsByteString w = B.pack [b1, b2, b3, b4, b5, b6, b7, b8]
  where
    b1 = fromIntegral $  w .&. 0x00000000000000FF
    b2 = fromIntegral $ (w .&. 0x000000000000FF00) `shiftR` 8
    b3 = fromIntegral $ (w .&. 0x0000000000FF0000) `shiftR` 16
    b4 = fromIntegral $ (w .&. 0x00000000FF000000) `shiftR` 24
    b5 = fromIntegral $ (w .&. 0x000000FF00000000) `shiftR` 32
    b6 = fromIntegral $ (w .&. 0x0000FF0000000000) `shiftR` 40
    b7 = fromIntegral $ (w .&. 0x00FF000000000000) `shiftR` 48
    b8 = fromIntegral $ (w .&. 0xFF00000000000000) `shiftR` 56

--------------------------------------------------------------------------------
-- Some combinators that make it easier to assert the results of a parser.

-- | The parser should parse this string, consuming it entirely, and succeed.
shouldParse :: Show e => FB.Parser e a -> ByteString -> Expectation
p `shouldParse` s = case FB.runParser p s of
  FB.OK _ "" -> pure ()
  FB.OK _ lo -> assertFailure $ "Unexpected leftover: " ++ show lo
  FB.Fail -> assertFailure "Parse failed unexpectedly"
  FB.Err e -> assertFailure $ "Parse threw unexpected error: " ++ show e

-- | The parser should parse this string, possibly with leftovers, and succeed.
shouldParsePartial :: Show e => FB.Parser e a -> ByteString -> Expectation
p `shouldParsePartial` s = case FB.runParser p s of
  FB.OK _ lo -> pure ()
  FB.Fail -> assertFailure "Parse failed unexpectedly"
  FB.Err e -> assertFailure $ "Parse threw unexpected error: " ++ show e

-- | The parser should parse this string, consuming it entirely, and succeed
-- yielding the matching value.
shouldParseWith ::
  (Show a, Eq a, Show e) => FB.Parser e a -> (ByteString, a) -> Expectation
p `shouldParseWith` (s, r) = case FB.runParser p s of
  FB.OK r' "" -> r' `shouldBe` r
  FB.OK _ lo -> assertFailure $ "Unexpected leftover: " ++ show lo
  FB.Fail -> assertFailure "Parse failed unexpectedly"
  FB.Err e -> assertFailure $ "Parse threw unexpected error: " ++ show e

-- | The parser should parse this string, possibly with leftovers, and succeed
-- yielding the matching value.
shouldParsePartialWith ::
  (Show a, Eq a, Show e) => FB.Parser e a -> (ByteString, a) -> Expectation
p `shouldParsePartialWith` (s, r) = case FB.runParser p s of
  FB.OK r' lo -> r' `shouldBe` r
  FB.Fail -> assertFailure "Parse failed unexpectedly"
  FB.Err e -> assertFailure $ "Parse threw unexpected error: " ++ show e

-- | The parser should fail when given this string.
shouldParseFail :: Show e => FB.Parser e a -> ByteString -> Expectation
p `shouldParseFail` s = case FB.runParser p s of
  FB.Fail -> pure ()
  FB.OK _ _ -> assertFailure "Parse succeeded unexpectedly"
  FB.Err e -> assertFailure $ "Parse threw unexpected error: " ++ show e

-- | The parser should throw an error when given this string.
shouldParseErr :: FB.Parser e a -> ByteString -> Expectation
p `shouldParseErr` s = case FB.runParser p s of
  FB.Err e -> pure ()
  FB.Fail -> assertFailure "Parse failed unexpectedly"
  FB.OK _ _ -> assertFailure "Parse succeeded unexpectedly"

-- | The parser should throw an error when given this string, and the error
-- should be the one given.
shouldParseErrWith ::
  (Show e, Eq e) => FB.Parser e a -> (ByteString, e) -> Expectation
p `shouldParseErrWith` (s, e) = case FB.runParser p s of
  FB.Err e' -> e' `shouldBe` e
  FB.Fail -> assertFailure "Parse failed unexpectedly"
  FB.OK _ _ -> assertFailure "Parse succeeded unexpectedly"
