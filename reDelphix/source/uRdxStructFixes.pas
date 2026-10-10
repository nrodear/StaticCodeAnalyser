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
// Geloescht wird nichts, was einen Kommentar oder eine Direktive traegt.

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
    // Leerraum); der letzte: ab dem Komma davor bis vor das ';'; der
    // einzige: die ganze Klausel ab 'uses' bis hinter ';' - ganze Zeilen,
    // wenn sie allein stehen. Kein Kommentar und keine Direktive im Bereich.
    class function RemoveUsesEntry(AMap: TRdxCodeMap;
      const AClause: TRdxUsesClause; AIndex: Integer; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // SCA168: ein else vor das end des case-Statements auf Zeile ALine
    // (genau ein 'case' im Code der Zeile). AStatement = '': leer ('else'
    // vor 'end', bedeutungsgleich); sonst diese Anweisung im else-Zweig
    // (RAISE_UNHANDLED). Das end
    // findet ein Token-Lauf (begin/case/try/asm/record zaehlen hoch, end
    // herunter). Keine Hilfe bei einer Direktive zwischen case und end (ein
    // Zweig koennte die Bilanz verschieben) und wenn schon ein else hinter
    // einem ';' steht.
    class function CaseElse(AMap: TRdxCodeMap; ALine: Integer;
      const AStatement: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

implementation

const
  SPAN_007 = 'sca007';
  SPAN_168 = 'sca168';
  // Token, die ein eigenes 'end' brauchen (Bilanz in MatchingEnd).
  END_OPENERS: array[0..4] of string = ('begin', 'case', 'try', 'asm',
    'record');

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

class function TRdxStructFixes.RemoveUsesEntry(AMap: TRdxCodeMap;
  const AClause: TRdxUsesClause; AIndex: Integer; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  Span : TRefactorSpan;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  if (AIndex < 0) or (AIndex > High(AClause.Entries)) then
  begin
    AReason := 'kein solcher uses-Eintrag';
    Exit;
  end;
  AReason := EntrySpan(AMap, AClause, AIndex,
    SeparatorAfter(AMap, AClause.Entries[AIndex]), Span);
  if (AReason = '') and CommentInRange(AMap, Span) then
    AReason := 'Kommentar oder Direktive im zu loeschenden Bereich';
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

// Das end zum case ACase: die Token-Bilanz (s. CaseElse). Ein else auf
// oberster Ebene hinter ';' gehoert dem case selbst - dann hat es schon
// einen Zweig (ein if-else in einem Arm steht nie hinter ';'). '' oder
// der Grund.
function MatchingEnd(AMap: TRdxCodeMap; const ACase: TRdxToken;
  out AEnd: TRdxToken): string;
var
  T, Prev : TRdxToken;
  Depth   : Integer;
begin
  AEnd := Default(TRdxToken);
  Depth := 1;
  Prev := ACase;
  T := After(AMap, ACase);
  while T.Low <> '' do
  begin
    if IsEndOpener(T.Low) then
      Inc(Depth)
    else if T.Low = 'end' then
    begin
      Dec(Depth);
      if Depth = 0 then
      begin
        AEnd := T;
        Exit('');
      end;
    end
    else if (Depth = 1) and (T.Low = 'else') and (Prev.Low = ';') then
      Exit('das case hat schon einen else-Zweig');
    Prev := T;
    T := After(AMap, T);
  end;
  Result := 'kein end zum case gefunden';
end;

// Der Ersatz fuer das end: steht es am Zeilenanfang, das else in eigener
// Zeile mit derselben Einrueckung (AStatement eine Stufe tiefer, Tab wenn
// die Einrueckung Tabs traegt), sonst inline vor dem end.
function ElseText(const ALine: string; const AEnd: TRdxToken;
  const AStatement: string): string;
var
  Indent, EndText, Step : string;
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
  Step := '  ';
  if Pos(#9, Indent) > 0 then
    Step := #9;
  Result := 'else' + #10;
  if AStatement <> '' then
    Result := Result + Indent + Step + AStatement + #10;
  Result := Result + Indent + EndText;
end;

class function TRdxStructFixes.CaseElse(AMap: TRdxCodeMap; ALine: Integer;
  const AStatement: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  CaseTok, EndTok : TRdxToken;
  L               : string;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  EndTok := Default(TRdxToken);
  AReason := CaseTokenOn(AMap, ALine, CaseTok);
  if AReason = '' then
    AReason := MatchingEnd(AMap, CaseTok, EndTok);
  if (AReason = '') and DirectiveBefore(AMap, CaseTok.Line, EndTok) then
    AReason := 'Compiler-Direktive im case - ein Zweig koennte die '
      + 'end-Bilanz verschieben';
  if AReason <> '' then Exit;
  L := AMap.Raw(EndTok.Line);
  AEdit.Span := TRefactorSpan.Make(SPAN_168, EndTok.Line, EndTok.Col,
    EndTok.Line, EndTok.EndCol);
  AEdit.Expected := Copy(L, EndTok.Col, EndTok.Len);
  AEdit.NewText := ElseText(L, EndTok, AStatement);
  Result := True;
end;

end.
