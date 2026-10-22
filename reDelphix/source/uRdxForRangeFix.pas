unit uRdxForRangeFix;

// reDelphix - Editorhilfe zu SCA046 ReversedForRange, OHNE ToolsAPI und ohne
// Parser (Konzept_Editorhilfen_Regelliste, Zeile SCA046): 'for i := 10 to 1
// do' laeuft nie. Der Detektor (uReversedForRange) meldet nur einen for-Kopf
// MIT zwei ganzzahligen Literalen (optional '-') und From > To; die Meldung
// nennt beide Werte ('Reversed for-range: 10 > 1 ...'), eine Spalte nennt
// sie nicht.
// Zwei Eintraege, beide aendern die Schleife (sie lief bisher nie):
//   ToDownto:   'to' -> 'downto' (Hauptweg; die Schleife zaehlt abwaerts).
//   SwapBounds: Start- und Endwert tauschen (Alt-Weg, Variant = 1; die
//               Schleife zaehlt aufwaerts).
// GRUNDSATZ wie in uRdxLineFixes: lieber keine Hilfe als eine falsche - der
// Planer sucht den Kopf am aktuellen Text, auf der Code-Sicht. Er bietet
// nichts an, wenn kein oder mehr als ein umgekehrter Kopf auf der Zeile
// steht, die Werte nicht zur Meldung passen, der Kopf ueber mehrere Zeilen
// geht oder einen Kommentar, eine Direktive oder einen String enthaelt.
// Eine Kopf-Form mit Typ ('for var i: Integer := ...') plant er nicht.

interface

uses
  uRdxBufferMath,     // TRdxEdit
  uRdxCodeMap;        // TRdxCodeMap

const
  // Die Gruende (deutsch, ASCII). Die Hinweise beider Eintraege
  // (R_FORRANGE_HINT, R_FORRANGE_SWAP_HINT) stehen mit den Adaptern in der
  // Tabelle (uRdxFixTable).
  R_FORRANGE_BOUNDS = 'die Meldung nennt die Grenzen nicht - Datei neu '
    + 'pruefen';
  R_FORRANGE_WHAT   = 'kein umgekehrter for-Kopf mit Literalgrenzen';
  R_FORRANGE_MANY   = '%d umgekehrte for-Koepfe';
  R_FORRANGE_OTHER  = 'der for-Kopf auf der Zeile hat andere Grenzen als der '
    + 'Fund - Zeile verschoben? Datei neu pruefen';
  R_FORRANGE_NONCODE = 'Kommentar, Direktive oder String im for-Kopf';

type
  // Die Planer an einer Zeile (TRdxMapPlanner-Form, MapFix oeffnet die
  // Code-Sicht): reine Textlogik, beide mit demselben Kopf-Test.
  TRdxForRangeFix = class
  public
    // Die Grenzen aus der Meldung 'Reversed for-range: A > B ...'. False,
    // wenn eine fehlt.
    class function BoundsOf(const AMessage: string; out AFrom,
      ATo: Int64): Boolean; static;

    // 'to' -> 'downto' im einen umgekehrten for-Kopf auf ALine; die
    // Schreibweise folgt dem 'to' ('TO' -> 'DOWNTO').
    class function ToDownto(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // Start- und Endwert des Kopfs vertauschen ('10 to 1' -> '1 to 10');
    // das 'to' und der Leerraum dazwischen bleiben, wie sie sind.
    class function SwapBounds(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRefactorInfo;     // TRefactorSpan.Make

const
  SPAN_046   = 'sca046';
  KEY_RANGE  = 'Reversed for-range: ';
  KEY_GREATER = ' > ';
  MAX_DIGITS = 18;   // sicher im Int64

type
  // Ein umgekehrter for-Kopf auf einer Zeile: die Token von 'for' bis 'do'.
  TRdxForSite = record
    ForTok    : TRdxToken;
    FromFirst : TRdxToken;   // erstes Token des Startwerts (ggf. '-')
    FromLast  : TRdxToken;   // die Ziffern des Startwerts
    ToTok     : TRdxToken;
    ToFirst   : TRdxToken;
    ToLast    : TRdxToken;
    DoTok     : TRdxToken;
    FromVal   : Int64;
    ToVal     : Int64;
  end;

// Nur Ziffern, nicht leer und nicht zu lang.
function IsDigits(const S: string): Boolean;
var
  i : Integer;
begin
  Result := (S <> '') and (Length(S) <= MAX_DIGITS);
  if not Result then Exit;
  for i := 1 to Length(S) do
    if not CharInSet(S[i], ['0'..'9']) then
      Exit(False);
end;

// Ein ganzzahliges Literal ab AStart: Ziffern, davor ein '-' unmittelbar
// angefuegt (wie der Detektor). ALast ist das Token mit den Ziffern.
function ReadInt(AMap: TRdxCodeMap; const AStart: TRdxToken;
  out ALast: TRdxToken; out AVal: Int64): Boolean;
var
  Neg : Boolean;
begin
  AVal := 0;
  Neg := AStart.Low = '-';
  if Neg then
    ALast := After(AMap, AStart)
  else
    ALast := AStart;
  Result := IsDigits(ALast.Low) and (ALast.Line = AStart.Line)
    and (not Neg or (ALast.Col = AStart.EndCol));
  if not Result then Exit;
  AVal := StrToInt64(ALast.Low);
  if Neg then AVal := -AVal;
end;

// Beginnt bei AFor der Kopf 'for [var] I := A to B do' mit Literalen? Die
// Token stehen alle auf der Zeile von AFor.
function ReadHead(AMap: TRdxCodeMap; const AFor: TRdxToken;
  out ASite: TRdxForSite): Boolean;
var
  T : TRdxToken;
begin
  Result := False;
  ASite := Default(TRdxForSite);
  ASite.ForTok := AFor;
  T := After(AMap, AFor);
  if T.Low = 'var' then
    T := After(AMap, T);
  if not T.IsWord then Exit;
  T := After(AMap, T);
  if T.Low <> ':=' then Exit;
  ASite.FromFirst := After(AMap, T);
  if not ReadInt(AMap, ASite.FromFirst, ASite.FromLast, ASite.FromVal) then
    Exit;
  ASite.ToTok := After(AMap, ASite.FromLast);
  if ASite.ToTok.Low <> 'to' then Exit;
  ASite.ToFirst := After(AMap, ASite.ToTok);
  if not ReadInt(AMap, ASite.ToFirst, ASite.ToLast, ASite.ToVal) then Exit;
  ASite.DoTok := After(AMap, ASite.ToLast);
  Result := (ASite.DoTok.Low = 'do') and (ASite.DoTok.Line = AFor.Line);
end;

// Der eine umgekehrte Kopf auf ALine, dessen Werte die Meldung nennt.
// '' und ASite, sonst der Grund.
function FindSite(AMap: TRdxCodeMap; ALine: Integer; const AMessage: string;
  out ASite: TRdxForSite): string;
var
  T, Prev : TRdxToken;
  S       : TRdxForSite;
  n       : Integer;
  BFrom, BTo : Int64;
begin
  ASite := Default(TRdxForSite);
  if not TRdxForRangeFix.BoundsOf(AMessage, BFrom, BTo) then
    Exit(R_FORRANGE_BOUNDS);
  n := 0;
  Prev := PrevToken(AMap, ALine, 1);
  T := NextToken(AMap, ALine, 1);
  while (T.Low <> '') and (T.Line = ALine) do
  begin
    if (T.Low = 'for') and IsKeywordAfter(T, Prev) and ReadHead(AMap, T, S)
       and (S.FromVal > S.ToVal) then
    begin
      Inc(n);
      ASite := S;
    end;
    Prev := T;
    T := After(AMap, T);
  end;
  Result := OneTokenReason(ALine, n, R_FORRANGE_WHAT, R_FORRANGE_MANY);
  if Result <> '' then Exit;
  if (ASite.FromVal <> BFrom) or (ASite.ToVal <> BTo) then
    Result := R_FORRANGE_OTHER
  else if AMap.HasNonCode(ALine, ASite.ForTok.Col, ASite.DoTok.EndCol - 1) then
    Result := R_FORRANGE_NONCODE;
end;

// 'downto' in der Schreibweise von AModel ('TO' -> 'DOWNTO', 'To' ->
// 'Downto').
function DowntoLike(const AModel: string): string;
begin
  Result := 'downto';
  if (AModel = UpperCase(AModel)) and (Length(AModel) > 1) then
    Result := 'DOWNTO'
  else if (AModel <> '') and (AModel[1] = UpperCase(AModel[1])) then
    Result := 'Downto';
end;

// Die ganze Zahl ab S[I] (optional '-'); I steht danach hinter ihr.
function ReadNumberAt(const S: string; var I: Integer; out AVal: Int64): Boolean;
var
  Start, Digits : Integer;
begin
  AVal := 0;
  Start := I;
  if (I <= Length(S)) and (S[I] = '-') then Inc(I);
  Digits := I;
  while (I <= Length(S)) and CharInSet(S[I], ['0'..'9']) do Inc(I);
  Result := IsDigits(Copy(S, Digits, I - Digits));
  if Result then
    AVal := StrToInt64(Copy(S, Start, I - Start));
end;

{ TRdxForRangeFix }

class function TRdxForRangeFix.BoundsOf(const AMessage: string; out AFrom,
  ATo: Int64): Boolean;
var
  P : Integer;
begin
  Result := False;
  AFrom := 0;
  ATo := 0;
  P := Pos(KEY_RANGE, AMessage);
  if P = 0 then Exit;
  Inc(P, Length(KEY_RANGE));
  if not ReadNumberAt(AMessage, P, AFrom) then Exit;
  if Copy(AMessage, P, Length(KEY_GREATER)) <> KEY_GREATER then Exit;
  Inc(P, Length(KEY_GREATER));
  Result := ReadNumberAt(AMessage, P, ATo);
end;

class function TRdxForRangeFix.ToDownto(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Site : TRdxForSite;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := FindSite(AMap, ALine, AMessage, Site);
  if AReason <> '' then Exit;
  AEdit.Span := TRefactorSpan.Make(SPAN_046, ALine, Site.ToTok.Col, ALine,
    Site.ToTok.EndCol);
  AEdit.Expected := Copy(AMap.Raw(ALine), Site.ToTok.Col, Site.ToTok.Len);
  AEdit.NewText := DowntoLike(AEdit.Expected);
  Result := True;
end;

class function TRdxForRangeFix.SwapBounds(AMap: TRdxCodeMap; ALine: Integer;
  const AMessage: string; out AEdit: TRdxEdit; out AReason: string): Boolean;
var
  Site          : TRdxForSite;
  L, A, Mid, B  : string;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := FindSite(AMap, ALine, AMessage, Site);
  if AReason <> '' then Exit;
  L := AMap.Raw(ALine);
  A := Copy(L, Site.FromFirst.Col, Site.FromLast.EndCol - Site.FromFirst.Col);
  Mid := Copy(L, Site.FromLast.EndCol, Site.ToFirst.Col - Site.FromLast.EndCol);
  B := Copy(L, Site.ToFirst.Col, Site.ToLast.EndCol - Site.ToFirst.Col);
  AEdit.Span := TRefactorSpan.Make(SPAN_046, ALine, Site.FromFirst.Col, ALine,
    Site.ToLast.EndCol);
  AEdit.Expected := A + Mid + B;
  AEdit.NewText := B + Mid + A;
  Result := True;
end;

end.
