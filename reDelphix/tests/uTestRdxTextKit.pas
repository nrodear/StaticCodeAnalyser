unit uTestRdxTextKit;

// Gemeinsame Testhelfer fuer Text, Ersetzungen und Temp-Dateien - KEINE
// Fixture, kein Test (Review reDelphix R6-08). Bis dahin hatte fast jede
// Testunit ihre eigene Kopie: Join 28-mal, Apply 22-mal (dazu ApplyEdits
// und ApplyOne), LineOf 9-mal in zwei Vertraegen (dazu LineWith),
// WriteText 4-mal (dazu SaveText), RemoveTree 4-mal und fuenf
// Temp-Verzeichnis-Helfer; Apply und LineOf standen zudem nachgebaut in
// uTestRdxCleanupScope.Fix und uTestRdxMagicGuards.PlanReason. Eine
// Aenderung am Schreibweg (PlanByteEdits) oder an den Zeilenenden musste in
// jeder Kopie nachgezogen werden - eine vergessene prueft einen anderen Weg
// als den des Editors. Hier steht nur,
// was in ALLEN Kopien denselben Vertrag hatte (Trenner, letzte Zeile,
// Fehlerverhalten); die Kopien sind ersetzt, kein Test und kein Assert
// aendert sich.
//
// FPC-tauglich: der Pruefstand (tools\fpc-pruefstand\build.sh) kopiert und
// passt die Unit bei JEDEM Lauf an wie eine Quelle. Sie ist kein
// Aufrufargument, und die Pruefung "jede Testunit meldet ihre Fixture an"
// trifft sie nicht: sie hat keine Fixture-Klasse (wie uTestRdxDetectorKit,
// die Helfer der Detektor-Rundlaeufe, nur Delphi).
//
// Varianten mit anderem Vertrag bleiben in ihrer Testunit, unter eigenem
// Namen:
//   * uTestRdxCleanupScope.LineAt - der Text der Zeile ALine einer Liste;
//   * uTestRdxFreeGatesDetector.LineOfOrFail - trennt nur an CRLF und
//     scheitert ohne Treffer (Assert.Fail), statt 0 zu liefern;
//   * uTestRdxText.WriteUtf8 - UTF-8 ohne BOM, der Text unveraendert;
//   * uTestRdxIntroEdits.JoinLines und uTestRdxIntroContext.Buf (je mit
//     JoinFrom) - sie verketten selbst und bleiben so auch unter FPC
//     verlustfrei (Join nicht, s. dort);
//   * uTestRdxFormatGuards.Joined - Verkettung ohne Trenner;
//   * uTestRdxSca044.WriteTemp - Name aus Uhrzeit und Zufall;
//   * uTestRdxMagicFixDetector.DeepDir/RemoveDeepDir - raeumt nur die drei
//     leeren Ebenen ab, die Dateien loescht der Test;
//   * uTestRdxMagicGuards.FixText - plant und schreibt wie Apply, meldet
//     ein Scheitern beim Schreiben aber als 'Schreiben: ', getrennt vom
//     Grund des Planers ('Plan: ').
// Die Temp-Verzeichnisse der Testunits (FreshDir, FreshRoot, TempDir)
// binden nur noch ihren Vorsatz (rdx_fa_, rdx_q14_, ...) - die Pfade unter
// TEMP bleiben, wie die Kopfkommentare der Testunits sie nennen.

interface

uses
  uRdxBufferMath;   // TRdxEdit

// Zeilen mit CRLF verbunden, ohne Zeilenende hinter der letzten; [] gibt
// ''. Ueber TStringBuilder (string.Join uebersetzt unter FPC 3.2.2 nicht) -
// dort ein AnsiString-Bauer: Zeichen ausserhalb der Systemcodepage werden
// '?' (U+4E2D bei Codepage 1252; ein Umlaut bleibt). Wer sie braucht,
// stellt die Systemcodepage auf UTF-8 (uTestRdxCleanupScope) oder
// verkettet selbst (uTestRdxIntroEdits).
function Join(const ALines: array of string): string;
// AParts mit ASep verbunden - wie Join, mit beliebigem Trenner.
function JoinWith(const ASep: string; const AParts: array of string): string;
// Wendet AEdits an wie der Editor (uRdxEditor.ReplaceSpans): EIN Plan ueber
// die UTF-8-Bytes von ASource - PlanByteEdits prueft jeden erwarteten Text,
// sortiert, lehnt Ueberlappungen ab und setzt #10 im neuen Text auf das
// Zeilenende des Puffers -, dann ApplyByteEdits. Lehnt PlanByteEdits ab,
// scheitert der Test (Assert) mit dessen Grund. Die offene Liste nimmt
// eine TArray-Variable ebenso an wie [E1, E2] - in Delphi und FPC ohne
// Mehrdeutigkeit neben der Einzel-Variante.
function Apply(const ASource: string;
  const AEdits: array of TRdxEdit): string; overload;
// Dasselbe fuer eine einzelne Ersetzung.
function Apply(const ASource: string; const AEdit: TRdxEdit): string; overload;
// Die erste Zeile (1-basiert), die AText enthaelt; 0 ohne Treffer. Zeilen
// wie TStringList.Text (CRLF, LF, CR).
function LineOf(const ASource, AText: string): Integer;
// Die erste Zeile (1-basiert), die - ohne fuehrenden Leerraum - mit AStart
// beginnt; 0 ohne Treffer. Den Leerraum nimmt TrimLeft: Leerzeichen,
// Tabulatoren, jedes Zeichen bis #32. AStart steht deshalb ohne Einzug - ein
// AStart mit fuehrendem Leerraum trifft nie.
function LineStartingWith(const ASource, AStart: string): Integer;
// Schreibt AText ueber TStringList.SaveToFile nach APath: Zeilenenden CRLF,
// eines auch hinter der letzten Zeile, Kodierung wie TStringList - ohne
// Umstellung der Systemcodepage ANSI, kein UTF-8 (das schreibt
// uTestRdxText.WriteUtf8).
procedure WriteText(const APath, AText: string);
// Ein frischer Name im TEMP-Verzeichnis: APrefix + GUID + ASuffix (etwa
// '.pas' oder PathDelim); angelegt wird nichts.
function TempName(const APrefix, ASuffix: string): string;
// Ein frisches, angelegtes Verzeichnis TEMP\<APrefix><GUID>\ (mit Trenner),
// eigen je Aufruf: parallele oder abgebrochene Laeufe teilen keine Dateien
// (Review R6-07). Abraeumen mit RemoveTree.
function NewTempDir(const APrefix: string): string;
// Loescht den Baum ADir (mit Trenner) samt Inhalt.
procedure RemoveTree(const ADir: string);

implementation

uses
  System.SysUtils, System.Classes,
  DUnitX.TestFramework;

function Join(const ALines: array of string): string;
begin
  Result := JoinWith(#13#10, ALines);
end;

function JoinWith(const ASep: string; const AParts: array of string): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(AParts) do
    begin
      if i > 0 then SB.Append(ASep);
      SB.Append(AParts[i]);
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function Apply(const ASource: string; const AEdits: array of TRdxEdit): string;
var
  Edits : TArray<TRdxEdit>;
  Bytes : TBytes;
  Plan  : TArray<TRdxByteEdit>;
  Err   : string;
  Ok    : Boolean;
  i     : Integer;
begin
  SetLength(Edits, Length(AEdits));
  for i := 0 to High(AEdits) do
    Edits[i] := AEdits[i];
  Bytes := TEncoding.UTF8.GetBytes(ASource);
  // Erst das Ergebnis, dann die Meldung: in welcher Reihenfolge die
  // Argumente eines Aufrufs ausgewertet werden, ist nicht festgelegt - Err
  // steht erst nach PlanByteEdits fest.
  Ok := PlanByteEdits(Bytes, Edits, Plan, Err);
  Assert.IsTrue(Ok, Err);
  Result := TEncoding.UTF8.GetString(ApplyByteEdits(Bytes, Plan));
end;

function Apply(const ASource: string; const AEdit: TRdxEdit): string;
begin
  Result := Apply(ASource, [AEdit]);
end;

function LineOf(const ASource, AText: string): Integer;
var
  SL : TStringList;
  i  : Integer;
begin
  Result := 0;
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    for i := 0 to SL.Count - 1 do
      if Pos(AText, SL[i]) > 0 then
        Exit(i + 1);
  finally
    SL.Free;
  end;
end;

function LineStartingWith(const ASource, AStart: string): Integer;
var
  SL : TStringList;
  i  : Integer;
begin
  Result := 0;
  SL := TStringList.Create;
  try
    SL.Text := ASource;
    for i := 0 to SL.Count - 1 do
      if Copy(TrimLeft(SL[i]), 1, Length(AStart)) = AStart then
        Exit(i + 1);
  finally
    SL.Free;
  end;
end;

procedure WriteText(const APath, AText: string);
var
  SL : TStringList;
begin
  SL := TStringList.Create;
  try
    SL.Text := AText;
    SL.SaveToFile(APath);
  finally
    SL.Free;
  end;
end;

function TempName(const APrefix, ASuffix: string): string;
var
  G : TGUID;
begin
  CreateGUID(G);
  Result := IncludeTrailingPathDelimiter(GetEnvironmentVariable('TEMP'))
    + APrefix + GUIDToString(G) + ASuffix;
end;

function NewTempDir(const APrefix: string): string;
begin
  Result := TempName(APrefix, PathDelim);
  ForceDirectories(Result);
end;

procedure RemoveTree(const ADir: string);
var
  SR : TSearchRec;
begin
  if FindFirst(ADir + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Name = '.') or (SR.Name = '..') then
        Continue;
      if (SR.Attr and faDirectory) <> 0 then
        RemoveTree(ADir + SR.Name + PathDelim)
      else
        DeleteFile(ADir + SR.Name);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  RemoveDir(ADir);
end;

end.
