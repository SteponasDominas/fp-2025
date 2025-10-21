{-# OPTIONS_GHC -Wno-orphans #-}
module Lib2
  ( parseCommand
  , ToCliCommand(..)
  , process
  ) where

import qualified Lib1
import Data.Char (isAlphaNum, isDigit, isSpace)
import Data.List (intercalate) -- cia keliui sujungti su šitais "/"




type ErrorMsg = String
type Parser a = String -> Either ErrorMsg (a, String) -- grazina arba viska ko neatpazino arba ka atpazino ir kas liko neatpazinta




--panaikina tarpa pradzioj tada paziuri komanda panaikina tarpa po jos ir poto ziuri ar dar kazkas lieka
runAll :: Parser a -> String -> Either ErrorMsg a
runAll parser inputText =
  case skipSpaces inputText of
    Right (_, inputAfterSpaces) -> case parser inputAfterSpaces of
      Right (parsedValue, remainingInput) -> case skipSpaces remainingInput of
        Right (_, finalRemaining) | null finalRemaining -> Right parsedValue
        _ -> Left "unexpected extra input"
      Left errorMsg -> Left errorMsg
    Left errorMsg -> Left errorMsg



--ziuri teksta jei neranda vienos atitinkancios tikrina kita ir t.t.
--jei viskas pavyksta visi parseriai susijungia ir gauni pilna komanda
orElse :: Parser a -> Parser a -> Parser a
orElse firstParser secondParser inputText = case firstParser inputText of
  Right parsed -> Right parsed
  Left _       -> secondParser inputText

and2 :: Parser a -> Parser b -> Parser (a,b)
and2 firstParser secondParser inputText = case firstParser inputText of
  Right (a, inputAfterFirst) -> case secondParser inputAfterFirst of
    Right (b, inputAfterSecond) -> Right ((a,b), inputAfterSecond)
    Left  err                  -> Left err
  Left err -> Left err

and3 :: Parser a -> Parser b -> Parser c -> Parser (a,b,c)
and3 firstParser secondParser thirdParser inputText = case and2 firstParser secondParser inputText of
  Right ((valueA,valueB), inputAfterTwo) -> case thirdParser inputAfterTwo of
    Right (valueC, inputAfterThree) -> Right ((valueA,valueB,valueC), inputAfterThree)
    Left errorMsg                   -> Left errorMsg
  Left errorMsg -> Left errorMsg

and4 :: Parser a -> Parser b -> Parser c -> Parser d -> Parser (a,b,c,d)
and4 firstParser secondParser thirdParser fourthParser inputText = case and3 firstParser secondParser thirdParser inputText of
  Right ((valueA,valueB,valueC), inputAfterThree) -> case fourthParser inputAfterThree of
    Right (valueD, inputAfterFour) -> Right ((valueA,valueB,valueC,valueD), inputAfterFour)
    Left errorMsg                  -> Left errorMsg
  Left errorMsg -> Left errorMsg

-- Combine five parsers in sequence, returning a 5-tuple of results
and5 :: Parser a -> Parser b -> Parser c -> Parser d -> Parser e -> Parser (a,b,c,d,e)
and5 firstParser secondParser thirdParser fourthParser fifthParser inputText =
  case and4 firstParser secondParser thirdParser fourthParser inputText of
    Right ((valueA,valueB,valueC,valueD), inputAfterFour) -> case fifthParser inputAfterFour of
      Right (valueE, inputAfterFive) -> Right ((valueA,valueB,valueC,valueD,valueE), inputAfterFive)
      Left errorMsg                  -> Left errorMsg
    Left errorMsg -> Left errorMsg


-- pakeist rezultata uzdet fucija kokia
mapParser :: (a -> b) -> Parser a -> Parser b
mapParser mapFn parser inputText = case parser inputText of
  Right (value, rest) -> Right (mapFn value, rest)
  Left err            -> Left err



--jei tuscia o tikejo dar tai irgi klaida meta(pasku)
pChar :: Char -> Parser Char
pChar expectedChar (currentChar:restInput)
  | currentChar == expectedChar = Right (currentChar, restInput)
  | otherwise                   = Left ("expected char '" ++ [expectedChar] ++ "'")
pChar expectedChar [] = Left ("expected char '" ++ [expectedChar] ++ "'")


--paima pirma skaiciu jei digit ok ir tada su span likusius skaicius iki kokio teksto pvz
pDigit :: Parser Char
pDigit (currentChar:restInput) | isDigit currentChar = Right (currentChar, restInput)
pDigit _                                            = Left "expected digit"

--visus skaitmenis paima ir pavercia i integer
--naudoja pdigit visa skaiciu i integeri pavercia
pNumber :: Parser Integer
pNumber inputText =
  case pDigit inputText of
    Right (firstDigit, restAfterFirst) ->
      let (moreDigits, restAfterDigits) = span isDigit restAfterFirst
      in Right (read (firstDigit:moreDigits), restAfterDigits)
    Left _ -> Left "expected number"


--rekursyviai po viena raide cia tas tarpas jei jau pasibaige zodis tai baigia
pString :: String -> Parser String
pString "" inputText = Right ("", inputText)
pString (expectedChar:remainingExpected) inputText = case pChar expectedChar inputText of
  Right (_, inputAfterExpected) -> case pString remainingExpected inputAfterExpected of
    Right (_, remainingInput) -> Right (expectedChar:remainingExpected, remainingInput)
    Left errorMsg             -> Left errorMsg
  Left errorMsg -> Left errorMsg

--turi but bent vienas tarpas nes kitaip klaida
pWhitespace1 :: Parser String
pWhitespace1 inputText =
  let (spaces, rest) = span isSpace inputText
  in if null spaces then Left "expected whitespace" else Right (spaces, rest)

--gali but betkiek tarpu
pWhitespace0 :: Parser String
pWhitespace0 inputText = let (spaces, rest) = span isSpace inputText in Right (spaces, rest)
--const() tsg viska ka gauna panaikina i nieka
skipSpaces :: Parser ()
skipSpaces = mapParser (const ()) pWhitespace0

requireSpaces :: Parser ()
requireSpaces = mapParser (const ()) pWhitespace1


--cia pvz kaip stringas bet kad nebutu pvz lsaaa tokio pvz 
pKeyword :: String -> Parser String
pKeyword expectedKeyword inputText = case pString expectedKeyword inputText of
  Right (_, remainingInput) ->
    case remainingInput of
      [] -> Right (expectedKeyword, remainingInput)
      (nextChar:_) | isSpace nextChar || nextChar == '/' -> Right (expectedKeyword, remainingInput)
      _ -> Left ("expected keyword '" ++ expectedKeyword ++ "' boundary")
  Left err -> Left err




  --tikrina ar charas ar skaicius ir dar prideda situos leistinus simbolius
isSegChar :: Char -> Bool
isSegChar currentChar = isAlphaNum currentChar || currentChar == '.' || currentChar == '-' || currentChar == '_'
--segmenta atpazista home/..   tai iki home eis tikrins o poto sustoja nes / neleistinas prie char kaip simbolis 
pSeg :: Parser String
pSeg (currentChar:remainingChars) | isSegChar currentChar =
  let (moreSegmentChars, remainingInput) = span isSegChar remainingChars
  in Right (currentChar:moreSegmentChars, remainingInput)
pSeg _ = Left "expected path segment"




--paima teksta ir grazina segmentus 
--po segmentuka ima kviecia pseg jei / tai rekursiskai toliau save kviecia
pPath :: Parser Lib1.Path
pPath inputText = case pSeg inputText of
  Right (segment, afterSegment) ->
    case afterSegment of
      ('/':rest) -> case pPath rest of
        Right (segments, remaining) -> Right (segment:segments, remaining)
        Left err                    -> Left err
      _ -> Right ([segment], afterSegment)
  Left _ -> Left "expected path"





--tris parserius sujungia ir grazina kas poto 
-- dump examples
--gauna teksta ir komanda bando grzint
pDumpExamples :: Parser Lib1.Command
pDumpExamples inputText =
  case and3 (pKeyword "dump") requireSpaces (pKeyword "examples") inputText of
    Right ((_,_,_), remaining) -> Right (Lib1.DumpExamples, remaining)
    Left err                   -> Left err


pMkDir :: Parser Lib1.Command
pMkDir inputText =
  case and3 (pKeyword "mkdir") requireSpaces pPath inputText of
    Right ((_,_,parsedPath), remaining) -> Right (Lib1.MkDir parsedPath, remaining)
    Left err                            -> Left err


pTouch :: Parser Lib1.Command
pTouch inputText =
  case and5 (pKeyword "touch") requireSpaces pPath requireSpaces pNumber inputText of
    Right ((_,_,parsedPath,_,num), remaining) -> Right (Lib1.Touch parsedPath num, remaining)
    Left err -> Left err


pLs :: Parser Lib1.Command
pLs inputText = case pKeyword "ls" inputText of
  Right (_, afterKw) ->
    case and2 requireSpaces pPath afterKw of
      Right ((_, parsedPath), remaining) -> Right (Lib1.Ls (Just parsedPath), remaining)
      Left _ -> Right (Lib1.Ls Nothing, afterKw)
  Left err -> Left err


pRm :: Parser Lib1.Command
pRm inputText =
  case and3 (pKeyword "rm") requireSpaces pPath inputText of
    Right ((_,_,parsedPath), remaining) -> Right (Lib1.Rm parsedPath, remaining)
    Left err                            -> Left err


pMv :: Parser Lib1.Command
pMv inputText =
  case and4 (pKeyword "mv") requireSpaces pPath requireSpaces inputText of
    Right ((_,_,srcPath,_), afterSrcAndSpace) ->
      case and3 (pKeyword "to") requireSpaces pPath afterSrcAndSpace of
        Right ((_,_,dstPath), remainingInput) -> Right (Lib1.Mv srcPath dstPath, remainingInput)
        Left errorMsg -> Left errorMsg
    Left errorMsg -> Left errorMsg

pSize :: Parser Lib1.Command
pSize inputText =
  case and5 (pKeyword "size") requireSpaces (pKeyword "in") requireSpaces pPath inputText of
    Right ((_,_,_,_, pathSegments), remaining) -> Right (Lib1.SizeCmd (Just pathSegments), remaining)
    Left _ -> case pKeyword "size" inputText of
      Right (_, remaining) -> Right (Lib1.SizeCmd Nothing, remaining)
      Left err             -> Left err


pFind :: Parser Lib1.Command
pFind inputText =
  case and5 (pKeyword "find") requireSpaces pSeg requireSpaces (pKeyword "in") inputText of
    Right ((_,_,query,_,_), afterIn) ->
      case and2 requireSpaces pPath afterIn of
        Right ((_, pathSegments), remaining) -> Right (Lib1.Find query (Just pathSegments), remaining)
        Left err -> Left err
    Left _ ->  
      case and3 (pKeyword "find") requireSpaces pSeg inputText of
        Right ((_,_,query), remaining) -> Right (Lib1.Find query Nothing, remaining)
        Left err -> Left err


pTree :: Parser Lib1.Command
pTree inputText =
  case pKeyword "tree" inputText of
    Right (_, inputAfterTreeKeyword) ->
      let parseOptional :: Parser a -> Parser (Maybe a)
          parseOptional parser currentInput =
            case parser currentInput of
              Right (value, remainingInput) -> Right (Just value, remainingInput)
              Left  _                       -> Right (Nothing, currentInput)

          parseInUnitPathSegments :: Parser Lib1.Path
          parseInUnitPathSegments =
            mapParser (\(_,_,_, pathSegments) -> pathSegments)
                     (and4 requireSpaces (pKeyword "in") requireSpaces pPath)

          parseDepthUnitNumber :: Parser Integer
          parseDepthUnitNumber =
            mapParser (\(_,_,_, depthNumber) -> depthNumber)
                     (and4 requireSpaces (pKeyword "depth") requireSpaces pNumber)

      in case parseOptional parseInUnitPathSegments inputAfterTreeKeyword of
           Right (maybePathSegments, inputAfterInClause) ->
             case parseOptional parseDepthUnitNumber inputAfterInClause of
               Right (maybeDepthNumber, remainingInput) ->
                 Right (Lib1.Tree maybePathSegments maybeDepthNumber, remainingInput)
               Left parseError -> Left parseError
           Left parseError -> Left parseError
    Left parseError -> Left parseError




pShowPath :: Parser Lib1.Command
pShowPath inputText =
  case and3 (pKeyword "show") requireSpaces pPath inputText of
    Right ((_,_,parsedPath), remaining) -> Right (Lib1.ShowPath parsedPath, remaining)
    Left err                            -> Left err



--is ivesties sukurti komanda
pCommand :: Parser Lib1.Command
pCommand =
      pDumpExamples
  `orElse` pMkDir
  `orElse` pTouch
  `orElse` pLs
  `orElse` pRm
  `orElse` pMv
  `orElse` pSize
  `orElse` pFind
  `orElse` pTree
  `orElse` pShowPath


parseCommand :: Parser Lib1.Command
parseCommand inputText = case runAll pCommand inputText of
  Right parsedCommand -> Right (parsedCommand, "")
  Left errorMsg       -> Left errorMsg



--betkuris tipas kuris tocli turi but igyvendintas per funcija i stringa
class ToCliCommand a where
  toCliCommand :: a -> String


--intercalate funcija sujungianti sarasa su norimu skirtuku
renderPath :: Lib1.Path -> String
renderPath = intercalate "/"



--instance tai nurodymai kaip paversti
instance ToCliCommand Lib1.Command where
  toCliCommand Lib1.DumpExamples                 = "dump examples"
  toCliCommand (Lib1.MkDir pathSegments)         = "mkdir " <> renderPath pathSegments
  toCliCommand (Lib1.Touch pathSegments num)     = "touch " <> renderPath pathSegments <> " " <> show num
  toCliCommand (Lib1.Ls Nothing)                 = "ls"
  toCliCommand (Lib1.Ls (Just pathSegments))     = "ls " <> renderPath pathSegments
  toCliCommand (Lib1.Rm pathSegments)            = "rm " <> renderPath pathSegments
  toCliCommand (Lib1.Mv sourcePath destPath)     = "mv " <> renderPath sourcePath <> " to " <> renderPath destPath
  toCliCommand (Lib1.SizeCmd Nothing)            = "size"
  toCliCommand (Lib1.SizeCmd (Just pathSegments))= "size in " <> renderPath pathSegments
  toCliCommand (Lib1.Find query Nothing)         = "find " <> query
  toCliCommand (Lib1.Find query (Just pathSegments))
                                                 = "find " <> query <> " in " <> renderPath pathSegments

  toCliCommand (Lib1.Tree maybePath maybeDepth)   =
    unwords $ ["tree"]
           ++ maybe [] (\pathSegments -> ["in", renderPath pathSegments]) maybePath
           ++ maybe [] (\depthNum -> ["depth", show depthNum]) maybeDepth

  toCliCommand (Lib1.ShowPath pathSegments)       = "show " <> renderPath pathSegments



--paskutine eilute bendras jei palygins dvi skirtingas nebus true
--eq reikalingas kad galetum palyginti duomenis lib1 comand nezinotu kaip lygint duomenis leidzia zodziu == lyginima
instance Eq Lib1.Command where
  Lib1.DumpExamples                        == Lib1.DumpExamples                         = True
  Lib1.MkDir pathA                         == Lib1.MkDir pathB                          = pathA == pathB
  Lib1.Touch pathA numA                    == Lib1.Touch pathB numB                     = pathA == pathB && numA == numB
  Lib1.Ls maybePathA                       == Lib1.Ls maybePathB                        = maybePathA == maybePathB
  Lib1.Rm pathA                            == Lib1.Rm pathB                             = pathA == pathB
  Lib1.Mv srcA dstA                        == Lib1.Mv srcB dstB                         = srcA == srcB && dstA == dstB
  Lib1.SizeCmd maybePathA                  == Lib1.SizeCmd maybePathB                   = maybePathA == maybePathB
  Lib1.Find queryA maybePathA              == Lib1.Find queryB maybePathB               = queryA == queryB && maybePathA == maybePathB
  Lib1.Tree maybePathA maybeDepthA         == Lib1.Tree maybePathB maybeDepthB          = maybePathA == maybePathB && maybeDepthA == maybeDepthB

  Lib1.ShowPath pathA                      == Lib1.ShowPath pathB                        = pathA == pathB
  _                                        == _                                         = False



--pirma isspausdina examples visu o antra komanda is esmes ka useris ivede
process :: Lib1.Command -> [String]
process Lib1.DumpExamples = "Examples:" : map toCliCommand Lib1.examples
process command = ["Parsed as " ++ show command]
