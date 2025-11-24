{-# OPTIONS_GHC -Wno-orphans #-}
module Lib3(
    emptyState, State(..), execute, load, save, storageOpLoop, StorageOp, Parser(..), parseCommand) where

import qualified Lib1
import qualified Lib2

import Control.Concurrent.STM.TVar (TVar)
import Control.Concurrent (Chan, readChan, writeChan, newChan)
import Control.Concurrent.STM (atomically, readTVar, writeTVar, readTVarIO)
import Control.Applicative (Alternative(..), many, some)
import Data.Char (isAlphaNum, isDigit, isSpace)
import Data.List (intercalate, inits, isPrefixOf, nub, sortOn)
import Control.Exception (try, IOException)



newtype Parser a = Parser {
    runParser :: String -> Either String (a, String)
}

instance Functor Parser where
  fmap transform (Parser parseFn) = Parser $ \input -> case parseFn input of
    Right (value, remainingInput) -> Right (transform value, remainingInput)
    Left err                      -> Left err

instance Applicative Parser where
  pure value = Parser $ \input -> Right (value, input)
  (Parser parseFn) <*> (Parser parseArg) = Parser $ \input -> case parseFn input of
    Left err -> Left err
    Right (func, inputAfterFunc) -> case parseArg inputAfterFunc of
      Left err2                      -> Left err2
      Right (argValue, inputAfterArg) -> Right (func argValue, inputAfterArg)

instance Alternative Parser where
  empty = Parser $ \_ -> Left "empty"
  (Parser parseFirst) <|> (Parser parseSecond) = Parser $ \input -> case parseFirst input of
    Right result -> Right result
    Left _       -> parseSecond input


--Paimam pirmą simbolį iš input grąžinam tą simbolį + likusį tekstą.
satisfy :: (Char -> Bool) -> Parser Char
satisfy predicate = Parser $ \input -> case input of
  (ch:rest) | predicate ch -> Right (ch, rest)
  _                        -> Left "unexpected char"

pChar :: Char -> Parser Char
pChar expected = satisfy (== expected)

pString :: String -> Parser String
pString = traverse pChar

pDigit :: Parser Char
pDigit = satisfy isDigit

pNumber :: Parser Integer
pNumber = read <$> some pDigit

spaces0 :: Parser String
spaces0 = many (satisfy isSpace)

spaces1 :: Parser String
spaces1 = some (satisfy isSpace)

skipSpaces :: Parser ()
skipSpaces = const () <$> spaces0

requireSpaces :: Parser ()
requireSpaces = const () <$> spaces1
--tikrinimas, ar po keyword’o eina “saugus simbolis”,
boundary :: Parser ()
boundary = Parser $ \input -> case input of
  [] -> Right ((), [])
  (ch:_) | isSpace ch || ch == '/' -> Right ((), input)
  _ -> Left "keyword boundary"

keyword :: String -> Parser String
keyword kw = (\_ -> kw) <$> (pString kw <* boundary)

isSegChar :: Char -> Bool
isSegChar ch = isAlphaNum ch || ch == '.' || ch == '-' || ch == '_'

pSeg :: Parser String
pSeg = some (satisfy isSegChar)

type Path = Lib1.Path

renderPath :: Path -> String
renderPath = intercalate "/"

pPath :: Parser Path
pPath = (:) <$> pSeg <*> many (pChar '/' *> pSeg)
--tikrina ar visiskai sunaudojom visa ivesti 
eof :: Parser ()
eof = Parser $ \input -> case input of
  [] -> Right ((), [])
  _  -> Left "unexpected extra input"




pDumpExamples' :: Parser Lib1.Command
pDumpExamples' = Lib1.DumpExamples <$ keyword "dump" <* requireSpaces <* keyword "examples"


pMkDir :: Parser Lib1.Command
pMkDir = Lib1.MkDir <$> (keyword "mkdir" *> requireSpaces *> pPath)


pTouch :: Parser Lib1.Command
pTouch = Lib1.Touch <$> (keyword "touch" *> requireSpaces *> pPath)
                    <*> (requireSpaces *> pNumber)


pLs :: Parser Lib1.Command
pLs = Lib1.Ls <$> (keyword "ls" *> ((Just <$> (requireSpaces *> pPath)) <|> pure Nothing))


pRm :: Parser Lib1.Command
pRm = Lib1.Rm <$> (keyword "rm" *> requireSpaces *> pPath)


pMv :: Parser Lib1.Command
pMv = Lib1.Mv <$> (keyword "mv" *> requireSpaces *> pPath)
              <*> (requireSpaces *> keyword "to" *> requireSpaces *> pPath)


pSize :: Parser Lib1.Command
pSize = Lib1.SizeCmd <$> (keyword "size"
                       *> ((Just <$> (requireSpaces *> keyword "in" *> requireSpaces *> pPath))
                           <|> pure Nothing))


pFind :: Parser Lib1.Command
pFind = Lib1.Find <$> (keyword "find" *> requireSpaces *> pSeg)
                  <*> ((Just <$> (requireSpaces *> keyword "in" *> requireSpaces *> pPath)) <|> pure Nothing)


pTree :: Parser Lib1.Command
pTree = (\_ maybePath maybeDepth -> Lib1.Tree maybePath maybeDepth)
    <$> keyword "tree"
    <*> ((Just <$> (requireSpaces *> keyword "in" *> requireSpaces *> pPath)) <|> pure Nothing)
    <*> ((Just <$> (requireSpaces *> keyword "depth" *> requireSpaces *> pNumber)) <|> pure Nothing)


pShowPath :: Parser Lib1.Command
pShowPath = Lib1.ShowPath <$> (keyword "show" *> requireSpaces *> pPath)

pCommand :: Parser Lib1.Command
pCommand = pDumpExamples'
       <|> pMkDir
       <|> pTouch
       <|> pLs
       <|> pRm
       <|> pMv
       <|> pSize
       <|> pFind
       <|> pTree
       <|> pShowPath

parseCommand :: Parser Lib1.Command
parseCommand = Parser $ \input -> 
  case runParser (skipSpaces *> pCommand <* skipSpaces <* eof) input of
    Right result -> Right result
    Left err     -> Left err









data State = State {
    stDirs  :: [Path],             
    stFiles :: [(Path, Integer)]   
  } deriving (Show)

emptyState :: State
emptyState = State { stDirs = [], stFiles = [] }

-- Kai sukuri failą arba folderį, turi būti užtikrinta, kad visi jo tėvai (parent directories) egzistuoja.
ensureDir :: [Path] -> Path -> [Path]
ensureDir existingDirs path =
  nub (existingDirs ++ filter (not . null) (tail (inits path)))
-- Kai kuri failą, jis turi būti pridėtas arba jei failas jau egzistuoja — turi būti pakeistas (overwrite)
setFile :: [(Path,Integer)] -> (Path,Integer) -> [(Path,Integer)]
setFile existingFiles (filePath,fileSize) =
  (filePath,fileSize) : filter ((/= filePath) . fst) existingFiles
--rm funcijai
dropUnder :: Path -> [Path] -> [Path]
dropUnder basePath =
  filter (not . (basePath `isPrefixOf`))

dropFilesUnder :: Path -> [(Path,Integer)] -> [(Path,Integer)]
dropFilesUnder basePath =
  filter (not . (basePath `isPrefixOf`) . fst)
--mv funcijai
renamePrefix :: Path -> Path -> Path -> Maybe Path
renamePrefix fromPrefix toPrefix path
  | fromPrefix `isPrefixOf` path = Just (toPrefix ++ drop (length fromPrefix) path)
  | otherwise                    = Nothing
--priima dabartini state priima vartotojo ivesta komanda ir nauja state padaro
applyCommand :: State -> Lib1.Command -> (State, [String])
applyCommand currentState Lib1.DumpExamples =
  (currentState, "Examples:" : map Lib2.toCliCommand Lib1.examples)

applyCommand currentState (Lib1.MkDir dirPath) =
  let dirsWithParents   = ensureDir (stDirs currentState) dirPath ++ [dirPath]
      normalizedDirs    = nub $ sortOn length dirsWithParents
  in (currentState { stDirs = normalizedDirs }, ["mkdir " ++ renderPath dirPath ++ " OK"])

applyCommand currentState (Lib1.Touch filePath fileSize) =
  let parentPath        = init filePath
      dirsWithParents   = ensureDir (stDirs currentState) parentPath ++ [parentPath | not (null parentPath)]
      updatedFiles      = setFile (stFiles currentState) (filePath, fileSize)
  in (currentState { stDirs = nub $ sortOn length dirsWithParents, stFiles = updatedFiles }
     , ["touch " ++ renderPath filePath ++ " " ++ show fileSize ++ " OK"])

applyCommand currentState (Lib1.Rm pathToRemove) =
  let remainingDirs  = dropUnder pathToRemove (stDirs currentState)
      remainingFiles = dropFilesUnder pathToRemove (stFiles currentState)
  in (currentState { stDirs = remainingDirs, stFiles = remainingFiles }, ["rm " ++ renderPath pathToRemove ++ " OK"])

applyCommand currentState (Lib1.Mv fromPath toPath) =
  let moveDir dirPath = maybe dirPath id (renamePrefix fromPath toPath dirPath)
      movedDirs       = nub $ sortOn length $ map moveDir (stDirs currentState)
      moveFile (filePath, fileSize) =
        maybe (filePath, fileSize) (\newPath -> (newPath, fileSize)) (renamePrefix fromPath toPath filePath)
      movedFiles      = map moveFile (stFiles currentState)
  in (currentState { stDirs = movedDirs, stFiles = movedFiles }, ["mv " ++ renderPath fromPath ++ " to " ++ renderPath toPath ++ " OK"])

applyCommand currentState (Lib1.Ls maybePath) =
  let basePath       = maybe [] id maybePath
      dirChildren    = [renderPath dirPath
                       | dirPath <- stDirs currentState
                       , basePath `isPrefixOf` dirPath
                       , length dirPath == length basePath + 1]
      fileChildren   = [renderPath filePath ++ " (" ++ show fileSize ++ ")"
                       | (filePath,fileSize) <- stFiles currentState
                       , basePath `isPrefixOf` filePath
                       , length filePath == length basePath + 1]
      outputLines    = if null dirChildren && null fileChildren then ["(empty)"] else dirChildren ++ fileChildren
  in (currentState, outputLines)

applyCommand currentState (Lib1.SizeCmd maybePath) =
  let basePath   = maybe [] id maybePath
      totalSize  = sum [ fileSize | (filePath, fileSize) <- stFiles currentState, basePath `isPrefixOf` filePath ]
  in (currentState, ["size: " ++ show totalSize])

applyCommand currentState (Lib1.Find query maybePath) =
  let basePath = maybe [] id maybePath

      isIn :: String -> String -> Bool
      isIn needle haystack =
           needle `isPrefixOf` haystack
        || any (needle `isPrefixOf`) (tails haystack)

      tails []         = [[]]
      tails xs@(_:rest) = xs : tails rest

      match path =
        basePath `isPrefixOf` path && case path of
          []         -> False
          segments   -> isIn query (last segments)

      dirHits  = [renderPath dirPath  | dirPath  <- stDirs currentState, match dirPath]
      fileHits = [renderPath filePath | (filePath,_) <- stFiles currentState, match filePath]
  in (currentState, dirHits ++ fileHits)

applyCommand currentState (Lib1.Tree maybePath maybeDepth) =
  let basePath = maybe [] id maybePath

      depthOk path = case maybeDepth of
        Nothing       -> True
        Just maxDepth -> length path - length basePath <= fromIntegral maxDepth

      allEntries = [ (dirPath, True)  | dirPath     <- stDirs currentState, basePath `isPrefixOf` dirPath, depthOk dirPath ]
                ++ [ (filePath, False) | (filePath,_) <- stFiles currentState, basePath `isPrefixOf` filePath, depthOk filePath ]

      sortedEntries = sortOn fst allEntries

      fmt (path, isDir) =
        replicate (2 * (length path - length basePath - 1)) ' '
        ++ (if isDir then "[D] " else "[F] ")
        ++ renderPath path

      outputLines = if null sortedEntries then ["(empty)"] else map fmt sortedEntries
  in (currentState, outputLines)

applyCommand currentState (Lib1.ShowPath path) =
  let isDirectory = path `elem` stDirs currentState
      maybeFile   = lookup path (stFiles currentState)
      outputLines
        | Just fileSize <- maybeFile = [renderPath path ++ " (" ++ show fileSize ++ ")"]
        | isDirectory                = [renderPath path ++ "/"]
        | otherwise                  = [renderPath path ++ " (not found)"]
  in (currentState, outputLines)
--iskviecia programa kai ivedam kazka
execute :: TVar State -> Lib1.Command -> IO ()
execute stateVar command = do
  outputLines <- atomically $ do
    currentState <- readTVar stateVar
    let (newState, outLines) = applyCommand currentState command
    writeTVar stateVar newState
    return outLines
  mapM_ putStrLn outputLines








data StorageOp = Save String (Chan ()) | Load (Chan String)

stateFile :: FilePath
stateFile = "state.txt"

storageOpLoop :: Chan StorageOp -> IO ()
storageOpLoop storageChannel = do
  request <- readChan storageChannel
  case request of
    Save content ackChannel -> do
      writeFile stateFile content
      writeChan ackChannel ()
    Load responseChannel -> do
      result <- try (readFile stateFile) :: IO (Either IOException String)
      case result of
        Left _  -> writeChan responseChannel "" 
        Right s -> writeChan responseChannel s
  storageOpLoop storageChannel


stateToCommands :: State -> [Lib1.Command]
stateToCommands state =
  let dirCmds  = [ Lib1.MkDir dirPath | dirPath <- sortOn length (nub (stDirs state)), not (null dirPath) ]
      fileCmds = [ Lib1.Touch filePath fileSize | (filePath, fileSize) <- stFiles state ]
  in dirCmds ++ fileCmds

save :: Chan StorageOp -> TVar State -> IO (Either String ())
save storageChannel stateVar = do
  currentState <- readTVarIO stateVar
  let cmds    = stateToCommands currentState
      content = unlines (map Lib2.toCliCommand cmds)
  ackChannel <- newAck
  writeChan storageChannel (Save content ackChannel)
  _ <- readChan ackChannel
  return (Right ())
  where
    newAck :: IO (Chan ())
    newAck = newChan


load :: Chan StorageOp -> TVar State -> IO (Either String ())
load storageChannel stateVar = do
  responseChannel <- newResp
  writeChan storageChannel (Load responseChannel)
  content <- readChan responseChannel
  let nonEmptyLines = filter (not . null) (lines content)
  case traverse (fmap fst . runParser parseCommand) nonEmptyLines of
    Left msg -> return (Left ("parse error in state file: " ++ msg))
    Right cmds -> do
      let restoredState = foldl (\accState cmd -> fst (applyCommand accState cmd)) emptyState cmds
      atomically $ writeTVar stateVar restoredState
      return (Right ())
  where
    newResp :: IO (Chan String)
    newResp = newChan
