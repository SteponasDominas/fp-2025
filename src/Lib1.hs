module Lib1
  ( Command(..)
  , Path
  , keywords
  , examples
  ) where

-- Kelias modeliuojamas kaip segmentų sąrašas
type Path = [String]

-- Komandų ADT, atitinkantis README BNF
data Command
  = DumpExamples
  | MkDir Path
  | Touch Path Integer
  | Ls (Maybe Path)
  | Rm Path
  | Mv Path Path
  | SizeCmd (Maybe Path)
  | Find String (Maybe Path)
  | ShowPath Path
  deriving (Show)

keywords :: [String]
keywords =
  [ "dump","examples"
  , "mkdir","touch","ls","rm","mv","to"
  , "size","find","in","depth","show"
  ]

examples :: [Command]
examples =
  [ MkDir ["home","user","docs"]
  , Touch ["home","user","docs","report.txt"] 120
  , Ls Nothing
  , Ls (Just ["home","user"])
  , SizeCmd (Just ["home"])
  , Find "report" (Just ["home"])
  , Mv ["home","user","docs","report.txt"] ["home","user","docs","report-old.txt"]
  , ShowPath ["home","user","docs"]
  , Rm ["home","user","docs","report-old.txt"]
  ]
