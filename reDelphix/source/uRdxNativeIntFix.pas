unit uRdxNativeIntFix;

// reDelphix - Editorhilfe SCA161 PointerSubtraction, OHNE ToolsAPI und ohne
// Parser: in 'Integer(P1) - Integer(P2)' (auch LongInt) werden beide
// Casts NativeInt, in 'Cardinal(P1) - Cardinal(P2)' (auch LongWord) beide
// NativeUInt. Unter Win64 haelt ein 32-Bit-Cast keine Adresse, NativeInt
// schon - die Hilfe AENDERT darum das Verhalten (Changes=True): der
// Abstand ist jetzt der volle, und unter Bereichspruefung kann die
// Zuweisung an ein Integer-Ziel ERangeError werfen statt still zu kappen.
// 'PtrUInt' schreibt die Hilfe nie (gibt es in der Delphi-RTL nicht).
// GRUNDSATZ wie in uRdxLineFixes: lieber keine Hilfe als eine falsche. Die
// Meldung nennt weder Spalte noch Operanden - der Planer sucht das Muster
// des Detektors (Cast(id) - Cast(id)) auf den Code-Spalten der Zeile und
// hilft nur bei genau einem Treffer.

interface

uses
  uRdxBufferMath,      // TRdxEdit
  uRdxCodeMap;         // TRdxCodeMap

type
  TRdxNativeIntFix = class
  public
    // SCA161: genau ein 'Cast(x) - Cast(y)' auf den Code-Spalten von ALine,
    // beide Casts gleicher Art (Integer/LongInt oder Cardinal/LongWord),
    // beide Operanden Bezeichner, nichts als Code dazwischen, keine
    // Fortsetzung der Kette mit einem weiteren 32-Bit-Cast. Die Ersetzung
    // ist EINE Spanne vom ersten Cast-Wort bis hinter die zweite Klammer;
    // nur die beiden Cast-Woerter aendern sich (AMessage bleibt
    // ungenutzt - die Form von TRdxMapPlanner).
    class function PointerSubtraction(AMap: TRdxCodeMap; ALine: Integer;
      const AMessage: string; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  uRdxText,        // _(), MsgMovedSuffix (E29, nie uLocalization)
  uRefactorInfo;   // TRefactorSpan.Make

const
  SPAN_161     = 'sca161';
  NEW_SIGNED   = 'NativeInt';
  NEW_UNSIGNED = 'NativeUInt';
  // Die vier Casts des Detektors, klein geschrieben.
  CAST_SIGNED: array[0..1] of string = ('integer', 'longint');
  CAST_UNSIGNED: array[0..1] of string = ('cardinal', 'longword');
  // Texte: englische msgids (Entscheid E29), uebersetzt ueber uRdxText._;
  // die Tests suchen die ASCII-Kennungen in Klammern bzw. Anfuehrung, die
  // in en/de/fr gleich bleiben.
  R_PS_MOVED = 'no "Cast(x) - Cast(y)" pair of 32-bit casts on the code '
    + 'columns of the reported line';
  R_PS_MANY = 'line %d carries %d pointer subtractions (SCA161) - ambiguous';
  R_PS_MIXED = 'the two casts differ (Cardinal or LongWord against Integer '
    + 'or LongInt) - NativeInt or NativeUInt would be a guess';
  R_PS_OPERAND = 'an operand is a number or no plain identifier (Cast(5))';
  R_PS_CHAIN = 'the subtraction continues with another 32-bit cast '
    + '("- Integer(c)") - the chain would stay half converted';
  R_PS_NONCODE = 'a comment, string or directive stands between the two '
    + 'casts (Cast { } -)';

type
  // Ein Treffer des Detektor-Musters: Spalten der beiden Cast-Woerter (Start,
  // Laenge), Ende der zweiten Klammer (EndCol, dahinter), Operanden.
  TCastMatch = record
    Start1, Len1 : Integer;
    Start2, Len2 : Integer;
    EndCol       : Integer;
    Word1, Word2 : string;   // klein
    Oper1, Oper2 : string;
  end;

// Die Zeile mit allem, was nicht Code ist, durch Leerzeichen ersetzt - so
// sieht der Detektor sie (Strings und Kommentare gestrippt).
function MaskedLine(AMap: TRdxCodeMap; ALine: Integer): string;
var
  i : Integer;
begin
  Result := AMap.Raw(ALine);
  for i := 1 to Length(Result) do
    if not AMap.IsCode(ALine, i) then
      Result[i] := ' ';
end;

function IsCastWord(const ALow: string): Boolean;
begin
  Result := InList(ALow, CAST_SIGNED) or InList(ALow, CAST_UNSIGNED);
end;

function IsSignedCast(const ALow: string): Boolean;
begin
  Result := InList(ALow, CAST_SIGNED);
end;

// Das Bezeichnerwort ab S[P] (P wird dahinter gesetzt); '' ohne.
function ReadRun(const S: string; var P: Integer): string;
var
  From : Integer;
begin
  From := P;
  while (P <= Length(S)) and IsIdentChar(S[P]) do
    Inc(P);
  Result := Copy(S, From, P - From);
end;

// Ein 'Cast(operand)' ab S[P]: Cast-Wort, '(', Operand, ')' mit Leerraum
// dazwischen wie der Regex des Detektors. P steht danach hinter ')'.
function ReadCast(const S: string; var P: Integer; out AStart, ALen: Integer;
  out ACast, AOperand: string): Boolean;
begin
  Result := False;
  AStart := P;
  ACast := LowerCase(ReadRun(S, P));
  ALen := P - AStart;
  if not IsCastWord(ACast) then Exit;
  P := SkipBlanks(S, P);
  if (P > Length(S)) or (S[P] <> '(') then Exit;
  P := SkipBlanks(S, P + 1);
  AOperand := ReadRun(S, P);
  if AOperand = '' then Exit;
  P := SkipBlanks(S, P);
  if (P > Length(S)) or (S[P] <> ')') then Exit;
  Inc(P);
  Result := True;
end;

// Das Muster des Detektors ab S[AStart]: Cast(id) - Cast(id).
function TryMatch(const S: string; AStart: Integer;
  out M: TCastMatch): Boolean;
var
  P : Integer;
begin
  Result := False;
  M := Default(TCastMatch);
  P := AStart;
  if not ReadCast(S, P, M.Start1, M.Len1, M.Word1, M.Oper1) then Exit;
  P := SkipBlanks(S, P);
  if (P > Length(S)) or (S[P] <> '-') then Exit;
  P := SkipBlanks(S, P + 1);
  if not ReadCast(S, P, M.Start2, M.Len2, M.Word2, M.Oper2) then Exit;
  M.EndCol := P;
  Result := True;
end;

// Alle Treffer auf S, nicht ueberlappend von links wie der Regex. Ein Cast-
// Wort nach '.', '&' oder '@' ist ein Member bzw. ein Bezeichner mit
// Escape, kein Cast des Detektor-Musters - dort kein Treffer.
function FindMatches(const S: string): TArray<TCastMatch>;
var
  i, j : Integer;
  M    : TCastMatch;
begin
  Result := nil;
  i := 1;
  while i <= Length(S) do
  begin
    if not IsIdentChar(S[i]) then
    begin
      Inc(i);
      Continue;
    end;
    if ((i = 1) or not CharInSet(S[i - 1], ['.', '&', '@']))
       and TryMatch(S, i, M) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := M;
      i := M.EndCol;
    end
    else
    begin
      j := i;
      ReadRun(S, j);
      i := j;
    end;
  end;
end;

// Setzt sich der Abzug hinter dem Treffer mit '- Cast(' fort?
function ChainContinues(const S: string; AEnd: Integer): Boolean;
var
  P : Integer;
begin
  Result := False;
  P := SkipBlanks(S, AEnd);
  if (P > Length(S)) or (S[P] <> '-') then Exit;
  P := SkipBlanks(S, P + 1);
  if not IsCastWord(LowerCase(ReadRun(S, P))) then Exit;
  P := SkipBlanks(S, P);
  Result := (P <= Length(S)) and (S[P] = '(');
end;

class function TRdxNativeIntFix.PointerSubtraction(AMap: TRdxCodeMap;
  ALine: Integer; const AMessage: string; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  L, S    : string;
  Found   : TArray<TCastMatch>;
  M       : TCastMatch;
  NewWord : string;
  Mid     : string;
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  AReason := '';
  L := AMap.Raw(ALine);
  S := MaskedLine(AMap, ALine);
  Found := FindMatches(S);
  if Length(Found) = 0 then
  begin
    AReason := MsgMovedSuffix(_(R_PS_MOVED));
    Exit;
  end;
  if Length(Found) > 1 then
  begin
    AReason := _(R_PS_MANY, [ALine, Length(Found)]);
    Exit;
  end;
  M := Found[0];
  if not IsIdentStart(M.Oper1[1]) or not IsIdentStart(M.Oper2[1]) then
  begin
    AReason := _(R_PS_OPERAND);
    Exit;
  end;
  if IsSignedCast(M.Word1) <> IsSignedCast(M.Word2) then
  begin
    AReason := _(R_PS_MIXED);
    Exit;
  end;
  if ChainContinues(S, M.EndCol) then
  begin
    AReason := _(R_PS_CHAIN);
    Exit;
  end;
  if AMap.HasNonCode(ALine, M.Start1, M.EndCol - 1) then
  begin
    AReason := _(R_PS_NONCODE);
    Exit;
  end;
  if IsSignedCast(M.Word1) then
    NewWord := NEW_SIGNED
  else
    NewWord := NEW_UNSIGNED;
  // Zwischen den Cast-Woertern: '(P1) - ' unveraendert.
  Mid := Copy(L, M.Start1 + M.Len1, M.Start2 - (M.Start1 + M.Len1));
  AEdit.Span := TRefactorSpan.Make(SPAN_161, ALine, M.Start1, ALine,
    M.EndCol);
  AEdit.Expected := Copy(L, M.Start1, M.EndCol - M.Start1);
  AEdit.NewText := NewWord + Mid + NewWord
    + Copy(L, M.Start2 + M.Len2, M.EndCol - (M.Start2 + M.Len2));
  Result := True;
end;

end.
