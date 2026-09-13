unit uConsecutiveVisibility;

// Detektor fuer konsekutive Visibility-Sections mit DERSELBEN Sichtbarkeit:
//   private FX ...
//   public  procedure Bar ...
//   private FY ...
//
// SonarDelphi-Aequivalent: communitydelphi:ConsecutiveVisibilitySection.
// Sobald innerhalb einer Klasse derselbe Visibility-Header EIN ZWEITES
// MAL auftritt (egal ob direkt benachbart oder durch andere Sections
// getrennt), gilt es als redundant - die Member sollten konsolidiert
// werden.
//
// Abgrenzung zu uEmptyVisibilitySection (SCA087): jenes feuert wenn der
// erste Header gar keine Member hat (`private\nprivate\n...`). Hier feuert
// es nur wenn dieselbe Visibility nach Membern ZURUECK kommt.
//
// Erkennung: zeilenweiser First-Word-Scan. Pro Klassen-Block (zwischen
// `class`/`record` und `end`) tracken wir eine Liste der Visibilities,
// die bereits "Member gesehen haben". Sobald dieselbe wieder auftritt:
// melden.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TConsecutiveVisibilityDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file BeginEndRequired, CyclomaticComplexity, GroupedDeclaration, LongMethod, MultipleExit, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uFileTextCache,
  uDetectorUtils;   // ExtractFirstWord (Voll-Review 2026-09-12)

function ExtractFirstWord(const Line: string): string;
var
  Dummy : Integer;
begin
  // Voll-Review 2026-09-12: zentral (TDetectorUtils.ExtractFirstWord);
  // diese Unit braucht die Spalte nicht.
  Result := TDetectorUtils.ExtractFirstWord(Line, Dummy);
end;

function IsVisibilityKw(const Lower: string): Boolean; inline;
begin
  Result := (Lower = 'private') or (Lower = 'protected')
         or (Lower = 'public')  or (Lower = 'published');
end;

// Zeilenrest nach den ersten AWords (Whitespace-getrennten) Woertern,
// TrimLeft-bereinigt. Ersetzt das fruehere LineHasContentAfter: die
// strict-Formen brauchen den Rest nach ZWEI Woertern ('strict private
// procedure A;'), und der laengenbasierte Schnitt der alten Fassung
// waere bei Mehrfach-Blanks zwischen den Woertern danebengegangen.
// Faengt weiterhin den Style ab, in dem Member und Visibility auf
// einer Zeile stehen ('public procedure A;') - ohne den Check glaubte
// der Detektor, die Section habe keine Member, und erkennt das zweite
// 'public' nicht als konsekutiv.
function RestAfterWords(const Line: string; AWords: Integer): string;
var
  i, n, w : Integer;
begin
  n := Length(Line);
  i := 1;
  for w := 1 to AWords do
  begin
    while (i <= n) and CharInSet(Line[i], [' ', #9]) do Inc(i);
    while (i <= n) and not CharInSet(Line[i], [' ', #9]) do Inc(i);
  end;
  Result := TrimLeft(Copy(Line, i, MaxInt));
end;

class procedure TConsecutiveVisibilityDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines       : TStringList;
  Cached      : Boolean;
  i           : Integer;
  Word, L     : string;
  W2          : string;
  VisWords    : Integer;
  SeenVis     : TStringList;
  CurrentVis  : string;
  CurHasMembs : Boolean;
  ScanState   : TCommentScanState;
  DummyCol    : Integer;
  Line        : string;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  SeenVis := TStringList.Create;
  try
    SeenVis.CaseSensitive := False;
    CurrentVis := '';
    CurHasMembs := False;
    ScanState := Default(TCommentScanState);
    for i := 0 to Lines.Count - 1 do
    begin
      // Kommentar-Zustand UEBER Zeilen (Voll-Review 2026-09-12, Major
      // 48): ein 'end' oder 'private' in der Fortsetzungszeile eines
      // mehrzeiligen Blockkommentars resettete bzw. vergiftete den
      // Klassen-State. ScanCodeLine entfernt Kommentare
      // zustandsbehaftet und blankt Literale.
      Line := TDetectorUtils.ScanCodeLine(Lines[i], ScanState, DummyCol);
      Word := ExtractFirstWord(Line);
      if Word = '' then Continue;
      L := LowerCase(Word);
      VisWords := 1;
      // strict private / strict protected (Voll-Review 2026-09-12,
      // Major 49): 'strict' allein ist keine Visibility - der
      // Schluessel wird aus BEIDEN Woertern gebildet und getrennt von
      // 'private'/'protected' gefuehrt (Delphi behandelt sie als
      // eigene Sichtbarkeiten; das SonarDelphi-Pendant deckt
      // strict-Sections ab). Vorher lief die Zeile in den
      // Member-Zweig: die Doppel-strict-Section blieb ungemeldet UND
      // die VORHERIGE Section galt faelschlich als 'hat Member'.
      if L = 'strict' then
      begin
        W2 := LowerCase(ExtractFirstWord(RestAfterWords(Line, 1)));
        if (W2 = 'private') or (W2 = 'protected') then
        begin
          L := 'strict ' + W2;
          VisWords := 2;
        end
        else
          Continue;
      end;
      // `end` schliesst Klassen-Block (oder andere) - State zuruecksetzen
      if L = 'end' then
      begin
        SeenVis.Clear;
        CurrentVis := '';
        CurHasMembs := False;
        Continue;
      end;
      if IsVisibilityKw(L) or (VisWords = 2) then
      begin
        // Dieselbe Visibility schon mit Membern gesehen?
        if SeenVis.IndexOf(L) >= 0 then
          Results.Add(TLeakFinding.New(FileName, '', i + 1,
            Format('Visibility section `%s` already appeared earlier in ' +
                   'this class - merge the members into a single %s block.',
              [L, L]),
            fkConsecutiveVisibility));
        CurrentVis  := L;
        CurHasMembs := False;
        // Same-line Member: `public procedure A;` zaehlt schon als
        // "Member gesehen" - sonst erkennen wir bei `public ...
        // public ...` die Wiederholung nicht.
        // Auf der BEREINIGTEN Zeile (ein Kommentar hinter der
        // Visibility zaehlte vorher als Member) und nach VisWords
        // Woertern (strict-Formen sind zweiwortig).
        if RestAfterWords(Line, VisWords) <> '' then
        begin
          if SeenVis.IndexOf(L) < 0 then SeenVis.Add(L);
          CurHasMembs := True;
        end;
      end
      else
      begin
        // Member-Zeile (oder andere Inhaltszeile innerhalb einer Section)
        if (CurrentVis <> '') and not CurHasMembs then
        begin
          if SeenVis.IndexOf(CurrentVis) < 0 then
            SeenVis.Add(CurrentVis);
          CurHasMembs := True;
        end;
      end;
    end;
  finally
    SeenVis.Free;
    ReleaseLines(Lines, Cached);
  end;
end;

end.
