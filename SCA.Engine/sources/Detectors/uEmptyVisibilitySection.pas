unit uEmptyVisibilitySection;

// Detektor fuer leere Visibility-Sections in Klassen-Bodies.
//
// SonarDelphi-Aequivalent: communitydelphi:EmptyVisibilitySection. Eine
// Klasse mit `public\n private` ohne Member dazwischen ist Refactor-Rest
// (alle public members wurden in andere Sections verschoben). Aufraeumen.
//
// Erkennung: zeilenweiser Scan. Wenn das erste Wort einer Zeile eines
// der Visibility-Keywords ist (`private`, `protected`, `public`,
// `published`, `strict private`, `strict protected`), und das NAECHSTE
// Visibility-Keyword direkt nach Whitespace/Kommentaren folgt (keine
// Felder/Methoden dazwischen), wird gemeldet.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TEmptyVisibilitySectionDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, CyclomaticComplexity, GroupedDeclaration, LongMethod, MultipleExit, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uFileTextCache,
  uDetectorUtils;   // ExtractFirstWord (Voll-Review 2026-09-12)

const
  // Das Wort steht in der Erkennung UND zweimal in der
  // Namensbildung fuer den Meldetext - ab der dritten Kopie
  // gehoert es an eine Stelle.
  KW_STRICT     = 'strict';

function ExtractFirstWord(const Line: string; out StartCol: Integer): string;
// Voll-Review 2026-09-12: zentral (ExtractFirstWordOrBracket).
// Attribut-Zeile ('[Test]', '[Weak]', ...): '[' als Pseudo-Wort liefern.
// Der Aufrufer behandelt es wie jeden Nicht-Keyword-Bezeichner - die
// Section hat INHALT, denn das Attribut gehoert zum folgenden Member.
// Vorher wurden solche Zeilen uebersprungen wie Leerzeilen, und JEDE
// DUnitX-Fixture ('public' + nur '[Test] procedure ...' + 'end') galt
// als leere Section - 226 False-Positives allein im eigenen
// Testverzeichnis (Baseline-Kommentar 2026-08-04). Trifft auch
// mehrzeilige Mengen-/Array-Konstanten, die mit '[' beginnen - dort ist
// 'Inhalt' ebenso die sichere Richtung fuer eine Hint-Regel.
begin
  Result := TDetectorUtils.ExtractFirstWordOrBracket(Line, StartCol);
end;

function IsVisibilityKw(const Lower: string): Boolean; inline;
begin
  Result := (Lower = 'private') or (Lower = 'protected')
         or (Lower = 'public')  or (Lower = 'published')
         or (Lower = KW_STRICT);
end;

function IsClassEnderKw(const Lower: string): Boolean; inline;
begin
  Result := (Lower = 'end');
end;

function SektionsName(const ALine, AErstesWort: string): string;
// Der Name FUER DEN MELDETEXT, nicht fuer die Erkennung.
//
// 'strict' steht in IsVisibilityKw als eigenes Schluesselwort, weil nur
// das erste Wort der Zeile geprueft wird. Fuer die Erkennung reicht das
// (jede 'strict ...'-Zeile eroeffnet eine Sektion und schliesst die
// vorige ab), fuer die MELDUNG nicht: 'Empty `strict` section' laesst
// offen, ob private oder protected gemeint ist, und in einer Klasse mit
// beiden sind zwei Funde nicht auseinanderzuhalten
// (Voll-Review 2026-09-12, Testluecke 148).
//
// Deshalb hier das zweite Wort anhaengen, wenn es eines gibt. Die
// Erkennung bleibt unangetastet.
var
  Rest : string;
  i    : Integer;
begin
  Result := AErstesWort;
  if AErstesWort <> KW_STRICT then Exit;
  i := Pos(KW_STRICT, LowerCase(ALine));
  if i <= 0 then Exit;
  Rest := TrimLeft(Copy(ALine, i + Length(KW_STRICT), MaxInt));
  i := 1;
  while (i <= Length(Rest)) and CharInSet(Rest[i], ['a'..'z', 'A'..'Z']) do
    Inc(i);
  Rest := Copy(Rest, 1, i - 1);
  if Rest <> '' then
    Result := AErstesWort + ' ' + LowerCase(Rest);
end;

class procedure TEmptyVisibilitySectionDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines       : TStringList;
  Cached      : Boolean;
  i           : Integer;
  Col         : Integer;
  Word        : string;
  Lower       : string;
  LastVis     : string;
  // Der Name FUER DIE MELDUNG - bei 'strict' zweiteilig, sonst
  // identisch mit LastVis (s. SektionsName).
  LastVisName : string;
  LastVisLine : Integer;
  F           : TLeakFinding;
  ScanState   : TCommentScanState;
  DummyCol    : Integer;
  Line        : string;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    LastVis := '';
    LastVisName := '';
    LastVisLine := -1;
    ScanState := Default(TCommentScanState);
    for i := 0 to Lines.Count - 1 do
    begin
      // Kommentar-Zustand UEBER Zeilen (Voll-Review 2026-09-12, Major
      // 61, gleiche Gattung wie Major 48): die Fortsetzungszeile eines
      // mehrzeiligen Blockkommentars wurde als Code gelesen - ein
      // 'private ...' darin setzte LastVis (FP am folgenden end), ein
      // Identifier-Anfang resettete eine WIRKLICH leere Section (FN).
      // Der '['-Pseudo-Wort-Vertrag (ExtractFirstWordOrBracket im
      // lokalen Wrapper) bleibt unveraendert - ScanCodeLine laesst
      // '['-Zeilen stehen.
      Line := TDetectorUtils.ScanCodeLine(Lines[i], ScanState, DummyCol);
      Word := ExtractFirstWord(Line, Col);
      if Word = '' then Continue;
      Lower := LowerCase(Word);
      if IsVisibilityKw(Lower) then
      begin
        if LastVis <> '' then
        begin
          // Vorherige Visibility-Section hatte keine Member-Zeilen
          F            := TLeakFinding.Create;
          F.FileName   := FileName;
          F.MethodName := '';
          F.LineNumber := IntToStr(LastVisLine + 1);
          F.MissingVar := Format(
            'Empty `%s` section - delete the section header or add ' +
            'its members.', [LastVisName]);
          F.SetKind(fkEmptyVisibilitySection);
          Results.Add(F);
        end;
        LastVis := Lower;
        LastVisName := SektionsName(Line, Lower);
        LastVisLine := i;
      end
      else if IsClassEnderKw(Lower) then
      begin
        if LastVis <> '' then
        begin
          F            := TLeakFinding.Create;
          F.FileName   := FileName;
          F.MethodName := '';
          F.LineNumber := IntToStr(LastVisLine + 1);
          F.MissingVar := Format(
            'Empty `%s` section at end of class - delete the section ' +
            'header.', [LastVisName]);
          F.SetKind(fkEmptyVisibilitySection);
          Results.Add(F);
        end;
        LastVis := '';
        LastVisName := '';
        LastVisLine := -1;
      end
      else
      begin
        // Anderer Identifier -> Section hat Inhalt, kein leerer Section
        LastVis := '';
        LastVisName := '';
        LastVisLine := -1;
      end;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
