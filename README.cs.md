# Hangar

[![CI](https://github.com/richardfaldyna-cell/hangar-launcher/actions/workflows/ci.yml/badge.svg)](https://github.com/richardfaldyna-cell/hangar-launcher/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platform: Windows](https://img.shields.io/badge/platform-Windows-0078D6.svg)
![PowerShell 7](https://img.shields.io/badge/PowerShell-7-5391FE.svg)

> Od „chci dělat na projektu X" k běžícímu `claude` ve správné složce za dvě
> vteřiny. Hangar zná všechny projekty ve tvém workspace, seřadí je podle toho, na
> čem skutečně děláš, a otevře záložku Windows Terminalu s už spuštěným Claude Code.

> 🇬🇧 English: [README.md](README.md)

Osobní nástroj sdílený „jak je", bez záruky a bez podpory. Viz [LICENSE](LICENSE).

![Okno Hangaru](img/hangar-gui.png)

> Obrázky ukazují ukázkový workspace. Obrázek z terminálu je skutečný výstup
> pickeru; obrázky okna jsou vykreslené náhledy WPF rozložení se stejnými daty.

## Požadavky

- Windows 10/11
- [PowerShell 7](https://github.com/PowerShell/PowerShell) (`pwsh`)
- [Windows Terminal](https://github.com/microsoft/terminal) (`wt`)
- [Claude Code](https://claude.com/claude-code) (`claude` v `PATH`)
- Volitelně: VS Code (`code` v `PATH`) pro akci „otevřít v editoru"

---

## Instalace

1. Naklonuj repo, ideálně vedle ostatních projektů:

   ```powershell
   git clone https://github.com/richardfaldyna-cell/hangar-launcher.git hangar
   ```

2. Řekni Hangaru, kde máš projekty, a přidej funkci `hangar` do PowerShell
   profilu (`notepad $PROFILE`):

   ```powershell
   $env:HANGAR_ROOT = "$env:USERPROFILE\code"      # složka, ve které jsou tvoje projekty
   function hangar { & "$env:USERPROFILE\code\hangar\hangar.ps1" @args }
   ```

   Když `HANGAR_ROOT` není nastavená, Hangar indexuje nadřazenou složku svého
   vlastního checkoutu.

3. Volitelně: vytvoř zástupce na ploše (viz [Ikony na ploše](#ikony-na-ploše)).

### Nastavení

| Proměnná prostředí | Význam | Výchozí hodnota |
|---|---|---|
| `HANGAR_ROOT` | kořen workspace, ve kterém se hledají projekty | nadřazená složka checkoutu Hangaru |
| `HANGAR_MACHINE_PREFIX` | krátké označení stroje v adrese Remote Control session (`LAPTOP-mujprojekt`) | `COMPUTERNAME` |

**Projekt** je každá složka až čtyři úrovně pod kořenem, která obsahuje `.git`
nebo `CLAUDE.md`. Kořen sám se počítá taky, pokud je to repo.

Volitelná konvence: projekty pod `business/` a `private/` v kořeni dostanou v okně
vlastní sekce a vlastní barvu záložky (červenou pro `business`, modrou pro
všechno ostatní). Ostatní projekty patří do sekce **OTHER**.

---

## Použití

| Příkaz | Co udělá |
|---|---|
| `hangar` | picker v terminálu (TUI) |
| `hangar ng` | **bez jakéhokoli UI**: rovnou spustí nejlepší shodu pro „ng" |
| `hangar -Gui` | grafické okno |
| `hangar ng -Gui` | okno s předvyplněným filtrem „ng" |
| `hangar -Refresh` | před startem vynutí čerstvý index |
| `hangar ng -DryRun` | jen vypíše, co by se spustilo |

Nejrychlejší cesta je prostřední. Když jméno projektu znáš, žádný seznam
nepotřebuješ: `hangar ng` a Enter.

### Ikony na ploše

```powershell
./install-shortcuts.ps1          # vytvoří zástupce
./install-shortcuts.ps1 -Remove  # zase je smaže
```

Vzniknou dva zástupci, **Hangar** (grafické okno) a **Hangar (terminal)**. Oba
používají `img/hangar.ico`, který se dá kdykoli přegenerovat přes `./make-icon.ps1`,
i v jiné barvě (`-Color '#C0392B'`). Zástupce jde pravým tlačítkem připnout na
hlavní panel.

Grafický zástupce míří na `hangar-gui.vbs`, ne přímo na `pwsh`. PowerShell 7 nemá
bezokenního hostitele, takže i `-WindowStyle Hidden` na okamžik ukáže konzolové
okno. VBS shim ho nevytvoří vůbec.

---

## Grafické okno: `hangar -Gui`

- **Řazení není abecední.** Nahoře je sekce **RECENT**: pět projektů, na kterých
  skutečně děláš (frecency, viz níž). Zbytek je rozdělený do sekcí
  **BUSINESS / PRIVATE / OTHER** podle umístění ve workspace. Tečka vlevo má
  stejnou barvu, jakou dostane záložka terminálu.
- **Řádek = projekt:** velký název, pod ním cesta. Vpravo stáří posledního sezení
  Claude a odznaky stavu (`~změněné soubory`, `⇡ahead`, `⇣behind`,
  `☐úkoly z TODO.md`, `wt:worktrees`).

Psaním se filtruje. Fokus zůstává v hledacím poli a šipky fungují i během psaní.

![Filtr „ng" a detailní panel](img/hangar-gui-filter.png)

- Při hledání se sekce vypnou a **nejlepší shoda je vždy první řádek**, takže
  Enter bez přemýšlení. Přesné jméno vyhrává nad podřetězci („ng" najde projekt
  `ng`, ne `somethi-ng`).
- **Detailní panel vpravo:** větev, počet změn, ahead/behind, otevřené úkoly,
  worktrees, poslední commit (hash, stáří, předmět) a kolik sezení Claude nad
  projektem proběhlo.

### Klávesy v okně

| Klávesa | Akce |
|---|---|
| psaní | filtr (fokus je vždy v hledání) |
| ↑ ↓, PgUp/PgDn | výběr v seznamu |
| **Enter** | `claude` v nové záložce aktuálního okna WT |
| **Shift+Enter** | `claude` v novém okně WT |
| **Ctrl+Enter** | `claude --continue`: naváže na poslední konverzaci |
| **Ctrl+S** | jen shell, bez claude |
| **Ctrl+E** | otevřít ve VS Code |
| **Ctrl+O** | otevřít v Průzkumníku |
| **F5** | obnovit index (běží na pozadí, okno nezamrzne) |
| **Esc** | zavřít |
| dvojklik | totéž co Enter |

---

## Picker v terminálu: `hangar`

Stejná data a stejné akce, jen v konzoli. Hodí se, když už v terminálu jsi.

![TUI picker s filtrem „ng"](img/hangar-tui.png)

Klávesy odpovídají oknu až na dvě výjimky: resume je `Ctrl+R` (ne Ctrl+Enter)
a místo F5 slouží `hangar -Refresh`. Picker běží v alternativním bufferu, takže
**po Esc se vrátí původní obsah terminálu** včetně historie.

Legenda stavových sloupců (platí i pro odznaky v okně):

| Symbol | Význam |
|---|---|
| `~3` | 3 změněné/nekomitnuté soubory |
| `⇡2` | 2 commity ještě nepushnuté (ahead) |
| `⇣1` | 1 commit na serveru navíc (behind) |
| `☐18` | 18 otevřených úkolů (`- [ ]`) v `TODO.md` |
| `wt:1` | 1 aktivní worktree v `.claude/worktrees` |
| `6d` vpravo | poslední terminálové sezení Claude před 6 dny |

---

## Jak funguje řazení (frecency)

Každé spuštění projektu přes Hangar se zapíše do `history.json`. Skóre projektu je
součet vah všech spuštění, kde váha klesá exponenciálně se stářím. **Poločas je
10 dní**, takže spuštění staré 10 dní váží polovinu dnešního. K tomu se přičítá
0,6× váha posledního sezení Claude, aby řazení dávalo smysl i na stroji, kde
historie ještě neexistuje. Výsledek: nahoře je to, na čem děláš teď, a měsíc
netknuté projekty samy klesnou. Nic se nenastavuje.

---

## Data a obnova

| Soubor | Co je | Obnova |
|---|---|---|
| `index.json` | katalog projektů + git stav + sezení | generuje `hangar-index.ps1`. Když je starší než 60 minut, obnoví se **na pozadí** (picker nikdy nečeká na git). Ručně: `F5` / `-Refresh` |
| `history.json` | časy spuštění pro frecency | zapisuje se při každém spuštění projektu |

Oba soubory jsou specifické pro stroj, a proto v `.gitignore`. Každý stroj si
vede vlastní.

---

## Když něco nesedí

- **Záložka má nečekaný font nebo barvy:** Hangar nenašel profil WT. Vzhled se
  dědí z profilu záložky, ve které picker běží (`$env:WT_PROFILE_ID`), mimo WT
  z výchozího profilu. Zkontroluj, že profil v nastavení WT existuje.
- **Údaje v seznamu jsou staré:** index se obnovuje na pozadí a výsledek je vidět
  až při příštím otevření pickeru. V okně stačí `F5`.
- **„VS Code (`code`) is not on PATH":** `Ctrl+E` potřebuje příkaz `code`
  (VS Code → `Shell Command: Install 'code' command in PATH`).
- **Otazníky místo `⇡⇣☐►`:** picker si přepíná výstup na UTF-8 a při ukončení
  kódování vrací. Pokud se přesto objeví, je to chyba, založ prosím issue.
- **Žádné projekty:** zkontroluj `HANGAR_ROOT` a spusť `hangar -Refresh`. Indexační
  skript vypíše, kolik projektů našel.
- **Dvě sezení nad stejným projektem a Remote Control:** druhé sezení se
  nezaregistruje, protože by sdílelo stejnou adresu. Známé omezení.

---

## Soubory v repu

| Soubor | Role |
|---|---|
| `hangar.ps1` | TUI picker + vstupní bod (`-Gui` předá oknu) |
| `hangar-gui.ps1` | grafické okno (WPF) |
| `hangar-core.ps1` | sdílené jádro: index, hledání, frecency, spouštění |
| `hangar-index.ps1` | generátor `index.json` |
| `hangar-launch.ps1` | spustí `claude` v nové záložce (úklid prostředí, `--name`, Remote Control) |
| `hangar-gui.vbs` | bezokenní spouštěč pro zástupce grafického okna |
| `install-shortcuts.ps1` | vytvoří/smaže zástupce na ploše |
| `make-icon.ps1` | nakreslí `img/hangar.ico` |
| `md2html.ps1` | vykreslí Markdown dokument (třeba tento README) do samostatného HTML |
| `tests/` | Pester smoke testy (index, hledání, příkaz ke spuštění), spouští je CI |

## Přispívání

Hlášení chyb a malé pull requesty jsou vítané. Viz [CONTRIBUTING.md](CONTRIBUTING.md)
a [Code of Conduct](CODE_OF_CONDUCT.md). Bezpečnostní problémy hlas soukromě podle
[SECURITY.md](SECURITY.md). Změny jsou v [CHANGELOG.md](CHANGELOG.md).

## Licence

[MIT](LICENSE)
