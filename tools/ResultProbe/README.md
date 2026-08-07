# ResultProbe — was passiert mit einem nicht zugewiesenen Funktionsergebnis?

Diagnose-Programm für die geplante Regel **SCA196
`ManagedResultNotInitialized`**. Es beantwortet zwei Fragen, die sich am
RTL-Quelltext allein **nicht** klären lassen:

1. **Behält `Result` wirklich den Altwert der Zielvariablen des Aufrufers?**
2. **Wo genau feuert `W1035` (NO_RETVAL) — und wo schweigt der Compiler?**

## Warum das nötig ist

Aus dem RTL-Quelltext von Studio 23.0 ist belegt, dass ein Funktionsergebnis
bestimmter Typen über einen versteckten Zeiger auf **Aufrufer-Speicher**
zurückkommt und beim Eintritt **nicht** geleert wird:

| Beleg | Datei:Zeile |
|---|---|
| `UseResultPointer` — die maßgebliche Typliste | `System.Rtti.pas:2117` |
| `function Unassigned: Variant; begin _VarClear(TVarData(Result)); end;` — der *ganze* Rumpf ist Aufräumen | `System.Variants.pas:6724` |
| `Result := ''; // prevent copying of existing data` | `System.SysUtils.pas:13019` |

Was daraus **nicht** folgt: ob bei `A := F;` tatsächlich `@A` durchgereicht
wird (statt eines Temporärwerts), wie sich das in Schleifen und bei
`for-in` verhält, und wo `W1035` greift. Genau das misst dieses Programm.

## Bedienung

1. `ResultProbe.dpr` in der IDE öffnen (**Datei › Öffnen**). Delphi legt das
   Projekt selbst an — eine `.dproj` liegt bewusst **nicht** dabei, die wäre
   nur eine Fehlerquelle.
2. **Für Win32 und Win64 bauen.** Beide Ausgaben vergleichen: die
   Aufrufkonvention unterscheidet sich, und darum geht es.
3. **Compiler-Meldungen mitschreiben.** Der Abschnitt „W1035-Proben" im
   Quelltext existiert nur dafür. In der IDE: Meldungsfenster ›
   Rechtsklick › *Alles kopieren*.
4. Ausgabe **und** Warnungsliste zurückmelden.

## Worauf zu achten ist

| Probe | Erwartung | Bedeutung, wenn sie eintritt |
|---|---|---|
| **2a** direkt | `[ALT]` | **Die Prämisse trägt.** `@A` wird durchgereicht. |
| 2b Schleife | ab `i=2` steht `[NEU]` | Der praxisrelevante Bug: abgestandener Wert aus dem Vordurchlauf. |
| 2c for-in | `i=2` mit `n>0` | Auch der for-in-Temporärwert wird wiederverwendet. |
| 2d verkettet | `[ALT]` | `Result := G;` reicht den Zeiger durch. |
| 2e über Temp | `<nil>` | **Gegenprobe** — erzwungener Zwischenwert ist genullt. |
| 2f Variant/ShortString/Interface | Altwert bzw. `True` | Die Typmenge geht über „managed" hinaus. |
| 2f record(roh) | offen | Kleiner unverwalteter Record kommt laut `UseResultPointer` im Register — hier ist **kein** Altwert zugesichert. |
| 2g SetLength / var-Param / `Exit;` | `[X]` / `[VIA-VAR]` / `[ALT]` | Die drei Formen, die der Detektor **nicht** melden darf. |

### Bei den Warnungen zählt vor allem

Erwartet wird `W1035` bei `I_Never`, `I_IfOnly`, `RU_Never` — und **kein**
`W1035` bei `A_Never`, `S_Never`, `V_Never`, `If_Never`, `A_IfOnly`.
Genau diese Lücke ist die Existenzberechtigung der Regel: Der Compiler
schweigt dort, wo der Fehler still ist.

Unklar und deshalb interessant: `SS_Never` (ShortString) und `RM_Never`
(Record mit verwaltetem Feld).

## Abbruchkriterium

**Zeigt Probe 2a nicht `[ALT]`, ist die Prämisse der Regel hinfällig.**
Dann bitte zuerst melden — dann wird nichts gebaut.
