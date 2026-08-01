unit uEmptyMethod;

// Detektor fuer Methoden ohne Anweisungen.
// Erkennt Implementations-Methoden mit leerem begin..end-Rumpf:
//
//   procedure TFoo.DoNothing;
//   begin
//   end;
//
// Abstract / virtual-Deklarationen ohne Body sind im AST gar nicht als
// Methoden mit nkBlock-Kind vertreten und werden also nicht gemeldet.
// Methoden mit nur einem 'inherited;' werden ebenfalls nicht gemeldet,
// weil das ein nkInherited-Kind im Block erzeugt.
//
// INTENT-KOMMENTAR (30%-Real-World-Audit 2026-07-31, User-Entscheidung
// 2026-08-01): ein leerer Rumpf MIT erklaerendem Kommentar ist KEIN Fund.
// Der Regeltext nennt den Kommentar selbst als konforme Loesung ("make the
// intent explicit ... or comment"), der Detektor unterschied bisher aber
// nicht zwischen ganz-leer und kommentiert-leer.
//
//   procedure TFoo.DoNothing;
//   begin
//     { do nothing - base class hook }        <-- konform, kein Fund
//   end;
//
// Kommentare zaehlen weiterhin NIE als Code-NUTZUNG (Projektregel); hier
// geht es nicht um Nutzung, sondern um die dokumentierte Absicht.
//
// Schweregrad: lsHint - kein Bug, sondern unbeabsichtigt vergessener Code
// oder uebrig gebliebener Stub.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12, uAnalyzeContext;

type
  TEmptyMethodDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil);
  private
    class function FindBodyBlock(MethodNode: TAstNode): TAstNode; static;
    // True, wenn zwischen `begin` und dem zugehoerigen `end` ein
    // inhaltlicher Kommentar steht - siehe Kopf-Kommentar.
    class function BodyHasIntentComment(Lines: TStringList;
      ABeginLine: Integer): Boolean; static;
  end;

implementation

// noinspection-file NilComparison, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  uFileTextCache;

const
  // Ein leerer Rumpf ist kurz. Die Grenze verhindert nur, dass ein
  // fehlplatzierter begin-Anker ueber die halbe Datei laeuft.
  MAX_EMPTY_BODY_LINES = 60;

class function TEmptyMethodDetector.FindBodyBlock(
  MethodNode: TAstNode): TAstNode;
var Child: TAstNode;
begin
  Result := nil;
  for Child in MethodNode.Children do
    if Child.Kind = nkBlock then
      Exit(Child);
end;

// Kommentartext einer Zeile einsammeln (Einzeilen-Formen plus der in einer
// Zeile geschlossene Blockkommentar - mehr braucht ein leerer Rumpf nicht).
//
// ROHZEILE, absichtlich: zwischen `begin` und `end` eines LEEREN Rumpfes gibt
// es keine Anweisungen und damit keine String-Literale, in denen ein '//'
// stecken koennte. Der Kontext ist eng genug fuer den direkten Scan.
function CommentTextOfLine(const ALine: string): string;
var
  p, q : Integer;
begin
  Result := '';
  p := Pos('//', ALine);
  if p > 0 then
  begin
    Result := Trim(Copy(ALine, p + 2, MaxInt));
    Exit;
  end;
  p := Pos('{', ALine);
  if p > 0 then
  begin
    q := Pos('}', ALine, p);
    if q = 0 then q := Length(ALine) + 1;
    Result := Trim(Copy(ALine, p + 1, q - p - 1));
    Exit;
  end;
  p := Pos('(*', ALine);
  if p > 0 then
  begin
    q := Pos('*)', ALine, p);
    if q = 0 then q := Length(ALine) + 1;
    Result := Trim(Copy(ALine, p + 2, q - p - 2));
  end;
end;

function CommentLooksLikeIntent(const AText: string): Boolean;
// Inhaltlich = mindestens ein Buchstabe/Ziffer. NICHT als Absicht zaehlen:
//   * Compiler-Direktiven ('{$REGION}', '{$IFDEF}') - Werkzeug, keine Aussage
//   * auskommentierter Code: endet mit ';' (Audit-Vorgabe - wer Code
//     stilllegt, dokumentiert damit keine Absicht)
var
  i        : Integer;
  HasAlnum : Boolean;
begin
  Result := False;
  if AText = '' then Exit;
  if AText[1] = '$' then Exit;
  if AText[Length(AText)] = ';' then Exit;
  HasAlnum := False;
  for i := 1 to Length(AText) do
    if CharInSet(AText[i], ['a'..'z', 'A'..'Z', '0'..'9']) then
    begin
      HasAlnum := True;
      Break;
    end;
  Result := HasAlnum;
end;

// Startposition des ersten Kommentars in der Zeile, 0 wenn keiner da ist.
function CommentStartOfLine(const ALine: string): Integer;
var
  p : Integer;
begin
  Result := 0;
  p := Pos('//', ALine);
  if (p > 0) and ((Result = 0) or (p < Result)) then Result := p;
  p := Pos('{', ALine);
  if (p > 0) and ((Result = 0) or (p < Result)) then Result := p;
  p := Pos('(*', ALine);
  if (p > 0) and ((Result = 0) or (p < Result)) then Result := p;
end;

class function TEmptyMethodDetector.BodyHasIntentComment(Lines: TStringList;
  ABeginLine: Integer): Boolean;
// WICHTIG (Funktionsprobe 2026-08-01): der Kommentar muss INNERHALB des
// Rumpfes stehen, also VOR dem `end`. Ein nachgestellter Kommentar auf der
// end-Zeile gehoert nicht mehr dazu:
//
//   procedure Foo;
//   begin
//   end;   // TFoo.Foo - Stub
//
// Der ist verbreitete Gliederung und sagt nichts ueber die Absicht des
// leeren Rumpfes. Die erste Fassung pruefte den Kommentar VOR dem
// end-Abbruch und schaltete solche Faelle mit still - die Probe fiel darauf
// herein (die Kontrolle im Probe-File trug genau so einen Kommentar).
var
  i, Last  : Integer;
  Raw      : string;
  Code     : string;
  pCmt     : Integer;
  pEnd     : Integer;
  pBegin   : Integer;
begin
  Result := False;
  if (Lines = nil) or (ABeginLine <= 0) or (ABeginLine > Lines.Count) then Exit;
  Last := ABeginLine + MAX_EMPTY_BODY_LINES;
  if Last > Lines.Count then Last := Lines.Count;
  for i := ABeginLine to Last do
  begin
    Raw  := Lines[i - 1];
    pCmt := CommentStartOfLine(Raw);
    // Code-Anteil = alles vor dem Kommentar.
    if pCmt > 0 then Code := Copy(Raw, 1, pCmt - 1) else Code := Raw;
    Code := LowerCase(Code);

    pEnd   := Pos('end', Code);
    pBegin := Pos('begin', Code);
    // Auf der begin-Zeile zaehlt nur ein `end` HINTER dem `begin`
    // ('begin { intentionally empty } end;' in einer Zeile).
    if (i = ABeginLine) and (pEnd > 0) and (pEnd < pBegin) then pEnd := 0;

    // Kommentar auswerten - aber nur, wenn er VOR dem Rumpfende steht.
    if (pCmt > 0) and (pEnd = 0) and
       CommentLooksLikeIntent(CommentTextOfLine(Raw)) then
      Exit(True);

    if pEnd > 0 then Exit;   // Rumpfende erreicht
  end;
end;

class procedure TEmptyMethodDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>;
  AContext: TAnalyzeContext);
var
  Methods : TList<TAstNode>;
  M       : TAstNode;
  Block   : TAstNode;
  Lines   : TStringList;
  Cached  : Boolean;
begin
  Methods := UnitNode.FindAll(nkMethod);
  Lines   := AcquireLines(FileName, Cached, CtxFileTextCache(AContext));
  try
    for M in Methods do
    begin
      Block := FindBodyBlock(M);
      // Kein Body-Block (Forward / Interface-Decl / abstract) - nichts melden
      if Block = nil then Continue;
      // Body hat mindestens eine Anweisung - nicht leer
      if Block.Children.Count > 0 then Continue;
      // Intent-Kommentar im Rumpf = laut Regeltext bereits konform.
      if BodyHasIntentComment(Lines, Block.Line) then Continue;

      Results.Add(TLeakFinding.New(FileName, M.Name, M.Line,
        'Method body is empty', fkEmptyMethod));
    end;
  finally
    ReleaseLines(Lines, Cached);
    Methods.Free;
  end;
end;

end.
