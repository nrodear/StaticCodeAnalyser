program VnpTypeProbe;

{$APPTYPE CONSOLE}

// VarNameProject - Kompilierprobe zu Entscheid E26 (Nico 2026-10-11): die
// Code-Aktion "Lokale Variable einfuehren" soll die Deklaration TYPISIERT
// schreiben ('var MagicNr01: <Typ> := 42;'), damit die Variable zur
// Laufzeit so rechnet, wie der Compiler das Literal zur Kompilierzeit
// gerechnet hat. Entwurf der Typregel (lokales Konzept
// Konzept_Integration_VarNameProject_reDelphix_2026-10-11.md, Abschnitt
// "E26 Entwurf der Typregel"):
//   Ganzzahl    Integer, wenn der Wert in Integer passt UND kein Vorkommen
//               der Zeile Operand einer Rechnung ist (+ - * div mod shl shr
//               and or xor); sonst Int64, oberhalb High(Int64) UInt64.
//   Gleitkomma  Extended (auf Win64 ein Alias fuer Double).
//   Gleiche Literale der Zeile teilen den strengsten Typ.
// FPC kennt keine Inline-Variablen, der Pruefstand kann das nicht klaeren -
// deshalb diese Probe fuer den Delphi-Compiler. Jeder Messpunkt bildet
// GENAU den Code nach, den die Code-Aktion schreibt: die Inline-Variable
// steht direkt vor der Anweisung, keine Hilfsroutine aendert den Typ des
// gemessenen Ausdrucks (Hilfen sehen nur das fertige Ergebnis).
//   P1  Welchen Typ bekommt die heutige untypisierte Form 'var M := ...'?
//   P2  Konstantenfaltung gegen Variable: Ueberlauf, shl, Cardinal,
//       Vorzeichenbit; dazu das Literal neben einer LAUFZEIT-Variablen
//       ('Total := Count * 1000'), wo gar nicht gefaltet wird.
//   P3  Gleitkomma: Bitmuster von 0.1 und 0.1 * 3, direkt und ueber eine
//       Extended-, Double- oder untypisierte Variable; 0.1 neben einer
//       Laufzeit-Double.
//   P4  Ueberladungswahl: Literal gegen Integer-, Int64- und
//       Gleitkomma-Variable, auch (Single, Double) ohne Extended.
//   P5  Kompiliert eine Int64-, UInt64- oder Cardinal-Variable dort, wo
//       Integer erwartet wird (SetLength, Copy, for, Inc, case, in, ...),
//       und welchen Typ erbt eine Inline- oder for-Variable davon?
//   P6  ENTSCHEID E26 (Nico 2026-10-13, nach dem Win32-Lauf von P1-P5):
//       die Aktion schreibt eine Inline-KONSTANTE 'const MagicNr01 = 42;'
//       statt einer Variablen. P6 wiederholt die Faelle von P2, P3 und P4
//       mit genau dieser Form; der Sollwert ist jedes Mal der des
//       gefalteten Originals (P2.9 = 256, P2.33 = 4294967295, P4.9 =
//       ShortInt ...). Wo das Original den Bau abbricht (E2099 in P2.1/6/
//       15/20, P4.3), ist derselbe Fehler die Erwartung - der Schalter
//       steht trotzdem an, damit ein Bau zeigt, ob die Konstante genauso
//       faltet; bricht er dort ab, ist das der Beleg, Schalter aus und
//       weiter. Kompiliert so ein Fall, meldet die Zeile 'ABWEICHUNG'.
//
// Ausgabe: je Messpunkt eine Zeile
//   P<n>.<k> | <Frage> | <beobachtet> | <was der Entwurf vorhersagt>
// auf der Konsole UND in %TEMP%\VarNameProject_TypeProbe.txt (ASCII, wird
// bei jedem Lauf ueberschrieben; ohne TEMP bricht die Probe ab). Die
// Kopfzeilen ('#') nennen Plattform, SizeOf(Extended), CompilerVersion,
// Optimierung und die abgeschalteten Schalter. 'Entwurf' ist die
// Vorhersage des Regel-Entwurfs, nicht der sichere Wert - weicht
// 'beobachtet' ab, ist genau das der Befund. Ausnahme: bei der
// untypisierten Form in P1 nennt die letzte Spalte nur den Typ, den die
// Regel SCHREIBEN wuerde ('heute offen'). Ueber die heutige Ableitung
// sagt der Entwurf nichts voraus; eine Abweichung dort zeigt, wo heutige
// Form und Regel auseinandergehen, und widerlegt den Entwurf nicht.
//
// Bedienung:
//   1. Diese .dpr in der IDE oeffnen (Datei > Oeffnen). Die IDE legt
//      VnpTypeProbe.dproj und VnpTypeProbe.res an - beide werden bewusst
//      nicht eingecheckt (wie bei tools\ResultProbe).
//   2. Win32 bauen. WICHTIG: die Compiler-Meldungen MITSCHREIBEN
//      (Meldungsfenster > Rechtsklick > Alles kopieren). Warnungen und
//      Hinweise sind Ergebnisse, die das Protokoll nicht sehen kann - vor
//      allem W1024 (vorzeichenbehaftet/-los gemischt) in P2 und alles in P5.
//   3. Ausfuehren. Ohne Parameter laeuft die Probe unbeaufsichtigt durch,
//      mit -wait wartet sie am Ende auf Enter. Danach die Datei in
//      VarNameProject_TypeProbe_Win32.txt umbenennen - der naechste Lauf
//      ueberschreibt sie sonst.
//   4. Wenn moeglich Win64 ebenso: bauen, Meldungen kopieren, ausfuehren,
//      Datei in VarNameProject_TypeProbe_Win64.txt umbenennen.
//   5. Protokoll(e) und Meldungen zurueckmelden.
//
// Schalter: jeder Messpunkt mit Kompilierrisiko steht hinter einem eigenen
// $DEFINE (Standard: alle an). Bricht der Bau dort ab, den Schalter
// auskommentieren ('{$DEFINE' wird '{.$DEFINE') und den Fehlertext melden -
// der Fehler selbst ist ein Ergebnis. Meldet der Bau mehrere Fehler, alle
// betroffenen Schalter in EINER Runde abschalten.

// ---- Schalter ---------------------------------------------------------------

// P1: Typname ueber das abgeleitete Typargument (NameOf(V) ohne <T>). Aus:
// P1 zeigt nur SizeOf und Bytes.
{$DEFINE PROBE_P1_INFER}
// P1: Literale am Rand von Int64/UInt64 und mit '_' in Hex.
{$DEFINE PROBE_P1_HEX_SEP}           // var M := $FFFF_FFFF
{$DEFINE PROBE_P1_HEX64}             // var M := $FFFFFFFFFFFFFFFF
{$DEFINE PROBE_P1_UINT64_DEC}        // var M := 18446744073709551615
{$DEFINE PROBE_P1_UINT64_TYPED_HEX}  // var M: UInt64 := $FFFFFFFFFFFFFFFF
{$DEFINE PROBE_P1_UINT64_TYPED_DEC}  // var M: UInt64 := 18446744073709551615
// P2: die Originale (gefaltet). E2099/E1012 hier hiesse: keine 64-Bit-Faltung.
// BEFUND D12 Win32 (Nico 2026-10-11, erster Bau): MUL, DIV, HEX, MAXINT und
// P4 BIGLIT_FOLD -> E2099 "Ueberlauf bei Konvertierung oder arithmetischer
// Operation". Der Compiler faltet Integer-Konstanten in 32 Bit; ein
// Ueberlauf ist ein Baufehler, kein stilles 64-Bit-Ergebnis. Deshalb aus.
{.$DEFINE PROBE_P2_FOLD_MUL}         // R := 100000 * 100000            E2099
{.$DEFINE PROBE_P2_FOLD_DIV}         // I := 100000 * 100000 div 100000 E2099
{$DEFINE PROBE_P2_FOLD_SHL}          // R := 1 shl 40 (kompiliert)
{.$DEFINE PROBE_P2_FOLD_HEX}         // R := $FFFFFFFF + 1              E2099
{.$DEFINE PROBE_P2_FOLD_MAXINT}      // R := 2147483647 + 1             E2099
{$DEFINE PROBE_P2_FOLD_SHL31}        // R := 1 shl 31 (Vorzeichenbit: 64 oder 32 Bit?)
{$DEFINE PROBE_P2_FOLD_SHR_NEG}      // R := (-8) shr 1 (64, 32 oder 8 Bit?)
{$DEFINE PROBE_P2_SHL_VAR}           // M shl 40 und 1 shl M mit Variable
// BEFUND D12 Win32 (zweiter und dritter Bau): 'R := M shl 40' -> E1012
// "Konstantenausdruck verletzt untere Grenzen", untypisiert (P2.10) UND mit
// 'M: Integer' (P2.11): eine konstante Schiebeweite ab 32 bei einem
// 32-Bit-Operanden ist ein Baufehler. dcc32 meldet diese Fehlerart nur
// EINZELN je Bau (P2.11 kam erst, als P2.10 aus war). Das Original
// '1 shl 40' (P2.9) kompiliert.
{.$DEFINE PROBE_P2_SHL_UNTYPED}      // P2.10: var M := 1; R := M shl 40           E1012
{.$DEFINE PROBE_P2_SHL_INTEGER}      // P2.11: var M: Integer := 1; R := M shl 40  E1012
// P4: Ueberladungen.
{.$DEFINE PROBE_P4_BIGLIT_FOLD}      // Ov(100000 * 100000) - E2099 wie PROBE_P2_FOLD_MUL
{$DEFINE PROBE_P4_BIGLIT_DEC}        // Ov(3000000000)
{$DEFINE PROBE_P4_UNTYPED}           // Aufrufe mit untypisierter Variable
{$DEFINE PROBE_P4_SHORTINT_LIT}      // (ShortInt, Integer, Int64) mit 42: E2251?
{$DEFINE PROBE_P4_BYTE_LIT}          // (Byte, Integer) mit 42 und 200: E2251?
{$DEFINE PROBE_P4_BYTE_INT64VAR}     // (Byte, Integer) mit Int64-Variable: E2251?
{$DEFINE PROBE_P4_FLOAT_LIT}         // (Single, Double[, Extended]) mit 3.5 / 0.1
{$DEFINE PROBE_P4_FLOAT_EXT}         // Extended-Ueberladung (nur SizeOf(Extended) >= 10)
{$DEFINE PROBE_P4_SD_LIT_INEXACT}    // (Single, Double) ohne Extended mit 0.1: E2251?
{$DEFINE PROBE_P4_SD_LIT_EXACT}      // (Single, Double) ohne Extended mit 3.5: E2251?
{$DEFINE PROBE_P4_SD_UNTYPED}        // (Single, Double) mit untypisierter Variable: E2251?
{$DEFINE PROBE_P4_SD_EXTVAR}         // (Single, Double) mit Extended-Variable: E2251?
// P5: Int64/UInt64/Cardinal, wo Integer erwartet wird.
{$DEFINE PROBE_P5_SETLENGTH}         // SetLength(A, M + 1)
{$DEFINE PROBE_P5_COPY}              // Copy(S, 1, M - 1)
{$DEFINE PROBE_P5_FOR}               // for I := 0 to M - 1 (I: Integer)
{$DEFINE PROBE_P5_FORVAR}            // for var J := 0 to M - 1
{$DEFINE PROBE_P5_INC}               // Inc(I, M * 2)
{$DEFINE PROBE_P5_STRINGOFCHAR}      // StringOfChar('x', M + 1)
{$DEFINE PROBE_P5_STRINDEX}          // S[Length(S) - M]
{$DEFINE PROBE_P5_ARRINDEX}          // A[M + 1]
{$DEFINE PROBE_P5_MAX}               // Max(I, M - 1)
{$DEFINE PROBE_P5_ASSIGN}            // I := M * 2
{$DEFINE PROBE_P5_UINT64_COPY}       // Copy(S, 1, M - 1), M: UInt64
{$DEFINE PROBE_P5_UINT64_SETLENGTH}  // SetLength(A, M + 1), M: UInt64
{$DEFINE PROBE_P5_CARDINAL_FOR}      // for I := 0 to M - 1, M: Cardinal
{$DEFINE PROBE_P5_CARDINAL_COPY}     // Copy(S, 1, M - 1), M: Cardinal
// P5: Stellen, die Int64 vielleicht nicht annehmen oder weitertragen.
{$DEFINE PROBE_P5_CASE}              // case I mod M of (Selektor <= 32 Bit?)
{$DEFINE PROBE_P5_IN}                // if I + M in [1..5]
{$DEFINE PROBE_P5_FORVAR_START}      // for var J := I - M downto 0 (J: Int64?)
{$DEFINE PROBE_P5_INLINE_PROPAGATE}  // var Last := I - M (Last: Int64?)
// P6: Inline-Konstante (E26) - je Kompilierrisiko ein Schalter, alle an.
// Erwartung bei FOLD_MUL/FOLD_DIV/FOLD_HEX/FOLD_MAXINT/FOLD_MAXINT_RIGHT/
// BIGLIT_FOLD: E2099 wie das Original; bei SHL_LEFT: 256 (E1012 waere der
// Befund "die Konstante rechnet wie eine Variable").
{$DEFINE PROBE_P6_FOLD_MUL}          // const M = 100000; R := M * M            Soll E2099 (P2.1)
{$DEFINE PROBE_P6_FOLD_DIV}          // const M = 100000; I := M * M div M      Soll E2099 (P2.6)
{$DEFINE PROBE_P6_SHL_LEFT}          // const M = 1; R := M shl 40              Soll 256 (P2.9)
{$DEFINE PROBE_P6_SHL_RIGHT}         // const M = 40; R := 1 shl M              Soll 256 (P2.9)
{$DEFINE PROBE_P6_FOLD_HEX}          // const M = $FFFFFFFF; R := M + 1         Soll E2099 (P2.15)
{$DEFINE PROBE_P6_FOLD_MAXINT}       // const M = 2147483647; R := M + 1        Soll E2099 (P2.20)
{$DEFINE PROBE_P6_FOLD_MAXINT_RIGHT} // const M = 1; R := 2147483647 + M        Soll E2099 (P2.20)
{$DEFINE PROBE_P6_BIGLIT_FOLD}       // const M = 100000; Ov(M * M)             Soll E2099 (P4.3)
{$DEFINE PROBE_P6_BIGLIT_DEC}        // const M = 3000000000; Ov(M)             Soll Int64 (P4.4)
{$DEFINE PROBE_P6_SHORTINT}          // (ShortInt, Integer, Int64) mit const 42 Soll ShortInt (P4.9)
{$DEFINE PROBE_P6_BYTE}              // (Byte, Integer) mit const 42 und 200    Soll Byte (P4.14/15)
{$DEFINE PROBE_P6_FLOAT}             // (Single, Double[, Extended]) mit const  Soll Extended (P4.18/19)
{$DEFINE PROBE_P6_SD_INEXACT}        // (Single, Double) mit const 0.1          Soll Double (P4.23)
{$DEFINE PROBE_P6_SD_EXACT}          // (Single, Double) mit const 3.5          Soll Double (P4.24)

// Abgeleitet, NICHT von Hand schalten: auf Win64 ist Extended ein Alias fuer
// Double, eine dritte Ueberladung waere dort E2252 (gleiche Parameter).
{$IFDEF PROBE_P4_FLOAT_EXT}
  {$IF SizeOf(Extended) >= 10}
    {$DEFINE PROBE_EXT_OVERLOAD}
  {$ENDIF}
{$ENDIF}
// Ein Extended-Argument (Variable ODER Gleitkomma-Literal) an OvFloat ohne
// Extended-Ueberladung waere auf Win32 vielleicht mehrdeutig - P4.18 bis
// P4.21 laufen deshalb nur mit Extended-Ueberladung oder auf Win64. Genau
// diesen Fall (Single, Double) ohne Extended misst OvSD (P4.23 bis P4.27)
// hinter eigenen Schaltern.
{$IF Defined(PROBE_EXT_OVERLOAD) or (SizeOf(Extended) < 10)}
  {$DEFINE PROBE_EXT_ARG_CALL}
{$ENDIF}

// Ueberlauf- und Bereichspruefung global AUS (Stand der meisten Projekte);
// P2 schaltet die Ueberlaufpruefung nur um die Routinen ein, die sie messen.
{$Q-}
{$R-}

uses
  System.SysUtils,
  System.TypInfo,
  System.Math;

const
  REPORT_NAME = 'VarNameProject_TypeProbe.txt';
  // Hoechster Code des druckbaren ASCII ('~'); alles darueber wird '?'.
  MAX_PRINTABLE_ASCII = 126;

{$IFDEF WIN64}
  PLATFORM_NAME = 'Win64';
{$ELSE}
  {$IFDEF WIN32}
  PLATFORM_NAME = 'Win32';
  {$ELSE}
  PLATFORM_NAME = 'unbekannt';
  {$ENDIF}
{$ENDIF}

{$IFDEF CPUX64}
  CPU_NAME = 'CPUX64';
{$ELSE}
  {$IFDEF CPUX86}
  CPU_NAME = 'CPUX86';
  {$ELSE}
  CPU_NAME = 'andere CPU';
  {$ENDIF}
{$ENDIF}

{$IFOPT O+}
  OPT_STATE = 'O+ (Optimierung an)';
{$ELSE}
  OPT_STATE = 'O- (Optimierung aus)';
{$ENDIF}

{$IFOPT Q+}
  Q_STATE = 'Q+';
{$ELSE}
  Q_STATE = 'Q-';
{$ENDIF}

{$IFOPT R+}
  R_STATE = 'R+';
{$ELSE}
  R_STATE = 'R-';
{$ENDIF}

{$IFDEF PROBE_EXT_OVERLOAD}
  EXT_OVERLOAD = 'an';
{$ELSE}
  EXT_OVERLOAD = 'aus';
{$ENDIF}

  // Die abgeschalteten Schalter - das Protokoll zeigt so, was fehlt.
  SWITCHES_OFF = ''
{$IFNDEF PROBE_P1_INFER}            + ' PROBE_P1_INFER' {$ENDIF}
{$IFNDEF PROBE_P1_HEX_SEP}          + ' PROBE_P1_HEX_SEP' {$ENDIF}
{$IFNDEF PROBE_P1_HEX64}            + ' PROBE_P1_HEX64' {$ENDIF}
{$IFNDEF PROBE_P1_UINT64_DEC}       + ' PROBE_P1_UINT64_DEC' {$ENDIF}
{$IFNDEF PROBE_P1_UINT64_TYPED_HEX} + ' PROBE_P1_UINT64_TYPED_HEX' {$ENDIF}
{$IFNDEF PROBE_P1_UINT64_TYPED_DEC} + ' PROBE_P1_UINT64_TYPED_DEC' {$ENDIF}
{$IFNDEF PROBE_P2_FOLD_MUL}         + ' PROBE_P2_FOLD_MUL' {$ENDIF}
{$IFNDEF PROBE_P2_FOLD_DIV}         + ' PROBE_P2_FOLD_DIV' {$ENDIF}
{$IFNDEF PROBE_P2_FOLD_SHL}         + ' PROBE_P2_FOLD_SHL' {$ENDIF}
{$IFNDEF PROBE_P2_FOLD_HEX}         + ' PROBE_P2_FOLD_HEX' {$ENDIF}
{$IFNDEF PROBE_P2_FOLD_MAXINT}      + ' PROBE_P2_FOLD_MAXINT' {$ENDIF}
{$IFNDEF PROBE_P2_FOLD_SHL31}       + ' PROBE_P2_FOLD_SHL31' {$ENDIF}
{$IFNDEF PROBE_P2_FOLD_SHR_NEG}     + ' PROBE_P2_FOLD_SHR_NEG' {$ENDIF}
{$IFNDEF PROBE_P2_SHL_VAR}          + ' PROBE_P2_SHL_VAR' {$ENDIF}
{$IFNDEF PROBE_P2_SHL_UNTYPED}      + ' PROBE_P2_SHL_UNTYPED' {$ENDIF}
{$IFNDEF PROBE_P2_SHL_INTEGER}      + ' PROBE_P2_SHL_INTEGER' {$ENDIF}
{$IFNDEF PROBE_P4_BIGLIT_FOLD}      + ' PROBE_P4_BIGLIT_FOLD' {$ENDIF}
{$IFNDEF PROBE_P4_BIGLIT_DEC}       + ' PROBE_P4_BIGLIT_DEC' {$ENDIF}
{$IFNDEF PROBE_P4_UNTYPED}          + ' PROBE_P4_UNTYPED' {$ENDIF}
{$IFNDEF PROBE_P4_SHORTINT_LIT}     + ' PROBE_P4_SHORTINT_LIT' {$ENDIF}
{$IFNDEF PROBE_P4_BYTE_LIT}         + ' PROBE_P4_BYTE_LIT' {$ENDIF}
{$IFNDEF PROBE_P4_BYTE_INT64VAR}    + ' PROBE_P4_BYTE_INT64VAR' {$ENDIF}
{$IFNDEF PROBE_P4_FLOAT_LIT}        + ' PROBE_P4_FLOAT_LIT' {$ENDIF}
{$IFNDEF PROBE_P4_FLOAT_EXT}        + ' PROBE_P4_FLOAT_EXT' {$ENDIF}
{$IFNDEF PROBE_P4_SD_LIT_INEXACT}   + ' PROBE_P4_SD_LIT_INEXACT' {$ENDIF}
{$IFNDEF PROBE_P4_SD_LIT_EXACT}     + ' PROBE_P4_SD_LIT_EXACT' {$ENDIF}
{$IFNDEF PROBE_P4_SD_UNTYPED}       + ' PROBE_P4_SD_UNTYPED' {$ENDIF}
{$IFNDEF PROBE_P4_SD_EXTVAR}        + ' PROBE_P4_SD_EXTVAR' {$ENDIF}
{$IFNDEF PROBE_P5_SETLENGTH}        + ' PROBE_P5_SETLENGTH' {$ENDIF}
{$IFNDEF PROBE_P5_COPY}             + ' PROBE_P5_COPY' {$ENDIF}
{$IFNDEF PROBE_P5_FOR}              + ' PROBE_P5_FOR' {$ENDIF}
{$IFNDEF PROBE_P5_FORVAR}           + ' PROBE_P5_FORVAR' {$ENDIF}
{$IFNDEF PROBE_P5_INC}              + ' PROBE_P5_INC' {$ENDIF}
{$IFNDEF PROBE_P5_STRINGOFCHAR}     + ' PROBE_P5_STRINGOFCHAR' {$ENDIF}
{$IFNDEF PROBE_P5_STRINDEX}         + ' PROBE_P5_STRINDEX' {$ENDIF}
{$IFNDEF PROBE_P5_ARRINDEX}         + ' PROBE_P5_ARRINDEX' {$ENDIF}
{$IFNDEF PROBE_P5_MAX}              + ' PROBE_P5_MAX' {$ENDIF}
{$IFNDEF PROBE_P5_ASSIGN}           + ' PROBE_P5_ASSIGN' {$ENDIF}
{$IFNDEF PROBE_P5_UINT64_COPY}      + ' PROBE_P5_UINT64_COPY' {$ENDIF}
{$IFNDEF PROBE_P5_UINT64_SETLENGTH} + ' PROBE_P5_UINT64_SETLENGTH' {$ENDIF}
{$IFNDEF PROBE_P5_CARDINAL_FOR}     + ' PROBE_P5_CARDINAL_FOR' {$ENDIF}
{$IFNDEF PROBE_P5_CARDINAL_COPY}    + ' PROBE_P5_CARDINAL_COPY' {$ENDIF}
{$IFNDEF PROBE_P5_CASE}             + ' PROBE_P5_CASE' {$ENDIF}
{$IFNDEF PROBE_P5_IN}               + ' PROBE_P5_IN' {$ENDIF}
{$IFNDEF PROBE_P5_FORVAR_START}     + ' PROBE_P5_FORVAR_START' {$ENDIF}
{$IFNDEF PROBE_P5_INLINE_PROPAGATE} + ' PROBE_P5_INLINE_PROPAGATE' {$ENDIF}
{$IFNDEF PROBE_P6_FOLD_MUL}         + ' PROBE_P6_FOLD_MUL' {$ENDIF}
{$IFNDEF PROBE_P6_FOLD_DIV}         + ' PROBE_P6_FOLD_DIV' {$ENDIF}
{$IFNDEF PROBE_P6_SHL_LEFT}         + ' PROBE_P6_SHL_LEFT' {$ENDIF}
{$IFNDEF PROBE_P6_SHL_RIGHT}        + ' PROBE_P6_SHL_RIGHT' {$ENDIF}
{$IFNDEF PROBE_P6_FOLD_HEX}         + ' PROBE_P6_FOLD_HEX' {$ENDIF}
{$IFNDEF PROBE_P6_FOLD_MAXINT}      + ' PROBE_P6_FOLD_MAXINT' {$ENDIF}
{$IFNDEF PROBE_P6_FOLD_MAXINT_RIGHT} + ' PROBE_P6_FOLD_MAXINT_RIGHT' {$ENDIF}
{$IFNDEF PROBE_P6_BIGLIT_FOLD}      + ' PROBE_P6_BIGLIT_FOLD' {$ENDIF}
{$IFNDEF PROBE_P6_BIGLIT_DEC}       + ' PROBE_P6_BIGLIT_DEC' {$ENDIF}
{$IFNDEF PROBE_P6_SHORTINT}         + ' PROBE_P6_SHORTINT' {$ENDIF}
{$IFNDEF PROBE_P6_BYTE}             + ' PROBE_P6_BYTE' {$ENDIF}
{$IFNDEF PROBE_P6_FLOAT}            + ' PROBE_P6_FLOAT' {$ENDIF}
{$IFNDEF PROBE_P6_SD_INEXACT}       + ' PROBE_P6_SD_INEXACT' {$ENDIF}
{$IFNDEF PROBE_P6_SD_EXACT}         + ' PROBE_P6_SD_EXACT' {$ENDIF}
    ;

type
  // Der Typname einer Variablen - T kommt aus dem Argument, so sieht die
  // Probe den Typ, den der Compiler der Inline-Variablen gegeben hat.
  TProbeType = class
  public
{$IFDEF PROBE_P1_INFER}
    class function NameOf<T>(const AValue: T): string; static;
{$ELSE}
    class function NameOf(const AValue): string; static;
{$ENDIF}
  end;

var
  GOut        : TextFile;
  GReportPath : string;

{$IFDEF PROBE_P1_INFER}
class function TProbeType.NameOf<T>(const AValue: T): string;
begin
  Result := GetTypeName(TypeInfo(T));
end;
{$ELSE}
class function TProbeType.NameOf(const AValue): string;
begin
  Result := '(Typname aus, PROBE_P1_INFER)';
end;
{$ENDIF}

// ---- Hilfen (sehen nur fertige Werte, nie den gemessenen Ausdruck) -----------

// Nur druckbares ASCII in Datei und Konsole - Meldungstexte der RTL koennen
// Umlaute tragen.
function AsciiOnly(const AText: string): string;
var
  I : Integer;
begin
  Result := AText;
  for I := 1 to Length(Result) do
    if Ord(Result[I]) > MAX_PRINTABLE_ASCII then
      Result[I] := '?';
end;

// Eine Zeile auf Konsole und in die Datei; Flush, damit ein spaeterer
// Absturz die bisherigen Zeilen nicht mitnimmt.
procedure PutRaw(const AText: string);
var
  Line : string;
begin
  Line := AsciiOnly(AText);
  WriteLn(Line);
  WriteLn(GOut, Line);
  Flush(GOut);
end;

procedure Put(const AId, AQuestion, AObserved, APredicted: string);
begin
  PutRaw(AId + ' | ' + AQuestion + ' | ' + AObserved + ' | ' + APredicted);
end;

// Die ASize Bytes ab ABuf als Hex in Speicherreihenfolge (little-endian).
function HexBytes(const ABuf; ASize: Integer): string;
var
  Bytes : TBytes;
  I     : Integer;
begin
  SetLength(Bytes, ASize);
  Move(ABuf, Bytes[0], ASize);
  Result := '';
  for I := 0 to ASize - 1 do
  begin
    if I > 0 then
      Result := Result + ' ';
    Result := Result + IntToHex(Integer(Bytes[I]), 2);
  end;
end;

// 'Typ <Name>, SizeOf <n>, Bytes <hex>' fuer P1.
function Describe(const ATypeName: string; const ABuf; ASize: Integer): string;
begin
  Result := 'Typ ' + ATypeName + ', SizeOf ' + IntToStr(ASize) + ', Bytes ' +
    HexBytes(ABuf, ASize);
end;

function SameOrDiff(const AHexA, AHexB: string): string;
begin
  if AHexA = AHexB then
    Result := 'gleich'
  else
    Result := 'VERSCHIEDEN';
end;

// Bytes von AValue, die des Originals AOrig und ob sie gleich sind (P3).
function BytesVersus(const AOrig; const AValue; ASize: Integer): string;
var
  HexOrig, HexValue : string;
begin
  HexOrig := HexBytes(AOrig, ASize);
  HexValue := HexBytes(AValue, ASize);
  Result := HexValue + ' (Original ' + HexOrig + ') -> ' +
    SameOrDiff(HexOrig, HexValue);
end;

// Mit -wait gestartet: auf Enter warten, damit die Konsole offen bleibt.
procedure WaitIfAsked;
begin
  if FindCmdLineSwitch('wait', ['-', '/'], True) then
    ReadLn;
end;

// Abbruch vor dem ersten Messpunkt: Meldung, ggf. warten, Exit-Code 1.
procedure AbortRun(const AText: string);
begin
  WriteLn(AsciiOnly(AText));
  WaitIfAsked;
  Halt(1);
end;

// Nur %TEMP% - kein Ausweichen ins Arbeitsverzeichnis (das laege im Repo).
// Ist die Datei gesperrt (z. B. zweiter Lauf gleichzeitig) oder TEMP nicht
// beschreibbar, bricht die Probe mit Meldung ab statt mit EInOutError.
procedure OpenReport;
var
  Dir : string;
begin
  Dir := GetEnvironmentVariable('TEMP');
  if Dir = '' then
    AbortRun('TEMP nicht gesetzt - kein Protokoll moeglich, Abbruch.');
  GReportPath := IncludeTrailingPathDelimiter(Dir) + REPORT_NAME;
  AssignFile(GOut, GReportPath);
  try
    Rewrite(GOut);
  except
    on E: EInOutError do
      AbortRun('Protokoll nicht anlegbar (' + GReportPath + '): ' + E.Message);
  end;
end;

procedure PutHeader;
var
  OffList : string;
begin
  OffList := Trim(SWITCHES_OFF);
  if OffList = '' then
    OffList := 'keine';
  PutRaw('# VnpTypeProbe - Kompilierprobe E26 (typisierte Inline-Variable)');
  PutRaw('# Plattform: ' + PLATFORM_NAME + ' / ' + CPU_NAME);
  PutRaw('# SizeOf(Extended): ' + IntToStr(SizeOf(Extended)));
  PutRaw('# CompilerVersion: ' +
    FloatToStr(CompilerVersion, TFormatSettings.Invariant) +
    ', RTLVersion: ' + FloatToStr(RTLVersion, TFormatSettings.Invariant));
  PutRaw('# Optimierung: ' + OPT_STATE + ', global ' + Q_STATE + ' ' + R_STATE);
  PutRaw('# Extended-Ueberladung in P4: ' + EXT_OVERLOAD);
  PutRaw('# abgeschaltete Schalter: ' + OffList);
  PutRaw('# Datei: ' + GReportPath);
  PutRaw('# Format: Id | Frage | beobachtet | Entwurf');
end;

// ---- P1: Typ der heutigen untypisierten Form ------------------------------
// Jede Routine: genau die Zeile, die die Code-Aktion heute schreibt.

procedure P1Int42;
begin
  var MagicNr01 := 42;
  Put('P1.1', 'var MagicNr01 := 42', Describe(TProbeType.NameOf(MagicNr01),
    MagicNr01, SizeOf(MagicNr01)), 'heute offen; Regel schreibt Integer');
end;

procedure P1Int100000;
begin
  var MagicNr01 := 100000;
  Put('P1.2', 'var MagicNr01 := 100000', Describe(TProbeType.NameOf(MagicNr01),
    MagicNr01, SizeOf(MagicNr01)), 'heute offen; Regel schreibt Integer');
end;

procedure P1IntMax;
begin
  var MagicNr01 := 2147483647;
  Put('P1.3', 'var MagicNr01 := 2147483647', Describe(TProbeType.NameOf(MagicNr01),
    MagicNr01, SizeOf(MagicNr01)), 'heute offen; Regel schreibt Integer');
end;

procedure P1IntMaxPlus1;
begin
  var MagicNr01 := 2147483648;
  Put('P1.4', 'var MagicNr01 := 2147483648', Describe(TProbeType.NameOf(MagicNr01),
    MagicNr01, SizeOf(MagicNr01)), 'heute offen; Regel schreibt Int64');
end;

procedure P1Int3G;
begin
  var MagicNr01 := 3000000000;
  Put('P1.5', 'var MagicNr01 := 3000000000', Describe(TProbeType.NameOf(MagicNr01),
    MagicNr01, SizeOf(MagicNr01)), 'heute offen; Regel schreibt Int64');
end;

procedure P1Hex32;
begin
  var MagicNr01 := $FFFFFFFF;
  Put('P1.6', 'var MagicNr01 := $FFFFFFFF', Describe(TProbeType.NameOf(MagicNr01),
    MagicNr01, SizeOf(MagicNr01)), 'heute offen; Regel schreibt Int64 (Wert 4294967295)');
end;

// Die typisierte Form, die die Regel fuer $FFFFFFFF schreibt.
procedure P1Hex32TypedInt64;
begin
  var MagicNr01: Int64 := $FFFFFFFF;
  Put('P1.7', 'var MagicNr01: Int64 := $FFFFFFFF',
    Describe(TProbeType.NameOf(MagicNr01), MagicNr01, SizeOf(MagicNr01)),
    'Regel schreibt das: Bytes FF FF FF FF 00 00 00 00 (4294967295)');
end;

{$IFDEF PROBE_P1_HEX_SEP}
procedure P1Hex32Sep;
begin
  var MagicNr01 := $FFFF_FFFF;
  Put('P1.8', 'var MagicNr01 := $FFFF_FFFF', Describe(TProbeType.NameOf(MagicNr01),
    MagicNr01, SizeOf(MagicNr01)), 'heute offen; Regel schreibt Int64 (wie P1.6)');
end;
{$ENDIF}

procedure P1Hex63;
begin
  var MagicNr01 := $7FFFFFFFFFFFFFFF;
  Put('P1.9', 'var MagicNr01 := $7FFFFFFFFFFFFFFF',
    Describe(TProbeType.NameOf(MagicNr01), MagicNr01, SizeOf(MagicNr01)) +
    ', > 0: ' + BoolToStr(MagicNr01 > 0, True),
    'heute offen; Regel schreibt Int64');
end;

{$IFDEF PROBE_P1_HEX64}
procedure P1Hex64;
begin
  var MagicNr01 := $FFFFFFFFFFFFFFFF;
  Put('P1.10', 'var MagicNr01 := $FFFFFFFFFFFFFFFF',
    Describe(TProbeType.NameOf(MagicNr01), MagicNr01, SizeOf(MagicNr01)) +
    ', > 0: ' + BoolToStr(MagicNr01 > 0, True),
    'heute offen (> 0 True = UInt64, False = Int64 -1); Regel schreibt UInt64');
end;
{$ENDIF}

{$IFDEF PROBE_P1_UINT64_DEC}
procedure P1UInt64Dec;
begin
  var MagicNr01 := 18446744073709551615;
  Put('P1.11', 'var MagicNr01 := 18446744073709551615',
    Describe(TProbeType.NameOf(MagicNr01), MagicNr01, SizeOf(MagicNr01)) +
    ', > 0: ' + BoolToStr(MagicNr01 > 0, True),
    'heute offen (> 0 True = UInt64, False = Int64 -1); Regel schreibt UInt64');
end;
{$ENDIF}

{$IFDEF PROBE_P1_UINT64_TYPED_HEX}
procedure P1UInt64TypedHex;
begin
  var MagicNr01: UInt64 := $FFFFFFFFFFFFFFFF;
  Put('P1.12', 'var MagicNr01: UInt64 := $FFFFFFFFFFFFFFFF',
    Describe(TProbeType.NameOf(MagicNr01), MagicNr01, SizeOf(MagicNr01)) +
    ', > 0: ' + BoolToStr(MagicNr01 > 0, True),
    'Regel schreibt das: kompiliert, Bytes FF x8, > 0: True');
end;
{$ENDIF}

{$IFDEF PROBE_P1_UINT64_TYPED_DEC}
procedure P1UInt64TypedDec;
begin
  var MagicNr01: UInt64 := 18446744073709551615;
  Put('P1.13', 'var MagicNr01: UInt64 := 18446744073709551615',
    Describe(TProbeType.NameOf(MagicNr01), MagicNr01, SizeOf(MagicNr01)) +
    ', > 0: ' + BoolToStr(MagicNr01 > 0, True),
    'Regel schreibt das: kompiliert, Bytes FF x8, > 0: True');
end;
{$ENDIF}

procedure P1IntSep;
begin
  var MagicNr01 := 1_000_000;
  Put('P1.14', 'var MagicNr01 := 1_000_000', Describe(TProbeType.NameOf(MagicNr01),
    MagicNr01, SizeOf(MagicNr01)), 'heute offen; Regel schreibt Integer');
end;

procedure P1Float35;
begin
  var MagicNr01 := 3.5;
  Put('P1.15', 'var MagicNr01 := 3.5', Describe(TProbeType.NameOf(MagicNr01),
    MagicNr01, SizeOf(MagicNr01)), 'heute offen; Regel schreibt Extended (Win64: Double)');
end;

procedure P1FloatExp;
begin
  var MagicNr01 := 1e-3;
  Put('P1.16', 'var MagicNr01 := 1e-3', Describe(TProbeType.NameOf(MagicNr01),
    MagicNr01, SizeOf(MagicNr01)), 'heute offen; Regel schreibt Extended (Win64: Double)');
end;

procedure P1FloatExpSign;
begin
  var MagicNr01 := 2.5E+10;
  Put('P1.17', 'var MagicNr01 := 2.5E+10', Describe(TProbeType.NameOf(MagicNr01),
    MagicNr01, SizeOf(MagicNr01)), 'heute offen; Regel schreibt Extended (Win64: Double)');
end;

// ---- P2: Konstantenfaltung gegen Variable --------------------------------
// R: Int64 ist das Ziel der Originalzeile; die Variable ersetzt ALLE gleichen
// Literale der Zeile (MagicNr01 * MagicNr01).

{$IFDEF PROBE_P2_FOLD_MUL}
procedure P2MulFold;
var
  R : Int64;
begin
  R := 100000 * 100000;
  Put('P2.1', 'R := 100000 * 100000 (Original, R: Int64)', IntToStr(R),
    'Entwurf: 64-Bit-Faltung = 10000000000');
end;
{$ENDIF}

procedure P2MulUntyped;
var
  R : Int64;
begin
  var MagicNr01 := 100000;
  R := MagicNr01 * MagicNr01;
  Put('P2.2', 'var MagicNr01 := 100000; R := MagicNr01 * MagicNr01', IntToStr(R),
    'Entwurf: heute Integer -> 1410065408 (weicht ab)');
end;

procedure P2MulInteger;
var
  R : Int64;
begin
  var MagicNr01: Integer := 100000;
  R := MagicNr01 * MagicNr01;
  Put('P2.3', 'var MagicNr01: Integer := 100000; R := MagicNr01 * MagicNr01',
    IntToStr(R), 'Entwurf: Integer laeuft ueber -> 1410065408');
end;

{$Q+}
procedure P2MulIntegerChecked;
var
  R   : Int64;
  Obs : string;
begin
  Obs := '';
  var MagicNr01: Integer := 100000;
  try
    R := MagicNr01 * MagicNr01;
    Obs := IntToStr(R);
  except
    on E: Exception do // Absicht: die Ausnahmeklasse ist der Messwert
      Obs := 'Ausnahme ' + E.ClassName;
  end;
  Put('P2.4', 'wie P2.3, mit Ueberlaufpruefung Q+', Obs,
    'Entwurf: Integer laeuft ueber -> EIntOverflow');
end;
{$Q-}

procedure P2MulInt64;
var
  R : Int64;
begin
  var MagicNr01: Int64 := 100000;
  R := MagicNr01 * MagicNr01;
  Put('P2.5', 'var MagicNr01: Int64 := 100000; R := MagicNr01 * MagicNr01',
    IntToStr(R), 'Regel: Int64 (Operand von *) -> 10000000000 = Original');
end;

{$IFDEF PROBE_P2_FOLD_DIV}
procedure P2DivFold;
var
  I : Integer;
begin
  I := 100000 * 100000 div 100000;
  Put('P2.6', 'I := 100000 * 100000 div 100000 (Original, I: Integer)', IntToStr(I),
    'Entwurf: 64-Bit-Faltung = 100000');
end;
{$ENDIF}

procedure P2DivInteger;
var
  I : Integer;
begin
  var MagicNr01: Integer := 100000;
  I := MagicNr01 * MagicNr01 div MagicNr01;
  Put('P2.7', 'var MagicNr01: Integer := 100000; I := MagicNr01 * MagicNr01 div MagicNr01',
    IntToStr(I), 'Entwurf: Integer laeuft ueber -> 14100');
end;

procedure P2DivInt64;
var
  I : Integer;
begin
  var MagicNr01: Int64 := 100000;
  I := MagicNr01 * MagicNr01 div MagicNr01;
  Put('P2.8', 'var MagicNr01: Int64 := 100000; I := MagicNr01 * MagicNr01 div MagicNr01',
    IntToStr(I), 'Regel: Int64 -> 100000 = Original');
end;

{$IFDEF PROBE_P2_FOLD_SHL}
procedure P2ShlFold;
var
  R : Int64;
begin
  R := 1 shl 40;
  Put('P2.9', 'R := 1 shl 40 (Original, R: Int64)', IntToStr(R),
    'Entwurf: 64-Bit-Faltung = 1099511627776');
end;
{$ENDIF}

{$IFDEF PROBE_P2_SHL_VAR}
// Caret auf der 1.
{$IFDEF PROBE_P2_SHL_UNTYPED}
procedure P2ShlLeftUntyped;
var
  R : Int64;
begin
  var MagicNr01 := 1;
  R := MagicNr01 shl 40;
  Put('P2.10', 'var MagicNr01 := 1; R := MagicNr01 shl 40', IntToStr(R),
    'Entwurf: heute Integer -> 256 (40 and 31 = 8)');
end;
{$ENDIF}

{$IFDEF PROBE_P2_SHL_INTEGER}
procedure P2ShlLeftInteger;
var
  R : Int64;
begin
  var MagicNr01: Integer := 1;
  R := MagicNr01 shl 40;
  Put('P2.11', 'var MagicNr01: Integer := 1; R := MagicNr01 shl 40', IntToStr(R),
    'Entwurf: Integer -> 256 (40 and 31 = 8)');
end;
{$ENDIF}

procedure P2ShlLeftInt64;
var
  R : Int64;
begin
  var MagicNr01: Int64 := 1;
  R := MagicNr01 shl 40;
  Put('P2.12', 'var MagicNr01: Int64 := 1; R := MagicNr01 shl 40', IntToStr(R),
    'Regel: Int64 (Operand von shl) -> 1099511627776 = Original');
end;

// Caret auf der 40: die 1 bleibt Konstante.
procedure P2ShlRightInteger;
var
  R : Int64;
begin
  var MagicNr01: Integer := 40;
  R := 1 shl MagicNr01;
  Put('P2.13', 'var MagicNr01: Integer := 40; R := 1 shl MagicNr01', IntToStr(R),
    'Entwurf: Integer -> weicht ab');
end;

procedure P2ShlRightInt64;
var
  R : Int64;
begin
  var MagicNr01: Int64 := 40;
  R := 1 shl MagicNr01;
  Put('P2.14', 'var MagicNr01: Int64 := 40; R := 1 shl MagicNr01', IntToStr(R),
    'Regel: Int64 (Operand von shl) -> 1099511627776 = Original');
end;
{$ENDIF}

{$IFDEF PROBE_P2_FOLD_HEX}
procedure P2HexFold;
var
  R : Int64;
begin
  R := $FFFFFFFF + 1;
  Put('P2.15', 'R := $FFFFFFFF + 1 (Original, R: Int64)', IntToStr(R),
    'Entwurf: 64-Bit-Faltung = 4294967296');
end;
{$ENDIF}

procedure P2HexUntyped;
var
  R : Int64;
begin
  var MagicNr01 := $FFFFFFFF;
  R := MagicNr01 + 1;
  Put('P2.16', 'var MagicNr01 := $FFFFFFFF; R := MagicNr01 + 1', IntToStr(R),
    'Entwurf: haengt am Typ aus P1.6 (Cardinal: 0, Int64: 4294967296)');
end;

procedure P2HexCardinal;
var
  R : Int64;
begin
  var MagicNr01: Cardinal := $FFFFFFFF;
  R := MagicNr01 + 1;
  Put('P2.17', 'var MagicNr01: Cardinal := $FFFFFFFF; R := MagicNr01 + 1', IntToStr(R),
    'Entwurf: Cardinal laeuft ueber -> 0');
end;

{$Q+}
procedure P2HexCardinalChecked;
var
  R   : Int64;
  Obs : string;
begin
  Obs := '';
  var MagicNr01: Cardinal := $FFFFFFFF;
  try
    R := MagicNr01 + 1;
    Obs := IntToStr(R);
  except
    on E: Exception do // Absicht: die Ausnahmeklasse ist der Messwert
      Obs := 'Ausnahme ' + E.ClassName;
  end;
  Put('P2.18', 'wie P2.17, mit Ueberlaufpruefung Q+', Obs,
    'Entwurf: Cardinal laeuft ueber -> EIntOverflow');
end;
{$Q-}

procedure P2HexInt64;
var
  R : Int64;
begin
  var MagicNr01: Int64 := $FFFFFFFF;
  R := MagicNr01 + 1;
  Put('P2.19', 'var MagicNr01: Int64 := $FFFFFFFF; R := MagicNr01 + 1', IntToStr(R),
    'Regel: Int64 -> 4294967296 = Original');
end;

{$IFDEF PROBE_P2_FOLD_MAXINT}
procedure P2MaxIntFold;
var
  R : Int64;
begin
  R := 2147483647 + 1;
  Put('P2.20', 'R := 2147483647 + 1 (Original, R: Int64)', IntToStr(R),
    'Entwurf: 64-Bit-Faltung = 2147483648');
end;
{$ENDIF}

// Caret auf 2147483647.
procedure P2MaxIntUntyped;
var
  R : Int64;
begin
  var MagicNr01 := 2147483647;
  R := MagicNr01 + 1;
  Put('P2.21', 'var MagicNr01 := 2147483647; R := MagicNr01 + 1', IntToStr(R),
    'Entwurf: heute Integer -> -2147483648 (weicht ab)');
end;

procedure P2MaxIntInteger;
var
  R : Int64;
begin
  var MagicNr01: Integer := 2147483647;
  R := MagicNr01 + 1;
  Put('P2.22', 'var MagicNr01: Integer := 2147483647; R := MagicNr01 + 1',
    IntToStr(R), 'Entwurf: Integer laeuft ueber -> -2147483648');
end;

{$Q+}
procedure P2MaxIntIntegerChecked;
var
  R   : Int64;
  Obs : string;
begin
  Obs := '';
  var MagicNr01: Integer := 2147483647;
  try
    R := MagicNr01 + 1;
    Obs := IntToStr(R);
  except
    on E: Exception do // Absicht: die Ausnahmeklasse ist der Messwert
      Obs := 'Ausnahme ' + E.ClassName;
  end;
  Put('P2.23', 'wie P2.22, mit Ueberlaufpruefung Q+', Obs,
    'Entwurf: Integer laeuft ueber -> EIntOverflow');
end;
{$Q-}

procedure P2MaxIntInt64;
var
  R : Int64;
begin
  var MagicNr01: Int64 := 2147483647;
  R := MagicNr01 + 1;
  Put('P2.24', 'var MagicNr01: Int64 := 2147483647; R := MagicNr01 + 1',
    IntToStr(R), 'Regel: Int64 (Operand von +) -> 2147483648 = Original');
end;

// Caret auf der 1: 2147483647 bleibt Konstante.
procedure P2OneInteger;
var
  R : Int64;
begin
  var MagicNr01: Integer := 1;
  R := 2147483647 + MagicNr01;
  Put('P2.25', 'var MagicNr01: Integer := 1; R := 2147483647 + MagicNr01',
    IntToStr(R), 'Entwurf: Integer laeuft ueber -> -2147483648');
end;

procedure P2OneInt64;
var
  R : Int64;
begin
  var MagicNr01: Int64 := 1;
  R := 2147483647 + MagicNr01;
  Put('P2.26', 'var MagicNr01: Int64 := 1; R := 2147483647 + MagicNr01',
    IntToStr(R), 'Regel: Int64 (Operand von +) -> 2147483648 = Original');
end;

// ---- P2: Literal neben einer LAUFZEIT-Variablen ----------------------------
// Der haeufige Fall 'Total := Count * 1000': das Original wird nicht
// gefaltet, sondern zur Laufzeit im Typ des Variablen-Operanden gerechnet.
// N bzw. C ist die Variable des Anwenders, MagicNr01 das eingefuehrte Literal.

procedure P2RunMulOrig;
var
  N : Integer;
  R : Int64;
begin
  N := 100000;
  R := N * 100000;
  Put('P2.27', 'N: Integer = 100000; R := N * 100000 (Original)', IntToStr(R),
    'Referenz: Laufzeit in Integer -> 1410065408');
end;

{$Q+}
procedure P2RunMulOrigChecked;
var
  N   : Integer;
  R   : Int64;
  Obs : string;
begin
  N := 100000;
  try
    R := N * 100000;
    Obs := IntToStr(R);
  except
    on E: Exception do // Absicht: die Ausnahmeklasse ist der Messwert
      Obs := 'Ausnahme ' + E.ClassName;
  end;
  Put('P2.28', 'wie P2.27, mit Ueberlaufpruefung Q+', Obs,
    'Referenz: EIntOverflow');
end;
{$Q-}

procedure P2RunMulInteger;
var
  N : Integer;
  R : Int64;
begin
  N := 100000;
  var MagicNr01: Integer := 100000;
  R := N * MagicNr01;
  Put('P2.29', 'N: Integer = 100000; var MagicNr01: Integer := 100000; R := N * MagicNr01',
    IntToStr(R), 'nicht Regel: Integer -> 1410065408 = Original');
end;

{$Q+}
procedure P2RunMulIntegerChecked;
var
  N   : Integer;
  R   : Int64;
  Obs : string;
begin
  N := 100000;
  var MagicNr01: Integer := 100000;
  try
    R := N * MagicNr01;
    Obs := IntToStr(R);
  except
    on E: Exception do // Absicht: die Ausnahmeklasse ist der Messwert
      Obs := 'Ausnahme ' + E.ClassName;
  end;
  Put('P2.30', 'wie P2.29, mit Ueberlaufpruefung Q+', Obs,
    'nicht Regel: Integer -> EIntOverflow = Original');
end;
{$Q-}

procedure P2RunMulInt64;
var
  N : Integer;
  R : Int64;
begin
  N := 100000;
  var MagicNr01: Int64 := 100000;
  R := N * MagicNr01;
  Put('P2.31', 'N: Integer = 100000; var MagicNr01: Int64 := 100000; R := N * MagicNr01',
    IntToStr(R), 'Regel: Int64 (Operand von *); Entwurf behauptet = Original (1410065408)');
end;

{$Q+}
procedure P2RunMulInt64Checked;
var
  N   : Integer;
  R   : Int64;
  Obs : string;
begin
  N := 100000;
  var MagicNr01: Int64 := 100000;
  try
    R := N * MagicNr01;
    Obs := IntToStr(R);
  except
    on E: Exception do // Absicht: die Ausnahmeklasse ist der Messwert
      Obs := 'Ausnahme ' + E.ClassName;
  end;
  Put('P2.32', 'wie P2.31, mit Ueberlaufpruefung Q+', Obs,
    'Regel: Int64; Entwurf behauptet = Original (EIntOverflow)');
end;
{$Q-}

// Das bekannte 'Count - 1' bei Count = 0 mit Count: Cardinal.
procedure P2RunCardOrig;
var
  C : Cardinal;
  R : Int64;
begin
  C := 0;
  R := C - 1;
  Put('P2.33', 'C: Cardinal = 0; R := C - 1 (Original)', IntToStr(R),
    'Referenz: Laufzeit in Cardinal -> 4294967295');
end;

procedure P2RunCardInteger;
var
  C : Cardinal;
  R : Int64;
begin
  C := 0;
  var MagicNr01: Integer := 1;
  R := C - MagicNr01;
  Put('P2.34', 'C: Cardinal = 0; var MagicNr01: Integer := 1; R := C - MagicNr01',
    IntToStr(R), 'nicht Regel: Integer (W1024?) -> -1');
end;

procedure P2RunCardInt64;
var
  C : Cardinal;
  R : Int64;
begin
  C := 0;
  var MagicNr01: Int64 := 1;
  R := C - MagicNr01;
  Put('P2.35', 'C: Cardinal = 0; var MagicNr01: Int64 := 1; R := C - MagicNr01',
    IntToStr(R), 'Regel: Int64 (Operand von -); Entwurf behauptet = Original (4294967295)');
end;

procedure P2RunCardCardinal;
var
  C : Cardinal;
  R : Int64;
begin
  C := 0;
  var MagicNr01: Cardinal := 1;
  R := C - MagicNr01;
  Put('P2.36', 'C: Cardinal = 0; var MagicNr01: Cardinal := 1; R := C - MagicNr01',
    IntToStr(R), 'nicht Regel: Cardinal -> 4294967295 = Original');
end;

// ---- P2: Faltung ueber das Vorzeichenbit ----------------------------------
// Alle Originale oben liegen ausserhalb von Integer - dort sehen 64-Bit-
// Faltung und '32 Bit, bei Ueberlauf aufweiten' gleich aus. Hier passt das
// Ergebnis als Bitmuster in 32 Bit, aber nicht als vorzeichenbehafteter Wert.

{$IFDEF PROBE_P2_FOLD_SHL31}
procedure P2Shl31Fold;
var
  R : Int64;
begin
  R := 1 shl 31;
  Put('P2.37', 'R := 1 shl 31 (Original, R: Int64)', IntToStr(R),
    'Entwurf: 64-Bit-Faltung = 2147483648 (32 Bit: -2147483648)');
end;
{$ENDIF}

// Caret auf der 1.
procedure P2Shl31Integer;
var
  R : Int64;
begin
  var MagicNr01: Integer := 1;
  R := MagicNr01 shl 31;
  Put('P2.38', 'var MagicNr01: Integer := 1; R := MagicNr01 shl 31', IntToStr(R),
    'nicht Regel: Integer -> -2147483648');
end;

procedure P2Shl31Int64;
var
  R : Int64;
begin
  var MagicNr01: Int64 := 1;
  R := MagicNr01 shl 31;
  Put('P2.39', 'var MagicNr01: Int64 := 1; R := MagicNr01 shl 31', IntToStr(R),
    'Regel: Int64 (Operand von shl) -> 2147483648; Entwurf behauptet = Original');
end;

{$IFDEF PROBE_P2_FOLD_SHR_NEG}
procedure P2ShrNegFold;
var
  R : Int64;
begin
  R := (-8) shr 1;
  Put('P2.40', 'R := (-8) shr 1 (Original, R: Int64)', IntToStr(R),
    'Entwurf: 64-Bit-Faltung = 9223372036854775804 (32 Bit: 2147483644, 8 Bit: 124)');
end;
{$ENDIF}

// Caret auf der 8: das Vorzeichen bleibt Operator (unaeres Minus). Die
// Klammern stehen schon im Original, damit die Probe die Faltungsbreite
// misst und nicht den Vorrang des unaeren Minus gegen shr.
procedure P2ShrNegInteger;
var
  R : Int64;
begin
  var MagicNr01: Integer := 8;
  R := (-MagicNr01) shr 1;
  Put('P2.41', 'var MagicNr01: Integer := 8; R := (-MagicNr01) shr 1', IntToStr(R),
    'nicht Regel: Integer -> 2147483644');
end;

procedure P2ShrNegInt64;
var
  R : Int64;
begin
  var MagicNr01: Int64 := 8;
  R := (-MagicNr01) shr 1;
  Put('P2.42', 'var MagicNr01: Int64 := 8; R := (-MagicNr01) shr 1', IntToStr(R),
    'Regel: Int64 -> 9223372036854775804; Entwurf behauptet = Original');
end;

// ---- P3: Gleitkomma ----------------------------------------------------------
// Jede Routine rechnet das Original (Literal direkt ins Ziel) und die Form
// mit Variable und vergleicht die Bytes.

procedure P3References;
var
  Sgl : Single;
  Dbl : Double;
  Ext : Extended;
begin
  Sgl := 0.1;
  Dbl := 0.1;
  Ext := 0.1;
  Put('P3.1', 'Sgl := 0.1 (Original, Single)', HexBytes(Sgl, SizeOf(Sgl)),
    'Referenz');
  Put('P3.2', 'Dbl := 0.1 (Original, Double)', HexBytes(Dbl, SizeOf(Dbl)),
    'Referenz');
  Put('P3.3', 'Ext := 0.1 (Original, Extended)', HexBytes(Ext, SizeOf(Ext)),
    'Referenz');
end;

procedure P3SingleViaUntyped;
var
  Orig, Sgl : Single;
begin
  Orig := 0.1;
  var MagicNr01 := 0.1;
  Sgl := MagicNr01;
  Put('P3.4', 'var MagicNr01 := 0.1; Sgl := MagicNr01 (Single)',
    BytesVersus(Orig, Sgl, SizeOf(Sgl)), 'Entwurf: heute Extended -> gleich');
end;

procedure P3SingleViaExtended;
var
  Orig, Sgl : Single;
begin
  Orig := 0.1;
  var MagicNr01: Extended := 0.1;
  Sgl := MagicNr01;
  Put('P3.5', 'var MagicNr01: Extended := 0.1; Sgl := MagicNr01 (Single)',
    BytesVersus(Orig, Sgl, SizeOf(Sgl)), 'Regel: Extended -> gleich');
end;

procedure P3SingleViaDouble;
var
  Orig, Sgl : Single;
begin
  Orig := 0.1;
  var MagicNr01: Double := 0.1;
  Sgl := MagicNr01;
  Put('P3.6', 'var MagicNr01: Double := 0.1; Sgl := MagicNr01 (Single)',
    BytesVersus(Orig, Sgl, SizeOf(Sgl)), 'nicht Regel: Double kann abweichen');
end;

procedure P3DoubleViaUntyped;
var
  Orig, Dbl : Double;
begin
  Orig := 0.1;
  var MagicNr01 := 0.1;
  Dbl := MagicNr01;
  Put('P3.7', 'var MagicNr01 := 0.1; Dbl := MagicNr01 (Double)',
    BytesVersus(Orig, Dbl, SizeOf(Dbl)), 'Entwurf: heute Extended -> gleich');
end;

procedure P3DoubleViaExtended;
var
  Orig, Dbl : Double;
begin
  Orig := 0.1;
  var MagicNr01: Extended := 0.1;
  Dbl := MagicNr01;
  Put('P3.8', 'var MagicNr01: Extended := 0.1; Dbl := MagicNr01 (Double)',
    BytesVersus(Orig, Dbl, SizeOf(Dbl)), 'Regel: Extended -> gleich');
end;

procedure P3DoubleViaDouble;
var
  Orig, Dbl : Double;
begin
  Orig := 0.1;
  var MagicNr01: Double := 0.1;
  Dbl := MagicNr01;
  Put('P3.9', 'var MagicNr01: Double := 0.1; Dbl := MagicNr01 (Double)',
    BytesVersus(Orig, Dbl, SizeOf(Dbl)), 'nicht Regel: Double kann abweichen');
end;

procedure P3ExtendedViaUntyped;
var
  Orig, Ext : Extended;
begin
  Orig := 0.1;
  var MagicNr01 := 0.1;
  Ext := MagicNr01;
  Put('P3.10', 'var MagicNr01 := 0.1; Ext := MagicNr01 (Extended)',
    BytesVersus(Orig, Ext, SizeOf(Ext)), 'Entwurf: heute Extended -> gleich');
end;

procedure P3ExtendedViaExtended;
var
  Orig, Ext : Extended;
begin
  Orig := 0.1;
  var MagicNr01: Extended := 0.1;
  Ext := MagicNr01;
  Put('P3.11', 'var MagicNr01: Extended := 0.1; Ext := MagicNr01 (Extended)',
    BytesVersus(Orig, Ext, SizeOf(Ext)), 'Regel: Extended -> gleich');
end;

procedure P3ExtendedViaDouble;
var
  Orig, Ext : Extended;
begin
  Orig := 0.1;
  var MagicNr01: Double := 0.1;
  Ext := MagicNr01;
  Put('P3.12', 'var MagicNr01: Double := 0.1; Ext := MagicNr01 (Extended)',
    BytesVersus(Orig, Ext, SizeOf(Ext)),
    'Entwurf: Double weicht auf Win32 ab (Grund fuer Extended)');
end;

// 0.1 * 3: der Compiler faltet; verglichen mit dem Literal 0.3.
procedure P3MulFold;
var
  Orig, Dbl : Double;
begin
  Orig := 0.3;
  Dbl := 0.1 * 3;
  Put('P3.13', 'Dbl := 0.1 * 3 (Original, gefaltet) gegen Dbl := 0.3',
    BytesVersus(Orig, Dbl, SizeOf(Dbl)), 'Referenz');
end;

// Caret auf 0.1.
procedure P3MulDoubleViaUntyped;
var
  Orig, Dbl : Double;
begin
  Orig := 0.1 * 3;
  var MagicNr01 := 0.1;
  Dbl := MagicNr01 * 3;
  Put('P3.14', 'var MagicNr01 := 0.1; Dbl := MagicNr01 * 3 (Double)',
    BytesVersus(Orig, Dbl, SizeOf(Dbl)), 'Entwurf: heute Extended -> gleich');
end;

procedure P3MulDoubleViaExtended;
var
  Orig, Dbl : Double;
begin
  Orig := 0.1 * 3;
  var MagicNr01: Extended := 0.1;
  Dbl := MagicNr01 * 3;
  Put('P3.15', 'var MagicNr01: Extended := 0.1; Dbl := MagicNr01 * 3 (Double)',
    BytesVersus(Orig, Dbl, SizeOf(Dbl)), 'Regel: Extended -> gleich');
end;

procedure P3MulDoubleViaDouble;
var
  Orig, Dbl : Double;
begin
  Orig := 0.1 * 3;
  var MagicNr01: Double := 0.1;
  Dbl := MagicNr01 * 3;
  Put('P3.16', 'var MagicNr01: Double := 0.1; Dbl := MagicNr01 * 3 (Double)',
    BytesVersus(Orig, Dbl, SizeOf(Dbl)),
    'Entwurf: Double weicht ab (Grund fuer Extended)');
end;

procedure P3MulExtendedViaExtended;
var
  Orig, Ext : Extended;
begin
  Orig := 0.1 * 3;
  var MagicNr01: Extended := 0.1;
  Ext := MagicNr01 * 3;
  Put('P3.17', 'var MagicNr01: Extended := 0.1; Ext := MagicNr01 * 3 (Extended)',
    BytesVersus(Orig, Ext, SizeOf(Ext)), 'Regel: Extended -> gleich');
end;

procedure P3MulExtendedViaDouble;
var
  Orig, Ext : Extended;
begin
  Orig := 0.1 * 3;
  var MagicNr01: Double := 0.1;
  Ext := MagicNr01 * 3;
  Put('P3.18', 'var MagicNr01: Double := 0.1; Ext := MagicNr01 * 3 (Extended)',
    BytesVersus(Orig, Ext, SizeOf(Ext)),
    'Entwurf: Double weicht auf Win32 ab (Grund fuer Extended)');
end;

// Caret auf der 3: 0.1 bleibt Konstante.
procedure P3MulRightInteger;
var
  Orig, Dbl : Double;
begin
  Orig := 0.1 * 3;
  var MagicNr01: Integer := 3;
  Dbl := 0.1 * MagicNr01;
  Put('P3.19', 'var MagicNr01: Integer := 3; Dbl := 0.1 * MagicNr01 (Double)',
    BytesVersus(Orig, Dbl, SizeOf(Dbl)), 'Entwurf: gleich');
end;

procedure P3MulRightInt64;
var
  Orig, Dbl : Double;
begin
  Orig := 0.1 * 3;
  var MagicNr01: Int64 := 3;
  Dbl := 0.1 * MagicNr01;
  Put('P3.20', 'var MagicNr01: Int64 := 3; Dbl := 0.1 * MagicNr01 (Double)',
    BytesVersus(Orig, Dbl, SizeOf(Dbl)), 'Regel: Int64 (Operand von *) -> gleich');
end;

// Caret auf 0.1 neben einer LAUFZEIT-Variablen X: Double = 3 (nicht
// gefaltet). Original: Konstante 0.1 mal Double-Variable.
procedure P3RunOrig;
var
  X, Dbl : Double;
begin
  X := 3;
  Dbl := X * 0.1;
  Put('P3.21', 'X: Double = 3; Dbl := X * 0.1 (Original)', HexBytes(Dbl, SizeOf(Dbl)),
    'Referenz (Win32: 33 .. D3 3F, wenn 0.1 als Extended-Konstante rechnet)');
end;

procedure P3RunViaUntyped;
var
  X, Orig, Dbl : Double;
begin
  X := 3;
  Orig := X * 0.1;
  var MagicNr01 := 0.1;
  Dbl := X * MagicNr01;
  Put('P3.22', 'X: Double = 3; var MagicNr01 := 0.1; Dbl := X * MagicNr01',
    BytesVersus(Orig, Dbl, SizeOf(Dbl)), 'Entwurf: heute Extended -> gleich');
end;

procedure P3RunViaExtended;
var
  X, Orig, Dbl : Double;
begin
  X := 3;
  Orig := X * 0.1;
  var MagicNr01: Extended := 0.1;
  Dbl := X * MagicNr01;
  Put('P3.23', 'X: Double = 3; var MagicNr01: Extended := 0.1; Dbl := X * MagicNr01',
    BytesVersus(Orig, Dbl, SizeOf(Dbl)), 'Regel: Extended -> gleich');
end;

procedure P3RunViaDouble;
var
  X, Orig, Dbl : Double;
begin
  X := 3;
  Orig := X * 0.1;
  var MagicNr01: Double := 0.1;
  Dbl := X * MagicNr01;
  Put('P3.24', 'X: Double = 3; var MagicNr01: Double := 0.1; Dbl := X * MagicNr01',
    BytesVersus(Orig, Dbl, SizeOf(Dbl)),
    'nicht Regel: Double weicht auf Win32 ab (34 .. D3 3F)');
end;

// ---- P4: Ueberladungswahl --------------------------------------------------
// Jede Ueberladung meldet ihren Parametertyp.

function OvIntInt64(AValue: Integer): string; overload;
begin
  Result := 'Integer';
end;

function OvIntInt64(AValue: Int64): string; overload;
begin
  Result := 'Int64';
end;

function OvShort3(AValue: ShortInt): string; overload;
begin
  Result := 'ShortInt';
end;

function OvShort3(AValue: Integer): string; overload;
begin
  Result := 'Integer';
end;

function OvShort3(AValue: Int64): string; overload;
begin
  Result := 'Int64';
end;

function OvByteInt(AValue: Byte): string; overload;
begin
  Result := 'Byte';
end;

function OvByteInt(AValue: Integer): string; overload;
begin
  Result := 'Integer';
end;

function OvFloat(AValue: Single): string; overload;
begin
  Result := 'Single';
end;

function OvFloat(AValue: Double): string; overload;
begin
  Result := 'Double';
end;

{$IFDEF PROBE_EXT_OVERLOAD}
function OvFloat(AValue: Extended): string; overload;
begin
  Result := 'Extended';
end;
{$ENDIF}

// (Single, Double) OHNE Extended - der haeufige Satz in FMX- und Grafikcode.
function OvSD(AValue: Single): string; overload;
begin
  Result := 'Single';
end;

function OvSD(AValue: Double): string; overload;
begin
  Result := 'Double';
end;

// (Integer, Int64) mit Literalen - die Originale.
procedure P4IntInt64Literals;
begin
  Put('P4.1', 'OvIntInt64(42), Ueberladungen (Integer, Int64)', OvIntInt64(42),
    'Entwurf: Integer');
  Put('P4.2', 'OvIntInt64(42 * 2) (Original)', OvIntInt64(42 * 2),
    'Entwurf: Integer');
{$IFDEF PROBE_P4_BIGLIT_FOLD}
  // Faellt aus demselben Grund wie P2.1 (PROBE_P2_FOLD_MUL).
  Put('P4.3', 'OvIntInt64(100000 * 100000) (Original, gefaltet)',
    OvIntInt64(100000 * 100000), 'Entwurf: Int64');
{$ENDIF}
{$IFDEF PROBE_P4_BIGLIT_DEC}
  Put('P4.4', 'OvIntInt64(3000000000)', OvIntInt64(3000000000), 'Entwurf: Int64');
{$ENDIF}
end;

{$IFDEF PROBE_P4_UNTYPED}
procedure P4IntInt64Untyped;
begin
  var MagicNr01 := 42;
  Put('P4.5', 'var MagicNr01 := 42; OvIntInt64(MagicNr01)', OvIntInt64(MagicNr01),
    'Entwurf: heute Integer -> Integer');
end;
{$ENDIF}

procedure P4IntInt64Integer;
begin
  var MagicNr01: Integer := 42;
  Put('P4.6', 'var MagicNr01: Integer := 42; OvIntInt64(MagicNr01)',
    OvIntInt64(MagicNr01), 'Regel (ohne Rechnung): Integer = wie P4.1');
end;

procedure P4IntInt64Int64;
begin
  var MagicNr01: Int64 := 42;
  Put('P4.7', 'var MagicNr01: Int64 := 42; OvIntInt64(MagicNr01)',
    OvIntInt64(MagicNr01), 'nicht Regel: Int64');
end;

// Die Regel gibt 42 hier Int64 (Operand von *): Original P4.2 waehlte Integer.
procedure P4IntInt64Int64Mul;
begin
  var MagicNr01: Int64 := 42;
  Put('P4.8', 'var MagicNr01: Int64 := 42; OvIntInt64(MagicNr01 * 2)',
    OvIntInt64(MagicNr01 * 2), 'Regel: Int64 -> Int64 statt Integer (Grenze)');
end;

{$IFDEF PROBE_P4_SHORTINT_LIT}
procedure P4ShortLiterals;
begin
  Put('P4.9', 'OvShort3(42), Ueberladungen (ShortInt, Integer, Int64)',
    OvShort3(42), 'Grenze: Literal waehlt evtl. ShortInt');
  Put('P4.10', 'OvShort3(42 * 2) (Original)', OvShort3(42 * 2),
    'Grenze: Literal waehlt evtl. ShortInt');
end;
{$ENDIF}

{$IFDEF PROBE_P4_UNTYPED}
procedure P4ShortUntyped;
begin
  var MagicNr01 := 42;
  Put('P4.11', 'var MagicNr01 := 42; OvShort3(MagicNr01)', OvShort3(MagicNr01),
    'Entwurf: heute Integer -> Integer');
end;
{$ENDIF}

procedure P4ShortInteger;
begin
  var MagicNr01: Integer := 42;
  Put('P4.12', 'var MagicNr01: Integer := 42; OvShort3(MagicNr01)',
    OvShort3(MagicNr01), 'Regel: Integer -> Integer (Grenze, wenn P4.9 ShortInt)');
end;

procedure P4ShortInt64;
begin
  var MagicNr01: Int64 := 42;
  Put('P4.13', 'var MagicNr01: Int64 := 42; OvShort3(MagicNr01)',
    OvShort3(MagicNr01), 'Int64');
end;

{$IFDEF PROBE_P4_BYTE_LIT}
procedure P4ByteLiterals;
begin
  Put('P4.14', 'OvByteInt(42), Ueberladungen (Byte, Integer)', OvByteInt(42),
    'Grenze: Literal waehlt evtl. Byte');
  Put('P4.15', 'OvByteInt(200)', OvByteInt(200), 'Grenze: Literal waehlt evtl. Byte');
end;
{$ENDIF}

procedure P4ByteInteger;
begin
  var MagicNr01: Integer := 42;
  Put('P4.16', 'var MagicNr01: Integer := 42; OvByteInt(MagicNr01)',
    OvByteInt(MagicNr01), 'Regel: Integer -> Integer (Grenze, wenn P4.14 Byte)');
end;

{$IFDEF PROBE_P4_BYTE_INT64VAR}
procedure P4ByteInt64;
begin
  var MagicNr01: Int64 := 42;
  Put('P4.17', 'var MagicNr01: Int64 := 42; OvByteInt(MagicNr01)',
    OvByteInt(MagicNr01), 'Grenze: E2251 oder Integer');
end;
{$ENDIF}

{$IFDEF PROBE_P4_FLOAT_LIT}
{$IFDEF PROBE_EXT_ARG_CALL}
procedure P4FloatLiterals;
begin
  Put('P4.18', 'OvFloat(3.5), Ueberladungen (Single, Double[, Extended])',
    OvFloat(3.5), 'Entwurf: Extended (Win64: Double)');
  Put('P4.19', 'OvFloat(0.1)', OvFloat(0.1), 'Entwurf: Extended (Win64: Double)');
end;
{$ENDIF}
{$ENDIF}

{$IFDEF PROBE_P4_UNTYPED}
{$IFDEF PROBE_EXT_ARG_CALL}
procedure P4FloatUntyped;
begin
  var MagicNr01 := 3.5;
  Put('P4.20', 'var MagicNr01 := 3.5; OvFloat(MagicNr01)', OvFloat(MagicNr01),
    'Entwurf: heute Extended -> Extended (Win64: Double)');
end;
{$ENDIF}
{$ENDIF}

{$IFDEF PROBE_EXT_ARG_CALL}
procedure P4FloatExtended;
begin
  var MagicNr01: Extended := 3.5;
  Put('P4.21', 'var MagicNr01: Extended := 3.5; OvFloat(MagicNr01)',
    OvFloat(MagicNr01), 'Regel: Extended -> wie P4.18');
end;
{$ENDIF}

procedure P4FloatDouble;
begin
  var MagicNr01: Double := 3.5;
  Put('P4.22', 'var MagicNr01: Double := 3.5; OvFloat(MagicNr01)',
    OvFloat(MagicNr01), 'nicht Regel: Double');
end;

// (Single, Double) ohne Extended: was waehlt das Literal, und kompiliert die
// Extended-Variable, die die Regel schreibt? Auf Win32 ist E2251 denkbar.
// Je ein Schalter: 0.1 und 3.5 koennen verschieden ausgehen.
{$IFDEF PROBE_P4_SD_LIT_INEXACT}
procedure P4SDLiteralInexact;
begin
  Put('P4.23', 'OvSD(0.1), Ueberladungen (Single, Double)', OvSD(0.1),
    'Grenze: Double oder E2251 (0.1 ist nicht exakt)');
end;
{$ENDIF}

{$IFDEF PROBE_P4_SD_LIT_EXACT}
procedure P4SDLiteralExact;
begin
  Put('P4.24', 'OvSD(3.5)', OvSD(3.5),
    'Grenze: Single, Double oder E2251 (3.5 ist exakt als Single)');
end;
{$ENDIF}

{$IFDEF PROBE_P4_SD_UNTYPED}
procedure P4SDUntyped;
begin
  var MagicNr01 := 0.1;
  Put('P4.25', 'var MagicNr01 := 0.1; OvSD(MagicNr01)', OvSD(MagicNr01),
    'Entwurf: heute Extended -> Win32 E2251 denkbar, Win64 Double');
end;
{$ENDIF}

{$IFDEF PROBE_P4_SD_EXTVAR}
procedure P4SDExtended;
begin
  var MagicNr01: Extended := 0.1;
  Put('P4.26', 'var MagicNr01: Extended := 0.1; OvSD(MagicNr01)', OvSD(MagicNr01),
    'Regel: Extended -> Win32 E2251 denkbar, Win64 Double');
end;
{$ENDIF}

procedure P4SDDouble;
begin
  var MagicNr01: Double := 0.1;
  Put('P4.27', 'var MagicNr01: Double := 0.1; OvSD(MagicNr01)', OvSD(MagicNr01),
    'nicht Regel: Double');
end;

// ---- P5: Int64/UInt64/Cardinal, wo Integer erwartet wird -----------------
// Die Regel gibt Int64 nur einem Literal, das Operand einer Rechnung ist -
// deshalb steht jede Variable hier in einer Rechnung.

{$IFDEF PROBE_P5_SETLENGTH}
procedure P5SetLength;
var
  A : TArray<Integer>;
begin
  var MagicNr01: Int64 := 3;
  SetLength(A, MagicNr01 + 1);
  Put('P5.1', 'var MagicNr01: Int64 := 3; SetLength(A, MagicNr01 + 1)',
    'kompiliert, Length(A) = ' + IntToStr(Length(A)), 'Entwurf: kompiliert, 4');
end;
{$ENDIF}

{$IFDEF PROBE_P5_COPY}
procedure P5Copy;
var
  S : string;
begin
  var MagicNr01: Int64 := 3;
  S := Copy('abcdef', 1, MagicNr01 - 1);
  Put('P5.2', 'var MagicNr01: Int64 := 3; S := Copy(''abcdef'', 1, MagicNr01 - 1)',
    'kompiliert, S = ''' + S + '''', 'Entwurf: kompiliert, ''ab''');
end;
{$ENDIF}

{$IFDEF PROBE_P5_FOR}
procedure P5For;
var
  I, Runs : Integer;
begin
  Runs := 0;
  var MagicNr01: Int64 := 3;
  for I := 0 to MagicNr01 - 1 do
    Inc(Runs);
  Put('P5.3', 'var MagicNr01: Int64 := 3; for I := 0 to MagicNr01 - 1 (I: Integer)',
    'kompiliert, ' + IntToStr(Runs) + ' Durchlaeufe', 'Entwurf: kompiliert, 3');
end;
{$ENDIF}

{$IFDEF PROBE_P5_FORVAR}
procedure P5ForVar;
var
  Runs     : Integer;
  ByteSize : Integer;
  TypeText : string;
begin
  Runs := 0;
  ByteSize := 0;
  TypeText := '';
  var MagicNr01: Int64 := 3;
  for var J := 0 to MagicNr01 - 1 do
  begin
    Inc(Runs);
    ByteSize := SizeOf(J);
    TypeText := TProbeType.NameOf(J);
  end;
  Put('P5.4', 'var MagicNr01: Int64 := 3; for var J := 0 to MagicNr01 - 1',
    'kompiliert, ' + IntToStr(Runs) + ' Durchlaeufe, J: Typ ' + TypeText +
    ', SizeOf ' + IntToStr(ByteSize), 'Entwurf: kompiliert, 3');
end;
{$ENDIF}

{$IFDEF PROBE_P5_INC}
procedure P5Inc;
var
  I : Integer;
begin
  I := 10;
  var MagicNr01: Int64 := 3;
  Inc(I, MagicNr01 * 2);
  Put('P5.5', 'I := 10; var MagicNr01: Int64 := 3; Inc(I, MagicNr01 * 2)',
    'kompiliert, I = ' + IntToStr(I), 'Entwurf: kompiliert, 16');
end;
{$ENDIF}

{$IFDEF PROBE_P5_STRINGOFCHAR}
procedure P5StringOfChar;
var
  S : string;
begin
  var MagicNr01: Int64 := 3;
  S := StringOfChar('x', MagicNr01 + 1);
  Put('P5.6', 'var MagicNr01: Int64 := 3; S := StringOfChar(''x'', MagicNr01 + 1)',
    'kompiliert, S = ''' + S + '''', 'Entwurf: kompiliert, ''xxxx''');
end;
{$ENDIF}

{$IFDEF PROBE_P5_STRINDEX}
procedure P5StrIndex;
var
  S : string;
  C : Char;
begin
  S := 'abcdef';
  var MagicNr01: Int64 := 3;
  C := S[Length(S) - MagicNr01];
  Put('P5.7', 'S := ''abcdef''; var MagicNr01: Int64 := 3; C := S[Length(S) - MagicNr01]',
    'kompiliert, C = ''' + C + '''', 'Entwurf: kompiliert, ''c''');
end;
{$ENDIF}

{$IFDEF PROBE_P5_ARRINDEX}
procedure P5ArrIndex;
var
  A : TArray<Integer>;
  V : Integer;
begin
  A := [10, 20, 30];
  var MagicNr01: Int64 := 1;
  V := A[MagicNr01 + 1];
  Put('P5.8', 'A := [10, 20, 30]; var MagicNr01: Int64 := 1; V := A[MagicNr01 + 1]',
    'kompiliert, V = ' + IntToStr(V), 'Entwurf: kompiliert, 30');
end;
{$ENDIF}

{$IFDEF PROBE_P5_MAX}
procedure P5Max;
var
  I : Integer;
begin
  I := 5;
  var MagicNr01: Int64 := 3;
  I := Max(I, MagicNr01 - 1);
  Put('P5.9', 'I := 5; var MagicNr01: Int64 := 3; I := Max(I, MagicNr01 - 1)',
    'kompiliert, I = ' + IntToStr(I), 'Entwurf: kompiliert, 5');
end;
{$ENDIF}

{$IFDEF PROBE_P5_ASSIGN}
procedure P5Assign;
var
  I : Integer;
begin
  var MagicNr01: Int64 := 3;
  I := MagicNr01 * 2;
  Put('P5.10', 'var MagicNr01: Int64 := 3; I := MagicNr01 * 2 (I: Integer)',
    'kompiliert, I = ' + IntToStr(I), 'Entwurf: kompiliert, 6');
end;
{$ENDIF}

{$IFDEF PROBE_P5_UINT64_COPY}
procedure P5UInt64Copy;
var
  S : string;
begin
  var MagicNr01: UInt64 := 3;
  S := Copy('abcdef', 1, MagicNr01 - 1);
  Put('P5.11', 'var MagicNr01: UInt64 := 3; S := Copy(''abcdef'', 1, MagicNr01 - 1)',
    'kompiliert, S = ''' + S + '''', 'Entwurf: kompiliert, ''ab''');
end;
{$ENDIF}

{$IFDEF PROBE_P5_UINT64_SETLENGTH}
procedure P5UInt64SetLength;
var
  A : TArray<Integer>;
begin
  var MagicNr01: UInt64 := 3;
  SetLength(A, MagicNr01 + 1);
  Put('P5.12', 'var MagicNr01: UInt64 := 3; SetLength(A, MagicNr01 + 1)',
    'kompiliert, Length(A) = ' + IntToStr(Length(A)), 'Entwurf: kompiliert, 4');
end;
{$ENDIF}

{$IFDEF PROBE_P5_CARDINAL_FOR}
procedure P5CardinalFor;
var
  I, Runs : Integer;
begin
  Runs := 0;
  var MagicNr01: Cardinal := 3;
  for I := 0 to MagicNr01 - 1 do
    Inc(Runs);
  Put('P5.13', 'var MagicNr01: Cardinal := 3; for I := 0 to MagicNr01 - 1 (I: Integer)',
    'kompiliert, ' + IntToStr(Runs) + ' Durchlaeufe', 'Entwurf: kompiliert, 3');
end;
{$ENDIF}

{$IFDEF PROBE_P5_CARDINAL_COPY}
procedure P5CardinalCopy;
var
  S : string;
begin
  var MagicNr01: Cardinal := 3;
  S := Copy('abcdef', 1, MagicNr01 - 1);
  Put('P5.14', 'var MagicNr01: Cardinal := 3; S := Copy(''abcdef'', 1, MagicNr01 - 1)',
    'kompiliert, S = ''' + S + '''', 'Entwurf: kompiliert, ''ab''');
end;
{$ENDIF}

// ---- P5: Stellen, die Int64 vielleicht NICHT annehmen oder weitertragen ----
// Original jeweils mit dem Literal 3 (case I mod 3, I + 3 in [..], I - 3);
// die Regel gibt der 3 Int64, weil sie Operand einer Rechnung ist.

{$IFDEF PROBE_P5_CASE}
// DocWiki: der case-Selektor ist ein Ordinalausdruck bis 32 Bit.
procedure P5Case;
var
  I   : Integer;
  Hit : string;
begin
  I := 7;
  var MagicNr01: Int64 := 3;
  case I mod MagicNr01 of
    0: Hit := 'Zweig 0';
    1: Hit := 'Zweig 1';
  else
    Hit := 'else';
  end;
  Put('P5.15', 'I := 7; var MagicNr01: Int64 := 3; case I mod MagicNr01 of 0, 1, else',
    'kompiliert, ' + Hit, 'Entwurf: kompiliert, Zweig 1 (Fehler denkbar)');
end;
{$ENDIF}

{$IFDEF PROBE_P5_IN}
procedure P5In;
var
  I   : Integer;
  Hit : string;
begin
  I := 1;
  Hit := 'nicht drin';
  var MagicNr01: Int64 := 3;
  if I + MagicNr01 in [1..5] then
    Hit := 'drin';
  Put('P5.16', 'I := 1; var MagicNr01: Int64 := 3; if I + MagicNr01 in [1..5]',
    'kompiliert, ' + Hit, 'Entwurf: kompiliert, drin (Fehler denkbar)');
end;
{$ENDIF}

{$IFDEF PROBE_P5_FORVAR_START}
// Anders als P5.4 kommt der Startwert hier aus der Rechnung mit M.
procedure P5ForVarStart;
var
  I        : Integer;
  Runs     : Integer;
  ByteSize : Integer;
  TypeText : string;
begin
  I := 5;
  Runs := 0;
  ByteSize := 0;
  TypeText := '';
  var MagicNr01: Int64 := 3;
  for var J := I - MagicNr01 downto 0 do
  begin
    Inc(Runs);
    ByteSize := SizeOf(J);
    TypeText := TProbeType.NameOf(J);
  end;
  Put('P5.17', 'I := 5; var MagicNr01: Int64 := 3; for var J := I - MagicNr01 downto 0',
    'kompiliert, ' + IntToStr(Runs) + ' Durchlaeufe, J: Typ ' + TypeText +
    ', SizeOf ' + IntToStr(ByteSize),
    'Entwurf: 3 Durchlaeufe; J Int64 (SizeOf 8) oder Fehler (Int64-Zaehler?)');
end;
{$ENDIF}

{$IFDEF PROBE_P5_INLINE_PROPAGATE}
// Ein Aufruf mit 'var X: Integer' (z. B. TryStrToInt(S, Last)) fehlt
// bewusst: ist Last Int64, ist E2033 Sprachregel (var-Parameter brauchen
// identische Typen) und kostete nur eine Bau-Runde. Der Typ von Last ist
// die offene Frage.
procedure P5InlinePropagate;
var
  I : Integer;
begin
  I := 5;
  var MagicNr01: Int64 := 3;
  var Last := I - MagicNr01;
  Put('P5.18', 'I := 5; var MagicNr01: Int64 := 3; var Last := I - MagicNr01',
    'kompiliert, Last: Typ ' + TProbeType.NameOf(Last) + ', SizeOf ' +
    IntToStr(SizeOf(Last)) + ', Wert ' + IntToStr(Last),
    'Entwurf: Last Int64 (SizeOf 8) -> ein spaeteres var-Integer-Argument waere E2033');
end;
{$ENDIF}

// ---- P6: Inline-Konstante (E26) gegen das gefaltete Original ---------------
// Jede Routine schreibt GENAU die Zeile der Code-Aktion seit E26
// ('const MagicNr01 = <Literal>;') direkt vor die Anweisung. Die letzte
// Spalte nennt den Sollwert: das Ergebnis des gefalteten Originals aus P2,
// P3 bzw. P4 (Win32-Lauf 2026-10-13); 'gleich'/'VERSCHIEDEN' bzw. ein
// anderer Wert ist der Befund.

// Soll aus AObserved gegen ASoll: dieselbe Zeile wie Put, mit Urteil.
procedure PutSoll(const AId, AQuestion, AObserved, ASoll: string);
var
  Urteil : string;
begin
  if AObserved = ASoll then
    Urteil := 'gleich'
  else
    Urteil := 'ABWEICHUNG';
  Put(AId, AQuestion, AObserved, 'Soll (Original): ' + ASoll + ' -> ' + Urteil);
end;

{$IFDEF PROBE_P6_FOLD_MUL}
procedure P6MulFold;
var
  R : Int64;
begin
  const MagicNr01 = 100000;
  R := MagicNr01 * MagicNr01;
  Put('P6.1', 'const MagicNr01 = 100000; R := MagicNr01 * MagicNr01', IntToStr(R),
    'Soll (Original P2.1): E2099 - kompiliert, also ABWEICHUNG');
end;
{$ENDIF}

{$IFDEF PROBE_P6_FOLD_DIV}
procedure P6DivFold;
var
  I : Integer;
begin
  const MagicNr01 = 100000;
  I := MagicNr01 * MagicNr01 div MagicNr01;
  Put('P6.2', 'const MagicNr01 = 100000; I := MagicNr01 * MagicNr01 div MagicNr01',
    IntToStr(I), 'Soll (Original P2.6): E2099 - kompiliert, also ABWEICHUNG');
end;
{$ENDIF}

{$IFDEF PROBE_P6_SHL_LEFT}
// Caret auf der 1 (P2.9: das Original faltet in 32 Bit, 40 and 31 = 8).
procedure P6ShlLeft;
var
  R : Int64;
begin
  const MagicNr01 = 1;
  R := MagicNr01 shl 40;
  PutSoll('P6.3', 'const MagicNr01 = 1; R := MagicNr01 shl 40', IntToStr(R),
    '256');
end;
{$ENDIF}

{$IFDEF PROBE_P6_SHL_RIGHT}
// Caret auf der 40.
procedure P6ShlRight;
var
  R : Int64;
begin
  const MagicNr01 = 40;
  R := 1 shl MagicNr01;
  PutSoll('P6.4', 'const MagicNr01 = 40; R := 1 shl MagicNr01', IntToStr(R),
    '256');
end;
{$ENDIF}

{$IFDEF PROBE_P6_FOLD_HEX}
procedure P6HexFold;
var
  R : Int64;
begin
  const MagicNr01 = $FFFFFFFF;
  R := MagicNr01 + 1;
  Put('P6.5', 'const MagicNr01 = $FFFFFFFF; R := MagicNr01 + 1', IntToStr(R),
    'Soll (Original P2.15): E2099 - kompiliert, also ABWEICHUNG');
end;
{$ENDIF}

{$IFDEF PROBE_P6_FOLD_MAXINT}
procedure P6MaxIntFold;
var
  R : Int64;
begin
  const MagicNr01 = 2147483647;
  R := MagicNr01 + 1;
  Put('P6.6', 'const MagicNr01 = 2147483647; R := MagicNr01 + 1', IntToStr(R),
    'Soll (Original P2.20): E2099 - kompiliert, also ABWEICHUNG');
end;
{$ENDIF}

{$IFDEF PROBE_P6_FOLD_MAXINT_RIGHT}
// Caret auf der 1: 2147483647 bleibt Literal.
procedure P6OneFold;
var
  R : Int64;
begin
  const MagicNr01 = 1;
  R := 2147483647 + MagicNr01;
  Put('P6.7', 'const MagicNr01 = 1; R := 2147483647 + MagicNr01', IntToStr(R),
    'Soll (Original P2.20): E2099 - kompiliert, also ABWEICHUNG');
end;
{$ENDIF}

// Literal neben einer LAUFZEIT-Variablen: die Konstante muss rechnen wie das
// Literal in P2.27/28 (Integer) und P2.33 (Cardinal - der Fall, der E26
// ausgeloest hat: 'var MagicNr01 := 1' ergab dort -1).
procedure P6RunMul;
var
  N : Integer;
  R : Int64;
begin
  N := 100000;
  const MagicNr01 = 100000;
  R := N * MagicNr01;
  PutSoll('P6.8', 'N: Integer = 100000; const MagicNr01 = 100000; R := N * MagicNr01',
    IntToStr(R), '1410065408');
end;

{$Q+}
procedure P6RunMulChecked;
var
  N   : Integer;
  R   : Int64;
  Obs : string;
begin
  N := 100000;
  const MagicNr01 = 100000;
  try
    R := N * MagicNr01;
    Obs := IntToStr(R);
  except
    on E: Exception do // Absicht: die Ausnahmeklasse ist der Messwert
      Obs := 'Ausnahme ' + E.ClassName;
  end;
  PutSoll('P6.9', 'wie P6.8, mit Ueberlaufpruefung Q+', Obs,
    'Ausnahme EIntOverflow');
end;
{$Q-}

procedure P6RunCard;
var
  C : Cardinal;
  R : Int64;
begin
  C := 0;
  const MagicNr01 = 1;
  R := C - MagicNr01;
  PutSoll('P6.10', 'C: Cardinal = 0; const MagicNr01 = 1; R := C - MagicNr01',
    IntToStr(R), '4294967295');
end;

// Faltung ueber das Vorzeichenbit (P2.37, P2.40).
procedure P6Shl31;
var
  R : Int64;
begin
  const MagicNr01 = 1;
  R := MagicNr01 shl 31;
  PutSoll('P6.11', 'const MagicNr01 = 1; R := MagicNr01 shl 31', IntToStr(R),
    '-2147483648');
end;

procedure P6ShrNeg;
var
  R : Int64;
begin
  const MagicNr01 = 8;
  R := (-MagicNr01) shr 1;
  PutSoll('P6.12', 'const MagicNr01 = 8; R := (-MagicNr01) shr 1', IntToStr(R),
    '2147483644');
end;

// Gleitkomma (P3): Bitmuster der Konstante gegen das Literal.
procedure P6FloatDirect;
var
  OrigS, Sgl : Single;
  OrigD, Dbl : Double;
  OrigE, Ext : Extended;
begin
  OrigS := 0.1;
  OrigD := 0.1;
  OrigE := 0.1;
  const MagicNr01 = 0.1;
  Sgl := MagicNr01;
  Dbl := MagicNr01;
  Ext := MagicNr01;
  Put('P6.13', 'const MagicNr01 = 0.1; Sgl := MagicNr01 (Single)',
    BytesVersus(OrigS, Sgl, SizeOf(Sgl)), 'Soll (Original P3.1): gleich');
  Put('P6.14', 'const MagicNr01 = 0.1; Dbl := MagicNr01 (Double)',
    BytesVersus(OrigD, Dbl, SizeOf(Dbl)), 'Soll (Original P3.2): gleich');
  Put('P6.15', 'const MagicNr01 = 0.1; Ext := MagicNr01 (Extended)',
    BytesVersus(OrigE, Ext, SizeOf(Ext)), 'Soll (Original P3.3): gleich');
end;

// Caret auf 0.1 in '0.1 * 3' (P3.13) bzw. auf der 3.
procedure P6FloatMul;
var
  OrigD, Dbl : Double;
  OrigE, Ext : Extended;
begin
  OrigD := 0.1 * 3;
  OrigE := 0.1 * 3;
  const MagicNr01 = 0.1;
  Dbl := MagicNr01 * 3;
  Ext := MagicNr01 * 3;
  Put('P6.16', 'const MagicNr01 = 0.1; Dbl := MagicNr01 * 3 (Double)',
    BytesVersus(OrigD, Dbl, SizeOf(Dbl)), 'Soll (Original P3.13): gleich');
  Put('P6.17', 'const MagicNr01 = 0.1; Ext := MagicNr01 * 3 (Extended)',
    BytesVersus(OrigE, Ext, SizeOf(Ext)), 'Soll (Original 0.1 * 3): gleich');
end;

procedure P6FloatMulRight;
var
  Orig, Dbl : Double;
begin
  Orig := 0.1 * 3;
  const MagicNr01 = 3;
  Dbl := 0.1 * MagicNr01;
  Put('P6.18', 'const MagicNr01 = 3; Dbl := 0.1 * MagicNr01 (Double)',
    BytesVersus(Orig, Dbl, SizeOf(Dbl)), 'Soll (Original P3.13): gleich');
end;

procedure P6FloatRun;
var
  X, Orig, Dbl : Double;
begin
  X := 3;
  Orig := X * 0.1;
  const MagicNr01 = 0.1;
  Dbl := X * MagicNr01;
  Put('P6.19', 'X: Double = 3; const MagicNr01 = 0.1; Dbl := X * MagicNr01',
    BytesVersus(Orig, Dbl, SizeOf(Dbl)), 'Soll (Original P3.21): gleich');
end;

// Ueberladungswahl (P4): die Konstante muss dieselbe Ueberladung waehlen
// wie das Literal - P4.9/14 (ShortInt/Byte) sind die Grenze, an der die
// Variable (P4.12/16: Integer) abwich.
procedure P6OvIntInt64;
begin
  const MagicNr01 = 42;
  PutSoll('P6.20', 'const MagicNr01 = 42; OvIntInt64(MagicNr01)',
    OvIntInt64(MagicNr01), 'Integer');
  PutSoll('P6.21', 'const MagicNr01 = 42; OvIntInt64(MagicNr01 * 2)',
    OvIntInt64(MagicNr01 * 2), 'Integer');
end;

{$IFDEF PROBE_P6_BIGLIT_FOLD}
procedure P6OvBigLitFold;
begin
  const MagicNr01 = 100000;
  Put('P6.22', 'const MagicNr01 = 100000; OvIntInt64(MagicNr01 * MagicNr01)',
    OvIntInt64(MagicNr01 * MagicNr01),
    'Soll (Original P4.3): E2099 - kompiliert, also ABWEICHUNG');
end;
{$ENDIF}

{$IFDEF PROBE_P6_BIGLIT_DEC}
procedure P6OvBigLitDec;
begin
  const MagicNr01 = 3000000000;
  PutSoll('P6.23', 'const MagicNr01 = 3000000000; OvIntInt64(MagicNr01)',
    OvIntInt64(MagicNr01), 'Int64');
end;
{$ENDIF}

{$IFDEF PROBE_P6_SHORTINT}
procedure P6OvShort;
begin
  const MagicNr01 = 42;
  PutSoll('P6.24', 'const MagicNr01 = 42; OvShort3(MagicNr01)',
    OvShort3(MagicNr01), 'ShortInt');
  PutSoll('P6.25', 'const MagicNr01 = 42; OvShort3(MagicNr01 * 2)',
    OvShort3(MagicNr01 * 2), 'ShortInt');
end;
{$ENDIF}

{$IFDEF PROBE_P6_BYTE}
procedure P6OvByte;
begin
  const MagicNr01 = 42;
  PutSoll('P6.26', 'const MagicNr01 = 42; OvByteInt(MagicNr01)',
    OvByteInt(MagicNr01), 'Byte');
  const MagicNr02 = 200;
  PutSoll('P6.27', 'const MagicNr02 = 200; OvByteInt(MagicNr02)',
    OvByteInt(MagicNr02), 'Byte');
end;
{$ENDIF}

{$IFDEF PROBE_P6_FLOAT}
{$IFDEF PROBE_EXT_ARG_CALL}
procedure P6OvFloat;
begin
  const MagicNr01 = 3.5;
  PutSoll('P6.28', 'const MagicNr01 = 3.5; OvFloat(MagicNr01)',
    OvFloat(MagicNr01), 'Extended');
  const MagicNr02 = 0.1;
  PutSoll('P6.29', 'const MagicNr02 = 0.1; OvFloat(MagicNr02)',
    OvFloat(MagicNr02), 'Extended');
end;
{$ENDIF}
{$ENDIF}

{$IFDEF PROBE_P6_SD_INEXACT}
procedure P6OvSDInexact;
begin
  const MagicNr01 = 0.1;
  PutSoll('P6.30', 'const MagicNr01 = 0.1; OvSD(MagicNr01)', OvSD(MagicNr01),
    'Double');
end;
{$ENDIF}

{$IFDEF PROBE_P6_SD_EXACT}
procedure P6OvSDExact;
begin
  const MagicNr01 = 3.5;
  PutSoll('P6.31', 'const MagicNr01 = 3.5; OvSD(MagicNr01)', OvSD(MagicNr01),
    'Double');
end;
{$ENDIF}

// ---- Ablauf -------------------------------------------------------------------

procedure RunP1;
begin
  P1Int42;
  P1Int100000;
  P1IntMax;
  P1IntMaxPlus1;
  P1Int3G;
  P1Hex32;
  P1Hex32TypedInt64;
{$IFDEF PROBE_P1_HEX_SEP}
  P1Hex32Sep;
{$ENDIF}
  P1Hex63;
{$IFDEF PROBE_P1_HEX64}
  P1Hex64;
{$ENDIF}
{$IFDEF PROBE_P1_UINT64_DEC}
  P1UInt64Dec;
{$ENDIF}
{$IFDEF PROBE_P1_UINT64_TYPED_HEX}
  P1UInt64TypedHex;
{$ENDIF}
{$IFDEF PROBE_P1_UINT64_TYPED_DEC}
  P1UInt64TypedDec;
{$ENDIF}
  P1IntSep;
  P1Float35;
  P1FloatExp;
  P1FloatExpSign;
end;

procedure RunP2;
begin
{$IFDEF PROBE_P2_FOLD_MUL}
  P2MulFold;
{$ENDIF}
  P2MulUntyped;
  P2MulInteger;
  P2MulIntegerChecked;
  P2MulInt64;
{$IFDEF PROBE_P2_FOLD_DIV}
  P2DivFold;
{$ENDIF}
  P2DivInteger;
  P2DivInt64;
{$IFDEF PROBE_P2_FOLD_SHL}
  P2ShlFold;
{$ENDIF}
{$IFDEF PROBE_P2_SHL_VAR}
{$IFDEF PROBE_P2_SHL_UNTYPED}
  P2ShlLeftUntyped;
{$ENDIF}
{$IFDEF PROBE_P2_SHL_INTEGER}
  P2ShlLeftInteger;
{$ENDIF}
  P2ShlLeftInt64;
  P2ShlRightInteger;
  P2ShlRightInt64;
{$ENDIF}
{$IFDEF PROBE_P2_FOLD_HEX}
  P2HexFold;
{$ENDIF}
  P2HexUntyped;
  P2HexCardinal;
  P2HexCardinalChecked;
  P2HexInt64;
{$IFDEF PROBE_P2_FOLD_MAXINT}
  P2MaxIntFold;
{$ENDIF}
  P2MaxIntUntyped;
  P2MaxIntInteger;
  P2MaxIntIntegerChecked;
  P2MaxIntInt64;
  P2OneInteger;
  P2OneInt64;
  P2RunMulOrig;
  P2RunMulOrigChecked;
  P2RunMulInteger;
  P2RunMulIntegerChecked;
  P2RunMulInt64;
  P2RunMulInt64Checked;
  P2RunCardOrig;
  P2RunCardInteger;
  P2RunCardInt64;
  P2RunCardCardinal;
{$IFDEF PROBE_P2_FOLD_SHL31}
  P2Shl31Fold;
{$ENDIF}
  P2Shl31Integer;
  P2Shl31Int64;
{$IFDEF PROBE_P2_FOLD_SHR_NEG}
  P2ShrNegFold;
{$ENDIF}
  P2ShrNegInteger;
  P2ShrNegInt64;
end;

procedure RunP3;
begin
  P3References;
  P3SingleViaUntyped;
  P3SingleViaExtended;
  P3SingleViaDouble;
  P3DoubleViaUntyped;
  P3DoubleViaExtended;
  P3DoubleViaDouble;
  P3ExtendedViaUntyped;
  P3ExtendedViaExtended;
  P3ExtendedViaDouble;
  P3MulFold;
  P3MulDoubleViaUntyped;
  P3MulDoubleViaExtended;
  P3MulDoubleViaDouble;
  P3MulExtendedViaExtended;
  P3MulExtendedViaDouble;
  P3MulRightInteger;
  P3MulRightInt64;
  P3RunOrig;
  P3RunViaUntyped;
  P3RunViaExtended;
  P3RunViaDouble;
end;

procedure RunP4;
begin
  P4IntInt64Literals;
{$IFDEF PROBE_P4_UNTYPED}
  P4IntInt64Untyped;
{$ENDIF}
  P4IntInt64Integer;
  P4IntInt64Int64;
  P4IntInt64Int64Mul;
{$IFDEF PROBE_P4_SHORTINT_LIT}
  P4ShortLiterals;
{$ENDIF}
{$IFDEF PROBE_P4_UNTYPED}
  P4ShortUntyped;
{$ENDIF}
  P4ShortInteger;
  P4ShortInt64;
{$IFDEF PROBE_P4_BYTE_LIT}
  P4ByteLiterals;
{$ENDIF}
  P4ByteInteger;
{$IFDEF PROBE_P4_BYTE_INT64VAR}
  P4ByteInt64;
{$ENDIF}
{$IFDEF PROBE_P4_FLOAT_LIT}
{$IFDEF PROBE_EXT_ARG_CALL}
  P4FloatLiterals;
{$ENDIF}
{$ENDIF}
{$IFDEF PROBE_P4_UNTYPED}
{$IFDEF PROBE_EXT_ARG_CALL}
  P4FloatUntyped;
{$ENDIF}
{$ENDIF}
{$IFDEF PROBE_EXT_ARG_CALL}
  P4FloatExtended;
{$ENDIF}
  P4FloatDouble;
{$IFDEF PROBE_P4_SD_LIT_INEXACT}
  P4SDLiteralInexact;
{$ENDIF}
{$IFDEF PROBE_P4_SD_LIT_EXACT}
  P4SDLiteralExact;
{$ENDIF}
{$IFDEF PROBE_P4_SD_UNTYPED}
  P4SDUntyped;
{$ENDIF}
{$IFDEF PROBE_P4_SD_EXTVAR}
  P4SDExtended;
{$ENDIF}
  P4SDDouble;
end;

procedure RunP5;
begin
{$IFDEF PROBE_P5_SETLENGTH}
  P5SetLength;
{$ENDIF}
{$IFDEF PROBE_P5_COPY}
  P5Copy;
{$ENDIF}
{$IFDEF PROBE_P5_FOR}
  P5For;
{$ENDIF}
{$IFDEF PROBE_P5_FORVAR}
  P5ForVar;
{$ENDIF}
{$IFDEF PROBE_P5_INC}
  P5Inc;
{$ENDIF}
{$IFDEF PROBE_P5_STRINGOFCHAR}
  P5StringOfChar;
{$ENDIF}
{$IFDEF PROBE_P5_STRINDEX}
  P5StrIndex;
{$ENDIF}
{$IFDEF PROBE_P5_ARRINDEX}
  P5ArrIndex;
{$ENDIF}
{$IFDEF PROBE_P5_MAX}
  P5Max;
{$ENDIF}
{$IFDEF PROBE_P5_ASSIGN}
  P5Assign;
{$ENDIF}
{$IFDEF PROBE_P5_UINT64_COPY}
  P5UInt64Copy;
{$ENDIF}
{$IFDEF PROBE_P5_UINT64_SETLENGTH}
  P5UInt64SetLength;
{$ENDIF}
{$IFDEF PROBE_P5_CARDINAL_FOR}
  P5CardinalFor;
{$ENDIF}
{$IFDEF PROBE_P5_CARDINAL_COPY}
  P5CardinalCopy;
{$ENDIF}
{$IFDEF PROBE_P5_CASE}
  P5Case;
{$ENDIF}
{$IFDEF PROBE_P5_IN}
  P5In;
{$ENDIF}
{$IFDEF PROBE_P5_FORVAR_START}
  P5ForVarStart;
{$ENDIF}
{$IFDEF PROBE_P5_INLINE_PROPAGATE}
  P5InlinePropagate;
{$ENDIF}
end;

procedure RunP6;
begin
{$IFDEF PROBE_P6_FOLD_MUL}
  P6MulFold;
{$ENDIF}
{$IFDEF PROBE_P6_FOLD_DIV}
  P6DivFold;
{$ENDIF}
{$IFDEF PROBE_P6_SHL_LEFT}
  P6ShlLeft;
{$ENDIF}
{$IFDEF PROBE_P6_SHL_RIGHT}
  P6ShlRight;
{$ENDIF}
{$IFDEF PROBE_P6_FOLD_HEX}
  P6HexFold;
{$ENDIF}
{$IFDEF PROBE_P6_FOLD_MAXINT}
  P6MaxIntFold;
{$ENDIF}
{$IFDEF PROBE_P6_FOLD_MAXINT_RIGHT}
  P6OneFold;
{$ENDIF}
  P6RunMul;
  P6RunMulChecked;
  P6RunCard;
  P6Shl31;
  P6ShrNeg;
  P6FloatDirect;
  P6FloatMul;
  P6FloatMulRight;
  P6FloatRun;
  P6OvIntInt64;
{$IFDEF PROBE_P6_BIGLIT_FOLD}
  P6OvBigLitFold;
{$ENDIF}
{$IFDEF PROBE_P6_BIGLIT_DEC}
  P6OvBigLitDec;
{$ENDIF}
{$IFDEF PROBE_P6_SHORTINT}
  P6OvShort;
{$ENDIF}
{$IFDEF PROBE_P6_BYTE}
  P6OvByte;
{$ENDIF}
{$IFDEF PROBE_P6_FLOAT}
{$IFDEF PROBE_EXT_ARG_CALL}
  P6OvFloat;
{$ENDIF}
{$ENDIF}
{$IFDEF PROBE_P6_SD_INEXACT}
  P6OvSDInexact;
{$ENDIF}
{$IFDEF PROBE_P6_SD_EXACT}
  P6OvSDExact;
{$ENDIF}
end;

begin
  OpenReport;
  try
    try
      PutHeader;
      RunP1;
      RunP2;
      RunP3;
      RunP4;
      RunP5;
      RunP6;
      PutRaw('# Ende');
    except
      on E: Exception do
        PutRaw('# ABBRUCH ' + E.ClassName + ': ' + E.Message);
    end;
  finally
    CloseFile(GOut);
  end;
  WriteLn('Protokoll: ' + GReportPath);
  WaitIfAsked;
end.
