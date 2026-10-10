unit uRdxStructFixes;

// reDelphix - Editorhilfen der Stufe 3 (Konzept_Editorhilfen_2026-10-08):
// Planer an Strukturen ueber mehrere Token oder Zeilen, OHNE ToolsAPI und
// ohne Parser. Die Bereiche der uses-Eintraege liefert der Aufrufer
// (TSourcePlaces.UsesEntries); alles andere liest die Code-Sicht.
//   SCA007 UnusedUses: einen Eintrag aus der uses-Klausel loeschen.
//   SCA168 DefaultCaseInCaseStatement: vor das end des case ein else setzen
//          - leer oder mit raise (Nico 2026-10-10: beide als Eintraege).
//
// GRUNDSATZ wie in uRdxSimpleFixes: lieber keine Hilfe als eine falsche.
// Geloescht wird nichts, was einen Kommentar oder eine Direktive traegt -
// ausser dem '//'-Kommentar hinter einem Eintrag, der allein auf seiner
// Zeile steht (er gehoert zum Eintrag).

interface

uses
  System.SysUtils,
  uRefactorInfo, uRdxBufferMath, uRdxCodeMap;

const
  // Die raise-Variante von SCA168 (Katalog-Beispiel). EProgrammerError
  // steht in System.SysUtils; FPC kennt die Klasse nicht - der Aufrufer
  // sperrt die Variante dort.
  RAISE_UNHANDLED = 'raise EProgrammerError.Create(''Unhandled case'');';

type
  // Eine uses-Klausel: die Eintraege (TSourcePlaces.UsesEntries, in
  // Quelltext-Reihenfolge) und die Zeile des Schluesselworts 'uses'.
  TRdxUsesClause = record
    Entries  : TArray<TRefactorSpan>;
    UsesLine : Integer;
  end;

  TRdxStructFixes = class
  public
    // SCA007: den Eintrag AIndex der Klausel loeschen. Vor dem letzten
    // Eintrag: bis zum Anfang des naechsten (Name, 'in'-Pfad, Komma,
    // Leerraum) - steht er allein auf seiner Zeile, die ganze Zeile samt
    // '//'-Kommentar; der letzte: ab dem Komma davor bis vor das ';'; der
    // einzige: die ganze Klausel ab 'uses' bis hinter ';' - ganze Zeilen,
    // wenn sie allein stehen. Kein Kommentar und keine Direktive im
    // Bereich, und darin steht genau dieser Eintrag mit einem Trenner (ein
    // Eintrag, den UsesEntries ausliess, ginge sonst mit).
    class function RemoveUsesEntry(AMap: TRdxCodeMap;
      const AClause: TRdxUsesClause; AIndex: Integer; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // SCA168: ein else vor das end des case-Statements auf Zeile ALine
    // (genau ein 'case' im Code der Zeile). AStatement = '': leer ('else'
    // vor 'end', bedeutungsgleich); sonst diese Anweisung im else-Zweig
    // (RAISE_UNHANDLED), eingerueckt wie die Arme. Das end findet ein
    // Token-Lauf (begin/case/try/asm/record zaehlen hoch, end herunter;
    // '&End' und '@@End' nicht). Endet der letzte Arm nicht auf ';', kommt
    // als zweite Ersetzung ein ';' dahinter - sonst bande das else an ein
    // offenes if ('1: if B then DoA' + 'else'). Keine Hilfe bei einer
    // Direktive zwischen case und end, bei einem else oder (FPC) otherwise
    // hinter ';' und bei einem case ohne Zweige.
    class function CaseElse(AMap: TRdxCodeMap; ALine: Integer;
      const AStatement: string; out AEdits: TArray<TRdxEdit>;
      out AReason: string): Boolean; static;
  end;

implementation

const
  SPAN_007 = 'sca007';
  SPAN_168 = 'sca168';
  // Token, die ein eigenes 'end' brauchen (Bilanz in MatchingEnd).
  END_OPENERS: array[0..4] of string = ('begin', 'case', 'try', 'asm',
    'record');

type
  // Code-Token eines Bereichs nach Art (CountRangeTokens).
  TRangeTokens = record
    Words  : Integer;   // ohne 'in' und 'uses'
    Dots   : Integer;
    Commas : Integer;
    Semis  : Integer;
    Others : Integer;
  end;

function IsEndOpener(const ALow: string): Boolean;
var
  S : string;
begin
  Result := False;
  for S in END_OPENERS do
    if ALow = S then
      Exit(True);
end;

// Der Text des Bereichs, Zeilen mit #10 verbunden - so, wie
// TRdxEdit.Expected ihn erwartet.
function RangeText(AMap: TRdxCodeMap; const ASpan: TRefactorSpan): string;
var
  SB : TStringBuilder;
  Li : Integer;
begin
  if ASpan.StartLine = ASpan.EndLine then
    Exit(Copy(AMap.Raw(ASpan.StartLine), ASpan.StartCol,
      ASpan.EndCol - ASpan.StartCol));
  SB := TStringBuilder.Create;
  try
    SB.Append(Copy(AMap.Raw(ASpan.StartLine), ASpan.StartCol, MaxInt));
    for Li := ASpan.StartLine + 1 to ASpan.EndLine - 1 do
      SB.Append(#10).Append(AMap.Raw(Li));
    SB.Append(#10).Append(Copy(AMap.Raw(ASpan.EndLine), 1, ASpan.EndCol - 1));
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// Kommentar oder Direktive im Bereich?
function CommentInRange(AMap: TRdxCodeMap; const ASpan: TRefactorSpan): Boolean;
var
  Li, First, Last : Integer;
begin
  Result := False;
  for Li := ASpan.StartLine to ASpan.EndLine do
  begin
    First := 1;
    if Li = ASpan.StartLine then
      First := ASpan.StartCol;
    Last := Length(AMap.Raw(Li));
    if Li = ASpan.EndLine then
      Last := ASpan.EndCol - 1;
    if AMap.HasComment(Li, First, Last) then
      Exit(True);
  end;
end;

{ ---- SCA007 ---- }

// Das Token hinter dem uses-Eintrag: ',' oder ';' - ein 'in'-Pfad
// dazwischen ('X in ''x.pas''') wird uebersprungen (Strings sieht der
// Token-Leser nicht).
function SeparatorAfter(AMap: TRdxCodeMap; const AEntry: TRefactorSpan): TRdxToken;
begin
  Result := NextToken(AMap, AEntry.EndLine, AEntry.EndCol);
  if Result.Low = 'in' then
    Result := After(AMap, Result);
end;

// Der einzige Eintrag: die ganze Klausel ab 'uses' (auf Zeile AUsesLine)
// bis hinter ASemi; stehen 'uses' am Zeilenanfang und hinter ';' nur
// Leerraum, ganze Zeilen. '' oder der Grund.
function WholeClauseSpan(AMap: TRdxCodeMap; AUsesLine: Integer;
  const ASemi: TRdxToken; out ASpan: TRefactorSpan): string;
var
  T : TRdxToken;
begin
  Result := '';
  ASpan := Default(TRefactorSpan);
  T := NextToken(AMap, AUsesLine, 1);
  while (T.Low <> '') and (T.Line = AUsesLine) and (T.Low <> 'uses') do
    T := After(AMap, T);
  if (T.Low <> 'uses') or (T.Line <> AUsesLine) then
    Exit('Schluesselwort uses nicht auf der erwarteten Zeile');
  ASpan := TRefactorSpan.Make(SPAN_007, T.Line, T.Col, ASemi.Line, ASemi.EndCol);
  if (SkipBlanks(AMap.Raw(T.Line), 1) = T.Col)
     and (Trim(Copy(AMap.Raw(ASemi.Line), ASemi.EndCol, MaxInt)) = '')
     and (ASemi.Line < AMap.LineCount) then
    ASpan := TRefactorSpan.Make(SPAN_007, T.Line, 1, ASemi.Line + 1, 1);
end;

// Der zu loeschende Bereich des Eintrags AIndex (s. RemoveUsesEntry);
// ASep ist das Token hinter ihm. '' oder der Grund.
function EntrySpan(AMap: TRdxCodeMap; const AClause: TRdxUsesClause;
  AIndex: Integer; const ASep: TRdxToken; out ASpan: TRefactorSpan): string;
var
  E    : TArray<TRefactorSpan>;
  Prev : TRdxToken;
begin
  Result := '';
  ASpan := Default(TRefactorSpan);
  E := AClause.Entries;
  if Length(E) = 1 then
  begin
    if ASep.Low <> ';' then
      Exit('hinter dem einzigen Eintrag steht kein ";"');
    Exit(WholeClauseSpan(AMap, AClause.UsesLine, ASep, ASpan));
  end;
  if AIndex < High(E) then
  begin
    if ASep.Low <> ',' then
      Exit('hinter dem Eintrag steht kein ","');
    ASpan := TRefactorSpan.Make(SPAN_007, E[AIndex].StartLine,
      E[AIndex].StartCol, E[AIndex + 1].StartLine, E[AIndex + 1].StartCol);
    Exit;
  end;
  Prev := SeparatorAfter(AMap, E[AIndex - 1]);
  if (Prev.Low <> ',') or (ASep.Low <> ';') then
    Exit('Komma vor bzw. Semikolon hinter dem letzten Eintrag nicht gefunden');
  ASpan := TRefactorSpan.Make(SPAN_007, Prev.Line, Prev.Col, ASep.Line, ASep.Col);
end;

// Steht der Eintrag allein auf seiner Zeile - davor nur Leerraum, dahinter
// sein ',' und hoechstens ein '//'-Kommentar (Stil 'System.Classes,
// // Grund')?
function OwnLine(AMap: TRdxCodeMap; const AEntry: TRefactorSpan;
  const ASep: TRdxToken): Boolean;
var
  L    : string;
  Rest : Integer;
begin
  L := AMap.Raw(AEntry.StartLine);
  Rest := SkipBlanks(L, ASep.EndCol);
  Result := (SkipBlanks(L, 1) = AEntry.StartCol) and (ASep.Low = ',')
    and (ASep.Line = AEntry.StartLine) and (AEntry.StartLine < AMap.LineCount)
    and ((Rest > Length(L)) or (Rest = AMap.LineCommentCol(AEntry.StartLine)));
end;

// Die Code-Token im Bereich nach Art gezaehlt (Strings und Kommentare
// sieht der Token-Leser nicht).
function CountRangeTokens(AMap: TRdxCodeMap;
  const ASpan: TRefactorSpan): TRangeTokens;
var
  T : TRdxToken;
begin
  Result := Default(TRangeTokens);
  T := NextToken(AMap, ASpan.StartLine, ASpan.StartCol);
  while (T.Low <> '') and ((T.Line < ASpan.EndLine)
     or ((T.Line = ASpan.EndLine) and (T.Col < ASpan.EndCol))) do
  begin
    if T.Low = '.' then
      Inc(Result.Dots)
    else if T.Low = ',' then
      Inc(Result.Commas)
    else if T.Low = ';' then
      Inc(Result.Semis)
    else if not T.IsWord then
      Inc(Result.Others)
    else if (T.Low <> 'in') and (T.Low <> 'uses') then
      Inc(Result.Words);
    T := After(AMap, T);
  end;
end;

// Darf ASpan geloescht werden? Kein Kommentar und keine Direktive in
// ACheck, und in ASpan steht genau der Eintrag AName (seine Namensteile)
// mit einem Trenner. '' oder der Grund.
function RangeReason(AMap: TRdxCodeMap; const ASpan, ACheck: TRefactorSpan;
  const AName: string): string;
var
  C        : TRangeTokens;
  Parts, i : Integer;
begin
  Result := '';
  if CommentInRange(AMap, ACheck) then
    Exit('Kommentar oder Direktive im zu loeschenden Bereich');
  Parts := 1;
  for i := 1 to Length(AName) do
    if AName[i] = '.' then
      Inc(Parts);
  C := CountRangeTokens(AMap, ASpan);
  if (C.Words <> Parts) or (C.Dots <> Parts - 1) or (C.Others <> 0)
     or (C.Commas + C.Semis <> 1) then
    Result := 'im Bereich steht mehr als dieser Eintrag - ginge ein '
      + 'weiterer mit? Datei neu pruefen';
end;

class function TRdxStructFixes.RemoveUsesEntry(AMap: TRdxCodeMap;
  const AClause: TRdxUsesClause; AIndex: Integer; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  E           : TRefactorSpan;
  Sep         : TRdxToken;
  Span, Check : TRefactorSpan;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  if (AIndex < 0) or (AIndex > High(AClause.Entries)) then
  begin
    AReason := 'kein solcher uses-Eintrag';
    Exit;
  end;
  E := AClause.Entries[AIndex];
  Sep := SeparatorAfter(AMap, E);
  AReason := EntrySpan(AMap, AClause, AIndex, Sep, Span);
  if AReason <> '' then Exit;
  Check := Span;
  if (AIndex < High(AClause.Entries)) and OwnLine(AMap, E, Sep) then
  begin
    Span := TRefactorSpan.Make(SPAN_007, E.StartLine, 1, E.StartLine + 1, 1);
    Check := TRefactorSpan.Make(SPAN_007, E.StartLine, 1, E.StartLine,
      Sep.EndCol);
  end;
  AReason := RangeReason(AMap, Span, Check, E.Resolved);
  if AReason <> '' then Exit;
  AEdit.Span := Span;
  AEdit.Expected := RangeText(AMap, Span);
  AEdit.NewText := '';
  Result := True;
end;

{ ---- SCA168 ---- }

// Das eine 'case' im Code der Zeile ALine. '' oder der Grund.
function CaseTokenOn(AMap: TRdxCodeMap; ALine: Integer;
  out ACase: TRdxToken): string;
var
  T : TRdxToken;
  n : Integer;
begin
  Result := '';
  ACase := Default(TRdxToken);
  n := 0;
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if T.Low = 'case' then
    begin
      Inc(n);
      ACase := T;
    end;
    T := After(AMap, T);
  end;
  if n = 0 then
    Result := 'kein case auf der gemeldeten Zeile - Zeile verschoben? Datei '
      + 'neu pruefen'
  else if n > 1 then
    Result := Format('Zeile %d traegt %d case-Anweisungen - mehrdeutig',
      [ALine, n]);
end;

// Auf oberster Ebene des case hinter ';': ein else ist schon sein Zweig (ein
// if-else in einem Arm steht nie hinter ';'), 'otherwise' der FPC-Zweig.
// '' oder der Grund.
function TopLevelReason(const T, APrev: TRdxToken): string;
begin
  Result := '';
  if APrev.Low <> ';' then Exit;
  if T.Low = 'else' then
    Result := 'das case hat schon einen else-Zweig'
  else if T.Low = 'otherwise' then
    Result := 'das case hat einen otherwise-Zweig (FPC)';
end;

// Ein Schritt der Bilanz: ADepth fortschreiben; '' oder der Grund zum
// Abbruch. '&End' und '@@End' (asm-Label) sind Bezeichner, keine
// Schluesselwoerter.
function BalanceStep(const T, APrev: TRdxToken; var ADepth: Integer): string;
begin
  Result := '';
  if (APrev.Low = '&') or (APrev.Low = '@') then Exit;
  if IsEndOpener(T.Low) then
    Inc(ADepth)
  else if T.Low = 'end' then
    Dec(ADepth)
  else if ADepth = 1 then
    Result := TopLevelReason(T, APrev);
end;

// Das end zum case ACase und das Token davor (ALast). '' oder der Grund.
function MatchingEnd(AMap: TRdxCodeMap; const ACase: TRdxToken;
  out AEnd, ALast: TRdxToken): string;
var
  T, Prev : TRdxToken;
  Depth   : Integer;
begin
  Result := '';
  AEnd := Default(TRdxToken);
  ALast := Default(TRdxToken);
  Depth := 1;
  Prev := ACase;
  T := After(AMap, ACase);
  while T.Low <> '' do
  begin
    Result := BalanceStep(T, Prev, Depth);
    if Result <> '' then Exit;
    if Depth = 0 then
    begin
      AEnd := T;
      ALast := Prev;
      Exit;
    end;
    Prev := T;
    T := After(AMap, T);
  end;
  Result := 'kein end zum case gefunden';
end;

// Eine Einrueckstufe: was die Zeile des letzten Arms (AArmLine) ueber
// AIndent hinaus einrueckt; sonst ein Tab, wenn AIndent Tabs traegt, oder
// zwei Leerzeichen.
function IndentStep(const AIndent, AArmLine: string): string;
var
  ArmIndent : string;
begin
  ArmIndent := Copy(AArmLine, 1, SkipBlanks(AArmLine, 1) - 1);
  if (Length(ArmIndent) > Length(AIndent))
     and (Copy(ArmIndent, 1, Length(AIndent)) = AIndent) then
    Exit(Copy(ArmIndent, Length(AIndent) + 1, MaxInt));
  Result := '  ';
  if Pos(#9, AIndent) > 0 then
    Result := #9;
end;

// Der Ersatz fuer das end: steht es am Zeilenanfang, das else in eigener
// Zeile mit derselben Einrueckung (AStatement eine Stufe tiefer), sonst
// inline vor dem end.
function ElseText(const ALine: string; const AEnd: TRdxToken;
  const AStatement, AArmLine: string): string;
var
  Indent, EndText : string;
begin
  EndText := Copy(ALine, AEnd.Col, AEnd.Len);
  if SkipBlanks(ALine, 1) <> AEnd.Col then
  begin
    Result := 'else ';
    if AStatement <> '' then
      Result := Result + AStatement + ' ';
    Exit(Result + EndText);
  end;
  Indent := Copy(ALine, 1, AEnd.Col - 1);
  Result := 'else' + #10;
  if AStatement <> '' then
    Result := Result + Indent + IndentStep(Indent, AArmLine) + AStatement + #10;
  Result := Result + Indent + EndText;
end;

// Das letzte Zeichen aus Code oder String vor ATok (Kommentare und
// Leerraum uebersprungen) - dort endet der letzte Arm. Der Token-Leser
// genuegt nicht: er sieht Strings nicht ('1: S := ''x''' endet auf dem
// Quote, nicht auf ':='). False am Dateianfang.
function LastCharBefore(AMap: TRdxCodeMap; const ATok: TRdxToken;
  out ALine, ACol: Integer): Boolean;
var
  Li, Co : Integer;
  L      : string;
begin
  Result := False;
  ALine := 0;
  ACol := 0;
  for Li := ATok.Line downto 1 do
  begin
    L := AMap.Raw(Li);
    Co := Length(L);
    if Li = ATok.Line then
      Co := ATok.Col - 1;
    while (Co >= 1) and ((AMap.ClassAt(Li, Co) = 'k') or IsBlank(L[Co])) do
      Dec(Co);
    if Co >= 1 then
    begin
      ALine := Li;
      ACol := Co;
      Exit(True);
    end;
  end;
end;

// Endet der letzte Arm vor AEnd nicht auf ';' (im Code), ein ';' hinter
// sein letztes Zeichen - als eigene Ersetzung (das Zeichen wird mit ';'
// dahinter neu geschrieben, ein leerer Erwartungstext ist nicht erlaubt).
procedure AppendSemicolon(AMap: TRdxCodeMap; const AEnd: TRdxToken;
  var AEdits: TArray<TRdxEdit>);
var
  Li, Co : Integer;
  E      : TRdxEdit;
begin
  if not LastCharBefore(AMap, AEnd, Li, Co) then Exit;
  E := Default(TRdxEdit);
  E.Expected := Copy(AMap.Raw(Li), Co, 1);
  if (E.Expected = ';') and AMap.IsCode(Li, Co) then Exit;
  E.Span := TRefactorSpan.Make(SPAN_168, Li, Co, Li, Co + 1);
  E.NewText := E.Expected + ';';
  SetLength(AEdits, Length(AEdits) + 1);
  AEdits[High(AEdits)] := E;
end;

class function TRdxStructFixes.CaseElse(AMap: TRdxCodeMap; ALine: Integer;
  const AStatement: string; out AEdits: TArray<TRdxEdit>;
  out AReason: string): Boolean;
var
  CaseTok, EndTok, LastTok : TRdxToken;
  L                        : string;
begin
  Result := False;
  AEdits := nil;
  EndTok := Default(TRdxToken);
  LastTok := Default(TRdxToken);
  AReason := CaseTokenOn(AMap, ALine, CaseTok);
  if AReason = '' then
    AReason := MatchingEnd(AMap, CaseTok, EndTok, LastTok);
  if (AReason = '') and (LastTok.Low = 'of') then
    AReason := 'das case hat keine Zweige';
  if (AReason = '') and DirectiveBefore(AMap, CaseTok.Line, EndTok) then
    AReason := 'Compiler-Direktive im case - ein Zweig koennte die '
      + 'end-Bilanz verschieben';
  if AReason <> '' then Exit;
  L := AMap.Raw(EndTok.Line);
  SetLength(AEdits, 1);
  AEdits[0].Span := TRefactorSpan.Make(SPAN_168, EndTok.Line, EndTok.Col,
    EndTok.Line, EndTok.EndCol);
  AEdits[0].Expected := Copy(L, EndTok.Col, EndTok.Len);
  AEdits[0].NewText := ElseText(L, EndTok, AStatement, AMap.Raw(LastTok.Line));
  AppendSemicolon(AMap, EndTok, AEdits);
  Result := True;
end;

end.
