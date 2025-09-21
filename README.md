# Functional Programming 2025 — Lab 1

## Domain: File System (FS)
**Idėja.** Modeliuojame failų sistemos medį su katalogais ir failais. Tai natūraliai rekursyvus domenas: katalogas turi vaikų sąrašą (katalogus/failus), todėl operacijos kaip `size`, `find`, `tree` pereina visą poskyrį.

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
            | "ls" [<path>]
            | "rm" <path>
            | "mv" <path> "to" <path>
            | "size" [<path>]
            | "find" <pattern> ["in" <path>]
            | "tree" [<path>] ["depth" <nat>]
            | "show" <path>

<path> ::= <name> { "/" <name> }
<name> ::= <identifier>
<identifier> ::= <letter> { <letter> | <digit> | "_" | "-" | "." }
<size> ::= <nat>
<nat> ::= <digit> { <digit> }
<pattern> ::= <string>
<string> ::= '"' { any-char-except-quote } '"'
```
## 4+ komandų pavyzdžiai (rekursija – `size`/`find`/`tree`)
- `mkdir home/user/docs`
- `touch home/user/docs/report.txt 120`
- `find "report" in home`
- `size home`

*Papildomi naudojami projekto testuose: `ls`, `mv`, `rm`, `show`, `tree depth 2`.*

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









