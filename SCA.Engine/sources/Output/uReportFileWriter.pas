unit uReportFileWriter;

// ATOMARE Schreibwege fuer Report-Dateien (CSV/JSON/HTML/Katalog;
// SARIF/Sonar folgen ueber das Stream-Trio).
//
// WARUM EIGENE UNIT (C-Charge 2026-09-19): zwei dokumentierte Posten
// in einem Zug -
//   1. Charge-22-Restposten "halb geschriebene Report-Dateien bleiben
//      liegen": alle Writer schrieben DIREKT aufs Ziel; ein Abbruch
//      mitten im Schreiben (Platte voll, Prozess-Kill, Exception im
//      Builder) hinterliess einen halben Report unter dem Zielnamen -
//      fuer eine CI-Pipeline ununterscheidbar von einem ganzen.
//   2. SCA141-Folgearbeit: die Schreibwege (SaveBuilderUtf8,
//      SaveUtf8WithBom) haben mit "Befundlisten exportieren" nichts zu
//      tun und verliessen TExporter (uExport) in diese kleine Klasse.
//
// ATOMAR heisst hier: erst nach <Ziel>.sca-tmp schreiben, dann per
// MoveFileEx(MOVEFILE_REPLACE_EXISTING) auf den Zielnamen tauschen.
// Ein Abbruch waehrend des Schreibens laesst das Ziel unangetastet
// (alter Report oder gar keiner - nie ein halber); zurueck bleibt
// hoechstens eine .sca-tmp, die der naechste erfolgreiche Lauf
// ueberschreibt.
//
// SCHICHTUNG: Output-Unit mit Absicht - Output darf Infrastructure
// nicht nutzen (Kommentar in uFindingCopyText.BuildJiraMini), also
// muss der gemeinsame Schreiber HIER liegen, damit uExport
// (Infrastructure) UND uExportSARIF/uExportSonarGeneric (Output) ihn
// rufen koennen.

interface

uses
  System.SysUtils, System.Classes;

type
  TReportFileWriter = class
  public
    // Schreibt einen TStringBuilder stueckweise als UTF-8 - atomar.
    // AMitBom steuert die Praeambel: True fuer CSV und HTML, False fuer
    // JSON (RFC 8259 par.8.1).
    //
    // WARUM NICHT UEBER TStringList: der Weg
    //   SL.Text := SB.ToString;  SaveUtf8*(SL, ...)
    // legt vor dem ersten Byte auf Platte VIER volle Kopien an - den
    // Builder, den ToString-String, die in Zeilen zerlegte Liste und den
    // von SaveToStream daraus wieder zusammengesetzten Text. Am Korpus-
    // Bericht hat genau dieses Muster im HTML-Export eine Spitze von rund
    // 8,4 GB erzeugt und dabei Exit-Code UND Zusammenfassung eines
    // ansonsten erfolgreichen Scans verworfen (T1 des HTML-Reviews,
    // 2026-08-05). Hier bleibt die Spitze der Builder plus ein Fenster
    // von wenigen Megabyte.
    //
    // SURROGATE: eine Stueckgrenze darf kein Surrogatpaar zerschneiden,
    // sonst kodiert GetBytes jede Haelfte fuer sich und die Datei ist
    // dort still kaputt. Liegt die letzte Stelle eines Stuecks auf einer
    // HOHEN Haelfte ($D800..$DBFF), wandert die Grenze um ein Zeichen
    // zurueck. Der Ordinalvergleich steht bewusst statt
    // TCharacter.IsHighSurrogate - er braucht keine weitere Unit.
    //
    // Historie: lag als TExporter.SaveBuilderUtf8 in uExport
    // (Infrastructure) und davor als TExporterHtml.SaveBuilderUtf8WithBom
    // in der HTML-Unit; die alten Einstiegspunkte delegieren hierher.
    class procedure SaveBuilderUtf8(ABuilder: TStringBuilder;
      const FileName: string; AMitBom: Boolean); static;

    // Speichert eine TStringList als UTF-8 MIT BOM (EF BB BF) - atomar.
    // Umgesetzt ueber SL.WriteBOM := True (D11-kompatibel, byte-identisch
    // zur frueheren TUTF8Encoding-Variante). Einziger Produktiv-Aufrufer
    // ist der Detektor-Katalog (uDetectorInfoExport); CSV und HTML gehen
    // ueber SaveBuilderUtf8.
    class procedure SaveUtf8WithBom(SL: TStringList;
      const FileName: string); static;

    // Stream-Trio fuer die STROM-Writer (SARIF-Chunk-Emitter, Sonar):
    // BeginAtomic liefert einen Schreib-Stream auf <FileName>.sca-tmp;
    // CommitAtomic schliesst ihn und tauscht atomar aufs Ziel;
    // RollbackAtomic schliesst und entfernt die Temp-Datei, das Ziel
    // bleibt unangetastet. Der Aufrufer haelt das uebliche Muster:
    //   FS := BeginAtomic(Ziel);
    //   try ... schreiben ...; CommitAtomic(FS, Ziel);
    //   except RollbackAtomic(FS, Ziel); raise; end;
    // Commit/Rollback uebernehmen den Stream (setzen nichts voraus als
    // einen von BeginAtomic gelieferten).
    class function BeginAtomic(const FileName: string): TFileStream; static;
    class procedure CommitAtomic(var AStream: TFileStream;
      const FileName: string); static;
    class procedure RollbackAtomic(var AStream: TFileStream;
      const FileName: string); static;
  end;

implementation

uses
  Winapi.Windows;   // MoveFileEx - der atomare Tausch

// Fester Temp-Name statt GUID: zwei gleichzeitige Schreiber auf
// DASSELBE Ziel sind so oder so ein Konflikt, und der feste Name macht
// Reste eines abgebrochenen Laufs deterministisch - der naechste
// erfolgreiche Save desselben Ziels ueberschreibt sie.
function TempNameFor(const FileName: string): string;
begin
  Result := FileName + '.sca-tmp';
end;

procedure AtomicSwap(const ATemp, AZiel: string);
// MOVEFILE_REPLACE_EXISTING ersetzt ein vorhandenes Ziel in einem
// Schritt; MOVEFILE_WRITE_THROUGH laesst den Aufruf erst nach dem
// physischen Abschluss zurueckkehren. Schlaegt der Tausch fehl, wird
// die Temp-Datei entfernt und der Fehler gemeldet - ein STILLER
// Fehlschlag hiesse "Report geschrieben", waehrend auf der Platte der
// alte liegt (dasselbe Argument, mit dem der BaseDir-Vertrag verworfen
// wurde).
var
  Fehler : DWORD;
begin
  if not MoveFileEx(PChar(ATemp), PChar(AZiel),
       MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
  begin
    Fehler := GetLastError;
    System.SysUtils.DeleteFile(ATemp);
    raise EInOutError.CreateFmt(
      'Report konnte nicht nach "%s" getauscht werden: %s',
      [AZiel, SysErrorMessage(Fehler)]);
  end;
end;

{ TReportFileWriter }

// noinspection BooleanParam
// AMitBom IST die BOM-Politik, nicht ein Schalter davor. Ein
// Methodenpaar wuerde entweder die Stueckelung samt Surrogat-
// Behandlung verdoppeln oder einen privaten Kern brauchen, der
// denselben Parameter traegt - beides schlechter als die eine Zeile
// hier. Dieselbe Abwaegung fuehrt uExportSonarGeneric mit demselben
// Marker.
//
// Der Marker steht VOR der Signatur, nicht im Kommentarblock darunter:
// gemessen (Selbstscan 08.09.) haengt der Fund an der Signaturzeile,
// und ein Marker dahinter unterdrueckt nichts - er wird dann selbst
// zum Fund (SCA165).
class procedure TReportFileWriter.SaveBuilderUtf8(ABuilder: TStringBuilder;
  const FileName: string; AMitBom: Boolean);
const
  CHUNK = 1024 * 1024;   // Zeichen, nicht Bytes
var
  Temp              : string;
  Stream            : TFileStream;
  Preamble, Bytes   : TBytes;
  Start, Len, Total : Integer;
  Part              : string;
begin
  // nil-Builder: wie ein LEERER Builder behandeln, nicht mit einer AV
  // quittieren. Dieselbe Zusage, mit der der Sonar-Writer am 08.09.
  // seinen nil-Guard bekommen hat - eine public Methode der
  // Ausgabeschicht stirbt nicht an einer leeren Eingabe.
  //
  // Bewusst KEIN frueher Exit: sonst bekaeme die nil-Datei kein BOM,
  // waehrend die Datei aus einem leeren Builder eines traegt. Zwei
  // Leerfaelle mit verschiedenen Bytes waeren eine Falle fuer den
  // naechsten Vergleich.
  if Assigned(ABuilder) then
    Total := ABuilder.Length
  else
    Total := 0;
  Temp := TempNameFor(FileName);
  Stream := TFileStream.Create(Temp, fmCreate);
  try
    try
      if AMitBom then
      begin
        Preamble := TEncoding.UTF8.GetPreamble;
        if Length(Preamble) > 0 then
          Stream.WriteBuffer(Preamble[0], Length(Preamble));
      end;
      Start := 0;
      while Start < Total do
      begin
        Len := CHUNK;
        if Start + Len >= Total then
          Len := Total - Start
        else if (Ord(ABuilder.Chars[Start + Len - 1]) >= $D800) and
                (Ord(ABuilder.Chars[Start + Len - 1]) <= $DBFF) then
          Dec(Len);
        Part  := ABuilder.ToString(Start, Len);
        Bytes := TEncoding.UTF8.GetBytes(Part);
        if Length(Bytes) > 0 then
          Stream.WriteBuffer(Bytes[0], Length(Bytes));
        Inc(Start, Len);
      end;
    except
      // Abbruch mitten im Schreiben: Temp weg, Ziel bleibt unberuehrt -
      // genau der Vertrag dieser Unit. Der Fehler geht weiter.
      Stream.Free;
      Stream := nil;
      System.SysUtils.DeleteFile(Temp);
      raise;
    end;
  finally
    Stream.Free;
  end;
  AtomicSwap(Temp, FileName);
end;

class procedure TReportFileWriter.SaveUtf8WithBom(SL: TStringList;
  const FileName: string);
var
  Temp : string;
begin
  // WriteBOM=True + TEncoding.UTF8 schreibt die EF BB BF Preamble.
  // (Vorher TUTF8Encoding.Create(True) - der Bool-Konstruktor existiert
  // erst seit Delphi 12; TStrings.WriteBOM ist D11-kompatibel und
  // byte-identisch im Output.)
  Temp := TempNameFor(FileName);
  SL.WriteBOM := True;
  try
    SL.SaveToFile(Temp, TEncoding.UTF8);
  except
    System.SysUtils.DeleteFile(Temp);
    raise;
  end;
  AtomicSwap(Temp, FileName);
end;

class function TReportFileWriter.BeginAtomic(
  const FileName: string): TFileStream;
begin
  Result := TFileStream.Create(TempNameFor(FileName), fmCreate);
end;

class procedure TReportFileWriter.CommitAtomic(var AStream: TFileStream;
  const FileName: string);
begin
  FreeAndNil(AStream);
  AtomicSwap(TempNameFor(FileName), FileName);
end;

class procedure TReportFileWriter.RollbackAtomic(var AStream: TFileStream;
  const FileName: string);
begin
  FreeAndNil(AStream);
  System.SysUtils.DeleteFile(TempNameFor(FileName));
end;

end.
