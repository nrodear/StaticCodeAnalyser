unit uEngineLock;

// Prozessweiter Engine-Lock als BLATT-Unit (Review Bereich C Engine-Kern,
// Major 11, 2026-10-14).
//
// WARUM eine eigene Unit: der Lock lag bis dahin in uEngineApi. Die
// einzige Fremd-Kante dorthin war uRepoSettings.PersistDiscoveredClasses,
// das fuer seinen Schnappschuss der Discovery-Globals nur den Lock
// brauchte - und dafuer die ganze Fassade samt Quellstellen-Dienst
// (uSourcePlaces im interface-uses von uEngineApi) in jeden Scan-Pfad
// linkte. tools/places_dep_gate.py musste diese Kante als bekannte
// Ausnahme fuehren. Jetzt zeigt die Abhaengigkeit in eine Richtung:
// uEngineApi und uRepoSettings nehmen den Lock von hier, kennen sich
// gegenseitig nicht mehr ueber ihn.
//
// Vertrag (unveraendert seit uEngineApi, Welle 1 2026-07-20):
//   * serialisiert ALLE Engine-Scans prozessweit - der Engine-Zustand
//     (LeakyClasses/DiscoveredClasses/Config-Globale in uSCAConsts) ist
//     nicht thread-sicher und wird waehrend des Scans mutiert;
//   * REKURSIV (TCriticalSection ist reentrant): ein Halter, der danach
//     TAnalysisSession.Run ruft, re-entert dessen internes Enter;
//   * NIE ueber Synchronize/ProcessMessages hinweg halten - ein wartender
//     UI-Thread und ein Worker, der auf den UI-Thread wartet, blockieren
//     sich sonst gegenseitig;
//   * TryAcquireEngineLock fuer UI-Thread-Aufrufer, die bei besetztem
//     Lock ueberspringen statt einzufrieren muessen (Silent-Scan gegen
//     laufenden Bulk-/Watch-Lauf). True = gehalten, der Aufrufer MUSS
//     ReleaseEngineLock rufen.
// Seriell (CLI/EXE) ist der Lock unkontent und damit verhaltensneutral.

interface

procedure AcquireEngineLock;
procedure ReleaseEngineLock;
function TryAcquireEngineLock: Boolean;

implementation

uses
  System.SysUtils, System.SyncObjs;

var
  GEngineLock : TCriticalSection = nil;

procedure AcquireEngineLock;
begin
  GEngineLock.Enter;
end;

procedure ReleaseEngineLock;
begin
  GEngineLock.Leave;
end;

function TryAcquireEngineLock: Boolean;
begin
  Result := GEngineLock.TryEnter;
end;

initialization
  GEngineLock := TCriticalSection.Create;

finalization
  FreeAndNil(GEngineLock);

end.
