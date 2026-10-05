unit uRdxRecipes;

// reDelphix - die Rezepte: aus beschriebenen Quellstellen (TRefactorInfo
// aus dem SCA-Core, Konzept_SourceRefactor_Quellstellen Abschnitt 5) neuen
// Quelltext bauen. Reine Textarbeit - kein ToolsAPI, keine Datei, kein
// VCL. Deshalb laeuft diese Unit im FPC-Pruefstand und ihre Tests sind
// ohne IDE ausfuehrbar.
//
// WAS HIER ENTSTEHT
//
//   BuildFormatCall   'a' + X + 'b'      ->  Format('a%sb', [X])
//   BuildSqlTemplate  Q.SQL.Text := 'SELECT ... ' + Id
//                     ->  Q.SQL.Text := 'SELECT ... :p1';
//                         Q.ParamByName('p1').Value := Id;      (Vorlage)
//   DetectFramework   VCL oder FMX, aus den qualifizierten uses-Eintraegen
//
// Die Fakten kommen aus dem Core (Teilbereiche mit Rolle und Typ), die
// Politik steht hier: ein Format() wird nur gebaut, wenn JEDER Operand
// beweisbar ein String ist (sonst %d-fuer-String: uebersetzt, wirft zur
// Laufzeit EConvertError), und nie fuer SQL-Text (SCA003 - Vertrag im
// Kopf von uRefactorConcat).
//
// LITERALE
//
// Ein Teilbereich mit ROLE_LITERAL traegt den QUELLTEXT des Literals
// ('it''s', 'a'#13#10'b', #$41). DecodeLiteral macht daraus den Wert,
// EncodeLiteral den Quelltext zurueck - so bleibt ein '%' im Wert
// escapebar ('%%') und Steuerzeichen bleiben als #13#10 lesbar.

interface

uses
  System.SysUtils, System.Classes,
  uRefactorInfo;

type
  // Ein Teilbereich mit seinem Quelltext - die Form, in der die Rezepte
  // die Parts eines TRefactorInfo bekommen (der Text kommt aus
  // TSourcePlaces.TextOf, hier wird keine Datei gelesen).
  TRdxPart = record
    Role      : string;
    Text      : string;
    ValueType : TRefactorValueType;
  end;
  TRdxParts = TArray<TRdxPart>;

  TRdxFramework = (fwUnknown, fwVcl, fwFmx, fwBoth);

  TRdxRecipes = class
  public
    class function MakePart(const ARole, AText: string;
      AValueType: TRefactorValueType = rvUnknown): TRdxPart; static;

    // Quelltext eines Pascal-String-Literals -> Wert. False bei allem,
    // was kein reines Literal ist (unbalancierte Quotes, '^M', Bezeichner).
    class function DecodeLiteral(const ASource: string;
      out AValue: string): Boolean; static;
    // Wert -> Quelltext: Quotes verdoppelt, Steuerzeichen (< #32) als #nn.
    class function EncodeLiteral(const AValue: string): string; static;

    // Zeilenumbrueche und Tabulatoren zu einem Leerzeichen, aussen getrimmt.
    class function CollapseWhitespace(const AText: string): string; static;

    // True, wenn der Text wie ein SQL-Statement aussieht: ein Statement-
    // Verb (select/insert/update/...) UND ein Strukturwort (from/into/
    // set/where/...) als ganze Woerter. 'Update available for' allein
    // ist KEIN SQL.
    class function LooksLikeSql(const AValue: string): Boolean; static;

    // Rezept 5.1 - Format() aus einer '+'-Kette. AParts in Quelltext-
    // Reihenfolge, Parts[0] darf ROLE_TARGET sein (wird uebersprungen).
    // False mit Grund, wenn ein Operand nicht beweisbar String ist, kein
    // Operand vorkommt, ein Teil keine Kette ist (ROLE_ARGUMENT) oder die
    // Literale SQL ergeben.
    class function BuildFormatCall(const AParts: TRdxParts;
      out ANewText, AReason: string): Boolean; static;

    // Das Query-Objekt eines SQL-Ziels: 'Query.SQL.Text' -> 'Query',
    // 'FDQuery1.SQL.Add' -> 'FDQuery1', 'Cmd.CommandText' -> 'Cmd'.
    class function QueryObjectOf(const ATarget: string): string; static;

    // Rezept 5.2 - parametrisierte Vorlage (nie geschrieben, nur Text).
    // AIsCall: das Ziel ist ein Aufrufkopf (Q.SQL.Add) statt einer
    // Zuweisung. AIndent: fuehrende Leerzeichen je Zeile.
    class function BuildSqlTemplate(const ATarget: string; AIsCall: Boolean;
      const AParts: TRdxParts; AIndent: Integer;
      out ATemplate, AReason: string): Boolean; static;

    // Rahmenwerk einer Datei aus ihren uses-Eintraegen (qualifizierte
    // Namen 'Vcl.*' / 'FMX.*').
    class function DetectFramework(
      const AUnitNames: TArray<string>): TRdxFramework; static;
    // True, wenn AShortName als Eintrag vorkommt - unqualifiziert oder
    // als letztes Segment ('SysUtils' trifft 'System.SysUtils').
    class function HasUnit(const AUnitNames: TArray<string>;
      const AShortName: string): Boolean; static;

    // ---- uses-Klausel ergaenzen (AH19: Format() braucht System.SysUtils) --

    // Der Name, unter dem eine RTL-Unit in DIESE Datei passt: der
    // qualifizierte, wenn die Datei qualifizierte Namen benutzt oder noch
    // keinen uses-Eintrag hat; sonst der Kurzname (eine Datei, die
    // 'Classes, Windows' schreibt, bekommt 'SysUtils').
    class function UsesNameFor(const AUnitNames: TArray<string>;
      const AShortName, AQualifiedName: string): string; static;
    // True, wenn die Namen case-insensitiv aufsteigend sortiert sind -
    // dasselbe Kriterium wie SCA142 UnsortedUses (CompareText).
    class function IsSortedUses(const AUnitNames: TArray<string>): Boolean;
      static;
    // Index des Eintrags, VOR dem ANewName einzufuegen ist, damit eine
    // sortierte Liste sortiert bleibt; Length(AUnitNames) = anhaengen.
    // Eine unsortierte Liste bekommt den Neuen vorn (0) - dort faellt
    // er dem Leser am ehesten auf und erzeugt keinen neuen SCA142-Fund,
    // denn der steht dort schon.
    class function SortedInsertIndex(const AUnitNames: TArray<string>;
      const ANewName: string): Integer; static;
  end;

implementation

const
  SQL_VERBS: array[0..8] of string = (
    'select', 'insert', 'update', 'delete', 'create', 'alter', 'drop',
    'truncate', 'merge');
  SQL_WORDS: array[0..8] of string = (
    'from', 'into', 'set', 'where', 'table', 'values', 'join', 'index',
    'view');

function InList(const AValue: string; const AList: array of string): Boolean;
var
  i : Integer;
begin
  Result := False;
  for i := Low(AList) to High(AList) do
    if AList[i] = AValue then
      Exit(True);
end;

function HexValue(C: Char): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

function CharStr(C: Char): string;
// Ein Zeichen als String: TStringBuilder.Append(Char) ist unter FPC
// (delphiunicode) mehrdeutig, Append(string) nicht.
begin
  Result := C;
end;

function LastSegment(const AName: string): string;
var
  P : Integer;
begin
  P := LastDelimiter('.', AName);
  Result := Copy(AName, P + 1, MaxInt);
end;

{ TRdxRecipes }

class function TRdxRecipes.MakePart(const ARole, AText: string;
  AValueType: TRefactorValueType): TRdxPart;
begin
  Result.Role      := ARole;
  Result.Text      := AText;
  Result.ValueType := AValueType;
end;

class function TRdxRecipes.DecodeLiteral(const ASource: string;
  out AValue: string): Boolean;
var
  SB     : TStringBuilder;
  i, n   : Integer;
  Code   : Integer;
  Digits : Integer;
  Closed : Boolean;
  Hex    : Integer;
begin
  Result := False;
  AValue := '';
  n := Length(ASource);
  SB := TStringBuilder.Create;
  try
    i := 1;
    while i <= n do
    begin
      if ASource[i] <= ' ' then
      begin
        Inc(i);
        Continue;
      end;
      if ASource[i] = '''' then
      begin
        Inc(i);
        Closed := False;
        while i <= n do
        begin
          if ASource[i] = '''' then
          begin
            if (i < n) and (ASource[i + 1] = '''') then
            begin
              SB.Append('''');
              Inc(i, 2);
            end
            else
            begin
              Inc(i);
              Closed := True;
              Break;
            end;
          end
          else
          begin
            SB.Append(CharStr(ASource[i]));
            Inc(i);
          end;
        end;
        if not Closed then Exit;
      end
      else if ASource[i] = '#' then
      begin
        Inc(i);
        Code   := 0;
        Digits := 0;
        if (i <= n) and (ASource[i] = '$') then
        begin
          Inc(i);
          while i <= n do
          begin
            Hex := HexValue(ASource[i]);
            if Hex < 0 then Break;
            Code := Code * 16 + Hex;
            Inc(i);
            Inc(Digits);
            if Code > $FFFF then Exit;
          end;
        end
        else
          while (i <= n) and CharInSet(ASource[i], ['0'..'9']) do
          begin
            Code := Code * 10 + (Ord(ASource[i]) - Ord('0'));
            Inc(i);
            Inc(Digits);
            if Code > $FFFF then Exit;
          end;
        if Digits = 0 then Exit;
        SB.Append(CharStr(Char(Code)));
      end
      else
        Exit;
    end;
    AValue := SB.ToString;
    Result := True;
  finally
    SB.Free;
  end;
end;

class function TRdxRecipes.EncodeLiteral(const AValue: string): string;
var
  SB      : TStringBuilder;
  i       : Integer;
  InQuote : Boolean;
  C       : Char;
begin
  if AValue = '' then Exit('''''');
  SB := TStringBuilder.Create;
  try
    InQuote := False;
    for i := 1 to Length(AValue) do
    begin
      C := AValue[i];
      if C < ' ' then
      begin
        if InQuote then
        begin
          SB.Append('''');
          InQuote := False;
        end;
        SB.Append('#');
        SB.Append(IntToStr(Ord(C)));
      end
      else
      begin
        if not InQuote then
        begin
          SB.Append('''');
          InQuote := True;
        end;
        if C = '''' then
          SB.Append('''''')
        else
          SB.Append(CharStr(C));
      end;
    end;
    if InQuote then
      SB.Append('''');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TRdxRecipes.CollapseWhitespace(const AText: string): string;
var
  i         : Integer;
  LastWhite : Boolean;
  C         : Char;
begin
  Result := '';
  LastWhite := True;   // fuehrenden Leerraum verschlucken
  for i := 1 to Length(AText) do
  begin
    C := AText[i];
    if C <= ' ' then
    begin
      if not LastWhite then
        Result := Result + ' ';
      LastWhite := True;
    end
    else
    begin
      Result := Result + C;
      LastWhite := False;
    end;
  end;
  Result := TrimRight(Result);
end;

class function TRdxRecipes.LooksLikeSql(const AValue: string): Boolean;
var
  Low     : string;
  i       : Integer;
  Word    : string;
  HasVerb : Boolean;
  HasWord : Boolean;

  procedure Flush;
  begin
    if Word = '' then Exit;
    if InList(Word, SQL_VERBS) then HasVerb := True;
    if InList(Word, SQL_WORDS) then HasWord := True;
    Word := '';
  end;

begin
  Low := LowerCase(AValue);
  HasVerb := False;
  HasWord := False;
  Word := '';
  for i := 1 to Length(Low) do
    if CharInSet(Low[i], ['a'..'z']) then
      Word := Word + Low[i]
    else
      Flush;
  Flush;
  Result := HasVerb and HasWord;
end;

class function TRdxRecipes.BuildFormatCall(const AParts: TRdxParts;
  out ANewText, AReason: string): Boolean;
var
  i        : Integer;
  Fmt      : string;
  Literals : string;
  Args     : string;
  Value    : string;
  Operands : Integer;
begin
  Result   := False;
  ANewText := '';
  AReason  := '';
  Fmt      := '';
  Literals := '';
  Args     := '';
  Operands := 0;
  for i := 0 to High(AParts) do
  begin
    if AParts[i].Role = ROLE_TARGET then Continue;
    if AParts[i].Role = ROLE_LITERAL then
    begin
      if not DecodeLiteral(AParts[i].Text, Value) then
      begin
        AReason := 'Literal nicht lesbar: ' + CollapseWhitespace(AParts[i].Text);
        Exit;
      end;
      Literals := Literals + Value;
      Fmt := Fmt + StringReplace(Value, '%', '%%', [rfReplaceAll]);
    end
    else if AParts[i].Role = ROLE_OPERAND then
    begin
      if AParts[i].ValueType <> rvString then
      begin
        AReason := 'Operand ''' + CollapseWhitespace(AParts[i].Text)
          + ''': Typ unbekannt';
        Exit;
      end;
      Inc(Operands);
      Fmt := Fmt + '%s';
      if Args <> '' then Args := Args + ', ';
      Args := Args + CollapseWhitespace(AParts[i].Text);
    end
    else
    begin
      AReason := 'kein reiner Term: ' + AParts[i].Role;
      Exit;
    end;
  end;
  if Operands = 0 then
  begin
    AReason := 'kein Operand in der Kette';
    Exit;
  end;
  if LooksLikeSql(Literals) then
  begin
    AReason := 'SQL-Text: Umformung gesperrt (SCA003)';
    Exit;
  end;
  ANewText := 'Format(' + EncodeLiteral(Fmt) + ', [' + Args + '])';
  Result := True;
end;

class function TRdxRecipes.QueryObjectOf(const ATarget: string): string;
var
  T   : string;
  Low : string;
  P   : Integer;
begin
  T   := Trim(ATarget);
  Low := LowerCase(T);
  P := Pos('.sql', Low);
  if P = 0 then
    P := Pos('.commandtext', Low);
  if P = 0 then
    P := LastDelimiter('.', T);
  if P > 0 then
    Result := Copy(T, 1, P - 1)
  else
    Result := T;
end;

class function TRdxRecipes.BuildSqlTemplate(const ATarget: string;
  AIsCall: Boolean; const AParts: TRdxParts; AIndent: Integer;
  out ATemplate, AReason: string): Boolean;
var
  i        : Integer;
  Sql      : string;
  Value    : string;
  N        : Integer;
  Operands : TArray<string>;
  Obj      : string;
  Indent   : string;
  Head     : string;
  k        : Integer;
  PName    : string;
begin
  Result    := False;
  ATemplate := '';
  AReason   := '';
  Sql := '';
  N   := 0;
  SetLength(Operands, 0);
  for i := 0 to High(AParts) do
  begin
    if AParts[i].Role = ROLE_TARGET then Continue;
    if AParts[i].Role = ROLE_LITERAL then
    begin
      if not DecodeLiteral(AParts[i].Text, Value) then
      begin
        AReason := 'Literal nicht lesbar: ' + CollapseWhitespace(AParts[i].Text);
        Exit;
      end;
      Sql := Sql + Value;
    end
    else if AParts[i].Role = ROLE_OPERAND then
    begin
      Inc(N);
      Sql := Sql + ':p' + IntToStr(N);
      SetLength(Operands, N);
      Operands[N - 1] := CollapseWhitespace(AParts[i].Text);
    end
    else
    begin
      AReason := 'Aufruf mit mehreren Argumenten - keine Vorlage';
      Exit;
    end;
  end;
  if N = 0 then
  begin
    AReason := 'kein Operand in der Kette';
    Exit;
  end;
  // Ein Parameter steht nie in Quotes: WHERE name=':p1' -> WHERE name=:p1
  for k := 1 to N do
  begin
    PName := ':p' + IntToStr(k);
    Sql := StringReplace(Sql, '''' + PName + '''', PName, [rfReplaceAll]);
  end;
  Obj    := QueryObjectOf(ATarget);
  Indent := StringOfChar(' ', AIndent);
  if AIsCall then
    Head := Trim(ATarget) + '(' + EncodeLiteral(Sql) + ');'
  else
    Head := Trim(ATarget) + ' := ' + EncodeLiteral(Sql) + ';';
  ATemplate := Indent + Head;
  for k := 1 to N do
    ATemplate := ATemplate + sLineBreak + Indent + Obj + '.ParamByName('
      + EncodeLiteral('p' + IntToStr(k)) + ').Value := ' + Operands[k - 1] + ';';
  Result := True;
end;

class function TRdxRecipes.DetectFramework(
  const AUnitNames: TArray<string>): TRdxFramework;
var
  i      : Integer;
  Low    : string;
  HasVcl : Boolean;
  HasFmx : Boolean;
begin
  HasVcl := False;
  HasFmx := False;
  for i := 0 to High(AUnitNames) do
  begin
    Low := LowerCase(AUnitNames[i]);
    if Copy(Low, 1, 4) = 'vcl.' then HasVcl := True;
    if Copy(Low, 1, 4) = 'fmx.' then HasFmx := True;
  end;
  if HasVcl and HasFmx then Exit(fwBoth);
  if HasVcl then Exit(fwVcl);
  if HasFmx then Exit(fwFmx);
  Result := fwUnknown;
end;

class function TRdxRecipes.HasUnit(const AUnitNames: TArray<string>;
  const AShortName: string): Boolean;
var
  i : Integer;
begin
  Result := False;
  for i := 0 to High(AUnitNames) do
    if SameText(LastSegment(AUnitNames[i]), AShortName) then
      Exit(True);
end;

class function TRdxRecipes.UsesNameFor(const AUnitNames: TArray<string>;
  const AShortName, AQualifiedName: string): string;
var
  i : Integer;
begin
  if Length(AUnitNames) = 0 then Exit(AQualifiedName);
  for i := 0 to High(AUnitNames) do
    if Pos('.', AUnitNames[i]) > 0 then
      Exit(AQualifiedName);
  Result := AShortName;
end;

class function TRdxRecipes.IsSortedUses(
  const AUnitNames: TArray<string>): Boolean;
var
  i : Integer;
begin
  Result := True;
  for i := 1 to High(AUnitNames) do
    if CompareText(AUnitNames[i - 1], AUnitNames[i]) > 0 then
      Exit(False);
end;

class function TRdxRecipes.SortedInsertIndex(
  const AUnitNames: TArray<string>; const ANewName: string): Integer;
var
  i : Integer;
begin
  if not IsSortedUses(AUnitNames) then Exit(0);
  for i := 0 to High(AUnitNames) do
    if CompareText(ANewName, AUnitNames[i]) < 0 then
      Exit(i);
  Result := Length(AUnitNames);
end;

end.
