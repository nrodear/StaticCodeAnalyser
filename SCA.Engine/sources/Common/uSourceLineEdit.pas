unit uSourceLineEdit;

// Zeilengenaue Aenderungen an Quelldateien AUF DER PLATTE.
//
// Konsument ist die Standalone-EXE (Suppress-Marker einfuegen, Ctrl+Alt+S
// wie im IDE-Plugin; ReplaceLine/ReadLine fuer Ctrl+Alt+F entfielen am
// 2026-10-10 mit uQuickFix). Das Plugin schreibt in den
// IDE-Editor, wo Strg+Z jede Aenderung zuruecknimmt; hier gibt es kein
// Undo. Deshalb gilt eine harte Regel: NICHTS ausser der Zielzeile darf
// sich aendern - Kodierung (UTF-8 mit/ohne BOM, UTF-16, ANSI),
// Zeilenenden (CRLF/LF/CR, auch gemischt) und ein fehlender Umbruch am
// Dateiende bleiben byte-genau erhalten.
//
// Durchgesetzt wird das nicht durch Sorgfalt, sondern durch eine PROBE:
// vor dem Schreiben wird der UNVERAENDERTE Text mit der erkannten
// Kodierung zurueck in Bytes gewandelt und mit dem Original verglichen.
// Nur bei Byte-Gleichheit wird ueberhaupt geschrieben - eine Datei, die
// die Rueckfahrt nicht uebersteht (exotische Kodierung, kaputte
// Sequenzen), wird mit Fehlermeldung abgelehnt statt still beschaedigt.

interface

type
  TSourceLineEdit = class
  public
    /// <summary>Fuegt AText als eigene Zeile UEBER Zeile ALineNo ein
    /// (1-basiert). Die Einrueckung der Zielzeile wird uebernommen,
    /// der Zeilenumbruch dem Umfeld entnommen.</summary>
    class function InsertLineAbove(const AFileName: string; ALineNo: Integer;
      const AText: string; var AError: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  System.Generics.Collections,   // TList<TSrcLine> (SplitKeepEol)
  uReportFileWriter;             // BeginAtomic/CommitAtomic (WriteBack) -
                                 // derselbe Temp+MoveFileEx-Tausch wie fuer
                                 // die Reports, keine zweite Kopie

const
  // Heute nur noch von InsertLineAbove gebraucht - ReplaceLine/ReadLine
  // entfielen am 2026-10-10 mit uQuickFix. Bleibt Konstante, damit ein
  // Rueckkehrer denselben Wortlaut nimmt (Review Bereich C, Minor).
  SLineOutOfRange = 'line %d out of range (file has %d lines)';

type
  // Eine Zeile = Inhalt + ihr eigener Terminator ('' nur bei der letzten
  // Zeile einer Datei ohne End-Umbruch).
  TSrcLine = record
    Text : string;
    Eol  : string;
  end;

  TSrcFile = record
    Enc    : TEncoding;   // nie besessen (nur Standard-Instanzen)
    Bom    : TBytes;      // die Original-BOM-Bytes ('' = keine)
    Lines  : TArray<TSrcLine>;
  end;

function JoinLines(const F: TSrcFile): string;
var
  SB : TStringBuilder;
  i  : Integer;
begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to High(F.Lines) do
      SB.Append(F.Lines[i].Text).Append(F.Lines[i].Eol);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function EncodeFile(const F: TSrcFile): TBytes;
var
  Body : TBytes;
begin
  Body := F.Enc.GetBytes(JoinLines(F));
  Result := Concat(F.Bom, Body);
end;

procedure SplitKeepEol(const S: string; var Lines: TArray<TSrcLine>);
var
  L     : TList<TSrcLine>;
  i, n  : Integer;
  Start : Integer;
  Line  : TSrcLine;
begin
  L := TList<TSrcLine>.Create;
  try
    n := Length(S);
    i := 1;
    Start := 1;
    while i <= n do
    begin
      if (S[i] = #13) or (S[i] = #10) then
      begin
        Line.Text := Copy(S, Start, i - Start);
        if (S[i] = #13) and (i < n) and (S[i + 1] = #10) then
        begin
          Line.Eol := #13#10;
          Inc(i, 2);
        end
        else
        begin
          Line.Eol := S[i];
          Inc(i);
        end;
        L.Add(Line);
        Start := i;
      end
      else
      begin
        Inc(i);
      end;
    end;
    // Rest ohne End-Umbruch (haeufig bei der letzten Zeile).
    if Start <= n then
    begin
      Line.Text := Copy(S, Start, n - Start + 1);
      Line.Eol  := '';
      L.Add(Line);
    end;
    Lines := L.ToArray;
  finally
    L.Free;
  end;
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and
            ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

// Beginnt Raw mit der BOM? Dann BOM/Body heraustrennen.
function TakeBom(const Raw: TBytes; const ABom: array of Byte;
  var Bom, Body: TBytes): Boolean;
var
  k : Integer;
begin
  if Length(Raw) < Length(ABom) then Exit(False);
  for k := 0 to High(ABom) do
    if Raw[k] <> ABom[k] then Exit(False);
  Bom  := Copy(Raw, 0, Length(ABom));
  Body := Copy(Raw, Length(ABom), MaxInt);
  Result := True;
end;

function DecodeFile(const AFileName: string; var F: TSrcFile;
  var AError: string): Boolean;
var
  Raw   : TBytes;
  Body  : TBytes;
  Text  : string;
begin
  Result := False;
  AError := '';
  F.Bom  := nil;
  try
    Raw := TFile.ReadAllBytes(AFileName);
  except
    // noinspection ExceptionTooGeneral
    // Fehlergrenze mit Klartext-Weitergabe: JEDER Lese-/Dekodierfehler
    // (EInOutError, EEncodingError, EOutOfMemory, ...) muss als AError
    // beim Aufrufer ankommen statt die UI zu sprengen - eine Teilmenge
    // zu fangen hiesse, die uebrigen doch wieder crashen zu lassen.
    on E: Exception do
    begin
      AError := E.Message;
      Exit;
    end;
  end;

  // UTF-32 VOR UTF-16 (Review Woche G03-11): die UTF-32LE-BOM FF FE 00 00
  // beginnt mit der UTF-16LE-BOM. Als UTF-16 gelesen besteht die Datei
  // die Byte-Probe (TUnicodeEncoding kopiert jedes Bytepaar verlustfrei),
  // und die neue Zeile landete als UTF-16 zwischen UTF-32-Zeilen.
  // TEncoding kennt kein UTF-32 - ablehnen statt beschaedigen.
  // Dieselbe Reihenfolge wie uFileTextCache.ComputeFileEncodingInfo.
  if TakeBom(Raw, [$FF, $FE, $00, $00], F.Bom, Body) or
     TakeBom(Raw, [$00, $00, $FE, $FF], F.Bom, Body) then
  begin
    AError := 'UTF-32 files are not supported - file left untouched';
    Exit;
  end;
  if TakeBom(Raw, [$EF, $BB, $BF], F.Bom, Body) then
    F.Enc := TEncoding.UTF8
  else if TakeBom(Raw, [$FF, $FE], F.Bom, Body) then
    F.Enc := TEncoding.Unicode
  else if TakeBom(Raw, [$FE, $FF], F.Bom, Body) then
    F.Enc := TEncoding.BigEndianUnicode
  else
  begin
    Body := Raw;
    // Ohne BOM: strikt UTF-8 versuchen (wirft bei ungueltigen
    // Sequenzen), sonst ANSI. Ob die Wahl TRAEGT, entscheidet unten
    // ohnehin die Byte-Probe - nicht diese Heuristik.
    F.Enc := TEncoding.UTF8;
    try
      F.Enc.GetString(Body);
    except
      F.Enc := TEncoding.Default;
    end;
  end;

  try
    Text := F.Enc.GetString(Body);
  except
    // noinspection ExceptionTooGeneral
    // Fehlergrenze mit Klartext-Weitergabe: JEDER Lese-/Dekodierfehler
    // (EInOutError, EEncodingError, EOutOfMemory, ...) muss als AError
    // beim Aufrufer ankommen statt die UI zu sprengen - eine Teilmenge
    // zu fangen hiesse, die uebrigen doch wieder crashen zu lassen.
    on E: Exception do
    begin
      AError := E.Message;
      Exit;
    end;
  end;
  SplitKeepEol(Text, F.Lines);

  // DIE Probe: unveraendert zurueckkodiert muss byte-identisch sein.
  // Nur dann ist bewiesen, dass ein spaeterer Schreibvorgang nichts
  // ausser der Zielzeile anfasst.
  if not SameBytes(EncodeFile(F), Raw) then
  begin
    AError := 'encoding roundtrip mismatch - file left untouched';
    Exit;
  end;
  Result := True;
end;

procedure SchreibeAtomar(const AFileName: string; const ABytes: TBytes);
// ATOMAR (Review Woche G03-02): erst <Datei>.sca-tmp schreiben, dann per
// MoveFileEx auf den Namen tauschen (TReportFileWriter, Output). Vorher
// schrieb TFile.WriteAllBytes direkt - fmCreate kuerzt die Datei zuerst,
// ein Abbruch danach (Platte voll, Netzlaufwerk weg, Sperre mitten im
// Schreiben) liess eine leere oder abgeschnittene Quelldatei zurueck,
// und hier gibt es kein Undo. Jetzt bleibt bei jedem Fehler die alte
// Datei stehen. Grenze: der Tausch ersetzt den Verzeichniseintrag - eine
// harte Verknuepfung auf die alte Datei sieht den neuen Inhalt nicht.
// Eigene Routine statt zweitem try in WriteBack (NestedTry).
var
  Stream : TFileStream;
begin
  Stream := TReportFileWriter.BeginAtomic(AFileName);
  try
    if Length(ABytes) > 0 then
      Stream.WriteBuffer(ABytes[0], Length(ABytes));
    TReportFileWriter.CommitAtomic(Stream, AFileName);
  except
    // Schreibfehler: Temp weg, Ziel unberuehrt. Scheitert erst der
    // Tausch, hat CommitAtomic den Stream schon freigegeben (nil) und
    // AtomicSwap die Temp-Datei entfernt - Rollback ist dann ein No-Op.
    TReportFileWriter.RollbackAtomic(Stream, AFileName);
    raise;
  end;
end;

function WriteBack(const AFileName: string; const F: TSrcFile;
  var AError: string): Boolean;
begin
  Result := False;
  AError := '';
  try
    SchreibeAtomar(AFileName, EncodeFile(F));
    Result := True;
  except
    // noinspection ExceptionTooGeneral
    // Fehlergrenze, s. DecodeFile - Schreibschutz/Platte-voll/ACL sollen
    // als Text in der Statuszeile landen, nicht als Dialogsturm.
    on E: Exception do
      AError := E.Message;
  end;
end;

function LeadingWhite(const S: string): string;
var
  i : Integer;
begin
  i := 1;
  while (i <= Length(S)) and ((S[i] = ' ') or (S[i] = #9)) do
    Inc(i);
  Result := Copy(S, 1, i - 1);
end;

{ TSourceLineEdit }

class function TSourceLineEdit.InsertLineAbove(const AFileName: string;
  ALineNo: Integer; const AText: string; var AError: string): Boolean;
var
  F       : TSrcFile;
  NewLine : TSrcLine;
  Idx, i  : Integer;
begin
  Result := False;
  if not DecodeFile(AFileName, F, AError) then Exit;
  Idx := ALineNo - 1;
  if (Idx < 0) or (Idx > High(F.Lines)) then
  begin
    AError := Format(SLineOutOfRange, [ALineNo, Length(F.Lines)]);
    Exit;
  end;

  // Einrueckung der Zielzeile uebernehmen - der Marker soll im Code
  // nicht am linken Rand kleben.
  NewLine.Text := LeadingWhite(F.Lines[Idx].Text) + AText;
  // Umbruch der Zielzeile uebernehmen. Hat sie keinen (letzte Zeile
  // ohne End-Umbruch), den der Zeile davor - die neue Zeile steht ja
  // nicht am Dateiende. Notanker: CRLF.
  if F.Lines[Idx].Eol <> '' then
    NewLine.Eol := F.Lines[Idx].Eol
  else if (Idx > 0) and (F.Lines[Idx - 1].Eol <> '') then
    NewLine.Eol := F.Lines[Idx - 1].Eol
  else
    NewLine.Eol := #13#10;

  SetLength(F.Lines, Length(F.Lines) + 1);
  for i := High(F.Lines) downto Idx + 1 do
    F.Lines[i] := F.Lines[i - 1];
  F.Lines[Idx] := NewLine;

  Result := WriteBack(AFileName, F, AError);
end;

end.
