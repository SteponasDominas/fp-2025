{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Concurrent (forkIO, threadDelay)
import Control.Concurrent.STM (TVar, atomically, readTVar, writeTVar)
import Control.Concurrent.STM.TVar (newTVarIO, readTVarIO)
import Control.Exception (IOException, finally, try)
import Control.Monad (forever)
import Data.ByteString.Lazy.Char8 qualified as LBS
import Network.HTTP.Types (methodPost, status200, status400)
import Network.Wai (Application, Request (requestMethod), responseLBS, strictRequestBody)
import Network.Wai.Handler.Warp (run)
import System.Environment (lookupEnv)
import System.IO (hPutStrLn, stderr)

import Lib2 qualified
import Lib3 qualified
import Lib4 qualified

defaultPort :: Int
defaultPort = 8080

stateFile :: FilePath
stateFile = "state.txt"

saveEverySeconds :: Int
saveEverySeconds = 5

parseEnvInt :: String -> Maybe Int
parseEnvInt s =
  case reads s of
    [(n, "")] -> Just n
    _ -> Nothing

loadStateFromFile :: FilePath -> IO Lib3.State
loadStateFromFile fp = do
  e <- try (readFile fp) :: IO (Either IOException String)
  case e of
    Left _ -> pure Lib3.emptyState
    Right content -> do
      let nonEmpty = filter (not . null) (lines content)
      case traverse Lib4.parseCommandString nonEmpty of
        Left _err -> pure Lib3.emptyState
        Right cmds ->
          pure $ foldl (\st cmd -> fst (Lib4.applyCommand st cmd)) Lib3.emptyState cmds

saveStateToFile :: FilePath -> Lib3.State -> IO ()
saveStateToFile fp st = do
  let cmds = Lib4.stateToCommands st
      content = unlines (map Lib2.toCliCommand cmds)
  writeFile fp content

mkApp :: TVar Lib3.State -> Application
mkApp stVar req respond = do
  if requestMethod req /= methodPost
    then respond (responseLBS status400 [("Content-Type", "text/plain")] "Only POST is supported\n")
    else do
      body <- strictRequestBody req
      let cmdStr = LBS.unpack body
      hPutStrLn stderr ("SERVER REQ: " ++ show cmdStr)
      case Lib4.parseCommandString cmdStr of
        Left err -> do
          let msg = "PARSE ERROR: " ++ err ++ "\n"
          hPutStrLn stderr ("SERVER RESP: " ++ show msg)
          respond (responseLBS status400 [("Content-Type", "text/plain")] (LBS.pack msg))
        Right cmd -> do
          outLines <- atomically $ do
            st <- readTVar stVar
            let (st', out) = Lib4.applyCommand st cmd
            writeTVar stVar st'
            pure out
          let respText = unlines outLines
          hPutStrLn stderr ("SERVER RESP: " ++ show respText)
          respond (responseLBS status200 [("Content-Type", "text/plain")] (LBS.pack respText))

main :: IO ()
main = do
  port <- maybe defaultPort id . (>>= parseEnvInt) <$> lookupEnv "FP2025_PORT"
  fp <- maybe stateFile id <$> lookupEnv "FP2025_STATE_FILE"
  interval <- maybe saveEverySeconds id . (>>= parseEnvInt) <$> lookupEnv "FP2025_SAVE_SECS"

  initial <- loadStateFromFile fp
  stVar <- newTVarIO initial

  hPutStrLn stderr ("SERVER: starting on port " ++ show port)
  hPutStrLn stderr ("SERVER: state file = " ++ show fp ++ ", autosave every " ++ show interval ++ "s")

  _ <- forkIO $ forever $ do
    threadDelay (interval * 1000000)
    st <- readTVarIO stVar
    hPutStrLn stderr "SERVER: autosave..."
    saveStateToFile fp st

  (run port (mkApp stVar))
    `finally` do
      hPutStrLn stderr "SERVER: shutdown, saving state..."
      st <- readTVarIO stVar
      saveStateToFile fp st


