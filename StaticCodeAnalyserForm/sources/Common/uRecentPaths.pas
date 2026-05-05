unit uRecentPaths;

// Gemeinsame MRU-Pfad-Liste fuer den Project-Path-ComboBox.
//
// Vorher: LoadRecentPaths / SaveRecentPath waren in IDE-Plugin und
// Standalone-Form 1:1 dupliziert mit kleinen Unterschieden:
//   - IDE     : pinned Eintrag = aktuelles IDE-Projekt, Position 0,
//               MAX_RECENT = 3
//   - Standalone: pinned Eintrag = App-Pfad, Position end,
//               MAX_RECENT = 4 (= 3 user + 1 app)
// Effektiv bei beiden: 3 user-recent Pfade plus ein "pinned" Eintrag.
//
// Beide Implementierungen hatten unterschiedliche Bugs:
//   - IDE schrieb das pinned IDE-Projekt mit in die INI -> bei naechstem
//     Load doppelt (siehe TODO 🟢 "SaveRecentPath schreibt IDE-Projekt-
//     Eintrag in INI").
//   - Standalone hatte zwei lokale `const MAX_RECENT = 4` Definitionen,
//     die auseinanderdriften konnten.
//
// Diese Unit centralisiert die Logik:
//   - INI-Section "Recent", Keys "Path1".."PathN" (kompatibel zur bisherigen
//     Persistence; bestehende INI-Files lesen weiter)
//   - Pinned-Pfad wird IMMER aus der Persistence ausgeschlossen
//   - Pinned-Position konfigurierbar (vorne / hinten / kein Pin)
//
// API (siehe TRecentPaths) ist klein gehalten: zwei statische
// Klassenmethoden, die jeder Caller mit seiner Combo + INI-Pfad +
// optionalem Pinned-Eintrag aufruft.

interface

uses
  Vcl.StdCtrls;

const
  DEFAULT_MAX_RECENT = 3;

type
  // Wo der Pinned-Eintrag in der Combo erscheint:
  //   ppNone  - kein Pinned-Eintrag (PinnedPath wird ignoriert)
  //   ppFirst - oben, Index 0 (z.B. aktuelles IDE-Projekt)
  //   ppLast  - unten, Index Count-1 (z.B. Standalone-App-Pfad)
  TPinPosition = (ppNone, ppFirst, ppLast);

  TRecentPaths = class
  public
    // Befuellt Combo aus IniPath. Pinned-Pfad wird, falls nicht leer,
    // an PinnedPos eingefuegt (NICHT aus INI gelesen). Combo.Text wird
    // auf den ersten Eintrag gesetzt (oder leer falls nichts da).
    class procedure Load(
      Combo            : TComboBox;
      const IniPath    : string;
      MaxRecent        : Integer = DEFAULT_MAX_RECENT;
      const PinnedPath : string = '';
      PinnedPos        : TPinPosition = ppNone); static;

    // Speichert APath als juengsten Eintrag:
    //   1. Wenn APath = PinnedPath -> kein Save (Pinned persistiert nicht)
    //   2. APath in Combo dedup'en und an Index 0 einfuegen
    //   3. Pinned-Pfad ggf. wieder an die richtige Position bringen
    //   4. Combo auf MaxRecent (+1 fuer Pinned) kuerzen
    //   5. Combo (ohne Pinned) in INI als Path1..PathN schreiben,
    //      ueberzaehlige Keys loeschen
    class procedure Save(
      Combo            : TComboBox;
      const IniPath    : string;
      const APath      : string;
      MaxRecent        : Integer = DEFAULT_MAX_RECENT;
      const PinnedPath : string = '';
      PinnedPos        : TPinPosition = ppNone); static;
  end;

implementation

uses
  System.SysUtils, System.IniFiles;

const
  INI_SECTION = 'Recent';
  INI_KEY_FMT = 'Path%d';

class procedure TRecentPaths.Load(
  Combo            : TComboBox;
  const IniPath    : string;
  MaxRecent        : Integer;
  const PinnedPath : string;
  PinnedPos        : TPinPosition);
var
  Ini  : TIniFile;
  i    : Integer;
  path : string;
begin
  Combo.Items.Clear;

  // Pinned vorne -> erst hinzufuegen, dann INI-Eintraege
  if (PinnedPath <> '') and (PinnedPos = ppFirst) then
    Combo.Items.Add(PinnedPath);

  ForceDirectories(ExtractFilePath(IniPath));
  Ini := TIniFile.Create(IniPath);
  try
    for i := 1 to MaxRecent do
    begin
      path := Ini.ReadString(INI_SECTION, Format(INI_KEY_FMT, [i]), '');
      if path = '' then Continue;
      if (PinnedPath <> '') and SameText(path, PinnedPath) then Continue;
      if Combo.Items.IndexOf(path) >= 0 then Continue;
      Combo.Items.Add(path);
    end;
  finally
    Ini.Free;
  end;

  // Pinned hinten -> jetzt anhaengen, falls noch nicht durch INI drin
  if (PinnedPath <> '') and (PinnedPos = ppLast) then
  begin
    if Combo.Items.IndexOf(PinnedPath) < 0 then
      Combo.Items.Add(PinnedPath);
  end;

  if Combo.Items.Count > 0 then
    Combo.Text := Combo.Items[0]
  else
    Combo.Text := '';
end;

class procedure TRecentPaths.Save(
  Combo            : TComboBox;
  const IniPath    : string;
  const APath      : string;
  MaxRecent        : Integer;
  const PinnedPath : string;
  PinnedPos        : TPinPosition);
var
  Ini      : TIniFile;
  idx      : Integer;
  i        : Integer;
  KeyNum   : Integer;
  TotalCap : Integer;
begin
  // Pinned-Pfad wird nicht persistiert
  if (PinnedPath <> '') and SameText(APath, PinnedPath) then Exit;

  // MRU: APath dedupen und an Position 0 einfuegen
  idx := Combo.Items.IndexOf(APath);
  if idx >= 0 then Combo.Items.Delete(idx);
  Combo.Items.Insert(0, APath);

  // Pinned hinten -> ans Ende verschieben (MRU-Insert oben hat es ggf.
  // verschoben). Pinned vorne: bleibt oben (Insert hat es nach Index 1
  // verdraengt) - das ist OK, Insert(0, APath) heisst APath ist neu MRU,
  // beim naechsten Load wird der Pinned-Eintrag wieder oben einsortiert.
  if (PinnedPath <> '') and (PinnedPos = ppLast) then
  begin
    idx := Combo.Items.IndexOf(PinnedPath);
    if idx >= 0 then Combo.Items.Delete(idx);
    Combo.Items.Add(PinnedPath);
  end;

  // Cap: MaxRecent fuer User-Pfade plus +1 falls Pinned aktiv
  TotalCap := MaxRecent;
  if (PinnedPath <> '') and (PinnedPos <> ppNone) then
    Inc(TotalCap);
  while Combo.Items.Count > TotalCap do
    Combo.Items.Delete(Combo.Items.Count - 1);

  // Text-Property nach Items-Manipulation explizit setzen
  Combo.Text := APath;

  // INI schreiben (Pinned ueberspringen)
  ForceDirectories(ExtractFilePath(IniPath));
  Ini := TIniFile.Create(IniPath);
  try
    KeyNum := 1;
    for i := 0 to Combo.Items.Count - 1 do
    begin
      if KeyNum > MaxRecent then Break;
      if (PinnedPath <> '') and SameText(Combo.Items[i], PinnedPath) then
        Continue;
      Ini.WriteString(INI_SECTION, Format(INI_KEY_FMT, [KeyNum]),
                      Combo.Items[i]);
      Inc(KeyNum);
    end;
    // ueberzaehlige Keys loeschen (z.B. wenn MaxRecent kleiner geworden ist)
    for i := KeyNum to MaxRecent do
      Ini.DeleteKey(INI_SECTION, Format(INI_KEY_FMT, [i]));
  finally
    Ini.Free;
  end;
end;

end.
