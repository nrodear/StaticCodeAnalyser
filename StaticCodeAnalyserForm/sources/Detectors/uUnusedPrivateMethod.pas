unit uUnusedPrivateMethod;

// Detektor: private Methode wird in der Unit nie aufgerufen.
//
// Pattern (Code Smell, Sonar-50 #37):
//   TFoo = class
//   private
//     procedure HelperA;            // <-- nie gerufen, alter Refactoring-Rest
//   public
//     procedure DoStuff;
//   end;
//
// Erkennung (AST + lexisch):
//   * Phase 1: walke nkClass -> nkVisibilitySection mit Name='private' oder
//     'strict private'. Sammle alle nkMethod-Children -> Method-Namen
//     (unqualifiziert) als Kandidaten.
//   * Phase 2: lese den File-Text, strippe Strings + Kommentare. Suche
//     pro Kandidaten-Namen nach `\bMethodName\b` als ganzes Wort.
//     Ein Treffer = Aufruf irgendwo. Skip-Pattern:
//        - Die Deklaration selbst (TypeRef-Zeile im class-body).
//        - Die Implementation `procedure TFoo.MethodName;` - der Identifier
//          taucht da auch auf, ist aber kein "Aufruf".
//     Heuristik: wir zaehlen ALLE Vorkommen. Wenn Count > 2 (Deklaration +
//     ggf. Implementation-Header) -> als verwendet markieren.
//     Damit bleiben TRUE-Unused-Methoden klar identifizierbar; FPs koennen
//     bei super-kurzen Namen entstehen (`Init`, `Get`) - in der Praxis aber
//     selten weil Pascal-Code unterschiedliche Klassen mit eigenen Methoden
//     selten ueber die gleiche Schreibweise verteilt.
//
// Limitierungen:
//   * Cross-unit-Aufrufe von public Methoden sind kein Problem - wir
//     analysieren nur PRIVATE Methoden, die ohnehin nur in der eigenen
//     Unit aufgerufen werden duerfen.
//   * Property-Getter/Setter (`Get*` / `Set*` private Methoden) werden
//     zwar als Methoden gesehen, ihre Verwendung via Property-Block
//     `read FGetSomething` zaehlt aber als Treffer in der Text-Suche -
//     also kein FP.
//   * RTTI / published / interfaces via TypeInfo werden NICHT erkannt.
//     Suppression-Marker `// noinspection UnusedPrivateMethod` als
//     Escape-Hatch.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TUnusedPrivateMethodDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

uses
  System.RegularExpressions, System.StrUtils,
  uFileTextCache;

function UnqualifiedName(const MethName: string): string;
var
  i : Integer;
begin
  Result := MethName;
  for i := Length(MethName) downto 1 do
    if MethName[i] = '.' then
    begin
      Result := Copy(MethName, i + 1, MaxInt);
      Exit;
    end;
end;

function IsPrivateSection(const Name: string): Boolean;
var
  Low : string;
begin
  Low := LowerCase(Trim(Name));
  Result := (Low = 'private') or (Low = 'strict private');
end;

// File-Text-Buffer mit gestrippten Strings + Kommentaren (Lower-Case).
function StripStringsAndComments(Lines: TStringList): string;
var
  Buf            : TStringBuilder;
  i, n, j        : Integer;
  Line           : string;
  InBlk, InParen : Boolean;
  InStr          : Boolean;
  c              : Char;
  pClose         : Integer;
begin
  Buf := TStringBuilder.Create;
  try
    InBlk := False; InParen := False;
    for i := 0 to Lines.Count - 1 do
    begin
      Line := Lines[i]; InStr := False; j := 1; n := Length(Line);
      while j <= n do
      begin
        if InBlk then
        begin
          pClose := PosEx('}', Line, j);
          if pClose = 0 then Break;
          InBlk := False; j := pClose + 1; Continue;
        end;
        if InParen then
        begin
          pClose := PosEx('*)', Line, j);
          if pClose = 0 then Break;
          InParen := False; j := pClose + 2; Continue;
        end;
        c := Line[j];
        if InStr then
        begin
          Buf.Append(' ');
          if c = '''' then
          begin
            if (j < n) and (Line[j + 1] = '''') then begin Buf.Append(' '); Inc(j, 2); end
            else begin InStr := False; Inc(j); end;
          end else Inc(j);
          Continue;
        end;
        if c = '''' then begin Buf.Append(' '); InStr := True; Inc(j); Continue; end;
        if (c = '/') and (j < n) and (Line[j + 1] = '/') then Break;
        if c = '{' then
        begin
          pClose := PosEx('}', Line, j + 1);
          if pClose = 0 then begin InBlk := True; Break; end;
          j := pClose + 1; Continue;
        end;
        if (c = '(') and (j < n) and (Line[j + 1] = '*') then
        begin
          pClose := PosEx('*)', Line, j + 2);
          if pClose = 0 then begin InParen := True; Break; end;
          j := pClose + 2; Continue;
        end;
        Buf.Append(LowerCase(c));
        Inc(j);
      end;
      Buf.Append(#10);
    end;
    Result := Buf.ToString;
  finally
    Buf.Free;
  end;
end;

class procedure TUnusedPrivateMethodDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Classes  : TList<TAstNode>;
  C        : TAstNode;
  Sections : TList<TAstNode>;
  S, Mth   : TAstNode;
  Lines    : TStringList;
  Cached   : Boolean;
  Code     : string;
  RE       : TRegEx;
  Count    : Integer;
  M        : TMatch;
  Mthods   : TList<TAstNode>;
  MethName : string;
  MethLow  : string;
  F        : TLeakFinding;
begin
  Lines := AcquireLines(FileName, Cached);
  if Lines = nil then Exit;
  try
    Code := StripStringsAndComments(Lines);

    Classes := UnitNode.FindAll(nkClass);
    try
      for C in Classes do
      begin
        // Direkte Children der Klasse durchgehen, Visibility-Sections
        // mit Name 'private' / 'strict private' aufspueren.
        for S in C.Children do
        begin
          if S.Kind <> nkVisibilitySection then Continue;
          if not IsPrivateSection(S.Name) then Continue;

          // Methoden in dieser Section sammeln.
          for Mth in S.Children do
          begin
            if Mth.Kind <> nkMethod then Continue;
            MethName := UnqualifiedName(Mth.Name);
            if MethName = '' then Continue;
            MethLow := LowerCase(MethName);

            // Text-Scan: wie oft taucht das Wort im File-Body auf?
            RE := TRegEx.Create('\b' + MethLow + '\b');
            Count := 0;
            for M in RE.Matches(Code) do
            begin
              Inc(Count);
              if Count > 2 then Break; // genug Belege fuer Use
            end;
            if Count > 2 then Continue;

            F            := TLeakFinding.Create;
            F.FileName   := FileName;
            F.MethodName := Mth.Name;
            F.LineNumber := IntToStr(Mth.Line);
            F.MissingVar := Format(
              'Private method %s.%s appears unused (no call within the unit)',
              [C.Name, MethName]);
            F.SetKind(fkUnusedPrivateMethod);
            Results.Add(F);
          end;
        end;
      end;
    finally
      Classes.Free;
    end;
  finally
    ReleaseLines(Lines, Cached);
  end;
end;

end.
