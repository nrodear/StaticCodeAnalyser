unit uHardcodedIpInConfig;

// SCA201 HardcodedIpInConfig: IPv4-/IPv6-Adressen als Werte in
// Konfigurationsdateien (.ini) des Quellbaums.
//
// KEIN Registry-Detektor: eine .ini darf nie in die Pascal-Pipeline (rund
// 180 Detektoren und die Indizes laesen sie als Pascal). TStaticFiles
// sammelt die Dateien in eine eigene Liste, TStaticAnalyzer2.ParseLeaks
// ruft AnalyzeFile im Konfigurations-Durchlauf nach der Hauptschleife -
// danach laufen Suppression, Evidenz, PathOverrides und Konfidenz wie fuer
// jeden Fund.
//
// INI-Lesart wie System.IniFiles: ';' am Zeilenanfang ist Kommentar ('#'
// zaehlt hier auch - Kommentare zaehlen nie als Wert), der Wert ist alles
// hinter dem ersten '='. Grammatik, Klassen und Gates (dazu Fliesstext-
// und Versionsschluessel) stehen in uIpAddressScan.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uMethodd12, uAnalyzeContext;

type
  THardcodedIpInConfigDetector = class
  public
    // Eine Konfigurationsdatei, deren Zeilen der Aufrufer schon gelesen hat.
    class procedure AnalyzeFile(const FileName: string; Lines: TStrings;
      Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext = nil); static;
  end;

implementation

uses
  uDetectorUtils, uIpAddressScan;

class procedure THardcodedIpInConfigDetector.AnalyzeFile(const FileName: string;
  Lines: TStrings; Results: TObjectList<TLeakFinding>; AContext: TAnalyzeContext);
var
  H : TIniIpHit;
begin
  if (Lines = nil) or (Results = nil) then Exit;
  // Testverzeichnisse schweigen wie bei SCA200 (Segmente test/tests/spec/
  // fixtures ... gelten fuer jede Endung).
  if TDetectorUtils.IsTestFixturePath(FileName, CtxScanRoot(AContext),
       tplSecret) then
    Exit;
  for H in TIpAddressScan.ScanIniLines(Lines) do
    if H.Reason = '' then
      Results.Add(TLeakFinding.New(FileName, '', H.Line,
        TIpAddressScan.IniMessage(H), fkHardcodedIpInConfig));
end;

end.
