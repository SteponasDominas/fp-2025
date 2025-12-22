# Functional Programming 2025 — Lab 1

## Domain: File System (FS)
**Idėja.** Modeliuojame failų sistemos medį su katalogais ir failais. Tai natūraliai rekursyvus domenas: katalogas turi vaikų sąrašą (katalogus/failus), todėl operacijos kaip `size`, `find`  pereina visą poskyrį.

**Esybės**
- `Dir` — katalogas (`name`, `children`)
- `File` — failas (`name`, `size` baitais)

**Būsena**
- Vienas FS medis. Paprastumo dėlei naudojami **absoliutūs keliai** (`home/user/docs`).

**CRUD komandos**
- `mkdir <path>` — sukuria katalogą
- `touch <path> <size>` — sukuria failą su dydžiu
- `rm <path>` — pašalina failą/katalogą
- `mv <from> to <to>` — perkelia/pervadina
- `ls [<path>]`, `show <path>` — peržiūra

**Naudingos (domeno) komandos**
- `size [<path>]` — **rekursyviai** sumuoja katalogo dydį
- `find "<pattern>" [in <path>]` — **rekursyviai** ieško pavadinimuose
- `tree [<path>] [depth <n>]` — **rekursyvus** atvaizdavimas iki gylio


**Privaloma pagal užduotį**
- `dump examples` — atspausdina pavyzdžines ADT reikšmes (sutampa su žemiau pateiktais pavyzdžiais).

---

## Grammar (BNF)
```bnf
<command> ::= "dump" "examples"
            | "mkdir" <path>
            | "touch" <path> <size>
            | "ls" <path>?
            | "rm" <path>
            | "mv" <path> "to" <path>
            | "size" <path>?
            | "find" <pattern> <in_clause>?
            | "tree" [<path>] ["depth" <nat>]
            | "show" <path>

<path> ::= <name>
         | <name> "/" <path>
<name> ::= <identifier>
<identifier> ::= <letter>
               | <letter> <identifier>
               | <letter> <digit> <identifier>
               | <letter> "_" <identifier>
               | <letter> "-" <identifier>
               | <letter> "." <identifier>
<size> ::= <nat>
<nat> ::= <digit>
        | <digit> <nat>
<pattern> ::= <string>
<string> ::= "\"" <string_content> "\""
<string_content> ::= <any_char_except_quote>
                   | <any_char_except_quote> <string_content>
<in_clause> ::= "in" <path>

<letter> ::= "a" | "b" | "c" | "d" | "e" | "f" | "g" | "h" | "i" | "j" | "k" | "l" | "m" | "n" | "o" | "p" | "q" | "r" | "s" | "t" | "u" | "v" | "w" | "x" | "y" | "z" | "A" | "B" | "C" | "D" | "E" | "F" | "G" | "H" | "I" | "J" | "K" | "L" | "M" | "N" | "O" | "P" | "Q" | "R" | "S" | "T" | "U" | "V" | "W" | "X" | "Y" | "Z"
<digit> ::= "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9"
<any_char_except_quote> ::= <letter> | <digit> | " " | "!" | "#" | "$" | "%" | "&" | "'" | "(" | ")" | "*" | "+" | "," | "-" | "." | "/" | ":" | ";" | "<" | "=" | ">" | "?" | "@" | "[" | "\\" | "]" | "^" | "_" | "`" | "{" | "|" | "}" | "~"
```
## 4+ komandų pavyzdžiai (rekursija – `size`/`find`)
- `mkdir home/user/docs`
- `touch home/user/docs/report.txt 120`
- `find "report" in home`
- `size home`

*Papildomi naudojami projekto testuose: `ls`, `mv`, `rm`, `show`.*

---

## BNF ↔ ADT mapping
| BNF                                   | ADT konstruktorius                   |
|---------------------------------------|--------------------------------------|
| `dump examples`                       | `DumpExamples`                       |
| `mkdir <path>`                        | `MkDir [String]`                     |
| `touch <path> <size>`                 | `Touch [String] Integer`             |
| `ls [<path>]`                         | `Ls (Maybe [String])`                |
| `rm <path>`                           | `Rm [String]`                        |
| `mv <path> to <path>`                 | `Mv [String] [String]`               |
| `size [<path>]`                       | `SizeCmd (Maybe [String])`           |
| `find <pattern> [in <path>]`          | `Find String (Maybe [String])`       |
| `tree [<path>] [depth <nat>]`         | `Tree (Maybe [String]) (Maybe Integer)` |
| `show <path>`                         | `ShowPath [String]`                  |


## State persistence

In this project, the program keeps a `State` that stores all directories and files created during the session.  
The program is persistent: the State is saved when the program exits and restored again when it starts.

### How the State is saved

The State has two parts:

- `stDirs :: [Path]` – list of directory paths  
- `stFiles :: [(Path, Integer)]` – list of files (path + size)

To save the State, I convert it into a list of CLI commands:

- each directory → `mkdir <path>`
- each file → `touch <path> <size>`

There are no other state fields that need to be mapped.  
Commands like `mv`, `rm`, `size`, `show`, `find`, or `tree` do not need to be saved, because their effects are already reflected in the final `stDirs` and `stFiles`.  
For example:

- `mv` is represented by the final file/directory paths  
- `rm` is represented by the fact that the removed paths no longer appear in the State  
- `size`, `find`, `show`, `tree` do not modify the State at all

All generated commands are written into the `state.txt` file.  
When the program starts again, I read this file, parse each line back into a command, and apply them in order to recreate the same State.

---

### Example 1 

**State:**
```
stDirs =
[ ["home"]
, ["home","user"]
]

stFiles =
[ (["home","user","a.txt"], 10) ]
```
**Saved commands:**
```
mkdir home
mkdir home/user
touch home/user/a.txt 10
```
### Example 2

Suppose the user executed these commands:
```
mkdir projects/lab3
touch projects/lab3/notes.txt 50
mkdir tmp
touch tmp/x.txt 5
mv tmp/x.txt to projects/lab3/x.txt
rm tmp
```
The resulting **final State** is:
```
stDirs =
[ ["projects"]
, ["projects","lab3"]
]

stFiles =
[ (["projects","lab3","notes.txt"], 50)
, (["projects","lab3","x.txt"], 5)
]
```
Even though the user used `mv` and `rm`, the saved command list still looks like this:
```
mkdir projects
mkdir projects/lab3
touch projects/lab3/notes.txt 50
touch projects/lab3/x.txt 5
```
Because persistence saves **the final state**, not the command history.

### Screenshots



<img width="1622" height="955" alt="Screenshot 2025-11-24 145317" src="https://github.com/user-attachments/assets/dc03e2fd-cbe9-4047-9213-720701408e06" />

## Client and Server

The server is implemented using the WAI/Warp web framework. It accepts plain text commands via HTTP POST requests, executes the command, and returns the result as plain text in the HTTP response.

### How to run

#### Server

Start the server:

```bash
stack run fp2025-four-server
```

## QuickCheck
<img width="1295" height="932" alt="lab4-quick-check" src="https://github.com/user-attachments/assets/64a2cd8d-6b25-4b42-a70d-281e5f894a60" />


## Client–Server
<img width="1407" height="985" alt="lab4-client-server" src="https://github.com/user-attachments/assets/f93bec50-3e2b-4a74-bfb4-4b993d437a51" />
<img width="1367" height="830" alt="lab4-client-server1" src="https://github.com/user-attachments/assets/3cd6792e-d347-4e6d-bc00-4e673a3dba36" />

## Local
<img width="1905" height="1107" alt="lab4-local" src="https://github.com/user-attachments/assets/da652d8d-66c7-4637-a15a-cc4238652204" />
<img width="1858" height="1109" alt="lab4-local1" src="https://github.com/user-attachments/assets/49140f8c-8451-44b4-bb4f-4bc478f08cc9" />










