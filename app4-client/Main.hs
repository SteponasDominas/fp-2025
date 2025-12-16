{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad.Free (foldFree)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.State.Strict (StateT, get, put, runStateT)
import Data.ByteString.Lazy.Char8 qualified as LBS
import Network.HTTP.Client
  ( Manager,
    Request (method, requestBody, requestHeaders),
    RequestBody (RequestBodyLBS),
    Response (responseBody),
    defaultManagerSettings,
    httpLbs,
    newManager,
    parseRequest
  )
import Network.HTTP.Types.Header (hContentType)
import System.Environment (getArgs)
import System.IO (hPutStrLn, stderr)

import Lib1 qualified
import Lib2 qualified
import Lib3 qualified
import Lib4 qualified

-- | A demo DSL program (no interactive CLI).
demoProgram :: Lib4.FsDSL ()
demoProgram = do
  _ <- Lib4.dumpExamples
  Lib4.mkdir ["home", "user", "docs"]
  Lib4.touch ["home", "user", "docs", "report.txt"] 120
  _ <- Lib4.ls (Just ["home", "user"])
  _ <- Lib4.sizeCmd (Just ["home"])
  _ <- Lib4.findCmd "report" (Just ["home"])
  _ <- Lib4.tree (Just ["home"]) (Just 2)
  _ <- Lib4.showPathCmd ["home", "user", "docs"]
  Lib4.rm ["home", "user", "docs", "report.txt"]
  pure ()

printPlannedDsl :: IO ()
printPlannedDsl = do
  hPutStrLn stderr "CLIENT: executing DSL program:"
  mapM_ (hPutStrLn stderr . (" - " ++)) $
    [ "dump examples",
      "mkdir home/user/docs",
      "touch home/user/docs/report.txt 120",
      "ls home/user",
      "size in home",
      "find report in home",
      "tree in home depth 2",
      "show home/user/docs",
      "rm home/user/docs/report.txt"
    ]

sendHttp :: Manager -> String -> String -> IO String
sendHttp manager url cmd = do
  req0 <- parseRequest url
  let req =
        req0
          { method = "POST",
            requestBody = RequestBodyLBS (LBS.pack cmd),
            requestHeaders = (hContentType, "text/plain") : requestHeaders req0
          }
  hPutStrLn stderr ("CLIENT(HTTP) REQ: " ++ show cmd)
  resp <- httpLbs req manager
  let body = LBS.unpack (responseBody resp)
  hPutStrLn stderr ("CLIENT(HTTP) RESP: " ++ show body)
  pure body

-- | Local interpreter that logs state transitions.
runLocalWithLogs :: Lib4.FsDSL a -> StateT Lib3.State IO a
runLocalWithLogs = foldFree step
  where
    runOne :: Lib1.Command -> StateT Lib3.State IO [String]
    runOne cmd = do
      st <- get
      let (st', out) = Lib4.applyCommand st cmd
      liftIO $ do
        hPutStrLn stderr ("CLIENT(LOCAL) CMD: " ++ Lib2.toCliCommand cmd)
        hPutStrLn stderr ("CLIENT(LOCAL) OUT: " ++ show out)
        hPutStrLn stderr ("CLIENT(LOCAL) STATE: " ++ show st')
      put st'
      pure out

    step op =
      case op of
        Lib4.DumpExamplesF k -> k <$> runOne Lib1.DumpExamples
        Lib4.MkDirF p n -> do _ <- runOne (Lib1.MkDir p); pure n
        Lib4.TouchF p s n -> do _ <- runOne (Lib1.Touch p s); pure n
        Lib4.LsF mp k -> k <$> runOne (Lib1.Ls mp)
        Lib4.RmF p n -> do _ <- runOne (Lib1.Rm p); pure n
        Lib4.MvF a b n -> do _ <- runOne (Lib1.Mv a b); pure n
        Lib4.SizeCmdF mp k -> k <$> runOne (Lib1.SizeCmd mp)
        Lib4.FindF q mp k -> k <$> runOne (Lib1.Find q mp)
        Lib4.TreeF mp md k -> k <$> runOne (Lib1.Tree mp md)
        Lib4.ShowPathF p k -> k <$> runOne (Lib1.ShowPath p)

main :: IO ()
main = do
  args <- getArgs
  printPlannedDsl
  case args of
    ["--http", url] -> do
      manager <- newManager defaultManagerSettings
      _ <- Lib4.runDslOverHttp (sendHttp manager url) demoProgram
      pure ()
    ["--local"] -> do
      _ <- runStateT (runLocalWithLogs demoProgram) Lib3.emptyState
      pure ()
    _ -> do
      hPutStrLn stderr "Usage:"
      hPutStrLn stderr " fp2025-four-client --local"
      hPutStrLn stderr " fp2025-four-client --http http://localhost:8080/"


