unit uParser2;

// Stub fuer den FPC-Pruefstand: KEIN Pascal-Parser. Baut aus einer Datei
// einen Baum mit genau den Knoten, die uSourcePlaces liest:
//   * 'interface' / 'implementation' als Abschnittsknoten am Root,
//   * 'uses' (auch mehrzeilig bis ';') als nkUses unter dem aktuellen
//     Abschnitt, je Name ein nkUsesItem (Name wie geschrieben, Spalte
//     des ersten Zeichens),
//   * je sonstiger Zeile mit ':=' ein nkAssign am ersten Bezeichner
//     (Name = Text vor ':=' ohne Leerraum), dazu je weiterem ':=' auf
//     derselben Zeile ein nkAssign am Bezeichner direkt davor; sonst je
//     Zeile mit '(' ein nkCall (Name = Zeile ab dem Bezeichner ohne ';'),
//   * fuer {$IFDEF ... {$ENDIF} einen nkConditionalRange-Marker am Root
//     (Line = Start, TypeRef = Endzeile) - wie uParser2 im Core.
// Tests, die darauf laufen, pruefen also die Logik von uSourcePlaces,
// nicht den echten Parser.

interface

uses
  uAstNode;

type
  TParser2 = class
  public
    constructor Create;
    function ParseFile(const FileName: string): TAstNode;
    function ParseSource(const Source: string): TAstNode;
    // Wie im Core: ParseSource + Root.Name = FileName.
    function ParseNamedSource(const Source, FileName: string): TAstNode;
  end;

implementation

uses
  SysUtils, StrUtils, Classes;

constructor TParser2.Create;
begin
  inherited Create;
end;

function FirstIdentCol(const L: string): Integer;
var
  i : Integer;
begin
  Result := 0;
  for i := 1 to Length(L) do
    if L[i] > ' ' then
      Exit(i);
end;

function IsIdentCh(C: Char): Boolean;
begin
  Result := ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z'))
    or ((C >= '0') and (C <= '9')) or (C = '_') or (C = '.');
end;

function TParser2.ParseSource(const Source: string): TAstNode;
var
  SL      : TStringList;
  i, c, p : Integer;
  q, e    : Integer;
  L, Low  : string;
  Section : TAstNode;   // Root, Interface- oder Implementation-Knoten
  M       : TAstNode;
  UsesN   : TAstNode;   // offen, solange die uses-Klausel kein ';' sah
  IfStart : Integer;
  k, s    : Integer;
begin
  Result  := TAstNode.Create(nkUnit, '', 1, 1);
  Section := Result;
  M       := Result.Add(nkMethod, 'Stub', 1, 1);
  UsesN   := nil;
  IfStart := 0;
  SL := TStringList.Create;
  try
    SL.Text := Source;
    for i := 0 to SL.Count - 1 do
    begin
      L := SL[i];
      Low := LowerCase(Trim(L));
      if Pos('{$IFDEF', L) > 0 then IfStart := i + 1
      else if (Pos('{$ENDIF', L) > 0) and (IfStart > 0) then
      begin
        Result.Add(nkConditionalRange, '', IfStart, 0).TypeRef := IntToStr(i + 1);
        IfStart := 0;
      end;

      // Abschnitte
      if Low = 'interface' then
      begin
        Section := Result.Add(nkInterface, 'interface', i + 1, 1);
        Continue;
      end;
      if Low = 'implementation' then
      begin
        Section := Result.Add(nkImplementation, 'implementation', i + 1, 1);
        Continue;
      end;

      // uses-Klausel (eine oder mehrere Zeilen)
      k := 1;
      if (Low = 'uses') or (Pos('uses ', Low) = 1) then
      begin
        c := FirstIdentCol(L);
        UsesN := Section.Add(nkUses, 'uses', i + 1, c);
        k := c + 4;
      end;
      if Assigned(UsesN) then
      begin
        while k <= Length(L) do
        begin
          if IsIdentCh(L[k]) and (L[k] <> '.') then
          begin
            s := k;
            while (k <= Length(L)) and IsIdentCh(L[k]) do Inc(k);
            UsesN.Add(nkUsesItem, Copy(L, s, k - s), i + 1, s);
            Continue;
          end;
          if L[k] = ';' then
          begin
            UsesN := nil;
            Break;
          end;
          Inc(k);
        end;
        Continue;
      end;

      c := FirstIdentCol(L);
      if c = 0 then Continue;
      if L[c] = '{' then Continue;
      p := Pos(':=', L);
      if p > 0 then
      begin
        M.Add(nkAssign, Trim(Copy(L, c, p - c)), i + 1, c).TypeRef :=
          Trim(Copy(L, p + 2, MaxInt));
        // weitere Zuweisungen auf derselben Zeile ('a := 1; b := 2;')
        q := PosEx(':=', L, p + 2);
        while q > 0 do
        begin
          e := q - 1;
          while (e > 0) and (L[e] = ' ') do Dec(e);
          s := e;
          while (s > 1) and IsIdentCh(L[s - 1]) do Dec(s);
          if (e >= s) and IsIdentCh(L[s]) then
            M.Add(nkAssign, Copy(L, s, e - s + 1), i + 1, s).TypeRef :=
              Trim(Copy(L, q + 2, MaxInt));
          q := PosEx(':=', L, q + 2);
        end;
      end
      else if Pos('(', L) > 0 then
        M.Add(nkCall, StringReplace(Trim(Copy(L, c, MaxInt)), ';', '',
          [rfReplaceAll]), i + 1, c);
    end;
  finally
    SL.Free;
  end;
end;

function TParser2.ParseNamedSource(const Source, FileName: string): TAstNode;
begin
  Result := ParseSource(Source);
  Result.Name := FileName;
end;

function TParser2.ParseFile(const FileName: string): TAstNode;
var
  SL : TStringList;
begin
  SL := TStringList.Create;
  try
    SL.LoadFromFile(FileName);
    Result := ParseSource(SL.Text);
  finally
    SL.Free;
  end;
end;

end.
