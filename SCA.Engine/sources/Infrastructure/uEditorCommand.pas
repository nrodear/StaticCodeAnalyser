unit uEditorCommand;

// Womit ein Befund geoeffnet wird: eingebauter Betrachter, Delphi-IDE oder
// ein frei konfigurierter externer Editor.
//
// Diese Unit haelt AUSSCHLIESSLICH die reine Logik - Einstellungen lesen,
// Platzhalter ersetzen, den konfigurierten Pfad pruefen. Sie startet
// NICHTS. Das Starten liegt beim Aufrufer (in der EXE), damit dieser Teil
// hier ohne VCL, ohne Fenster und ohne Prozessstart testbar bleibt.
//
// Warum es die Option ueberhaupt gibt: die Standalone-EXE kann einen Fund
// nur ueber den Windows-Standardhandler oeffnen und die Zeile danach mit
// simulierten Tastenanschlaegen anspringen (uMainForm.NavigateDelphiToLine).
// Das ist unvermeidlich fragil - die IDE bietet von aussen keinen Schalter
// fuer eine Zeilennummer, und der Weg des Plugins ueber die ToolsAPI ist
// aus einem Fremdprozess nicht nachbaubar. Ein externer Editor, der eine
// Zeilennummer auf der Kommandozeile annimmt, trifft dagegen immer.

interface

type
  /// <summary>Was ein Doppelklick auf einen .dfm-Befund oeffnen soll.</summary>
  /// <remarks>
  ///   Greift nur, wenn KEIN externer Editor eingerichtet ist - ein
  ///   eingerichteter Editor gilt fuer alle Dateiarten.
  /// </remarks>
  TDfmTarget = (
    dtIde,      // Delphi-IDE. Faellt auf den Betrachter zurueck, wenn kein
                // Handler antwortet.
    dtViewer    // Eingebauter Textbetrachter (uDfmTextViewer).
  );

  /// <summary>Die eingerichtete Oeffnen-Strategie, wie sie in der INI steht.</summary>
  TEditorSpec = record
    Exe       : string;      // leer = kein externer Editor
    ArgsTpl   : string;      // Vorlage mit Platzhaltern, s. Expand
    DfmTarget : TDfmTarget;
  end;

  TEditorCommand = record
  public
    const
      /// <summary>INI-Abschnitt und Schluessel - auch von der EXE beim Schreiben benutzt.</summary>
      INI_SECTION   = 'Editor';
      KEY_EXE       = 'ExternalEditor';
      KEY_ARGS      = 'ExternalEditorArgs';
      KEY_DFMTARGET = 'DfmTarget';

      /// <summary>Vorgabe: Visual Studio Code, weil dessen Aufrufform die
      /// verbreitetste ist. Sie greift NUR, wenn ExternalEditor gesetzt ist.</summary>
      // Frueher stand hier ein 'noinspection PublicField' samt Vermerk
      // "eigener Fehlbefund, Ursache ungeklaert": SCA089 las den
      // const-Abschnitt dieses Verbunds als oeffentliche Felder und schlug
      // eine Eigenschaft vor - in die sich eine Konstante gar nicht
      // umbauen laesst. Die Ursache ist seit 2026-08-27 geklaert und
      // behoben: das G2-Gate ueberspringt Zeilen mit '=' (Typaliase und
      // typisierte Konstanten sind Deklarationen, keine Felder). Der
      // Marker war damit tot und wurde von unserer eigenen Regel
      // UnusedSuppression gemeldet - Dogfooding, das funktioniert hat.
      DEFAULT_ARGS  = '-g "%file%:%line%"';

    /// <summary>Liest die Einstellungen aus der analyser.ini.</summary>
    /// <remarks>
    ///   Bewusst ueber TRepoSettings.QuickReadStr statt ueber eine volle
    ///   TRepoSettings-Instanz: ein Doppelklick soll die frisch geaenderte
    ///   INI sehen, ohne dass erst ein Analyselauf sie neu einliest.
    /// </remarks>
    class function Load: TEditorSpec; static;

    /// <summary>Setzt die Platzhalter einer Argumentvorlage ein.</summary>
    /// <remarks>
    ///   Erkannt werden (Gross-/Kleinschreibung egal):
    ///     %file%  voller Pfad der Datei
    ///     %line%  Zeilennummer, mindestens 1
    ///     %col%   Spalte, mindestens 1
    ///     %dir%   Verzeichnis der Datei, ohne abschliessenden Trenner
    ///     %%      ein woertliches Prozentzeichen
    ///   Alles andere zwischen Prozentzeichen bleibt unveraendert stehen -
    ///   ein Pfad wie C:\50%%\x.pas ueberlebt das also.
    ///
    ///   BEQUEMLICHKEIT MIT ABSICHT: enthaelt der eingesetzte Wert ein
    ///   Leerzeichen und steht der Platzhalter nicht ohnehin schon in
    ///   einem Anfuehrungsbereich, wird er in welche gesetzt. Die
    ///   haeufigste Fehlbedienung ist eine Vorlage ohne Anfuehrungszeichen
    ///   plus ein Pfad mit Leerzeichen; das Ergebnis waere ein Editor, der
    ///   wortlos die falsche (oder gar keine) Datei oeffnet.
    ///
    ///   Ersetzt wird in EINEM Durchlauf von links nach rechts, nicht mit
    ///   mehreren StringReplace nacheinander. Sonst koennte ein bereits
    ///   eingesetzter Wert, der selbst nach einem Platzhalter aussieht,
    ///   von der naechsten Ersetzung noch einmal angefasst werden.
    /// </remarks>
    class function Expand(const ATemplate, AFile: string;
      ALine: Integer = 0; ACol: Integer = 0): string; static;

    /// <summary>Ist das ein Programm, das man starten kann?</summary>
    /// <remarks>
    ///   Zwei Bedingungen: die Datei existiert, und die Endung ist eine
    ///   ausfuehrbare. Das ist dieselbe Strenge, mit der schon der
    ///   eingerichtete Git-Pfad geprueft wird (uVcsChanges).
    ///
    ///   .bat und .cmd sind zugelassen, weil Leute ihren Editor gern in
    ///   ein Skript wickeln - man sollte aber wissen, dass ein Skript
    ///   seine Argumente noch einmal durch den Kommandozeilen-Interpreter
    ///   schickt. Eine .exe ist die robustere Wahl.
    /// </remarks>
    class function IsLaunchableExe(const APath: string): Boolean; static;

    class function DfmTargetToStr(AValue: TDfmTarget): string; static;
    class function StrToDfmTarget(const AValue: string): TDfmTarget; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,   // MatchStr, PosEx
  System.Math,       // Max
  uRepoSettings;

{ TEditorCommand }

class function TEditorCommand.DfmTargetToStr(AValue: TDfmTarget): string;
begin
  case AValue of
    dtViewer: Result := 'viewer';
  else
    Result := 'ide';
  end;
end;

class function TEditorCommand.StrToDfmTarget(const AValue: string): TDfmTarget;
begin
  // Unbekanntes gilt als 'ide' - das ist die Vorgabe, und ein Tippfehler in
  // der INI soll nicht in den eingebauten Betrachter zurueckfallen, ohne
  // dass jemand das gewollt haette.
  if SameText(Trim(AValue), 'viewer') then
    Result := dtViewer
  else
    Result := dtIde;
end;

class function TEditorCommand.Load: TEditorSpec;
begin
  Result.Exe     := Trim(TRepoSettings.QuickReadStr(INI_SECTION, KEY_EXE, ''));
  Result.ArgsTpl := Trim(TRepoSettings.QuickReadStr(INI_SECTION, KEY_ARGS, ''));
  // Leere Vorlage bei eingerichtetem Editor waere ein Aufruf ganz ohne
  // Dateinamen - der Editor ginge dann mit leerem Fenster auf. Die Vorgabe
  // ist immerhin ein Aufruf, der eine Datei uebergibt.
  if (Result.Exe <> '') and (Result.ArgsTpl = '') then
    Result.ArgsTpl := DEFAULT_ARGS;
  Result.DfmTarget := StrToDfmTarget(
    TRepoSettings.QuickReadStr(INI_SECTION, KEY_DFMTARGET, 'ide'));
end;

class function TEditorCommand.IsLaunchableExe(const APath: string): Boolean;
var
  Ext : string;
begin
  Result := False;
  if Trim(APath) = '' then Exit;
  if not FileExists(APath) then Exit;
  Ext := LowerCase(ExtractFileExt(APath));
  Result := MatchStr(Ext, ['.exe', '.com', '.bat', '.cmd']);
end;

// --- Helfer fuer Expand ------------------------------------------------
// Freistehend, nicht verschachtelt: so bleibt Expand selbst flach genug,
// um sie am Stueck lesen zu koennen.

/// <summary>Wert zu einem Platzhalternamen. False = unbekannt.</summary>
function TryValueOf(const AName, AFile: string; ALine, ACol: Integer;
  var AValue: string): Boolean;
begin
  Result := True;
  if SameText(AName, 'file') then
    AValue := AFile
  else if SameText(AName, 'line') then
    // Editoren zaehlen ab 1; eine 0 waere fuer manche ein Fehler und fuer
    // andere "letzte Zeile". Unbekannt heisst hier: Dateianfang.
    AValue := IntToStr(Max(ALine, 1))
  else if SameText(AName, 'col') then
    AValue := IntToStr(Max(ACol, 1))
  else if SameText(AName, 'dir') then
    AValue := ExcludeTrailingPathDelimiter(ExtractFilePath(AFile))
  else
    Result := False;
end;

/// <summary>Steht die Stelle vor APos in einem Anfuehrungsbereich?</summary>
/// <remarks>
///   Ueber die ANZAHL der Anfuehrungszeichen davor, nicht ueber die beiden
///   Nachbarzeichen: bei -g "%file%:%line%" ist %file% sehr wohl in
///   Anfuehrungszeichen, steht aber nicht unmittelbar zwischen zweien.
///   Ungerade Anzahl = drin.
/// </remarks>
function InQuotedRegion(const AText: string; APos: Integer): Boolean;
var
  k : Integer;
begin
  Result := False;
  for k := 1 to APos - 1 do
    if AText[k] = '"' then
      Result := not Result;
end;

class function TEditorCommand.Expand(const ATemplate, AFile: string;
  ALine: Integer = 0; ACol: Integer = 0): string;
var
  SB      : TStringBuilder;
  i, j    : Integer;
  Value   : string;
begin
  // TStringBuilder statt 'Result := Result + ...': die Schleife laeuft
  // ueber jedes einzelne Zeichen, und das waere quadratisch.
  SB := TStringBuilder.Create;
  try
    i := 1;
    while i <= Length(ATemplate) do
    begin
      // Alles ausser '%' geht unveraendert durch.
      if ATemplate[i] <> '%' then
      begin
        SB.Append(ATemplate[i]);
        Inc(i);
        Continue;
      end;

      // '%%' ist ein woertliches Prozentzeichen.
      if (i < Length(ATemplate)) and (ATemplate[i + 1] = '%') then
      begin
        SB.Append('%');
        Inc(i, 2);
        Continue;
      end;

      // Schliessendes '%' suchen. Fehlt es, ist das kein Platzhalter,
      // sondern ein einzelnes Prozentzeichen.
      j := PosEx('%', ATemplate, i + 1);
      if (j = 0)
         or (not TryValueOf(Copy(ATemplate, i + 1, j - i - 1),
                            AFile, ALine, ACol, Value)) then
      begin
        // Unbekannt oder unvollstaendig - unveraendert uebernehmen.
        if j = 0 then
        begin
          SB.Append(ATemplate[i]);
          Inc(i);
        end
        else
        begin
          SB.Append(Copy(ATemplate, i, j - i + 1));
          i := j + 1;
        end;
        Continue;
      end;

      if (Pos(' ', Value) > 0) and (not InQuotedRegion(ATemplate, i)) then
        Value := '"' + Value + '"';
      SB.Append(Value);
      i := j + 1;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

end.
