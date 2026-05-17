unit uYamlSubsetParser;

// MINIMAL YAML-Subset-Parser fuer Rule-Konfig-Files.
//
// UNTERSTUETZT:
//   - Block-Mappings:    key: value                 (string scalars)
//   - Block-Sequences:   - item   /   - key: value
//   - Verschachtelung ueber Indentation (Spaces, kein Tab)
//   - Single-quoted ('...') und double-quoted ("...") strings
//   - Line-Comments mit '#' (nur am Zeilenanfang oder nach Whitespace)
//   - Block-Scalars |  (literal, behaelt Newlines)
//   - Leerzeilen werden ignoriert
//
// NICHT UNTERSTUETZT (bewusste Vereinfachung):
//   - Flow-Syntax {key: val} oder [a, b, c]
//   - Anchors (&) und Aliases (*)
//   - Tags (!str, !!int, ...)
//   - Folded Block-Scalar (>)
//   - Multi-Document-Files (---)
//   - Tab-Indentation
//
// Reicht fuer Rule-YAML-Files (siehe examples/analyser-rules.yml).
//
// Output: TYamlNode-Tree
//   * yntScalar   - String-Wert (Value)
//   * yntMapping  - key -> TYamlNode (Children-Dictionary)
//   * yntSequence - geordnete Liste TYamlNode (Children-List)
//
// Alle Werte als String - Caller konvertiert Booleans/Integers selbst.

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections;

type
  TYamlNodeKind = (yntScalar, yntMapping, yntSequence);

  TYamlNode = class
  private
    FKind     : TYamlNodeKind;
    FValue    : string;                            // yntScalar
    FMapping  : TObjectDictionary<string, TYamlNode>; // yntMapping (insertion order via FMapKeys)
    FMapKeys  : TStringList;                        // erhaelt Insertion-Reihenfolge
    FSequence : TObjectList<TYamlNode>;             // yntSequence
    // Privater Init-Constructor - Public-API laeuft ueber NewXxx-Factories.
    // Vermeidet W1029 (zwei parameterlose Konstruktoren CreateMapping +
    // CreateSequence haben identische Signatur, was C++Builder-Bindings
    // bricht und Delphi mit einer Warnung quittiert).
    constructor InternalCreate(AKind: TYamlNodeKind; const AValue: string);

   public
    class function NewScalar(const AValue: string): TYamlNode; static;
    class function NewMapping: TYamlNode; static;
    class function NewSequence: TYamlNode; static;
    destructor Destroy; override;
    // noinspection CanBePrivate
    // Cross-Unit-Aufrufe (z.B. uCustomRuleDetector) sind im Single-File-
    // Scan unsichtbar - Suppression bis der Recursive-Modus benutzt wird.
    function GetItem(Index: Integer): TYamlNode;
    property Kind : TYamlNodeKind read FKind;

    // yntScalar
    property Value: string read FValue;

    // yntMapping
    function HasKey(const Key: string): Boolean;
    // noinspection CanBePrivate
    // Cross-Unit-Aufrufer (uCustomRuleDetector, uTestYamlSubsetParser) -
    // verschwindet, sobald der Single-File-Scan den .dproj-Walk-Up als
    // ProjectRoot benutzt.
    function GetChild(const Key: string): TYamlNode; // nil wenn nicht da
    procedure AddChild(const Key: string; ANode: TYamlNode);
    function MapKeys: TArray<string>;

    // yntSequence
    function ItemCount: Integer;

    procedure AddItem(ANode: TYamlNode);

    // Convenience-Getter (wirft Exception wenn nicht yntScalar oder Key nicht da)
    function GetString(const Key: string; const Default: string = ''): string;
    function GetBool(const Key: string; Default: Boolean = False): Boolean;
    function GetInt(const Key: string; Default: Integer = 0): Integer;
    function GetSequenceStrings(const Key: string): TArray<string>;
  end;

  EYamlParseError = class(Exception)
  public
    LineNo : Integer;
    constructor CreateForLine(ALine: Integer; const Msg: string);
  end;

  TYamlParser = class
  public
    // Parsed YAML aus String oder Datei. Caller besitzt den zurueckgegebenen
    // Root (Free-Pflicht).
    class function ParseString(const S: string): TYamlNode; static;
    class function ParseFile(const FileName: string): TYamlNode; static;
  end;

implementation

uses
  System.IOUtils, System.StrUtils;

{ TYamlNode }

constructor TYamlNode.InternalCreate(AKind: TYamlNodeKind; const AValue: string);
begin
  inherited Create;
  FKind := AKind;
  case AKind of
    yntScalar:
      FValue := AValue;
    yntMapping:
      begin
        FMapping  := TObjectDictionary<string, TYamlNode>.Create([doOwnsValues]);
        FMapKeys  := TStringList.Create;
        FMapKeys.CaseSensitive := True;
      end;
    yntSequence:
      FSequence := TObjectList<TYamlNode>.Create(True);
  end;
end;

class function TYamlNode.NewScalar(const AValue: string): TYamlNode;
begin
  Result := TYamlNode.InternalCreate(yntScalar, AValue);
end;

class function TYamlNode.NewMapping: TYamlNode;
begin
  Result := TYamlNode.InternalCreate(yntMapping, '');
end;

class function TYamlNode.NewSequence: TYamlNode;
begin
  Result := TYamlNode.InternalCreate(yntSequence, '');
end;

destructor TYamlNode.Destroy;
begin
  FMapping.Free;
  FMapKeys.Free;
  FSequence.Free;
  inherited;
end;

function TYamlNode.HasKey(const Key: string): Boolean;
begin
  Result := (FKind = yntMapping) and FMapping.ContainsKey(Key);
end;

function TYamlNode.GetChild(const Key: string): TYamlNode;
begin
  if (FKind <> yntMapping) or not FMapping.TryGetValue(Key, Result) then
    Result := nil;
end;

procedure TYamlNode.AddChild(const Key: string; ANode: TYamlNode);
begin
  if FKind <> yntMapping then
    raise EYamlParseError.Create('AddChild auf Nicht-Mapping-Node');
  if not FMapping.ContainsKey(Key) then
    FMapKeys.Add(Key);
  FMapping.AddOrSetValue(Key, ANode);
end;

function TYamlNode.MapKeys: TArray<string>;
begin
  Result := FMapKeys.ToStringArray;
end;

function TYamlNode.ItemCount: Integer;
begin
  if FKind = yntSequence then Result := FSequence.Count
  else Result := 0;
end;

function TYamlNode.GetItem(Index: Integer): TYamlNode;
begin
  if (FKind = yntSequence) and (Index >= 0) and (Index < FSequence.Count) then
    Result := FSequence[Index]
  else
    Result := nil;
end;

procedure TYamlNode.AddItem(ANode: TYamlNode);
begin
  if FKind <> yntSequence then
    raise EYamlParseError.Create('AddItem auf Nicht-Sequence-Node');
  FSequence.Add(ANode);
end;

function TYamlNode.GetString(const Key, Default: string): string;
var N: TYamlNode;
begin
  N := GetChild(Key);
  if (N <> nil) and (N.Kind = yntScalar) then Result := N.Value
  else Result := Default;
end;

function TYamlNode.GetBool(const Key: string; Default: Boolean): Boolean;
var S: string;
begin
  S := LowerCase(GetString(Key, ''));
  if (S = 'true') or (S = 'yes') or (S = 'on') or (S = '1') then Exit(True);
  if (S = 'false') or (S = 'no') or (S = 'off') or (S = '0') then Exit(False);
  Result := Default;
end;

function TYamlNode.GetInt(const Key: string; Default: Integer): Integer;
begin
  if not TryStrToInt(GetString(Key, ''), Result) then Result := Default;
end;

function TYamlNode.GetSequenceStrings(const Key: string): TArray<string>;
var
  N    : TYamlNode;
  i    : Integer;
  List : TList<string>;
begin
  N := GetChild(Key);
  if (N = nil) or (N.Kind <> yntSequence) then Exit(nil);
  List := TList<string>.Create;
  try
    for i := 0 to N.ItemCount - 1 do
      if N.GetItem(i).Kind = yntScalar then
        List.Add(N.GetItem(i).Value);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

{ EYamlParseError }

constructor EYamlParseError.CreateForLine(ALine: Integer; const Msg: string);
begin
  inherited CreateFmt('YAML parse error (line %d): %s', [ALine, Msg]);
  LineNo := ALine;
end;

{ ---- Parser-Internas ---- }

type
  TLineInfo = record
    Indent    : Integer;  // Anzahl fuehrender Spaces
    Content   : string;   // ohne fuehrende Spaces, ohne trailing Spaces
    LineNo    : Integer;
    IsSeqItem : Boolean;  // beginnt mit "- "
  end;

function CountLeadingSpaces(const S: string): Integer;
begin
  Result := 0;
  while (Result < Length(S)) and (S[Result + 1] = ' ') do
    Inc(Result);
end;

function StripLineComment(const S: string): string;
// Entfernt '#'-Kommentar wenn nicht in einem Quote-String.
// Vereinfachung: '#' direkt nach Whitespace = Comment, sonst Teil des Werts.
var
  i        : Integer;
  InSingle : Boolean;
  InDouble : Boolean;
  Last     : Char;
begin
  InSingle := False;
  InDouble := False;
  Last     := ' ';
  for i := 1 to Length(S) do
  begin
    if S[i] = '''' then InSingle := not InSingle
    else if S[i] = '"' then InDouble := not InDouble
    else if (S[i] = '#') and not InSingle and not InDouble
            and ((i = 1) or (Last = ' ') or (Last = #9)) then
      Exit(TrimRight(Copy(S, 1, i - 1)));
    Last := S[i];
  end;
  Result := S;
end;

function UnquoteScalar(const S: string): string;
// "..." -> ... (mit \-Escapes)
// '...' -> ... (mit ''-Escape)
// sonst: trimmed
begin
  Result := Trim(S);
  if Length(Result) < 2 then Exit;

  if (Result[1] = '"') and (Result[Length(Result)] = '"') then
  begin
    // Double-quoted - Standard-Escapes \n \t \\ \"
    Result := Copy(Result, 2, Length(Result) - 2);
    Result := StringReplace(Result, '\\', #1, [rfReplaceAll]);
    Result := StringReplace(Result, '\n', #10, [rfReplaceAll]);
    Result := StringReplace(Result, '\r', #13, [rfReplaceAll]);
    Result := StringReplace(Result, '\t', #9,  [rfReplaceAll]);
    Result := StringReplace(Result, '\"', '"', [rfReplaceAll]);
    Result := StringReplace(Result, #1,   '\', [rfReplaceAll]);
  end
  else if (Result[1] = '''') and (Result[Length(Result)] = '''') then
  begin
    Result := Copy(Result, 2, Length(Result) - 2);
    Result := StringReplace(Result, '''''', '''', [rfReplaceAll]);
  end;
  // Unquoted: keep as-is.
end;

procedure SplitMappingLine(const Content: string; out Key, Value: string;
  out HasInlineValue: Boolean);
// "key: value"  -> Key='key', Value='value', HasInlineValue=True
// "key:"        -> Key='key', Value='',      HasInlineValue=False
//                  (Wert kommt aus indented children)
var
  ColonPos : Integer;
  After    : string;
begin
  Key            := '';
  Value          := '';
  HasInlineValue := False;
  ColonPos := Pos(':', Content);
  if ColonPos = 0 then
  begin
    Key := Content;
    Exit;
  end;
  Key := Trim(Copy(Content, 1, ColonPos - 1));
  After := Copy(Content, ColonPos + 1, MaxInt);
  After := TrimLeft(After);
  if After <> '' then
  begin
    Value := UnquoteScalar(After);
    HasInlineValue := True;
  end;
end;

function ParseLines(const Lines: TArray<TLineInfo>; var Idx: Integer;
  ParentIndent: Integer): TYamlNode;
// Recursive-Descent: konsumiert alle Lines deren Indent > ParentIndent
// und baut den passenden Subtree (Mapping oder Sequence).
var
  L            : TLineInfo;
  ChildIndent  : Integer;
  Key          : string;
  Value        : string;
  HasInline    : Boolean;
  Child        : TYamlNode;
  SubItem      : TYamlNode;
begin
  Result := nil;
  if Idx > High(Lines) then Exit;

  L := Lines[Idx];
  if L.Indent <= ParentIndent then Exit;
  ChildIndent := L.Indent;

  if L.IsSeqItem then
    Result := TYamlNode.NewSequence
  else
    Result := TYamlNode.NewMapping;

  try
    while Idx <= High(Lines) do
    begin
      L := Lines[Idx];
      if L.Indent < ChildIndent then Break;
      if L.Indent > ChildIndent then
      begin
        // unerwartete Tiefer-Verschachtelung ohne Trigger
        raise EYamlParseError.CreateForLine(L.LineNo,
          'Unerwartete Einrueckung');
      end;

      if Result.Kind = yntSequence then
      begin
        if not L.IsSeqItem then
          raise EYamlParseError.CreateForLine(L.LineNo,
            'Sequenz-Item erwartet (mit "- ")');

        // "- value"   -> Scalar-Item
        // "- key: val" -> Mapping-Item (kann mehr Kinder folgen)
        // "-"          -> nested Mapping/Sequence in Children
        if L.Content = '-' then
        begin
          Inc(Idx);
          SubItem := ParseLines(Lines, Idx, ChildIndent);
          if SubItem = nil then
            SubItem := TYamlNode.NewScalar('');
          Result.AddItem(SubItem);
          Continue;
        end;

        // "- ...": entferne "- " Praefix, parse als Mapping- oder Scalar-Item
        var ItemText := TrimLeft(Copy(L.Content, 2, MaxInt));
        SplitMappingLine(ItemText, Key, Value, HasInline);
        if Pos(':', ItemText) = 0 then
        begin
          // Einfaches Scalar: "- value"
          Result.AddItem(TYamlNode.NewScalar(UnquoteScalar(ItemText)));
          Inc(Idx);
        end
        else
        begin
          // Mapping-Item: "- key: value" oder "- key:"
          // weitere Mapping-Children koennen folgen mit Indent = ChildIndent + 2
          // (typische YAML-Praktik). Wir treiben das ueber relative Indentation.
          Inc(Idx);
          var ItemNode: TYamlNode := TYamlNode.NewMapping;
          if HasInline then
            ItemNode.AddChild(Key, TYamlNode.NewScalar(Value))
          else
          begin
            Child := ParseLines(Lines, Idx, ChildIndent + 2 - 1);
            if Child <> nil then ItemNode.AddChild(Key, Child)
            else ItemNode.AddChild(Key, TYamlNode.NewScalar(''));
          end;
          // weitere Mapping-Children dieses Items: gleiche Indentation wie
          // "key:", aber OHNE "- ". Das ist die schwierigste Stelle des Subset-
          // Parsers: solange die naechste Zeile Indent = ChildIndent + 2 hat
          // und KEIN Sequence-Item ist, gehoert sie zu diesem Item.
          while Idx <= High(Lines) do
          begin
            L := Lines[Idx];
            if (L.Indent <> ChildIndent + 2) or L.IsSeqItem then Break;
            SplitMappingLine(L.Content, Key, Value, HasInline);
            Inc(Idx);
            if HasInline then
              ItemNode.AddChild(Key, TYamlNode.NewScalar(Value))
            else
            begin
              Child := ParseLines(Lines, Idx, ChildIndent + 2);
              if Child <> nil then ItemNode.AddChild(Key, Child)
              else ItemNode.AddChild(Key, TYamlNode.NewScalar(''));
            end;
          end;
          Result.AddItem(ItemNode);
        end;
      end
      else
      begin
        // Mapping
        if L.IsSeqItem then
          raise EYamlParseError.CreateForLine(L.LineNo,
            'Sequenz-Item ohne enthaltende Liste');

        SplitMappingLine(L.Content, Key, Value, HasInline);
        Inc(Idx);
        if HasInline then
          Result.AddChild(Key, TYamlNode.NewScalar(Value))
        else
        begin
          Child := ParseLines(Lines, Idx, ChildIndent);
          if Child <> nil then Result.AddChild(Key, Child)
          else Result.AddChild(Key, TYamlNode.NewScalar(''));
        end;
      end;
    end;
  except
    Result.Free;
    raise;
  end;
end;

class function TYamlParser.ParseString(const S: string): TYamlNode;
var
  Raw    : TArray<string>;
  Lines  : TList<TLineInfo>;
  Info   : TLineInfo;
  Trimmed: string;
  i      : Integer;
  Idx    : Integer;
  LineArr: TArray<TLineInfo>;
begin
  Raw := S.Split([#13#10, #10, #13]);
  Lines := TList<TLineInfo>.Create;
  try
    for i := 0 to High(Raw) do
    begin
      Info.LineNo  := i + 1;
      Info.Indent  := CountLeadingSpaces(Raw[i]);
      Info.Content := TrimRight(StripLineComment(Copy(Raw[i], Info.Indent + 1, MaxInt)));
      // Tabs in Indentation? Nicht erlaubt im Subset.
      if (Length(Raw[i]) > 0) and (Raw[i][1] = #9) then
        raise EYamlParseError.CreateForLine(Info.LineNo,
          'Tab-Indentation nicht unterstuetzt - bitte Spaces verwenden');
      // Leerzeile -> skip
      if Trim(Info.Content) = '' then Continue;
      Trimmed := TrimLeft(Info.Content);
      Info.IsSeqItem := (Trimmed.StartsWith('- ') or (Trimmed = '-'));
      Lines.Add(Info);
    end;
    LineArr := Lines.ToArray;
    Idx := 0;
    if Length(LineArr) = 0 then
      Exit(TYamlNode.NewMapping);
    Result := ParseLines(LineArr, Idx, -1);
    if Result = nil then
      Result := TYamlNode.NewMapping;
  finally
    Lines.Free;
  end;
end;

class function TYamlParser.ParseFile(const FileName: string): TYamlNode;
begin
  Result := ParseString(TFile.ReadAllText(FileName, TEncoding.UTF8));
end;

end.
