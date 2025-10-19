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
| `show <path>`                         | `ShowPath [String]`                  |









