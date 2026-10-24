unit uAtomicFile;

// ATOMARER Dateitausch als BLATT-Unit in Common (Folgewelle des
// Wochen-Reviews 2026-10-21, zu G03-02).
//
// ATOMAR heisst: erst in eine Nachbardatei schreiben, dann per
// MoveFileEx(MOVEFILE_REPLACE_EXISTING) auf den Zielnamen tauschen. Ein
// Abbruch waehrend des Schreibens laesst das Ziel unangetastet (alte
// Datei oder gar keine - nie eine halbe); zurueck bleibt hoechstens die
// Nachbardatei, die der naechste erfolgreiche Lauf ueberschreibt.
//
// WARUM EIGENE UNIT: der Tausch lag unit-privat in uReportFileWriter
// (Output). Seit G03-02 schreibt auch uSourceLineEdit (Common) eine
// Quelldatei auf diesem Weg und band dafuer Output - die Schichtung
// zeigt aber von Output nach Common, nicht umgekehrt. Die dritte Kopie
// stand in TRuleCatalog.WriteUserProfiles (Common) mit eigenem
// MoveFileEx. Jetzt nehmen alle drei den Tausch von hier:
//   uReportFileWriter    - Reports (CSV/JSON/HTML/Katalog, SARIF, Sonar)
//   uSourceLineEdit      - Suppress-Marker in Quelldateien (EXE)
//   uRuleCatalog         - profiles.json (eigene Profile)
// Die Unit bindet nur RTL und Winapi.Windows - keine Engine-Unit.

interface

uses
  System.SysUtils, System.Classes;

type
  TAtomicFile = class
  public
    // <AFileName>.sca-tmp. Fester Name statt GUID: zwei gleichzeitige
    // Schreiber auf DASSELBE Ziel sind so oder so ein Konflikt, und der
    // feste Name macht Reste eines abgebrochenen Laufs deterministisch -
    // der naechste erfolgreiche Save desselben Ziels ueberschreibt sie.
    class function TempNameFor(const AFileName: string): string; static;

    // Tauscht ATemp auf ATarget (ersetzt ein vorhandenes Ziel in einem
    // Schritt). Schlaegt der Tausch fehl, wird ATemp entfernt und
    // EInOutError geworfen - ein STILLER Fehlschlag hiesse "geschrieben",
    // waehrend auf der Platte die alte Datei liegt.
    class procedure Swap(const ATemp, ATarget: string); static;

    // Stream-Trio: BeginWrite liefert einen Schreib-Stream auf
    // TempNameFor(AFileName); Commit schliesst ihn und tauscht atomar aufs
    // Ziel; Rollback schliesst und entfernt die Temp-Datei, das Ziel
    // bleibt unangetastet. Muster beim Aufrufer:
    //   FS := BeginWrite(Ziel);
    //   try ... schreiben ...; Commit(FS, Ziel);
    //   except Rollback(FS, Ziel); raise; end;
    // Scheitert erst der Tausch, hat Commit den Stream schon freigegeben
    // (nil) und Swap die Temp-Datei entfernt - Rollback ist dann ein No-Op.
    class function BeginWrite(const AFileName: string): TFileStream; static;
    class procedure Commit(var AStream: TFileStream;
      const AFileName: string); static;
    class procedure Rollback(var AStream: TFileStream;
      const AFileName: string); static;
  end;

implementation

uses
  Winapi.Windows;   // MoveFileEx - der atomare Tausch

{ TAtomicFile }

class function TAtomicFile.TempNameFor(const AFileName: string): string;
begin
  Result := AFileName + '.sca-tmp';
end;

class procedure TAtomicFile.Swap(const ATemp, ATarget: string);
// MOVEFILE_REPLACE_EXISTING ersetzt ein vorhandenes Ziel in einem
// Schritt; MOVEFILE_WRITE_THROUGH laesst den Aufruf erst nach dem
// physischen Abschluss zurueckkehren. Grenze: der Tausch ersetzt den
// Verzeichniseintrag - eine harte Verknuepfung auf die alte Datei sieht
// den neuen Inhalt nicht.
//
// Der Meldetext nennt "Datei", nicht "Report": derselbe Tausch schreibt
// Quelldateien (uSourceLineEdit) und profiles.json.
var
  Fehler : DWORD;
begin
  if not MoveFileEx(PChar(ATemp), PChar(ATarget),
       MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
  begin
    Fehler := GetLastError;
    System.SysUtils.DeleteFile(ATemp);
    raise EInOutError.CreateFmt(
      'Datei konnte nicht nach "%s" getauscht werden: %s',
      [ATarget, SysErrorMessage(Fehler)]);
  end;
end;

class function TAtomicFile.BeginWrite(const AFileName: string): TFileStream;
begin
  Result := TFileStream.Create(TempNameFor(AFileName), fmCreate);
end;

class procedure TAtomicFile.Commit(var AStream: TFileStream;
  const AFileName: string);
begin
  FreeAndNil(AStream);
  Swap(TempNameFor(AFileName), AFileName);
end;

class procedure TAtomicFile.Rollback(var AStream: TFileStream;
  const AFileName: string);
begin
  FreeAndNil(AStream);
  System.SysUtils.DeleteFile(TempNameFor(AFileName));
end;

end.
