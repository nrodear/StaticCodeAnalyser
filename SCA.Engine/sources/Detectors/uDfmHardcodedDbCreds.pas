unit uDfmHardcodedDbCreds;

// Detektor: Klartext-Credentials auf DB-Verbindungs-Komponenten im DFM.
//
// Findet zwei klassische Vulnerabilities, die der Form-Designer leicht
// einbaut, weil "Connect" zur Designzeit getestet wird und das Passwort
// dabei in die .dfm gespeichert wird:
//
//   1) 'Password' nicht leer als String-Literal
//        Beispiel: 'Password' = 's3cret'
//   2) 'ConnectionString' enthaelt 'Password=' oder 'Pwd=' mit Wert
//        Beispiel: 'ConnectionString' = 'Provider=...;User ID=admin;Password=s3cret;'
//   3) 'Params.Strings' enthaelt einen Eintrag Password=/Pwd=/User_Password=
//      mit nicht-leerem Wert (FireDAC TFDConnection, dbExpress TSQLConnection,
//      IBX TIBDatabase speichern ihre Verbindungsparameter so):
//        Params.Strings = (
//          'User_Name=shop'
//          'Password=Sommer2024!')
//      Gemeldet wird die Zeile des Eintrags. Bis 2026-10-24 sah der Detektor
//      diese Form nicht, obwohl Katalog-Beispiel und DETECTORS.md sie nennen
//      (ShowcaseDemo uOrderForm.dfm; realworld +16, alle echte Literale).
//
// Die String-Liste kommt als pvkStrList-ROHTEXT (inkl. Klammern und
// Anfuehrungszeichen). Die Items zerlegt SplitStrListItems hier lokal: der
// DFM-Lexer taugt dafuer nicht, weil sein ReadString fuer Property-Werte
// auch Whitespace-getrennte Segmente zu EINEM String verschmilzt.
//
// Greift nur auf einer kuratierten Whitelist von Connection-Klassen
// (TADOConnection, TFDConnection, TIBDatabase, ...). Query-/StoredProc-
// Komponenten haben in der Regel keine Credentials - sie greifen ueber eine
// Connection auf die DB zu. Die Liste kann via analyser.ini erweitert
// werden (Phase 2, [Components] CredentialBearers=...).
//
// Schweregrad: lsError, FindingType: ftVulnerability.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uSCAConsts, uMethodd12, uComponentGraph;

type
  TDfmHardcodedDbCredsDetector = class
  public
    class procedure Analyze(Graph: TComponentGraph; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils;

const
  // Default-Whitelist der Klassen, die Credentials tragen koennen.
  // Phase 2 macht das via analyser.ini ueberschreibbar.
  CONNECTION_CLASSES: array[0..6] of string = (
    'TADOConnection', 'TFDConnection', 'TIBDatabase',
    'TSQLConnection', 'TZConnection',  'TUniConnection',
    'TOracleSession'
  );

function IsCredentialBearer(const ClassRef: string): Boolean;
var
  C: string;
begin
  for C in CONNECTION_CLASSES do
    if SameText(ClassRef, C) then Exit(True);
  Result := False;
end;

function ConnectionStringHasPassword(const S: string): Boolean;
// Pruefung ohne echten Connection-String-Parser - die zwei gaengigen
// Schluesselwoerter case-insensitiv abklopfen.
//
// Bewusst false-positive-tolerant: wenn 'Password=' im String vorkommt
// (auch mit angeblich leerem Wert wie 'Password=;'), wird gemeldet -
// echte leere Passwoerter sind in Production-Configs ein eigener Smell.
// Phase-2-Erweiterung kann zwischen "Password=" und "Password=value"
// unterscheiden.
begin
  Result := ContainsText(S, 'Password=') or ContainsText(S, 'Pwd=');
end;

type
  TStrListItem = record
    Text    : string;
    LineOff : Integer;   // Zeilenversatz zur Zeile der oeffnenden '('
  end;

procedure ReadQuotedSegment(const Raw: string; var I, Line: Integer;
  Buf: TStringBuilder);
// I steht auf dem oeffnenden Apostroph, danach hinter dem schliessenden.
// '' im Segment ist ein Apostroph.
var
  N : Integer;
begin
  N := Length(Raw);
  Inc(I);
  while I <= N do
  begin
    if Raw[I] <> '''' then
    begin
      if Raw[I] = #10 then Inc(Line);
      Buf.Append(Raw[I]);
      Inc(I);
    end
    else if (I < N) and (Raw[I + 1] = '''') then
    begin
      Buf.Append(Raw[I]);
      Inc(I, 2);
    end
    else
    begin
      Inc(I);
      Exit;
    end;
  end;
end;

procedure ReadCharCode(const Raw: string; var I: Integer; Buf: TStringBuilder);
// I steht auf '#', danach hinter der Zahl (#nn dezimal, #$xx hexadezimal).
// Wie uDfmLexer: ausserhalb der BMP wird U+FFFD eingesetzt.
var
  N, Start : Integer;
  Code     : Integer;
begin
  N := Length(Raw);
  Inc(I);
  if (I <= N) and (Raw[I] = '$') then
  begin
    Inc(I);
    Start := I;
    while (I <= N) and CharInSet(Raw[I], ['0'..'9', 'A'..'F', 'a'..'f']) do
      Inc(I);
    Code := StrToIntDef('$' + Copy(Raw, Start, I - Start), 0);
  end
  else
  begin
    Start := I;
    while (I <= N) and CharInSet(Raw[I], ['0'..'9']) do
      Inc(I);
    Code := StrToIntDef(Copy(Raw, Start, I - Start), 0);
  end;
  if (Code < 0) or (Code > $FFFF) then
    Buf.Append(#$FFFD)
  else
    Buf.Append(Chr(Code));
end;

function IsSegmentStart(C: Char): Boolean; inline;
begin
  Result := (C = '''') or (C = '#');
end;

procedure ReadSegment(const Raw: string; var I, Line: Integer;
  Buf: TStringBuilder);
begin
  if Raw[I] = '''' then
    ReadQuotedSegment(Raw, I, Line, Buf)
  else
    ReadCharCode(Raw, I, Buf);
end;

procedure FlushItem(Items: TList<TStrListItem>; var Item: TStrListItem;
  Buf: TStringBuilder);
begin
  Item.Text := Buf.ToString;
  Items.Add(Item);
  Buf.Clear;
end;

procedure ScanSeparator(C: Char; var Line: Integer; var Joined: Boolean);
// Zeichen zwischen Segmenten: '+' verbindet (auch ueber folgenden
// Whitespace hinweg), ein Zeilenwechsel zaehlt die Zeile weiter.
begin
  if C = '+' then
    Joined := True
  else if C = #10 then
    Inc(Line);
end;

function SplitStrListItems(const Raw: string): TArray<TStrListItem>;
// Zerlegt den Rohtext einer DFM-String-Liste ('(' ... ')') in ihre Items,
// so wie System.Classes (ObjectBinaryToText) sie schreibt:
//   * ein Item besteht aus Segmenten '...' ('' = Apostroph) und #nn/#$xx,
//     die DIREKT aneinander stehen ('a'#13'b') oder ueber '+' verbunden
//     sind (TWriter bricht lange Items mit ' +' und Zeilenwechsel um);
//   * Whitespace OHNE '+' trennt zwei Items.
var
  Items  : TList<TStrListItem>;
  Item   : TStrListItem;
  Buf    : TStringBuilder;
  I, N   : Integer;
  Line   : Integer;
  HasCur : Boolean;
  Joined : Boolean;   // naechstes Segment gehoert zum laufenden Item
begin
  Items := TList<TStrListItem>.Create;
  Buf   := TStringBuilder.Create;
  try
    N := Length(Raw);
    I := 1;
    if (N > 0) and (Raw[1] = '(') then I := 2;
    Line   := 0;
    HasCur := False;
    Joined := False;
    Item.LineOff := 0;
    while (I <= N) and (Raw[I] <> ')') do
    begin
      if not IsSegmentStart(Raw[I]) then
      begin
        ScanSeparator(Raw[I], Line, Joined);
        Inc(I);
        Continue;
      end;
      if HasCur and not Joined then FlushItem(Items, Item, Buf);
      if not (HasCur and Joined) then Item.LineOff := Line;
      HasCur := True;
      ReadSegment(Raw, I, Line, Buf);
      // direkt angrenzendes Segment ('a'#13'b') gehoert dazu
      Joined := (I <= N) and IsSegmentStart(Raw[I]);
    end;
    if HasCur then FlushItem(Items, Item, Buf);
    Result := Items.ToArray;
  finally
    Buf.Free;
    Items.Free;
  end;
end;

function CredentialParamKey(const Item: string): string;
// Liefert den Schluessel, wenn das Item 'Password=...', 'Pwd=...' oder
// 'User_Password=...' (Name case-insensitiv, wie TStrings.Values) mit
// nicht-leerem Wert ist, sonst ''. Ein leerer Wert ('Password=') ist kein
// Klartext-Credential.
var
  P   : Integer;
  Key : string;
begin
  Result := '';
  P := Pos('=', Item);
  if P = 0 then Exit;
  Key := Trim(Copy(Item, 1, P - 1));
  if not (SameText(Key, 'Password') or SameText(Key, 'Pwd')
          or SameText(Key, 'User_Password')) then Exit;
  if Trim(Copy(Item, P + 1, MaxInt)) <> '' then
    Result := Key;
end;

function CredentialEntries(const Raw: string): TArray<TStrListItem>;
// Die Credential-Eintraege einer Params-String-Liste; Text traegt hier den
// SCHLUESSEL so, wie er im DFM steht (fuer den Meldetext), LineOff bleibt.
var
  Hits : TList<TStrListItem>;
  Item : TStrListItem;
  Hit  : TStrListItem;
begin
  Hits := TList<TStrListItem>.Create;
  try
    for Item in SplitStrListItems(Raw) do
    begin
      Hit.Text    := CredentialParamKey(Item.Text);
      Hit.LineOff := Item.LineOff;
      if Hit.Text <> '' then Hits.Add(Hit);
    end;
    Result := Hits.ToArray;
  finally
    Hits.Free;
  end;
end;

procedure AddFindingTo(Results: TObjectList<TLeakFinding>;
  const FileName: string; N: TComponentNode; const Detail: string;
  Line: Integer);
// Detail = '<Property>: <Grund>'; Meldetext '<Name> (<Klasse>).<Detail>'.
var
  F: TLeakFinding;
begin
  F            := TLeakFinding.Create;
  F.FileName   := FileName;
  F.MethodName := '';
  F.LineNumber := IntToStr(Line);
  F.MissingVar := Format('%s (%s).%s', [N.Name, N.ClassRef, Detail]);
  F.SetKind(fkDfmHardcodedDbCreds);
  Results.Add(F);
end;

procedure AddParamsFindings(Results: TObjectList<TLeakFinding>;
  const FileName: string; N: TComponentNode);
// 3) Params.Strings = ( ... 'Password=...' ... ) - ein Fund je Eintrag,
// auf dessen Zeile.
var
  V    : TPropValue;
  Item : TStrListItem;
begin
  if not N.TryGetProperty('Params.Strings', V) then Exit;
  if V.Kind <> pvkStrList then Exit;
  for Item in CredentialEntries(V.RawValue) do
    AddFindingTo(Results, FileName, N,
                 Format('Params.Strings: plaintext %s= entry in connection parameters',
                        [Item.Text]),
                 V.Line + Item.LineOff);
end;

class procedure TDfmHardcodedDbCredsDetector.Analyze(Graph: TComponentGraph;
  const FileName: string; Results: TObjectList<TLeakFinding>);

  procedure AddFinding(N: TComponentNode; const PropName, Why: string;
    Line: Integer);
  begin
    AddFindingTo(Results, FileName, N, PropName + ': ' + Why, Line);
  end;

var
  All : TList<TComponentNode>;
  N   : TComponentNode;
  V   : TPropValue;
begin
  if Graph = nil then Exit;

  All := Graph.EnumerateAll;
  try
    for N in All do
    begin
      if not IsCredentialBearer(N.ClassRef) then Continue;

      // 1) Password = '...'
      if N.TryGetProperty('Password', V)
         and (V.Kind = pvkString)
         and (V.RawValue <> '') then
        AddFinding(N, 'Password', 'plaintext password literal in DFM', V.Line);

      // 2) ConnectionString = '...Password=...'
      if N.TryGetProperty('ConnectionString', V)
         and (V.Kind = pvkString)
         and ConnectionStringHasPassword(V.RawValue) then
        AddFinding(N, 'ConnectionString',
                   'connection string embeds Password=/Pwd= credentials',
                   V.Line);

      // 3) Params.Strings = ( ... 'Password=...' ... )
      AddParamsFindings(Results, FileName, N);
    end;
  finally
    All.Free;
  end;
end;

end.
