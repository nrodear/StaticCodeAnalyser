unit uHardcodedString;

// Detektor: User-sichtbarer String wird als Literal zugewiesen statt
// aus resourcestring / i18n-Helper.
//
// Pattern (Code Smell, Sonar-50 #46, narrow):
//   Form1.Caption     := 'Mein Programm';     // hardcoded -> nicht uebersetzbar
//   Button1.Hint      := 'Klick mich';
//   Label1.Text       := 'Hallo Welt';
//   ShowMessage('Daten gespeichert');
//
// Korrekt:
//   resourcestring
//     SCaption     = 'Mein Programm';
//     SHint        = 'Klick mich';
//   ...
//   Form1.Caption := _(SCaption);             // via dxgettext / TLang.GetString
//
// Erkennung (lexisch, narrow):
//   * Strip Strings + Kommentare NICHT - wir wollen ja die String-Literale
//     finden. Stattdessen direkt Pattern-Match auf die User-sichtbaren
//     Properties.
//   * Pattern: `<ident>.Caption|Hint|Text := '<text>'`
//     ODER: `ShowMessage|MessageDlg\s*\('<text>'`
//   * Skip-Conditions:
//     - Leerer String / nur Whitespace.
//     - Single-Char-Strings ('-', '.', ':', '/').
//     - String enthaelt nur Sonderzeichen / kein Buchstabe.
//     - String hat Resource-Key-Style: beginnt mit '$' oder ist
//       UPPER_SNAKE_CASE.
//
// Limitierungen:
//   * Kann nicht erkennen ob das Caption-Property auf einer non-UI-Klasse
//     gesetzt wird (z.B. einer internen Helper-Klasse mit Caption-
//     Property zur Doku) - dann FP.
//   * `_('text')` direkt im Pattern wird auch geflaggt - aber das Pattern
//     `:= '...'` matched nicht wenn das ein Funktionsaufruf ist, weil
//     da `:= _('...')` oder `:= _SOMETHING_` steht.
//
// Schweregrad: lsHint - i18n-Empfehlung, kein Bug.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  THardcodedStringDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file BeginEndRequired, MultipleExit, NilComparison, RedundantBoolean, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.RegularExpressions, System.StrUtils,
  uFileTextCache;

var
  // Lazy-Cache (Round 11): konstante Patterns einmalig kompilieren.
  CachedRePropertyAssign : TRegEx;
  CachedReDialogCall     : TRegEx;
  CachedReInit           : Boolean = False;

procedure EnsureRegexCacheBuilt;
begin
  if CachedReInit then Exit;
  CachedRePropertyAssign := TRegEx.Create(
    '(?i)\.\s*(?:Caption|Hint|Text)\s*:=\s*''([^'']*(?:''''[^'']*)*)''');
  CachedReDialogCall     := TRegEx.Create(
    '(?i)\b(?:ShowMessage|MessageDlg)\s*\(\s*''([^'']*(?:''''[^'']*)*)''');
  CachedReInit := True;
end;

function ContainsLetter(const S: string): Boolean;
var
  i : Integer;
begin
  for i := 1 to Length(S) do
    if CharInSet(S[i], ['A'..'Z', 'a'..'z']) then Exit(True);
  Result := False;
end;

function IsResourceKeyStyle(const S: string): Boolean;
// UPPER_SNAKE_CASE oder beginnt mit '$' - sieht aus wie ein Schluessel,
// nicht wie User-Text.
var
  i : Integer;
  HasLetter : Boolean;
begin
  if (S = '') then Exit(False);
  if S[1] = '$' then Exit(True);
  HasLetter := False;
  for i := 1 to Length(S) do
  begin
    if CharInSet(S[i], ['A'..'Z', '0'..'9', '_']) then
    begin
      if CharInSet(S[i], ['A'..'Z']) then HasLetter := True;
      Continue;
    end;
    Exit(False);
  end;
  Result := HasLetter;
end;

function ShouldReport(const Lit: string): Boolean;
// Lit ist die Substring-Capture (ohne Quotes).
var
  T : string;
begin
  T := Trim(Lit);
  if T = '' then Exit(False);                  // leer
  if Length(T) < 2 then Exit(False);           // single-char: '-', '.', ':', ...
  if not ContainsLetter(T) then Exit(False);   // nur Sonderzeichen / Zahlen
  if IsResourceKeyStyle(T) then Exit(False);   // Resource-Key-Style
  Result := True;
end;

class procedure THardcodedStringDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Lines    : TStringList;
  Cached   : Boolean;
  i        : Integer;
  Line     : string;
  M        : TMatch;
  Lit      : string;
  F        : TLeakFinding;
begin
  EnsureRegexCacheBuilt;
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i];
      // Comment-Skip: einfache Zeilen-Kommentare ueberspringen wir grob.
      if Trim(Line).StartsWith('//') then Continue;

      for M in CachedRePropertyAssign.Matches(Line) do
      begin
        Lit := M.Groups[1].Value;
        if not ShouldReport(Lit) then Continue;
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := '';
        F.LineNumber := IntToStr(i + 1);
        F.MissingVar := Format(
          'User-visible string %s assigned directly - move to resourcestring / i18n',
          [QuotedStr(Lit)]);
        F.SetKind(fkHardcodedString);
        Results.Add(F);
      end;
      for M in CachedReDialogCall.Matches(Line) do
      begin
        Lit := M.Groups[1].Value;
        if not ShouldReport(Lit) then Continue;
        F            := TLeakFinding.Create;
        F.FileName   := FileName;
        F.MethodName := '';
        F.LineNumber := IntToStr(i + 1);
        F.MissingVar := Format(
          'User-visible string %s in ShowMessage/MessageDlg - move to resourcestring / i18n',
          [QuotedStr(Lit)]);
        F.SetKind(fkHardcodedString);
        Results.Add(F);
      end;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
