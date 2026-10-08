unit uRdxBufferMath;

// reDelphix - Rechnen im Editor-Puffer, OHNE ToolsAPI (Review reDelphiX
// 2026-10-07, Major 6 und 3; Editorhilfen Stufe 0).
//
// Der Editor-Puffer kommt als UTF-8-BYTES (IOTAEditReader), der Scan und
// der Quellstellen-Dienst rechnen in Zeilen und Zeichen-Spalten (UTF-16-
// Einheiten, Tabulator = ein Zeichen). Hier wird beides verbunden:
// Zeilenanfaenge und Byte-Offsets aus GENAU den Pufferbytes, dazu die
// Pruefung aller Ersetzungen einer Aktion, bevor eine einzige geschrieben
// wird. uRdxEditor schreibt danach nur noch, was PlanByteEdits freigibt.
//
// Bis Stufe 0 lagen diese Funktionen in der ToolsAPI-Unit uRdxEditor und
// waren deshalb ungetestet; jetzt laufen sie in reDelphix.Test und im
// FPC-Pruefstand (uTestRdxBufferMath) - mit Tabulator, Umlaut,
// Surrogatpaar und kombinierendem Zeichen vor dem Bereich.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uRefactorInfo;

type
  // Eine Ersetzung im Editor: Bereich, erwarteter alter Text, neuer Text.
  // Zeilenumbrueche in Expected und NewText sind #10; beim Schreiben
  // bekommt NewText das Zeilenende des Puffers.
  TRdxEdit = record
    Span     : TRefactorSpan;
    Expected : string;
    NewText  : string;
  end;

  // Eine gepruefte Ersetzung in Byte-Positionen des Puffers (0-basiert,
  // EndPos zeigt hinter das letzte entfernte Byte).
  TRdxByteEdit = record
    StartPos : Integer;
    EndPos   : Integer;
    NewText  : string;    // schon mit dem Zeilenende des Puffers
  end;

// Byte-Offset (0-basiert) jedes Zeilenanfangs; Terminatoren CRLF, LF und
// CR - dieselbe Trennung wie TStringList.Text.
procedure LineStartsOf(const ABytes: TBytes; AStarts: TList<Integer>);

// Byte-Offset der Zeichen-Spalte ACol (1-basiert) in Zeile ALine: Anfang
// der Zeile plus UTF-8-Laenge der Zeichen davor.
function OffsetOf(AStarts: TList<Integer>; ALines: TStrings;
  ALine, ACol: Integer; out AOffset: Integer): Boolean;

// CRLF und CR -> LF.
function NormalizeEol(const S: string): string;

// Das Zeilenende, das der Puffer benutzt: CRLF, wenn das erste Zeilenende
// eins ist, sonst LF (ein Puffer ohne Umbruch bekommt CRLF).
function BufferEol(const ABytes: TBytes): string;

// Zeilenumbrueche und Tabulatoren sichtbar machen (Meldung, Protokoll).
function Visible(const S: string): string;

// Erste abweichende Stelle samt Umfeld aus beiden Texten.
function DescribeMismatch(const AExpected, AActual: string): string;

// Prueft ALLE Ersetzungen einer Aktion gegen DENSELBEN Puffer - je als
// Zeilen (SpanText) und als Bytes (der Ausschnitt, der geloescht wuerde) -
// und liefert sie AUFSTEIGEND nach Byte-Position (so verlangt es der
// IOTAEditWriter, der nur vorwaerts kopiert). Ueberlappende Bereiche,
// ein leerer Erwartungstext oder eine Abweichung -> False und AError; dann
// darf NICHTS geschrieben werden (Review Major 3: kein Teilschreiben).
function PlanByteEdits(const ABytes: TBytes; const AEdits: TArray<TRdxEdit>;
  out APlan: TArray<TRdxByteEdit>; out AError: string): Boolean;

implementation

uses
  uRefactorInfoBuilder;   // SpanText: derselbe Bereichstext wie beim Scan

const
  SDiffers = 'Quelltext im Editor weicht vom Scan ab - nicht geschrieben';
  BYTE_CR  = 13;
  BYTE_LF  = 10;

type
  // Der Puffer in den drei Fassungen, die jede Pruefung braucht.
  TBufferView = record
    Bytes  : TBytes;
    Lines  : TStrings;
    Starts : TList<Integer>;
    Eol    : string;
  end;

procedure LineStartsOf(const ABytes: TBytes; AStarts: TList<Integer>);
var
  i, n : Integer;
begin
  AStarts.Clear;
  AStarts.Add(0);
  i := 0;
  n := Length(ABytes);
  while i < n do
  begin
    if ABytes[i] = BYTE_CR then
    begin
      if (i + 1 < n) and (ABytes[i + 1] = BYTE_LF) then
        Inc(i, 2)
      else
        Inc(i);
      AStarts.Add(i);
    end
    else if ABytes[i] = BYTE_LF then
    begin
      Inc(i);
      AStarts.Add(i);
    end
    else
      Inc(i);
  end;
end;

function OffsetOf(AStarts: TList<Integer>; ALines: TStrings;
  ALine, ACol: Integer; out AOffset: Integer): Boolean;
begin
  AOffset := 0;
  Result := (ALine >= 1) and (ALine <= ALines.Count) and (ALine <= AStarts.Count)
    and (ACol >= 1);
  if not Result then Exit;
  AOffset := AStarts[ALine - 1]
    + Length(TEncoding.UTF8.GetBytes(Copy(ALines[ALine - 1], 1, ACol - 1)));
end;

function NormalizeEol(const S: string): string;
begin
  Result := StringReplace(S, #13#10, #10, [rfReplaceAll]);
  Result := StringReplace(Result, #13, #10, [rfReplaceAll]);
end;

function BufferEol(const ABytes: TBytes): string;
var
  i : Integer;
begin
  Result := #13#10;
  for i := 0 to High(ABytes) do
    if ABytes[i] = BYTE_CR then
    begin
      if (i < High(ABytes)) and (ABytes[i + 1] = BYTE_LF) then
        Exit(#13#10);
      Exit(#13);
    end
    else if ABytes[i] = BYTE_LF then
      Exit(#10);
end;

function Visible(const S: string): string;
begin
  Result := StringReplace(S, #10, '\n', [rfReplaceAll]);
  Result := StringReplace(Result, #13, '\r', [rfReplaceAll]);
  Result := StringReplace(Result, #9, '\t', [rfReplaceAll]);
end;

function DescribeMismatch(const AExpected, AActual: string): string;
const
  CTX    = 24;
  BEFORE = 8;
var
  i, n : Integer;
  From : Integer;
begin
  n := Length(AExpected);
  if Length(AActual) < n then n := Length(AActual);
  i := 1;
  while (i <= n) and (AExpected[i] = AActual[i]) do Inc(i);
  From := i - BEFORE;
  if From < 1 then From := 1;
  Result := Format(' (ab Zeichen %d: Scan "%s", Editor "%s")', [i,
    Visible(Copy(AExpected, From, CTX)), Visible(Copy(AActual, From, CTX))]);
end;

// Einfuegesortierung nach StartPos - eine Aktion hat eine Handvoll Edits.
procedure SortAscending(var APlan: TArray<TRdxByteEdit>);
var
  i, j : Integer;
  T    : TRdxByteEdit;
begin
  for i := 1 to High(APlan) do
  begin
    T := APlan[i];
    j := i - 1;
    while (j >= 0) and (APlan[j].StartPos > T.StartPos) do
    begin
      APlan[j + 1] := APlan[j];
      Dec(j);
    end;
    APlan[j + 1] := T;
  end;
end;

// Eine Ersetzung pruefen und in Bytes umrechnen.
function PlanOne(const AView: TBufferView; const AEdit: TRdxEdit;
  out AOut: TRdxByteEdit; out AError: string): Boolean;
var
  Actual : string;
  Slice  : string;
begin
  Result := False;
  AOut := Default(TRdxByteEdit);
  if not AEdit.Span.IsValid or (AEdit.Expected = '') then
  begin
    AError := 'kein gueltiger Bereich';
    Exit;
  end;
  // 1) als Zeilen gegen den Scan-Text
  if AEdit.Span.EndLine > AView.Lines.Count then
  begin
    AError := SDiffers + Format(' (Zeile %d, der Puffer hat %d Zeilen)',
      [AEdit.Span.EndLine, AView.Lines.Count]);
    Exit;
  end;
  Actual := TRefactorInfoBuilder.SpanText(AView.Lines, AEdit.Span);
  if Actual <> AEdit.Expected then
  begin
    AError := SDiffers + DescribeMismatch(AEdit.Expected, Actual);
    Exit;
  end;
  // 2) Byte-Offsets aus demselben Puffer; der Ausschnitt muss den
  //    Scan-Text ergeben - sonst stimmt die Offset-Rechnung nicht.
  if not OffsetOf(AView.Starts, AView.Lines, AEdit.Span.StartLine,
       AEdit.Span.StartCol, AOut.StartPos)
     or not OffsetOf(AView.Starts, AView.Lines, AEdit.Span.EndLine,
       AEdit.Span.EndCol, AOut.EndPos)
     or (AOut.EndPos <= AOut.StartPos)
     or (AOut.EndPos > Length(AView.Bytes)) then
  begin
    AError := Format('Position im Puffer nicht berechenbar (%d..%d von %d)',
      [AOut.StartPos, AOut.EndPos, Length(AView.Bytes)]);
    Exit;
  end;
  Slice := NormalizeEol(TEncoding.UTF8.GetString(AView.Bytes, AOut.StartPos,
    AOut.EndPos - AOut.StartPos));
  if Slice <> AEdit.Expected then
  begin
    AError := 'Byte-Bereich weicht vom Scan ab - nicht geschrieben'
      + DescribeMismatch(AEdit.Expected, Slice);
    Exit;
  end;
  AOut.NewText := StringReplace(AEdit.NewText, #10, AView.Eol, [rfReplaceAll]);
  Result := True;
end;

function PlanByteEdits(const ABytes: TBytes; const AEdits: TArray<TRdxEdit>;
  out APlan: TArray<TRdxByteEdit>; out AError: string): Boolean;
var
  View : TBufferView;
  i    : Integer;
begin
  Result := False;
  AError := '';
  APlan  := nil;
  if Length(AEdits) = 0 then
  begin
    AError := 'keine Ersetzung';
    Exit;
  end;
  View.Bytes  := ABytes;
  View.Lines  := TStringList.Create;
  View.Starts := TList<Integer>.Create;
  try
    View.Lines.Text := TEncoding.UTF8.GetString(ABytes);
    LineStartsOf(ABytes, View.Starts);
    View.Eol := BufferEol(ABytes);
    SetLength(APlan, Length(AEdits));
    for i := 0 to High(AEdits) do
      if not PlanOne(View, AEdits[i], APlan[i], AError) then
      begin
        APlan := nil;
        Exit;
      end;
    SortAscending(APlan);
    for i := 1 to High(APlan) do
      if APlan[i].StartPos < APlan[i - 1].EndPos then
      begin
        AError := Format('Ersetzungen ueberlappen (Bytes %d..%d und %d..%d)',
          [APlan[i - 1].StartPos, APlan[i - 1].EndPos, APlan[i].StartPos,
           APlan[i].EndPos]);
        APlan := nil;
        Exit;
      end;
    Result := True;
  finally
    View.Starts.Free;
    View.Lines.Free;
  end;
end;

end.
