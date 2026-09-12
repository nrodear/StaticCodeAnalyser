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
//   * Kommentare werden ueber TDetectorUtils.StripFileCommentsKeepStrings-
//     Cached entfernt, die String-Literale bleiben stehen - wir wollen sie
//     ja finden (Voll-Review 2026-09-12, Major 69: vorher wurden nur
//     GANZZEILIGE //-Kommentare uebersprungen; auskommentierter Code in
//     {..}-Bloecken und hinter Trailing-// wurde gemeldet und verstiess
//     gegen die Projektregel 'Kommentare zaehlen NIE als Code-Use').
//     Pattern-Match auf die User-sichtbaren Properties im gestrippten
//     Gesamttext, Quellzeile via LineForChar.
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
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  THardcodedStringDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file BeginEndRequired, MultipleExit, NilComparison, RedundantBoolean, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.RegularExpressions,
  uFileTextCache, uRegExMatches,
  uDetectorUtils;   // StripFileCommentsKeepStringsCached (Major 69)

const
  // Thread-Fix (2026-08-19): die frueheren unit-vars (CachedReX + Init-Flag)
  // teilten EINE kompilierte TPerlRegEx-Instanz ueber alle Threads; ein
  // paralleles Match mutierte deren Subject/Offsets. Die Patterns kommen
  // jetzt pro Thread aus TRegExMatches.CachedEx; [roNotEmpty] entspricht
  // exakt dem Default des alten Ein-Arg-TRegEx.Create.
  // Seit Major 69 laufen die Patterns ueber den GESTRIPPTEN GESAMTTEXT
  // statt zeilenweise. `[ \t]` statt `\s` und `[^''\n]` statt `[^'']`
  // konservieren die alte Zeilengrenze: ein Match reicht nie ueber ein
  // Zeilenende - sonst waere der Umbau eine zweite, ungewollte
  // Bewegungsrichtung (mehrzeilige Zuweisungen).
  RE_PROPERTY_ASSIGN =
    '(?i)\.[ \t]*(?:Caption|Hint|Text)[ \t]*:=[ \t]*''([^''\n]*(?:''''[^''\n]*)*)''';
  RE_DIALOG_CALL =
    '(?i)\b(?:ShowMessage|MessageDlg)[ \t]*\([ \t]*''([^''\n]*(?:''''[^''\n]*)*)''';

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
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines    : TStringList;
  Cached   : Boolean;
  Code     : string;
  LineFor  : TArray<Integer>;
  M        : TMatch;
  Lit      : string;
  F        : TLeakFinding;
  RePropertyAssign : TRegEx;
  ReDialogCall     : TRegEx;

  // Quellzeile (1-basiert) zum Match-Anfang; 0 wenn ausserhalb (defensiv,
  // analog uIfElseBegin - LineForChar traegt je Ergebnis-Zeichen den
  // 0-basierten Quellzeilen-Index).
  function ZeileZuMatch(const AMatch: TMatch): Integer;
  begin
    if (AMatch.Index >= 1) and (AMatch.Index <= Length(LineFor)) then
      Result := LineFor[AMatch.Index - 1] + 1
    else
      Result := 0;
  end;

begin
  RePropertyAssign := TRegExMatches.CachedEx(RE_PROPERTY_ASSIGN, [roNotEmpty]);
  ReDialogCall     := TRegExMatches.CachedEx(RE_DIALOG_CALL, [roNotEmpty]);
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    // Major 69: Kommentare zentral strippen statt nur ganzzeilige
    // //-Kommentare zu ueberspringen - Strings bleiben stehen, die
    // Literale sind ja das Suchziel.
    Code := TDetectorUtils.StripFileCommentsKeepStringsCached(
      Lines, LineFor, AContext, FileName);
    for M in RePropertyAssign.Matches(Code) do
    begin
      Lit := M.Groups[1].Value;
      if not ShouldReport(Lit) then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(ZeileZuMatch(M));
      F.MissingVar := Format(
        'User-visible string %s assigned directly - move to resourcestring / i18n',
        [QuotedStr(Lit)]);
      F.SetKind(fkHardcodedString);
      Results.Add(F);
    end;
    for M in ReDialogCall.Matches(Code) do
    begin
      Lit := M.Groups[1].Value;
      if not ShouldReport(Lit) then Continue;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(ZeileZuMatch(M));
      F.MissingVar := Format(
        'User-visible string %s in ShowMessage/MessageDlg - move to resourcestring / i18n',
        [QuotedStr(Lit)]);
      F.SetKind(fkHardcodedString);
      Results.Add(F);
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
