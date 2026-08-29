unit uDestructorWithoutInherited;

// Detektor fuer Destruktoren ohne `inherited`-Aufruf.
//
// SonarDelphi-Aequivalent: communitydelphi:DestructorWithoutInherited.
// Ein Destruktor MUSS `inherited Destroy` (oder `inherited;`) aufrufen,
// damit die Parent-Klasse aufraeumen kann (eigene Felder freigeben,
// notify-Handler abmelden, Refcounting korrekt). Vergessen -> Speicher-
// und Resource-Leaks.
//
// Erkennung: AST-basiert. Pro `nkMethod`-Knoten mit TypeRef `destructor`
// pruefen ob `nkInherited` im Body vorkommt.
//
// Schweregrad: lsError - vergessenes `inherited` im Destruktor ist
// fast immer ein Leak.
//
// FP-Gates:
//   * PScript-Stub-Files (>=5 leere Bodies, >70% Ratio) - siehe AnalyzeUnit.
//   * Codegen-Template-Dateien mit '<#Platzhalter>'-Tokens (2026-07-31) -
//     siehe IsCodegenTemplateFile.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TDestructorWithoutInheritedDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  end;

implementation

// noinspection-file NilComparison, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.Classes, System.StrUtils,
  uTypeIndex,        // ParentOf/TypeKindOf - Basisklasse des Destruktors
                     // (uAnalyzeContext steht bereits im interface-uses)
  uFileTextCache;

const
  EMIT_SEVERITY = lsError;

function ErbtDirektVonTObject(const AMethodName: string;
  AContext: TAnalyzeContext): Boolean;
// True, wenn die Klasse des Destruktors DIREKT von TObject erbt.
//
// WARUM DAS ZAEHLT (Kundenkorpus SVGIconImageList, 29.08.): dort waren
// FUENF der 18 Error-Funde von dieser Art - TRectClip64, 
// TCustomRendererCache, TFloodFillStack, TSvgParser, TWSVGGraphicFilter,
// alle "= class" oder "= class(TObject)". Bei direkter TObject-Ableitung
// ist TObject.Destroy LEER: das fehlende inherited ueberspringt nichts,
// die Meldung "parent class cleanup is skipped, likely leak" trifft
// nicht zu. Als lsError ("bewiesen") ist das zu hoch gegriffen.
//
// KEIN Drop: der Konventionsbruch bleibt real und wird in dem Moment zum
// Fehler, in dem jemand eine Zwischenklasse einzieht. Deshalb nur
// Konfidenz herunter (fcHigh -> fcMedium = Warnung statt Fehler).
//
// Ohne TypeIndex (nil) oder ohne Klassennamen wird NICHT demotet - im
// Zweifel bleibt der Fund so streng wie bisher.
var
  Punkt : Integer;
  Klasse, Eltern : string;
  Idx : TTypeIndex;
begin
  Result := False;
  Idx := CtxTypeIndex(AContext);
  if Idx = nil then Exit;
  Punkt := Pos('.', AMethodName);
  if Punkt <= 1 then Exit;   // kein qualifizierter Name -> kein Urteil
  Klasse := LowerCase(Copy(AMethodName, 1, Punkt - 1));
  Eltern := Idx.ParentOf(Klasse);
  // Leer = kein Parent im Index. Das heisst "class" ohne Basis, also
  // implizit TObject - genau der Fall. Eine unbekannte Klasse liefert
  // ebenfalls leer, deshalb steht die Kind-Pruefung davor.
  if Idx.TypeKindOf(Klasse) <> tkiClass then Exit;
  Result := (Eltern = '') or (Eltern = 'tobject');
end;

function IsDestructor(MethodNode: TAstNode): Boolean; inline;
var
  TR : string;
begin
  TR := LowerCase(Trim(MethodNode.TypeRef));
  // `class destructor` ist ein Klassen-Initialisierungs-Mechanismus (laeuft
  // einmal pro Klasse beim Modul-Unload) - hat KEINE inheritance chain und
  // braucht daher KEIN `inherited`. Parser markiert die mit ';class'-Suffix
  // im TypeRef (sowohl in der Class-Body- als auch in der Implementation-
  // Section). Skip wenn dieser Marker vorhanden.
  if Pos(';class', TR) > 0 then Exit(False);
  Result := TR.StartsWith('destructor');
end;

function IsClassDestructorByLine(const FileName: string;
  LineNo: Integer; AContext: TAnalyzeContext): Boolean;
// Fallback wenn der Parser die ';class'-Markierung verfehlt
// (z.B. MVCFramework.Commons.pas TMVCSqids.Destroy). Liest die Source-Zeile
// und prueft auf 'class destructor' am linken Rand (Whitespace egal).
var
  Lines : TStringList;
  Cached : Boolean;
  Line : string;
  Trimmed : string;
begin
  Result := False;
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;
  try
    if (LineNo < 1) or (LineNo > Lines.Count) then Exit;
    Line := Lines[LineNo - 1];
    Trimmed := LowerCase(TrimLeft(Line));
    Result := StartsStr('class destructor', Trimmed);
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

// ---------------------------------------------------------------------------
// FP-Gate (2026-07-31, 30%-Real-World-Audit sca-rw-after119)
// FP-Klasse: Codegen-Template-Dateien (.pas mit '<#Platzhalter>'-Tokens).
// Beleg: cnwizards/Bin/Data/Templates/CnIniFiler_Section.pas:75 - Zeile 77
// lautet '<#IniSectionsFree>  inherited;', das `inherited` IST also textuell
// da. Mechanismus: die Nicht-Pascal-Platzhalter brechen Lexer/Parser, der
// Destruktor-Rumpf kommt als Phantom/leer an und HasInheritedCall sieht
// nichts (gleiche Familie wie die bekannten Phantom-Rumpf-Quellen). Ohne
// parsebaren Rumpf gibt es kein Urteil -> in solchen Dateien feuert SCA097
// gar nicht.
// ---------------------------------------------------------------------------

// Entfernt String-Literale und Kommentare aus EINER Quellzeile. InBrace /
// InParenStar tragen den Kommentar-Zustand ueber Zeilengrenzen (Block-
// Kommentare). Bewusst lokal in dieser Unit: der Gate darf keine geteilte
// Infrastruktur mitziehen.
function StripCodeLine(const Line: string; var InBrace, InParenStar: Boolean): string;
var
  i, N  : Integer;
  InStr : Boolean;
begin
  Result := '';
  InStr  := False;
  N      := Length(Line);
  i      := 1;
  while i <= N do
  begin
    if InBrace then
    begin
      if Line[i] = '}' then InBrace := False;
      Inc(i);
      Continue;
    end;
    if InParenStar then
    begin
      if (Line[i] = '*') and (i < N) and (Line[i + 1] = ')') then
      begin
        InParenStar := False;
        Inc(i, 2);
        Continue;
      end;
      Inc(i);
      Continue;
    end;
    if InStr then
    begin
      // Verdoppeltes Hochkomma faellt korrekt heraus: das erste schliesst,
      // das zweite oeffnet wieder - Netto-Ergebnis identisch.
      if Line[i] = '''' then InStr := False;
      Inc(i);
      Continue;
    end;
    if Line[i] = '''' then begin InStr := True; Inc(i); Continue; end;
    if Line[i] = '{'  then begin InBrace := True; Inc(i); Continue; end;
    if (Line[i] = '(') and (i < N) and (Line[i + 1] = '*') then
    begin
      InParenStar := True;
      Inc(i, 2);
      Continue;
    end;
    if (Line[i] = '/') and (i < N) and (Line[i + 1] = '/') then Break;
    Result := Result + Line[i];
    Inc(i);
  end;
end;

// True wenn im (bereits gestrippten) Code ein Template-Platzhalter der Form
// '<#Bezeichner>' steht. BEWUSST eng: nach '<#' muss ein Buchstabe oder '_'
// kommen und der Token muss mit '>' schliessen. Damit faellt der legale
// Delphi-Ausdruck 'if c<#13 then' (Char-Literal-Vergleich, ZIFFER nach '#')
// nicht darunter.
function HasTemplatePlaceholder(const Code: string): Boolean;
var
  i, j, N : Integer;
begin
  Result := False;
  N := Length(Code);
  i := 1;
  while i < N do
  begin
    if (Code[i] = '<') and (Code[i + 1] = '#') then
    begin
      j := i + 2;
      if (j <= N) and CharInSet(Code[j], ['A'..'Z', 'a'..'z', '_']) then
      begin
        Inc(j);
        while (j <= N) and
              CharInSet(Code[j], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(j);
        if (j <= N) and (Code[j] = '>') then Exit(True);
      end;
    end;
    Inc(i);
  end;
end;

function IsCodegenTemplateFile(const FileName: string;
  AContext: TAnalyzeContext): Boolean;
var
  Lines            : TStringList;
  Cached           : Boolean;
  i                : Integer;
  InBrace, InParen : Boolean;
begin
  Result := False;
  Lines := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  if Lines = nil then Exit;   // nicht lesbar -> kein Urteil, altes Verhalten
  try
    InBrace := False;
    InParen := False;
    for i := 0 to Lines.Count - 1 do
      if HasTemplatePlaceholder(StripCodeLine(Lines[i], InBrace, InParen)) then
        Exit(True);
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

// Liefert den Body-Block (nkBlock) der Methode oder nil wenn keiner da
// ist. Forward-Deklarationen in Class-Bodies (`destructor Destroy;
// override;`) sind nkMethod-Knoten ohne nkBlock - wir muessen die
// ausnehmen, sonst feuert der Detektor auf der Signatur statt auf der
// Implementierung. Pattern aus uEmptyMethod uebernommen.
function FindBodyBlock(MethodNode: TAstNode): TAstNode;
var Child: TAstNode;
begin
  Result := nil;
  for Child in MethodNode.Children do
    if Child.Kind = nkBlock then Exit(Child);
end;

function HasInheritedCall(Node: TAstNode): Boolean;
var
  Child : TAstNode;
begin
  Result := False;
  if Node = nil then Exit;
  if Node.Kind = nkInherited then Exit(True);
  for Child in Node.Children do
    if HasInheritedCall(Child) then Exit(True);
end;

// True wenn der Method-Body effektiv leer ist (`begin end;` ohne
// irgendein Statement). Wird fuer den PScript-Stub-File-Skip benutzt.
function IsEffectivelyEmptyBody(MethodNode: TAstNode): Boolean;
var
  Child : TAstNode;
  GrandChild : TAstNode;
begin
  Result := True;
  for Child in MethodNode.Children do
  begin
    case Child.Kind of
      nkBlock:
        for GrandChild in Child.Children do
          if GrandChild.Kind in [nkAssign, nkCall, nkIfStmt, nkCaseStmt,
                                  nkForStmt, nkWhileStmt, nkRepeatStmt,
                                  nkTryExcept, nkTryFinally, nkRaise, nkExit,
                                  nkBreak, nkContinue, nkInherited] then
            Exit(False);
      nkAssign, nkCall, nkIfStmt, nkCaseStmt, nkForStmt, nkWhileStmt,
      nkRepeatStmt, nkTryExcept, nkTryFinally, nkRaise, nkExit,
      nkBreak, nkContinue, nkInherited:
        Exit(False);
    end;
  end;
end;

class procedure TDestructorWithoutInheritedDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
// Real-World-Sweep 2026-06-13: cnwizards/Bin/PSDeclEx/CnWizClasses.pas
// 6 SCA097 FPs - alle leere Destructor-Bodies in PScript-Bridge-Stubs.
// Gleiche Heuristik wie uRoutineResultAssigned: wenn >=5 effektiv-
// leere Method-Bodies UND >70% empty/total Ratio in der Unit, dann
// PScript-Stub-File und keine Findings emittieren.
const
  STUB_FILE_MIN_EMPTY   = 5;
  STUB_FILE_RATIO_LIMIT = 0.7;
var
  Methods           : TList<TAstNode>;
  M                 : TAstNode;
  F                 : TLeakFinding;
  EmptyCount, Total : Integer;
  // Template-Gate (2026-07-31): LAZY - erst pruefen wenn wirklich ein Fund
  // anstehen wuerde. Sonst zahlte jede saubere Datei den Zeilen-Scan.
  TemplateChecked   : Boolean;
  IsTemplate        : Boolean;
begin
  TemplateChecked := False;
  IsTemplate      := False;
  Methods := UnitNode.FindAll(nkMethod);
  try
    EmptyCount := 0;
    Total      := 0;
    for M in Methods do
    begin
      if FindBodyBlock(M) = nil then Continue;
      Inc(Total);
      if IsEffectivelyEmptyBody(M) then Inc(EmptyCount);
    end;
    if (EmptyCount >= STUB_FILE_MIN_EMPTY) and (Total > 0) and
       (EmptyCount / Total > STUB_FILE_RATIO_LIMIT) then
      Exit;  // PScript-Stub-File - keine Findings emittieren

    for M in Methods do
    begin
      if not IsDestructor(M) then Continue;
      // Nur echte Implementierungen pruefen - Forward-Decls in Class-Bodies
      // haben kein nkBlock und wuerden sonst falsch-positiv anschlagen.
      if FindBodyBlock(M) = nil then Continue;
      // Source-Line-Fallback: Parser verfehlt manchmal die ';class'-
      // Markierung bei impl-level class-destructors (MVCFramework.Commons
      // TMVCSqids.Destroy). Direkt am Source pruefen.
      if IsClassDestructorByLine(FileName, M.Line, AContext) then Continue;
      if HasInheritedCall(M) then Continue;
      // FP-Gate (2026-07-31): Codegen-Template-Datei - der Rumpf ist nicht
      // parsebar, also kein Urteil ueber ein fehlendes `inherited`.
      // Datei-weit, weil ein gebrochener Lexer-Zustand nicht auf den einen
      // Destruktor beschraenkt ist (Beleg CnIniFiler_Section.pas).
      if not TemplateChecked then
      begin
        TemplateChecked := True;
        IsTemplate      := IsCodegenTemplateFile(FileName, AContext);
      end;
      if IsTemplate then Exit;
      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := M.Name;
      F.LineNumber := IntToStr(M.Line);
      F.MissingVar := 'Destructor has no `inherited` call - parent ' +
        'class cleanup is skipped, likely leak. Add `inherited Destroy;` ' +
        'or `inherited;` at the end of the body.';
      if ErbtDirektVonTObject(M.Name, AContext) then
        // TObject.Destroy ist leer - Konventionsbruch, kein Leck.
        F.SetKind(fkDestructorWithoutInherited, fcMedium)
      else
        F.SetKind(fkDestructorWithoutInherited);
      Results.Add(F);
    end;
  finally
    Methods.Free;
  end;
end;

end.
