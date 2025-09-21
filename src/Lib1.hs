-- src/Lib1.hs
module Lib1
  ( Command(..)
  , Path(..)
  , (</>)
  , p
  , keywords
  , examples
  ) where


data Path = PEnd | PSeg String Path
  deriving (Eq, Show)

infixr 5 </>
(</>) :: String -> Path -> Path
(</>) seg rest = PSeg seg rest

p :: [String] -> Path
p = foldr PSeg PEnd

-- Komandų ADT, atitinkantis README BNF
-- dump examples | mkdir/touch/ls/rm/mv | size/find | tree | show
data Command
  = DumpExamples
  | MkDir Path
  | Touch Path Integer
  | Ls (Maybe Path)
  | Rm Path
  | Mv Path Path
  | SizeCmd (Maybe Path)
  | Find String (Maybe Path)
  | Tree (Maybe Path) (Maybe Integer)
  | ShowPath Path
  deriving (Eq, Show)

-- Raktiniai žodžiai (naudinga testams ir parseriui)
keywords :: [String]
keywords =
  [ "dump","examples"
  , "mkdir","touch","ls","rm","mv","to"
  , "size","find","in","tree","depth","show"
  ]

-- Bent 8–10 pavyzdžių 
examples :: [Command]
examples =
  [ MkDir (p ["home","user","docs"])
  , Touch (p ["home","user","docs","report.txt"]) 120
  , Ls Nothing
  , Ls (Just (p ["home","user"]))
  , SizeCmd (Just (p ["home"]))
  , Find "report" (Just (p ["home"]))
  , Tree (Just (p ["home"])) (Just 2)
  , Mv (p ["home","user","docs","report.txt"]) (p ["home","user","docs","report-old.txt"])
  , ShowPath (p ["home","user","docs"])
  , Rm (p ["home","user","docs","report-old.txt"])
  ]
