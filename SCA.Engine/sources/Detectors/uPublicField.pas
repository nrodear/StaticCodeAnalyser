unit uPublicField;

// Detektor fuer oeffentliche Felder in Klassen.
//
// SonarDelphi-Aequivalent: communitydelphi:PublicField. Oeffentliche
// Felder brechen Kapselung - der Aufrufer kann den Wert direkt
// aendern, ohne dass die Klasse das mitbekommt. Stattdessen sollte
// die Klasse eine Property anbieten (getter/setter), damit
// Invarianten geprueft werden koennen und spaetere Refactors (z.B.
// "wir wollen den Wert beim Setzen normalisieren") moeglich sind.
//
// Erkennung: Visibility-Section-Tracking. Wenn nach einem `public`
// Keyword eine Zeile folgt, die ein Feld deklariert (Pattern
// `Name: Typ;` ohne `function`/`procedure`/`property`/
// `class function`/`const`/`constructor`/`destructor`), wird gemeldet.
//
// `published` schaltet die Sektion mit, wird aber NICHT gemeldet
// (Autopsie 2026-08-27, G1) - dort ist das oeffentliche Feld die vom
// DFM-Streamer vorgeschriebene Form, kein Kapselungsfehler. Details
// samt Zaehlung am Melde-Guard in AnalyzeUnit.
//
// Schweregrad: lsHint.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TPublicFieldDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file AvoidOut, BeginEndRequired, CommentedOutCode, CyclomaticComplexity, DeepNesting, GroupedDeclaration, MultipleExit, NilComparison, TooLongLine, UnsortedUses, UnusedParameter
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uFileTextCache;

const
  EMIT_SEVERITY = lsHint;

// Zeilenweiser Kommentar-/String-Strip MIT Zustand ueber Zeilengrenzen
// (Autopsie 2026-08-26, Fix C; Vorbild uTautologicalExpr). Der alte
// Detektor kannte Blockkommentare nur, wenn die Zeile damit BEGANN -
// "published by the Free Software Foundation" in einem GPL-Header
// schaltete InPublic an, und Klammern in {..}-Kommentaren haetten die
// neue Balance-Zaehlung vergiftet (LoggerPro.FileAppender:107 u.a.).
procedure StripLineStateful(const Line: string; var InBrace, InStar: Boolean;
  out Clean: string);
var
  i, n : Integer;
  Sb   : TStringBuilder;
begin
  n := Length(Line);
  Sb := TStringBuilder.Create(n);
  try
    i := 1;
    while i <= n do
    begin
      if InBrace then
      begin
        if Line[i] = '}' then InBrace := False;
        Inc(i);
        Continue;
      end;
      if InStar then
      begin
        if (Line[i] = '*') and (i < n) and (Line[i + 1] = ')') then
        begin
          InStar := False;
          Inc(i, 2);
          Continue;
        end;
        Inc(i);
        Continue;
      end;
      case Line[i] of
        '{': begin InBrace := True; Inc(i); end;
        '(': if (i < n) and (Line[i + 1] = '*') then
             begin
               InStar := True;
               Inc(i, 2);
             end
             else
             begin
               Sb.Append('(');
               Inc(i);
             end;
        '/': if (i < n) and (Line[i + 1] = '/') then
               Break // Zeilenkommentar - Rest der Zeile weg
             else
             begin
               Sb.Append('/');
               Inc(i);
             end;
        '''':
          begin
            // String-Literal komplett schlucken ('' = Escape).
            Inc(i);
            while i <= n do
            begin
              if Line[i] = '''' then
              begin
                if (i < n) and (Line[i + 1] = '''') then
                  Inc(i, 2)
                else
                begin
                  Inc(i);
                  Break;
                end;
              end
              else
                Inc(i);
            end;
          end;
      else
        Sb.Append(Line[i]);
        Inc(i);
      end;
    end;
    Clean := Sb.ToString;
  finally
    Sb.Free;
  end;
end;

function ExtractFirstWord(const Line: string; out StartCol: Integer): string;
var
  i, n, wStart : Integer;
  c            : Char;
begin
  Result := '';
  StartCol := 0;
  n := Length(Line);
  i := 1;
  while (i <= n) and CharInSet(Line[i], [' ', #9]) do Inc(i);
  if i > n then Exit;
  c := Line[i];
  if c = '{' then Exit;
  if (c = '/') and (i < n) and (Line[i + 1] = '/') then Exit;
  if (c = '(') and (i < n) and (Line[i + 1] = '*') then Exit;
  if not CharInSet(c, ['A'..'Z','a'..'z','_']) then Exit;
  wStart := i;
  StartCol := wStart;
  while (i <= n) and CharInSet(Line[i], ['A'..'Z','a'..'z','0'..'9','_']) do
    Inc(i);
  Result := Copy(Line, wStart, i - wStart);
end;

// True wenn die Zeile ein Feld deklariert (kein procedure/function/...)
function LooksLikeField(const Line: string): Boolean;
var
  trimmed : string;
  Lower   : string;
  ColonPos: Integer;
begin
  Result := False;
  trimmed := TrimLeft(Line);
  Lower := LowerCase(trimmed);
  // Methoden / Property / Const / Constructor / Class-Methods ausschliessen
  if Lower.StartsWith('procedure ')   or Lower.StartsWith('procedure(') then Exit;
  if Lower.StartsWith('function ')    or Lower.StartsWith('function(')  then Exit;
  if Lower.StartsWith('constructor ') then Exit;
  if Lower.StartsWith('destructor ')  then Exit;
  if Lower.StartsWith('property ')    then Exit;
  if Lower.StartsWith('const ')       then Exit;
  if Lower.StartsWith('type ')        then Exit;
  if Lower.StartsWith('class ')       then Exit;
  if Lower.StartsWith('strict ')      then Exit;
  // Parameter-Modifier-Continuation-Lines ausschliessen. Multi-line Method-
  // Header schreiben gerne `out X: T; var Y: T):` auf einer Folgezeile -
  // ohne diesen Filter wird 'out' als Field-Name geflaggt.
  if Lower.StartsWith('out ')         then Exit;
  if Lower.StartsWith('var ')         then Exit;
  if Lower.StartsWith('inout ')       then Exit;
  if Lower.StartsWith('array ')       then Exit;
  // Method-Decl-Tail einer Continuation-Zeile: `): TypeName; static;`. Ein
  // `)` VOR dem `:` ist ein starkes Signal das die Zeile keine Field-Decl
  // ist, sondern der Schwanz einer mehrzeiligen Method-Signatur.
  ColonPos := Pos(':', trimmed);
  if (ColonPos > 0) and (Pos(')', Copy(trimmed, 1, ColonPos)) > 0) then Exit;
  // Param-Continuation-Tail: `Param: Type);` oder `Param: Type)` als letzte
  // Param-Zeile einer mehrzeiligen Method-Signatur. Hat `:` und `;`, aber
  // ALSO `)` IRGENDWO in der Zeile. Echte Field-Decls haben nie ')'.
  // (Edge: Methoden-Pointer-Felder `MyEvt: procedure(x: Integer);` haben '(' -
  //  die werden ueber die Inside-Parens-Continuation-Heuristik gefiltert.)
  if Pos(')', trimmed) > 0 then Exit;
  // Ein `=` in der bereinigten Zeile heisst: DEKLARATION, kein Feld.
  // Delphi kennt keinen Feld-Initialisierer in Klassen - was hier mit
  // `=` steht, ist entweder ein Nested-Type-Alias unter `public type`
  // oder eine typisierte Konstante, deren `const` auf einer eigenen
  // Zeile steht und deshalb den `const `-Praefixtest oben nicht
  // ausloest.
  // GEZAEHLT (Autopsie 2026-08-27, Korpus D:/git-sca-realworld,
  // 13.419 .pas-Dateien, 4.209 Funde): genau 39 Fundzeilen enthalten
  // nach dem Strip ein `=`, und alle 39 sind Deklarationen - kein
  // einziges Feld darunter. Wirkung -39 Funde, 0 Adds.
  //   18x Nested-Type-Alias, z.B. Alcinoe.BroadcastReceiver:26
  //       `TCreateInstanceFunc = function: TALBroadcastReceiver;`
  //       (17x Alcinoe, dazu mormot.core.threads:1070)
  //   21x typisierte Konstante, MVCFramework.JWT:99 ff.
  //       `Issuer: string = 'iss';` unter einer nackten `const`-Zeile
  //       (7 Konstanten x 3 Repo-Kopien im Korpus)
  // Der String-Strip loescht dabei den Wert, nicht das `=` - genau
  // deshalb traegt das `=` die Entscheidung und nicht der Literal-Text.
  if Pos('=', trimmed) > 0 then Exit;
  // Muss `:` und `;` enthalten - charakteristisch fuer Feld-Decl
  if (Pos(':', trimmed) = 0) then Exit;
  if (Pos(';', trimmed) = 0) then Exit;
  Result := True;
end;

function IsSectionHeadLine(const CleanTrimmed, KeywordLow: string): Boolean;
// Echte Sektionskopfzeile: das Keyword allein ODER mit bekanntem
// Sektions-Zusatz ('class var' & Co, rw13-A/B: 4 Klassenfeld-TPs).
// Geschlossene Liste - alles andere (insbesondere die FPC-Export-
// Direktive 'public name ''...''') schaltet KEINE Sektion.
const
  ZUSATZ : array[0..5] of string = (
    'var', 'const', 'type', 'class var', 'class const', 'class threadvar'
  );
var
  T, Rest : string;
  k : Integer;
begin
  T := LowerCase(StringReplace(CleanTrimmed, #9, ' ', [rfReplaceAll]));
  if T = KeywordLow then Exit(True);
  if not T.StartsWith(KeywordLow + ' ') then Exit(False);
  Rest := Trim(Copy(T, Length(KeywordLow) + 2, MaxInt));
  while Pos('  ', Rest) > 0 do
    Rest := StringReplace(Rest, '  ', ' ', [rfReplaceAll]);
  for k := 0 to High(ZUSATZ) do
    if Rest = ZUSATZ[k] then Exit(True);
  Result := False;
end;

class procedure TPublicFieldDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  Lines    : TStringList;
  Cached   : Boolean;
  i, Col   : Integer;
  Word     : string;
  Lower    : string;
  InPublic : Boolean;
  // G1 (Autopsie 2026-08-27): `published` schaltet die Sektion weiter
  // mit (sonst wuerde ein nachfolgendes Feld dem VORIGEN public-Block
  // zugerechnet), wird aber getrennt gefuehrt und nicht gemeldet.
  InPublished : Boolean;
  F        : TLeakFinding;
  // Autopsie 2026-08-26: drei neue Zustaende ueber Zeilengrenzen.
  InBrace, InStar : Boolean;   // Fix C - Blockkommentar-Zustand
  OpenParens      : Integer;   // Fix A - Klammer-Balance (Signaturen)
  WarInParens     : Boolean;
  InValueType     : Boolean;   // Fix B - record/object statt class
  Clean, CleanLow : string;
  k               : Integer;
begin
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    InPublic    := False;
    InPublished := False;
    InBrace     := False;
    InStar      := False;
    OpenParens  := 0;
    InValueType := False;
    for i := 0 to Lines.Count - 1 do
    begin
      // Fix C: ALLES arbeitet auf der kommentar-/literalfreien Zeile -
      // damit kann weder "published" aus einem GPL-Header InPublic
      // schalten noch eine Kommentar-Klammer die Balance vergiften.
      StripLineStateful(Lines[i], InBrace, InStar, Clean);
      Word := ExtractFirstWord(Clean, Col);
      if Word = '' then Continue;
      Lower := LowerCase(Word);
      CleanLow := LowerCase(Clean);
      // Fix B: Typkopf mitlesen. Oeffentliche Felder sind bei record/
      // object das Idiom - die Kapselungs-Empfehlung gilt nur fuer
      // Klassen. 'end' unten setzt den Zustand zurueck (Politik
      // "unbekannt = melden": im Zweifel Klassen-Verhalten).
      if Pos('= class', CleanLow) + Pos('=class', CleanLow) > 0 then
        InValueType := False
      else if (Pos('= record', CleanLow) + Pos('=record', CleanLow) +
               Pos('= object', CleanLow) + Pos('=object', CleanLow) +
               Pos('= packed record', CleanLow) +
               Pos('= packed object', CleanLow)) > 0 then
        InValueType := True;
      // Fix A: stand die Zeile noch in einer offenen Klammer aus einer
      // Vorzeile (mehrzeilige Signatur/Methodenzeiger-Feld), ist sie
      // eine Parameter-Fortsetzung - NIE ein Feld. Balance-Update folgt
      // UNTEN, auch fuer gemeldete Zeilen (die Kopfzeile eines
      // Funktionszeiger-FELDES ist ein echter Fund und oeffnet die
      // Klammer fuer ihre Fortsetzungen). Der fruehere Code-Kommentar
      // behauptete diese Heuristik nur - jetzt existiert sie.
      WarInParens := OpenParens > 0;
      // Der SCHALTER verlangt eine Allein-Wort-Zeile (rw12-A/B-Fund,
      // 62 Adds): 'public name ''__udivdi3''' ist die FPC-Export-
      // Direktive in '{$ifdef FPC} public name ...; {$endif}' - der
      // Kommentar-Strip legte das 'public' frei und schaltete mitten in
      // der IMPLEMENTATION eine Sektion an (lokale Vars wurden Felder,
      // mormot.lib.static x3). Eine echte Sektionszeile besteht nach dem
      // Strip NUR aus dem Keyword - ODER aus Keyword + bekanntem
      // Sektions-Zusatz: rw13-A/B fand 4 verlorene Klassenfeld-TPs
      // unter 'public class var' (vcl.skia FrameRate, alcinoe
      // FPaintStage/AniFrameRate, doublecmd isMountSupported). Die
      // Zusatzliste ist geschlossen; 'name' (FPC-Export) steht bewusst
      // NICHT drin. Der seltene Einzeiler-Stil 'public Feld: T;'
      // verliert weiterhin den Schalter - FN-Richtung, billig.
      if ((Lower = 'public') or (Lower = 'published')) and
         IsSectionHeadLine(Trim(Clean), Lower) then
      begin
        InPublic   := True;
        // G1: ZUWEISUNG, kein blosses Setzen - ein `public` nach einem
        // `published` im selben Typ muss das Flag wieder loeschen.
        // GEZAEHLT: die Setzen-ohne-Loeschen-Variante kostet 2 echte
        // TPs im Korpus (rgmain.pas:83/84, mORMot2-Beispiel: der Typ
        // wechselt published -> public -> published, und HelpMenu/
        // HelpAboutMenuItem stehen im public-Block dazwischen). Genau
        // richtig so: was der Autor aus published herausnimmt, wird vom
        // Streamer NICHT mehr gebunden - FieldAddress findet es nicht -
        // und faellt damit zurueck unter die Kapselungs-Empfehlung.
        InPublished := (Lower = 'published');
        OpenParens := 0;   // Sektionsgrenze bricht jede Drift
      end
      else if (Lower = 'private') or (Lower = 'protected') or
              (Lower = 'strict')  or (Lower = 'end') or
              // Section-Boundaries: nach 'implementation' / 'initialization' /
              // 'finalization' gibt es keine Klassen-Felder mehr. Vor v0.9.x
              // blieb InPublic True bis zum naechsten Visibility-Keyword -
              // damit wurden Methoden-Parameter (out X / var Y) in
              // multi-line Method-Headers in der Implementation faelschlich
              // als Public-Field geflaggt.
              (Lower = 'implementation') or
              (Lower = 'initialization') or
              (Lower = 'finalization') then
      begin
        InPublic    := False;
        InPublished := False;
        OpenParens  := 0;
        if Lower = 'end' then
          InValueType := False;
      end
      else
      begin
        // G1 (Autopsie 2026-08-27): published-Sektionen schweigen.
        // Ein published-Feld ist kein Kapselungsfehler, sondern die
        // einzige Form, die der DFM-Streamer laden KANN:
        // TComponent.SetReference sucht ueber Owner.FieldAddress(Name)
        // im Feld-Table - und der Compiler emittiert dieses Table nur
        // fuer published-Felder. Eine Property statt des Feldes wuerde
        // das Laden brechen; die Empfehlung waere schlicht falsch.
        // Dazu passt, dass Delphi in published ueberhaupt nur Felder
        // von Klassen-/Interface-Typ zulaesst - die Sektion existiert
        // fuer die Komponentenbindung, nicht fuer Nutzdaten.
        // GEZAEHLT (Korpus D:/git-sca-realworld, 4.209 Funde): 37 Funde
        // stehen unter einem expliziten `published`, und alle 37 sind
        // DFM-Komponentenfelder - issrc IDE.ImagesModule:20-25
        // (TImageList/TImageCollection, 6), jvcl
        // fJvHLEdPropDlgTestParams (TPageControl/TTabSheet, 8 in 4
        // Repo-Kopien), mORMot2-Beispiel rgmain:76-109 (TMenuItem/
        // TPanel/TLabel/TSplitter, 23). Wirkung -37 Funde, 0 Adds.
        // Der Normalfall - IDE-generierte Komponentenfelder in der
        // IMPLIZITEN published-Sektion ohne Keyword - war ohnehin stumm
        // (ohne Keyword bleibt InPublic False); G1 schliesst nur die
        // Luecke fuer die handgeschriebene explizite Form.
        if (not WarInParens) and InPublic and (not InPublished) and
           (not InValueType) and LooksLikeField(Clean) then
        begin
          F            := TLeakFinding.Create;
          F.FileName   := FileName;
          F.MethodName := '';
          F.LineNumber := IntToStr(i + 1);
          F.MissingVar := Format(
            'Public field `%s` - prefer a property for encapsulation ' +
            '(getter/setter can be added later without breaking callers).',
            [Word]);
          F.SetKind(fkPublicField);
          Results.Add(F);
        end;
        // Fix A, Balance-Update NACH der Melde-Entscheidung: Klammern
        // dieser (kommentar-/literalfreien) Zeile fortschreiben; nie
        // unter 0 (verirrte ')' aus Code-Fragmenten sollen die
        // Folgezeilen nicht vergiften).
        for k := 1 to Length(Clean) do
          case Clean[k] of
            '(': Inc(OpenParens);
            ')': if OpenParens > 0 then Dec(OpenParens);
          end;
      end;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
