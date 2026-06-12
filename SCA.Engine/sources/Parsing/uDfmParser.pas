unit uDfmParser;

// DFM-Parser - Phase 1 (Walking Skeleton).
//
// Grammatik dieser Stufe:
//   File           := ObjectDecl* EOF
//   ObjectDecl     := ('object'|'inherited'|'inline') Ident ':' Ident
//                     BodyItem*
//                     'end'
//   BodyItem       := ObjectDecl | Property
//   Property       := QualifiedName '=' VALUE
//   QualifiedName  := Ident ('.' Ident)*
//
// Properties werden in Phase 1 vollständig übersprungen - der Parser baut
// nur die Komponenten-Hierarchie. Property-Werte werden anhand der Zeilen-
// Information übersprungen: ein Property-Wert liegt per Konvention auf
// derselben Zeile wie das '=' (Multi-Line-Werte wie Lines.Strings = (...)
// oder Columns = <...> kommen aus dem Lexer bereits als ein einziges
// atomares Token, das auf der '='-Zeile beginnt).
//
// Phase 2/3 erweitern diesen Parser um typisierte Property-Werte und
// Event-Bindungen (siehe TODO.md).

interface

uses
  System.SysUtils,
  uDfmLexer,
  uComponentGraph;

type
  EDfmParse = class(Exception);

  TDfmParser = class
  private
    FLex : TDfmLexer;

    function  ParseQualifiedName(out FirstLine, FirstCol: Integer): string;
    function  TryParsePropertyValue(EqLine: Integer; out Value: TPropValue): Boolean;
    procedure ParseProperty(Owner: TComponentNode);
    procedure ParseObjectInto(Parent: TComponentNode; Graph: TComponentGraph);
    procedure ParseBody(Owner: TComponentNode);
    function  IsObjectStart(Kind: TDfmTokenKind): Boolean; inline;
  public
    function ParseSource(const ASource: string): TComponentGraph;
  end;

implementation

// noinspection-file ConcatToFormat, MultipleExit, StringConcatInLoop
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

function TDfmParser.IsObjectStart(Kind: TDfmTokenKind): Boolean;
begin
  Result := (Kind = tkKwObject)
         or (Kind = tkKwInherited)
         or (Kind = tkKwInline);
end;

function TDfmParser.ParseSource(const ASource: string): TComponentGraph;
var
  Graph : TComponentGraph;
begin
  FLex := TDfmLexer.Create(ASource);
  try
    Graph := TComponentGraph.Create;
    try
      while not FLex.AtEnd do
      begin
        if IsObjectStart(FLex.Peek.Kind) then
          ParseObjectInto(nil, Graph)
        else
          // Top-Level-Junk (Leerzeilen, Kommentare bereits weg) - tolerant
          // überspringen, damit der Parser bei degeneriertem Input nicht
          // hart bricht. Property-Tokens auf Top-Level sind ungültig, aber
          // ein einzelnes Überspringen ist billiger als eine Exception.
          FLex.Next;
      end;
      Result := Graph;
    except
      Graph.Free;
      raise;
    end;
  finally
    FLex.Free;
    FLex := nil;
  end;
end;

procedure TDfmParser.ParseObjectInto(Parent: TComponentNode;
  Graph: TComponentGraph);
// Liest einen kompletten object/inherited/inline-Block einschließlich
// 'end' und allen Body-Items. Hängt den entstandenen Knoten entweder an
// Parent.Children (Parent <> nil) oder an Graph.Roots (Parent = nil).
var
  Header  : TDfmToken;
  NameTok : TDfmToken;
  ClsTok  : TDfmToken;
  Node    : TComponentNode;
begin
  Header  := FLex.Next;                  // object | inherited | inline
  NameTok := FLex.Consume(tkIdent);
  FLex.Consume(tkColon);
  ClsTok  := FLex.Consume(tkIdent);

  if Parent <> nil then
    Node := Parent.Add(NameTok.Value, ClsTok.Value, Header.Line, Header.Col)
  else
    Node := Graph.AddRoot(NameTok.Value, ClsTok.Value, Header.Line, Header.Col);

  Node.IsInherited := Header.Kind = tkKwInherited;
  Node.IsInline    := Header.Kind = tkKwInline;

  ParseBody(Node);
  FLex.Consume(tkKwEnd);
end;

procedure TDfmParser.ParseBody(Owner: TComponentNode);
var
  Peek: TDfmToken;
begin
  while True do
  begin
    Peek := FLex.Peek;
    case Peek.Kind of
      tkKwEnd, tkEof:
        Exit;
      tkKwObject, tkKwInherited, tkKwInline:
        ParseObjectInto(Owner, nil);
      tkIdent:
        ParseProperty(Owner);
    else
      // Unbekanntes Token - tolerieren und überspringen, damit der Parser
      // bei kleinen Format-Defekten nicht ganze Forms verliert.
      FLex.Next;
    end;
  end;
end;

function TDfmParser.ParseQualifiedName(out FirstLine, FirstCol: Integer): string;
// Ident ('.' Ident)*  z.B. 'Caption' oder 'Font.Style' oder 'Picture.Data.Foo'
// Position des Property-Namens liefert First/Col (Detektoren brauchen die
// Stelle der Property-Definition fuer Befund-Lokalisierung).
var
  Tok : TDfmToken;
begin
  Tok       := FLex.Consume(tkIdent);
  Result    := Tok.Value;
  FirstLine := Tok.Line;
  FirstCol  := Tok.Col;
  while FLex.Peek.Kind = tkDot do
  begin
    FLex.Next;                               // '.'
    Tok    := FLex.Consume(tkIdent);
    Result := Result + '.' + Tok.Value;
  end;
end;

procedure TDfmParser.ParseProperty(Owner: TComponentNode);
var
  Path     : string;
  PathLine : Integer;
  PathCol  : Integer;
  EqTok    : TDfmToken;
  Value    : TPropValue;
begin
  Path  := ParseQualifiedName(PathLine, PathCol);
  EqTok := FLex.Consume(tkEquals);
  if TryParsePropertyValue(EqTok.Line, Value) and (Owner <> nil) then
    Owner.SetProperty(Path, Value);
end;

function TDfmParser.TryParsePropertyValue(EqLine: Integer;
  out Value: TPropValue): Boolean;
// Wert nach dem '=' einlesen.
// Strategie: ein DFM-Property hat semantisch GENAU EINEN Wert. Wir lesen
// daher exakt ein Wert-Token - mit Vorzeichen-Sonderfall:
//   * '-' gefolgt von Zahl wird zu einem einzigen pvkInteger/pvkFloat-Wert
//     zusammengefuegt (RawValue: '-42').
//   * Alle anderen Wert-Formen (String, Set, ItemList, StrList, Binary,
//     Bool, Ident) sind im Lexer bereits atomar.
//
// Robustheit:
//   * Wert muss auf der gleichen Zeile wie '=' beginnen (DFM-Konvention).
//     Wenn nicht, wird KEIN Token konsumiert - Property bleibt unregistriert
//     und der Body-Loop ueber Property/Object-Tokens treibt weiter.
//   * Kein nachlaufender Token-Skip: jedes weitere Token gehoert syntaktisch
//     bereits zum naechsten Body-Item.
var
  Tok      : TDfmToken;
  Sign     : string;
begin
  Result := False;
  Value.Kind     := pvkUnknown;
  Value.RawValue := '';
  Value.Line     := 0;
  Value.Col      := 0;

  if FLex.AtEnd then Exit;
  if FLex.Peek.Line <> EqLine then Exit;     // Wert nicht auf '='-Zeile -> Skip

  Tok  := FLex.Peek;
  Sign := '';
  if Tok.Kind = tkMinus then
  begin
    FLex.Next;                                // '-' konsumieren
    Sign := '-';
    if FLex.AtEnd or (FLex.Peek.Line <> EqLine) then Exit;
    Tok := FLex.Peek;
  end;

  case Tok.Kind of
    tkString:    Value.Kind := pvkString;
    tkInteger:   Value.Kind := pvkInteger;
    tkFloat:     Value.Kind := pvkFloat;
    tkKwTrue,
    tkKwFalse:   Value.Kind := pvkBool;
    tkIdent:     Value.Kind := pvkIdent;
    tkSet:       Value.Kind := pvkSet;
    tkBinary:    Value.Kind := pvkBinary;
    tkItemList:  Value.Kind := pvkItemList;
    tkStrList:   Value.Kind := pvkStrList;
  else
    // Kein erkennbares Wert-Token. Property wird nicht gespeichert; der
    // Body-Loop verarbeitet das aktuelle Token im naechsten Schritt.
    Exit;
  end;

  FLex.Next;                                  // Wert-Token konsumieren
  Value.RawValue := Sign + Tok.Value;
  Value.Line     := Tok.Line;
  Value.Col      := Tok.Col;
  Result := True;
end;

end.
