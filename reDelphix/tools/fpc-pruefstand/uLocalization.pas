unit uLocalization;

// Stub fuer den FPC-Pruefstand: genau die Teile von uLocalization, die
// uRdxText braucht - SetLanguage, CurrentLanguage, NormalizeLangCode,
// TranslateTo (Entscheid E29, Charge C0). Die echte Unit uebersetzt unter
// FPC 3.2.2 -Mdelphiunicode nicht (gemessen 2026-10-15: TMonitor fehlt,
// TStringBuilder ist dort ein AnsiString-Bauer - Append(#10) mehrdeutig -,
// und string.Split gibt es fuer UnicodeString nicht).
//
// Die Uebersetzungen kommen aus den ECHTEN i18n\*.po des Checkouts: build.sh
// kopiert sie bei jedem Lauf nach out\i18n\ - neben den Runner, wie im
// Uebersetzer-Workflow der echten Unit (ReadExternalPo: <Modul>\i18n\
// <lang>.po). Eine eingebettete Kopie (uLocalizationPo.inc) gibt es hier
// nicht: ein Test mit deutscher Erwartung prueft so zugleich, dass die
// msgid in i18n\de.po steht.
//
// Der .po-Leser folgt ParsePo: msgid/msgstr mit Fortsetzungszeilen und
// Escapes (\n \t \r \a \b \f \v \0, sonst das Zeichen); Kommentare, #~,
// msgctxt-Eintraege und Pluralformen fallen weg, eine Zeile mit
// unbekanntem Schluesselwort beendet den Eintrag, ein leerer msgstr heisst
// unuebersetzt, die erste msgid gewinnt; eine nicht lesbare .po ist wie
// eine fehlende. Gleich fuer WOHLGEFORMTE .po - eine kaputte (Literal ohne
// schliessendes Quote, Fortsetzung ohne msgid) verwirft die echte Unit
// ganz (ParsePo False), der Stub behaelt, was er lesen konnte (Review
// Woche G05-27: bis dahin wichen Escapes, Fremdzeilen und der Lesefehler
// ab; die i18n/*.po haben keinen dieser Faelle).
// NormalizeLangCode ist eine Kopie der echten - uTestRdxText pinnt ihr
// Verhalten in reDelphix.Test (echte Unit) UND hier, eine Drift faellt auf.
//
// Bewusst KEIN _(): eine reDelphix-Unit, die uLocalization statt uRdxText
// bindet, scheitert im Pruefstand schon beim Bau.

interface

procedure SetLanguage(const Lang: string);
function CurrentLanguage: string;
function NormalizeLangCode(const ALang: string): string;
function TranslateTo(const ALang, S: string): string; overload;
function TranslateTo(const ALang, FormatStr: string;
  const Args: array of const): string; overload;

implementation

uses
  SysUtils, Classes, Generics.Collections;

type
  TPoMap = TDictionary<string, string>;
  // Wohin Fortsetzungszeilen ("...") gerade laufen.
  TPoSection = (psNone, psCtx, psId, psStr);
  // Der laufende Eintrag des Lesers (ParsePoText).
  TPoState = record
    MsgId   : string;
    MsgStr  : string;
    Section : TPoSection;
    Skip    : Boolean;   // msgctxt/Pluralform: Eintrag verwerfen
  end;

var
  GCurrentLang : string = '';
  // Kuerzel -> Tabelle; nil = keine .po (gecacht wie in der echten Unit).
  GCache       : TDictionary<string, TPoMap> = nil;

function NormalizeLangCode(const ALang: string): string;
var
  S : string;
  I : Integer;
begin
  Result := '';
  S := LowerCase(Trim(ALang));
  I := 1;
  while (I <= Length(S)) and (S[I] <> '-') and (S[I] <> '_') do
    Inc(I);
  S := Copy(S, 1, I - 1);
  if S = '' then
    Exit;
  for I := 1 to Length(S) do
    if not CharInSet(S[I], ['a'..'z', '0'..'9']) then
      Exit;
  Result := S;
end;

// Das Zeichen hinter einem Backslash - dieselben Escapes wie
// PoExtractLiteral der echten Unit.
function Unescape(C: Char): Char;
begin
  case C of
    'n': Result := #10;
    't': Result := #9;
    'r': Result := #13;
    'a': Result := #7;
    'b': Result := #8;
    'f': Result := #12;
    'v': Result := #11;
    '0': Result := #0;
  else
    Result := C;                  // \" \\ und Unbekanntes: das Zeichen
  end;
end;

// Das erste "..."-Literal der Zeile, Escapes aufgeloest; False ohne
// schliessendes Quote. Der Puffer hat die Laenge der Zeile (Escapes
// kuerzen nur) - kein Anhaengen Zeichen fuer Zeichen.
function PoLiteral(const ALine: string; out AValue: string): Boolean;
var
  I, N : Integer;
  C    : Char;
begin
  AValue := '';
  I := Pos('"', ALine);
  if I = 0 then
    Exit(False);
  SetLength(AValue, Length(ALine));
  N := 0;
  Inc(I);
  while (I <= Length(ALine)) and (ALine[I] <> '"') do
  begin
    C := ALine[I];
    if (C = '\') and (I < Length(ALine)) then
    begin
      Inc(I);
      C := Unescape(ALine[I]);
    end;
    Inc(N);
    AValue[N] := C;
    Inc(I);
  end;
  Result := I <= Length(ALine);
  SetLength(AValue, N);
end;

// Die Zeile ab APos (getrimmt); APos steht danach hinter dem Zeilenende.
function NextLine(const AText: string; var APos: Integer): string;
var
  Start : Integer;
begin
  Start := APos;
  while (APos <= Length(AText)) and (AText[APos] <> #13)
        and (AText[APos] <> #10) do
    Inc(APos);
  Result := Trim(Copy(AText, Start, APos - Start));
  if (APos <= Length(AText)) and (AText[APos] = #13) then
    Inc(APos);
  if (APos <= Length(AText)) and (AText[APos] = #10) then
    Inc(APos);
end;

// Schreibt den laufenden Eintrag weg - nicht verworfen, beide Texte da,
// die erste msgid gewinnt - und leert ihn. Skip bleibt (msgctxt gilt fuer
// den laufenden Eintrag).
procedure FlushEntry(var AState: TPoState; AMap: TPoMap);
begin
  if (not AState.Skip) and (AState.MsgId <> '') and (AState.MsgStr <> '')
     and not AMap.ContainsKey(AState.MsgId) then
    AMap.Add(AState.MsgId, AState.MsgStr);
  AState.MsgId := '';
  AState.MsgStr := '';
  AState.Section := psNone;
end;

// Eine Fortsetzungszeile "..." haengt an msgid bzw. msgstr an (wenige
// Zeilen je Eintrag - wie ParsePo der echten Unit).
procedure ContinueEntry(var AState: TPoState; const ALine: string);
var
  Lit : string;
begin
  if not PoLiteral(ALine, Lit) then
    Exit;
  if AState.Section = psId then
    AState.MsgId := AState.MsgId + Lit
  else if AState.Section = psStr then
    AState.MsgStr := AState.MsgStr + Lit;
end;

// msgid beginnt einen neuen Eintrag - ausser hinter msgctxt: dann gehoert
// es zum SELBEN Eintrag, und Skip bleibt.
procedure StartMsgId(var AState: TPoState; const ALine: string;
  AMap: TPoMap);
begin
  if AState.Section in [psId, psStr] then
  begin
    FlushEntry(AState, AMap);
    AState.Skip := False;
  end;
  PoLiteral(ALine, AState.MsgId);
  AState.Section := psId;
end;

// Eine Zeile mit Schluesselwort: msgctxt und Pluralformen verwerfen den
// Eintrag (die Section bleibt gesetzt, damit ihre Fortsetzungszeilen
// keine Fehler sind), msgid/msgstr setzen die Texte; ein unbekanntes
// Wort beendet den Eintrag wie EndEntry in ParsePo.
procedure KeywordLine(var AState: TPoState; const ALine: string;
  AMap: TPoMap);
begin
  if Copy(ALine, 1, 7) = 'msgctxt' then
  begin
    if AState.Section <> psNone then
      FlushEntry(AState, AMap);
    AState.Skip := True;
    AState.Section := psCtx;
  end
  else if Copy(ALine, 1, 12) = 'msgid_plural' then
  begin
    AState.Skip := True;
    AState.Section := psId;
  end
  else if Copy(ALine, 1, 7) = 'msgstr[' then
  begin
    AState.Skip := True;
    AState.Section := psStr;
  end
  else if Copy(ALine, 1, 5) = 'msgid' then
    StartMsgId(AState, ALine, AMap)
  else if Copy(ALine, 1, 6) = 'msgstr' then
  begin
    PoLiteral(ALine, AState.MsgStr);
    AState.Section := psStr;
  end
  else
  begin
    FlushEntry(AState, AMap);
    AState.Skip := False;
  end;
end;

procedure ParsePoText(const AText: string; AMap: TPoMap);
var
  P     : Integer;
  Line  : string;
  State : TPoState;
begin
  State := Default(TPoState);
  P := 1;
  while P <= Length(AText) do
  begin
    Line := NextLine(AText, P);
    if (Line = '') or (Line[1] = '#') then
    begin
      // Leerzeile oder Kommentar (auch #~): Eintragsgrenze.
      FlushEntry(State, AMap);
      State.Skip := False;
    end
    else if Line[1] = '"' then
      ContinueEntry(State, Line)
    else
      KeywordLine(State, Line, AMap);
  end;
  FlushEntry(State, AMap);
end;

// out\i18n\<ALang>.po neben dem Runner; nil, wenn sie fehlt oder nicht zu
// lesen ist (gesperrt) - wie ReadExternalPo der echten Unit, die dann
// still Englisch zeigt.
function LoadPo(const ALang: string): TPoMap;
var
  Path  : string;
  FS    : TFileStream;
  Bytes : TBytes;
  Text  : string;
begin
  Result := nil;
  Path := ExtractFilePath(ParamStr(0)) + 'i18n' + PathDelim + ALang + '.po';
  if not FileExists(Path) then
    Exit;
  try
    FS := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
    try
      SetLength(Bytes, FS.Size);
      if Length(Bytes) > 0 then
        FS.ReadBuffer(Bytes[0], Length(Bytes));
    finally
      FS.Free;
    end;
  except
    on EStreamError do
      Exit;
  end;
  Text := TEncoding.UTF8.GetString(Bytes);
  if (Text <> '') and (Text[1] = #$FEFF) then
    Delete(Text, 1, 1);
  Result := TPoMap.Create;
  ParsePoText(Text, Result);
end;

function MapFor(const ALang: string): TPoMap;
var
  Norm : string;
begin
  Result := nil;
  Norm := NormalizeLangCode(ALang);
  if Norm = '' then
    Exit;
  if not GCache.TryGetValue(Norm, Result) then
  begin
    Result := LoadPo(Norm);
    GCache.Add(Norm, Result);
  end;
end;

procedure SetLanguage(const Lang: string);
begin
  GCurrentLang := Lang;
end;

function CurrentLanguage: string;
begin
  Result := GCurrentLang;
end;

function TranslateTo(const ALang, S: string): string;
var
  Map : TPoMap;
begin
  Map := MapFor(ALang);
  if (Map = nil) or not Map.TryGetValue(S, Result) then
    Result := S;
end;

function TranslateTo(const ALang, FormatStr: string;
  const Args: array of const): string;
begin
  Result := Format(TranslateTo(ALang, FormatStr), Args);
end;

procedure FreeCache;
var
  Map : TPoMap;
begin
  for Map in GCache.Values do
    Map.Free;
  FreeAndNil(GCache);
end;

initialization
  GCache := TDictionary<string, TPoMap>.Create;

finalization
  FreeCache;

end.
