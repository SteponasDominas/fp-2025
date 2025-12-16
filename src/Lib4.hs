{-# OPTIONS_GHC -Wno-orphans #-}
{-# LANGUAGE InstanceSigs #-}

module Lib4
  ( ErrorMsg,
    Input,
    Parser,
    parseCommand,
    parseCommandString,
    applyCommand,
    stateToCommands,
    FsOp (..),
    FsDSL,
    dumpExamples,
    mkdir,
    touch,
    ls,
    rm,
    mv,
    sizeCmd,
    findCmd,
    tree,
    showPathCmd,
    SendCommand,
    runDslOverHttp,
    interpretLocal,
    runDslLocal
  )
where

import Control.Monad.Free (Free, foldFree, liftF)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import Control.Monad.Trans.State.Strict (State, get, put, runState, state)
import Data.Char (isAlphaNum, isDigit, isSpace)
import Data.List (intercalate, inits, isPrefixOf, nub, sortOn)
import Test.QuickCheck
  ( Arbitrary (arbitrary),
    Gen,
    chooseInteger,
    elements,
    frequency,
    listOf1,
    oneof
  )

import qualified Lib1
import qualified Lib2
import qualified Lib3

--------------------------------------------------------------------------------
-- Parser infrastructure (Lab 4)
--------------------------------------------------------------------------------

type ErrorMsg = String

type Input = String

-- Lab 4 requirement: Parser is defined in Lib4.
type Parser a = ExceptT ErrorMsg (State Input) a

runParserOn :: Parser a -> Input -> (Either ErrorMsg a, Input)
runParserOn p input = runState (runExceptT p) input

-- | Choice combinator with backtracking.
orElseP :: Parser a -> Parser a -> Parser a
orElseP p q =
  ExceptT $
    state $ \input ->
      case runParserOn p input of
        (Right a, rest) -> (Right a, rest)
        (Left _, _rest) -> runParserOn q input

-- | Parse zero or more occurrences (recursive).
manyP :: Parser a -> Parser [a]
manyP p = orElseP (someP p) (pure [])

-- | Parse one or more occurrences (recursive).
someP :: Parser a -> Parser [a]
someP p = do
  x <- p
  xs <- manyP p
  pure (x : xs)

-- | Optional parser.
optionalP :: Parser a -> Parser (Maybe a)
optionalP p = orElseP (Just <$> p) (pure Nothing)

-- BNF: <char> ::= any char satisfying predicate
satisfy :: (Char -> Bool) -> Parser Char
satisfy predicate = do
  input <- lift get
  case input of
    (ch : rest)
      | predicate ch -> lift (put rest) >> pure ch
    _ -> throwE "unexpected char"

-- BNF: <char> ::= 'x'
pChar :: Char -> Parser Char
pChar ch = satisfy (== ch)

-- BNF: <string> ::= exact sequence of characters
pString :: String -> Parser String
pString [] = pure []
pString (c : cs) = do
  _ <- pChar c
  _ <- pString cs
  pure (c : cs)

-- BNF: <digit> ::= '0' | ... | '9'
pDigit :: Parser Char
pDigit = satisfy isDigit

-- BNF: <number> ::= <digit> { <digit> }
pNumber :: Parser Integer
pNumber = read <$> someP pDigit

-- BNF: <whitespace> ::= { space }
spaces0 :: Parser ()
spaces0 = () <$ manyP (satisfy isSpace)

-- BNF: <whitespace1> ::= space { space }
spaces1 :: Parser ()
spaces1 = () <$ someP (satisfy isSpace)

skipSpaces :: Parser ()
skipSpaces = spaces0

requireSpaces :: Parser ()
requireSpaces = spaces1

peekChar :: Parser (Maybe Char)
peekChar = do
  input <- lift get
  case input of
    [] -> pure Nothing
    (c : _) -> pure (Just c)

-- | Keyword boundary: after keyword must be EOF/space/'/'.
boundary :: Parser ()
boundary = do
  mch <- peekChar
  case mch of
    Nothing -> pure ()
    Just ch
      | isSpace ch || ch == '/' -> pure ()
      | otherwise -> throwE "keyword boundary"

keyword :: String -> Parser String
keyword kw = do
  _ <- pString kw
  boundary
  pure kw

-- BNF: <segChar> ::= alphaNum | '.' | '-' | '_'
isSegChar :: Char -> Bool
isSegChar ch = isAlphaNum ch || ch == '.' || ch == '-' || ch == '_'

-- BNF: <name> ::= <segChar> { <segChar> }
pSeg :: Parser String
pSeg = someP (satisfy isSegChar)

type Path = Lib1.Path

-- BNF: <path> ::= <name> { "/" <name> }
pPath :: Parser Path
pPath = do
  first <- pSeg
  rest <- manyP (pChar '/' *> pSeg)
  pure (first : rest)

-- | Ensure input fully consumed.
eof :: Parser ()
eof = do
  input <- lift get
  case input of
    [] -> pure ()
    _ -> throwE "unexpected extra input"

--------------------------------------------------------------------------------
-- Command parsers (one per constructor; symmetric to BNF)
--------------------------------------------------------------------------------

-- BNF: <command> ::= "dump" <ws1> "examples"
pDumpExamples :: Parser Lib1.Command
pDumpExamples = do
  _ <- keyword "dump"
  requireSpaces
  _ <- keyword "examples"
  pure Lib1.DumpExamples

-- BNF: <command> ::= "mkdir" <ws1> <path>
pMkDir :: Parser Lib1.Command
pMkDir = do
  _ <- keyword "mkdir"
  requireSpaces
  Lib1.MkDir <$> pPath

-- BNF: <command> ::= "touch" <ws1> <path> <ws1> <number>
pTouch :: Parser Lib1.Command
pTouch = do
  _ <- keyword "touch"
  requireSpaces
  path <- pPath
  requireSpaces
  size <- pNumber
  pure (Lib1.Touch path size)

-- BNF: <command> ::= "ls" [ <ws1> <path> ]
pLs :: Parser Lib1.Command
pLs = do
  _ <- keyword "ls"
  mpath <- optionalP (requireSpaces *> pPath)
  pure (Lib1.Ls mpath)

-- BNF: <command> ::= "rm" <ws1> <path>
pRm :: Parser Lib1.Command
pRm = do
  _ <- keyword "rm"
  requireSpaces
  Lib1.Rm <$> pPath

-- BNF: <command> ::= "mv" <ws1> <path> <ws1> "to" <ws1> <path>
pMv :: Parser Lib1.Command
pMv = do
  _ <- keyword "mv"
  requireSpaces
  fromP <- pPath
  requireSpaces
  _ <- keyword "to"
  requireSpaces
  toP <- pPath
  pure (Lib1.Mv fromP toP)

-- BNF: <command> ::= "size" [ <ws1> "in" <ws1> <path> ]
pSize :: Parser Lib1.Command
pSize = do
  _ <- keyword "size"
  mpath <- optionalP (requireSpaces *> keyword "in" *> requireSpaces *> pPath)
  pure (Lib1.SizeCmd mpath)

-- BNF: <command> ::= "find" <ws1> <name> [ <ws1> "in" <ws1> <path> ]
pFind :: Parser Lib1.Command
pFind = do
  _ <- keyword "find"
  requireSpaces
  q <- pSeg
  mpath <- optionalP (requireSpaces *> keyword "in" *> requireSpaces *> pPath)
  pure (Lib1.Find q mpath)

-- BNF: <command> ::= "tree" [ <ws1> "in" <ws1> <path> ] [ <ws1> "depth" <ws1> <number> ]
pTree :: Parser Lib1.Command
pTree = do
  _ <- keyword "tree"
  mpath <- optionalP (requireSpaces *> keyword "in" *> requireSpaces *> pPath)
  mdepth <- optionalP (requireSpaces *> keyword "depth" *> requireSpaces *> pNumber)
  pure (Lib1.Tree mpath mdepth)

-- BNF: <command> ::= "show" <ws1> <path>
pShowPath :: Parser Lib1.Command
pShowPath = do
  _ <- keyword "show"
  requireSpaces
  Lib1.ShowPath <$> pPath

pCommand :: Parser Lib1.Command
pCommand =
  pDumpExamples
    `orElseP` pMkDir
    `orElseP` pTouch
    `orElseP` pLs
    `orElseP` pRm
    `orElseP` pMv
    `orElseP` pSize
    `orElseP` pFind
    `orElseP` pTree
    `orElseP` pShowPath

-- | Parses user's input (consumes all input; ignores leading/trailing spaces).
parseCommand :: Parser Lib1.Command
parseCommand = do
  skipSpaces
  cmd <- pCommand
  skipSpaces
  eof
  pure cmd

-- | Parse a full command from a String (helper for server + persistence).
parseCommandString :: String -> Either ErrorMsg Lib1.Command
parseCommandString s =
  case runState (runExceptT parseCommand) s of
    (res, rest) ->
      case res of
        Left e -> Left e
        Right c ->
          if null rest
            then Right c
            else Left "unexpected extra input"

--------------------------------------------------------------------------------
-- QuickCheck: Arbitrary instance for Lib1.Command
--------------------------------------------------------------------------------

genSeg :: Gen String
genSeg = listOf1 (elements (['a' .. 'z'] ++ ['0' .. '9'] ++ "._-"))

genPath :: Gen Path
genPath = do
  n <- frequency [(3, pure 1), (4, pure 2), (3, pure 3)]
  segs <- sequence (replicate n genSeg)
  pure segs

instance Arbitrary Lib1.Command where
  arbitrary :: Gen Lib1.Command
  arbitrary =
    oneof
      [ pure Lib1.DumpExamples,
        Lib1.MkDir <$> genPath,
        Lib1.Touch <$> genPath <*> chooseInteger (0, 10000),
        Lib1.Ls <$> frequency [(2, pure Nothing), (3, Just <$> genPath)],
        Lib1.Rm <$> genPath,
        Lib1.Mv <$> genPath <*> genPath,
        Lib1.SizeCmd <$> frequency [(2, pure Nothing), (3, Just <$> genPath)],
        Lib1.Find <$> genSeg <*> frequency [(2, pure Nothing), (3, Just <$> genPath)],
        Lib1.Tree
          <$> frequency [(2, pure Nothing), (3, Just <$> genPath)]
          <*> frequency [(2, pure Nothing), (3, Just <$> chooseInteger (0, 10))],
        Lib1.ShowPath <$> genPath
      ]

--------------------------------------------------------------------------------
-- Shared domain logic (server + local interpreter)
--------------------------------------------------------------------------------

renderPath :: Path -> String
renderPath = intercalate "/"

ensureDir :: [Path] -> Path -> [Path]
ensureDir existingDirs path =
  nub (existingDirs ++ filter (not . null) (tail (inits path)))

setFile :: [(Path, Integer)] -> (Path, Integer) -> [(Path, Integer)]
setFile existingFiles (filePath, fileSize) =
  (filePath, fileSize) : filter ((/= filePath) . fst) existingFiles

dropUnder :: Path -> [Path] -> [Path]
dropUnder basePath =
  filter (not . (basePath `isPrefixOf`))

dropFilesUnder :: Path -> [(Path, Integer)] -> [(Path, Integer)]
dropFilesUnder basePath =
  filter (not . (basePath `isPrefixOf`) . fst)

renamePrefix :: Path -> Path -> Path -> Maybe Path
renamePrefix fromPrefix toPrefix path
  | fromPrefix `isPrefixOf` path =
      Just (toPrefix ++ drop (length fromPrefix) path)
  | otherwise = Nothing

-- | Pure command execution, returns updated state and output lines.
applyCommand :: Lib3.State -> Lib1.Command -> (Lib3.State, [String])
applyCommand currentState Lib1.DumpExamples =
  (currentState, "Examples:" : map Lib2.toCliCommand Lib1.examples)
applyCommand currentState (Lib1.MkDir dirPath) =
  let dirsWithParents = ensureDir (Lib3.stDirs currentState) dirPath ++ [dirPath]
      normalizedDirs = nub $ sortOn length dirsWithParents
      newState = currentState {Lib3.stDirs = normalizedDirs}
   in (newState, ["mkdir " ++ renderPath dirPath ++ " OK"])
applyCommand currentState (Lib1.Touch filePath fileSize) =
  let parentPath = init filePath
      dirsWithParents =
        ensureDir (Lib3.stDirs currentState) parentPath
          ++ [parentPath | not (null parentPath)]
      updatedFiles = setFile (Lib3.stFiles currentState) (filePath, fileSize)
      newState =
        currentState
          { Lib3.stDirs = nub $ sortOn length dirsWithParents,
            Lib3.stFiles = updatedFiles
          }
   in (newState, ["touch " ++ renderPath filePath ++ " " ++ show fileSize ++ " OK"])
applyCommand currentState (Lib1.Rm pathToRemove) =
  let remainingDirs = dropUnder pathToRemove (Lib3.stDirs currentState)
      remainingFiles = dropFilesUnder pathToRemove (Lib3.stFiles currentState)
      newState = currentState {Lib3.stDirs = remainingDirs, Lib3.stFiles = remainingFiles}
   in (newState, ["rm " ++ renderPath pathToRemove ++ " OK"])
applyCommand currentState (Lib1.Mv fromPath toPath) =
  let moveDir dirPath = maybe dirPath id (renamePrefix fromPath toPath dirPath)
      movedDirs = nub $ sortOn length $ map moveDir (Lib3.stDirs currentState)
      moveFile (fileP, fileSize') =
        maybe (fileP, fileSize') (\newPath -> (newPath, fileSize')) (renamePrefix fromPath toPath fileP)
      movedFiles = map moveFile (Lib3.stFiles currentState)
      newState = currentState {Lib3.stDirs = movedDirs, Lib3.stFiles = movedFiles}
   in (newState, ["mv " ++ renderPath fromPath ++ " to " ++ renderPath toPath ++ " OK"])
applyCommand currentState (Lib1.Ls maybePath) =
  let basePath = maybe [] id maybePath
      dirChildren =
        [ renderPath dirPath
          | dirPath <- Lib3.stDirs currentState,
            basePath `isPrefixOf` dirPath,
            length dirPath == length basePath + 1
        ]
      fileChildren =
        [ renderPath filePath ++ " (" ++ show fileSize' ++ ")"
          | (filePath, fileSize') <- Lib3.stFiles currentState,
            basePath `isPrefixOf` filePath,
            length filePath == length basePath + 1
        ]
      outputLines =
        if null dirChildren && null fileChildren
          then ["(empty)"]
          else dirChildren ++ fileChildren
   in (currentState, outputLines)
applyCommand currentState (Lib1.SizeCmd maybePath) =
  let basePath = maybe [] id maybePath
      totalSize =
        sum
          [ fileSize'
            | (filePath, fileSize') <- Lib3.stFiles currentState,
              basePath `isPrefixOf` filePath
          ]
   in (currentState, ["size: " ++ show totalSize])
applyCommand currentState (Lib1.Find query maybePath) =
  let basePath = maybe [] id maybePath
      tailsList [] = [[]]
      tailsList xs@(_ : rest) = xs : tailsList rest
      isIn needle haystack = needle `isPrefixOf` haystack || any (needle `isPrefixOf`) (tailsList haystack)
      match path =
        basePath `isPrefixOf` path
          && case path of
            [] -> False
            segments -> isIn query (last segments)
      dirHits = [renderPath dirPath | dirPath <- Lib3.stDirs currentState, match dirPath]
      fileHits =
        [ renderPath filePath
          | (filePath, _) <- Lib3.stFiles currentState,
            match filePath
        ]
   in (currentState, dirHits ++ fileHits)
applyCommand currentState (Lib1.Tree maybePath maybeDepth) =
  let basePath = maybe [] id maybePath
      depthOk path =
        case maybeDepth of
          Nothing -> True
          Just maxDepth -> length path - length basePath <= fromIntegral maxDepth
      allEntries =
        [ (dirPath, True)
          | dirPath <- Lib3.stDirs currentState,
            basePath `isPrefixOf` dirPath,
            depthOk dirPath
        ]
          ++ [ (filePath, False)
               | (filePath, _) <- Lib3.stFiles currentState,
                 basePath `isPrefixOf` filePath,
                 depthOk filePath
             ]
      sortedEntries = sortOn fst allEntries
      fmt (path, isDir) =
        replicate (2 * (length path - length basePath - 1)) ' '
          ++ (if isDir then "[D] " else "[F] ")
          ++ renderPath path
      outputLines = if null sortedEntries then ["(empty)"] else map fmt sortedEntries
   in (currentState, outputLines)
applyCommand currentState (Lib1.ShowPath path) =
  let isDirectory = path `elem` Lib3.stDirs currentState
      maybeFile = lookup path (Lib3.stFiles currentState)
      outputLines
        | Just fileSize' <- maybeFile = [renderPath path ++ " (" ++ show fileSize' ++ ")"]
        | isDirectory = [renderPath path ++ "/"]
        | otherwise = [renderPath path ++ " (not found)"]
   in (currentState, outputLines)

-- | Convert state into a replay log of commands (used for persistence).
stateToCommands :: Lib3.State -> [Lib1.Command]
stateToCommands st =
  let dirCmds =
        [ Lib1.MkDir dirPath
          | dirPath <- sortOn length (nub (Lib3.stDirs st)),
            not (null dirPath)
        ]
      fileCmds = [Lib1.Touch p sz | (p, sz) <- Lib3.stFiles st]
   in dirCmds ++ fileCmds

--------------------------------------------------------------------------------
-- Free monad DSL (client side)
--------------------------------------------------------------------------------

data FsOp next
  = DumpExamplesF ([String] -> next)
  | MkDirF Path next
  | TouchF Path Integer next
  | LsF (Maybe Path) ([String] -> next)
  | RmF Path next
  | MvF Path Path next
  | SizeCmdF (Maybe Path) ([String] -> next)
  | FindF String (Maybe Path) ([String] -> next)
  | TreeF (Maybe Path) (Maybe Integer) ([String] -> next)
  | ShowPathF Path ([String] -> next)

instance Functor FsOp where
  fmap f op =
    case op of
      DumpExamplesF k -> DumpExamplesF (f . k)
      MkDirF p n -> MkDirF p (f n)
      TouchF p s n -> TouchF p s (f n)
      LsF mp k -> LsF mp (f . k)
      RmF p n -> RmF p (f n)
      MvF a b n -> MvF a b (f n)
      SizeCmdF mp k -> SizeCmdF mp (f . k)
      FindF q mp k -> FindF q mp (f . k)
      TreeF mp md k -> TreeF mp md (f . k)
      ShowPathF p k -> ShowPathF p (f . k)

type FsDSL a = Free FsOp a

-- DSL "methods" (same parameters as Lib1.Command constructors)
dumpExamples :: FsDSL [String]
dumpExamples = liftF (DumpExamplesF id)

mkdir :: Path -> FsDSL ()
mkdir p = liftF (MkDirF p ())

touch :: Path -> Integer -> FsDSL ()
touch p s = liftF (TouchF p s ())

ls :: Maybe Path -> FsDSL [String]
ls mp = liftF (LsF mp id)

rm :: Path -> FsDSL ()
rm p = liftF (RmF p ())

mv :: Path -> Path -> FsDSL ()
mv a b = liftF (MvF a b ())

sizeCmd :: Maybe Path -> FsDSL [String]
sizeCmd mp = liftF (SizeCmdF mp id)

findCmd :: String -> Maybe Path -> FsDSL [String]
findCmd q mp = liftF (FindF q mp id)

tree :: Maybe Path -> Maybe Integer -> FsDSL [String]
tree mp md = liftF (TreeF mp md id)

showPathCmd :: Path -> FsDSL [String]
showPathCmd p = liftF (ShowPathF p id)

--------------------------------------------------------------------------------
-- Interpreter 1: HTTP (stateless)
--------------------------------------------------------------------------------

type SendCommand m = String -> m String

runDslOverHttp :: Monad m => SendCommand m -> FsDSL a -> m a
runDslOverHttp sendFn = foldFree step
  where
    sendLines cmd = lines <$> sendFn (Lib2.toCliCommand cmd)

    step op =
      case op of
        DumpExamplesF k -> k <$> sendLines Lib1.DumpExamples
        MkDirF p n -> do _ <- sendFn (Lib2.toCliCommand (Lib1.MkDir p)); pure n
        TouchF p s n -> do _ <- sendFn (Lib2.toCliCommand (Lib1.Touch p s)); pure n
        LsF mp k -> k <$> sendLines (Lib1.Ls mp)
        RmF p n -> do _ <- sendFn (Lib2.toCliCommand (Lib1.Rm p)); pure n
        MvF a b n -> do _ <- sendFn (Lib2.toCliCommand (Lib1.Mv a b)); pure n
        SizeCmdF mp k -> k <$> sendLines (Lib1.SizeCmd mp)
        FindF q mp k -> k <$> sendLines (Lib1.Find q mp)
        TreeF mp md k -> k <$> sendLines (Lib1.Tree mp md)
        ShowPathF p k -> k <$> sendLines (Lib1.ShowPath p)

--------------------------------------------------------------------------------
-- Interpreter 2: local State interpreter
--------------------------------------------------------------------------------

interpretLocal :: FsDSL a -> State Lib3.State a
interpretLocal = foldFree step
  where
    runOne :: Lib1.Command -> State Lib3.State [String]
    runOne cmd = do
      st <- get
      let (st', out) = applyCommand st cmd
      put st'
      pure out

    step op =
      case op of
        DumpExamplesF k -> k <$> runOne Lib1.DumpExamples
        MkDirF p n -> do _ <- runOne (Lib1.MkDir p); pure n
        TouchF p s n -> do _ <- runOne (Lib1.Touch p s); pure n
        LsF mp k -> k <$> runOne (Lib1.Ls mp)
        RmF p n -> do _ <- runOne (Lib1.Rm p); pure n
        MvF a b n -> do _ <- runOne (Lib1.Mv a b); pure n
        SizeCmdF mp k -> k <$> runOne (Lib1.SizeCmd mp)
        FindF q mp k -> k <$> runOne (Lib1.Find q mp)
        TreeF mp md k -> k <$> runOne (Lib1.Tree mp md)
        ShowPathF p k -> k <$> runOne (Lib1.ShowPath p)

runDslLocal :: Lib3.State -> FsDSL a -> (a, Lib3.State)
runDslLocal st program = runState (interpretLocal program) st


