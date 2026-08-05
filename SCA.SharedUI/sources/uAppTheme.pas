unit uAppTheme;

// Hell/Dunkel fuer die STANDALONE-Anwendung.
//
// Abgrenzung zum IDE-Plugin: das Plugin faerbt bewusst PRO CONTROL ein
// (TIDETheme) und ruft NIE TStyleManager - ein globaler Style wuerde die
// ganze IDE mitreissen. Die EXE ist der einzige Ort im Produkt, an dem ein
// globaler VCL-Style richtig ist; genau das macht diese Unit.
//
// Die Farbableitung darunter ist bereits vorhanden und braucht nichts
// Neues: uAnalyserTheme.ActiveStyleServices faellt ohne gesetzten
// StyleServicesProvider auf Vcl.Themes.StyleServices zurueck, also auf
// TStyleManager.ActiveStyle. Ein gesetzter Style wirkt damit automatisch
// bis in SeverityBg und den Grid-Renderer durch.
//
// WICHTIG - STYLE-VERFUEGBARKEIT: ein VCL-Style muss in die EXE GELINKT
// sein (Projektoptionen > Anwendung > Erscheinungsbild). Ist er das nicht,
// liefert TStyleManager.TrySetStyle einfach False. Diese Unit behandelt
// das als Normalfall und bleibt dann beim hellen Systemstil - kein
// Absturz, nur kein Dunkelmodus. Solange 'Windows10Dark' nicht angehakt
// ist, ist der Dunkelmodus also wirkungslos.
//
// Windows-Erkennung: HKCU\...\Themes\Personalize\AppsUseLightTheme
// (DWORD, 0 = dunkel). Der Wert fehlt auf Windows 8.1 und aelter - dann
// gilt hell. Die RTL kennt diesen Schluessel nicht, das ist Handarbeit.

interface

uses
  System.Classes, System.Generics.Collections,
  Vcl.Graphics,   // TColor
  Vcl.Controls,   // TWinControl (ResolveSystemColors)
  Vcl.Themes;     // TStyleServicesHandle (Klassenfeld FDarkHandle)

type
  /// <summary>Gemerkte Original-Farben eines Controls.</summary>
  TAppThemeColors = record
    Color     : TColor;
    FontColor : TColor;
  end;

  /// <summary>Woher die Hell/Dunkel-Entscheidung kommt.</summary>
  TAppThemeMode = (
    atmSystem,   // dem Windows-Systemthema folgen (Auslieferwert)
    atmLight,    // fest hell
    atmDark      // fest dunkel
  );

  TAppTheme = class
  private
    class var FMode      : TAppThemeMode;
    class var FOnChanged : TNotifyEvent;
    class var FApplying  : Boolean;
    // TStyleServicesHandle ist ein PUBLIC TYPE innerhalb von TStyleManager
    // (Vcl.Themes.pas:1771, '= type Pointer') - unqualifiziert ist der
    // Bezeichner E2003. Der erste Build hat genau das gezeigt.
    class var FDarkHandle: TStyleManager.TStyleServicesHandle;
    // Originalfarben je Control - s. ResolveSystemColors.
    class var FOrigColors: TDictionary<Pointer, TAppThemeColors>;
    class function ModeToStr(AMode: TAppThemeMode): string; static;
    class function StrToMode(const S: string): TAppThemeMode; static;
    // Roher Registry-Zugriff. Wirft bei unlesbarer Registry - der
    // Aufrufer SystemPrefersDark faengt das ab. Getrennt, damit die
    // Freigabe per try/finally sauber bleibt und kein try/except sie
    // ueberspringt.
    class function ReadSystemDark: Boolean; static;
    // Eine nicht schreibbare Konfiguration darf die Umschaltung nicht
    // verhindern - die Wahl gilt dann nur fuer diese Sitzung. Bewusst
    // OHNE Rueckgabewert: niemand wertet ihn aus, und ein ungenutztes
    // Result ist H2077.
    class procedure PersistMode(AMode: TAppThemeMode); static;
    class function ActiveStyleIsDark: Boolean; static;
    class procedure ApplyStyle; static;
  public
    /// <summary>
    ///   True, wenn Windows den dunklen Modus fuer Anwendungen meldet.
    ///   Fehlt der Registry-Wert (Windows 8.1 und aelter), False.
    /// </summary>
    class function SystemPrefersDark: Boolean; static;

    /// <summary>
    ///   Wirkt sich JETZT dunkel aus? Bei atmSystem die Systemantwort,
    ///   sonst die feste Wahl.
    /// </summary>
    class function EffectiveDark: Boolean; static;

    /// <summary>
    ///   Gemerkte Wahl aus analyser.ini lesen und den Style setzen. Vor
    ///   Application.CreateForm rufen, damit die Form schon im richtigen
    ///   Stil entsteht und nicht sichtbar umspringt.
    /// </summary>
    class procedure Initialize; static;

    /// <summary>Wahl setzen, merken und sofort anwenden.</summary>
    class procedure SetMode(AMode: TAppThemeMode); static;

    /// <summary>
    ///   Auf WM_SETTINGCHANGE mit Section 'ImmersiveColorSet' rufen.
    ///   Wirkt nur im Modus atmSystem und nur, wenn sich die Antwort
    ///   tatsaechlich geaendert hat - sonst waere jeder Einstellungs-
    ///   Broadcast ein Voll-Repaint.
    /// </summary>
    class procedure HandleSystemThemeChanged; static;

    /// <summary>
    ///   Loest Systemfarb-Bezeichner (clBtnFace, clWindow, clBtnText, ...)
    ///   auf konkrete RGB-Werte des AKTIVEN Styles auf - rekursiv ab
    ///   ARoot. Nur fuer Controls, die den Style fuer diesen Aspekt
    ///   ABGESCHALTET haben (seClient bzw. seFont nicht in
    ///   StyleElements); alle anderen faerbt der Style selbst.
    /// </summary>
    /// <remarks>
    ///   Warum das noetig ist: Windows' Dunkelmodus aendert die
    ///   KLASSISCHEN Systemfarben NICHT. GetSysColor(COLOR_BTNFACE)
    ///   liefert weiterhin Hellgrau - und genau darauf greift
    ///   Vcl.Graphics.ColorToRGB zu, wenn ein Control mit seiner eigenen
    ///   Color malt. Die Kacheln blieben deshalb weiss, waehrend der Rest
    ///   dunkel war (Abnahme 2026-08-05).
    ///
    ///   Aufgeloest wird immer gegen den ORIGINAL-Bezeichner: nach dem
    ///   ersten Aufloesen ist das clSystemColor-Bit weg und ein zweiter
    ///   Wechsel haette nichts mehr zu tun. Die Originalwerte liegen
    ///   deshalb je Control in einem Cache - dieselbe Falle, die das
    ///   Plugin als "Second-Switch-Bug" dokumentiert.
    /// </remarks>
    class procedure ResolveSystemColors(ARoot: TWinControl); static;

    class property Mode: TAppThemeMode read FMode;

    /// <summary>
    ///   Wird nach jedem wirksamen Wechsel gerufen. Die Form haengt hier
    ///   ihr Neuzeichnen ein (Grid, Kacheln, Hilfe-Panel) - ein
    ///   VCL-Style-Wechsel allein erreicht selbstgezeichnete Flaechen
    ///   nicht.
    /// </summary>
    class property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  System.SysUtils, System.Win.Registry, System.IniFiles,
  Winapi.Windows,
  Vcl.Styles,
  uRepoSettings;

const
  // Der native Windows-Stil. Bewusst NICHT 'Windows10': ohne gesetzten
  // Style zeichnet die VCL nativ, und genau so sieht die Anwendung heute
  // im hellen Fall aus. 'Windows10' waere ein VCL-gezeichneter Nachbau -
  // eine sichtbare Aenderung fuer alle, die gar keinen Dunkelmodus wollen.
  STYLE_LIGHT = 'Windows';

  // Der dunkle Style liegt als RCDATA-Ressource in der EXE
  // (styles\sca_styles.RES, gelinkt im .dpr). Aktiviert wird er ueber
  // das HANDLE aus TryLoadFromResource - der INTERNE Name eines .vsf ist
  // nicht garantiert gleich dem Dateinamen, und ein Namensraten waere
  // genau die stille Fehlerquelle, die die erste Fassung hatte: ohne
  // gelinkten Style lieferte TrySetStyle('Windows10Dark') False, und die
  // EXE startete auf dunklem Windows hell (Abnahme-Befund 2026-08-05).
  DARK_RESOURCE = 'WIN10DARK';

  // Der Ressourcen-TYP muss 'VCLSTYLE' sein, NICHT RT_RCDATA. Grund, am
  // 2026-08-05 durch eine Zugriffsverletzung gelernt:
  // TStyleManager.TryLoadFromResource reicht den ResourceType-PChar an
  // FindStyleDescriptor weiter - und DAS nimmt einen 'string'
  // (Vcl.Themes.pas:6001). Die implizite Umwandlung DEREFERENZIERT den
  // Zeiger. RT_RCDATA ist aber PChar(10), also der Zahlenwert 10 als
  // Zeiger - und genau das meldete der Absturz:
  //   'access violation ... read of address 0x0000000a'.
  // Der Compiler kann das nicht sehen: PChar passt formal auf beide
  // Bedeutungen.
  // 'VCLSTYLE' ist der Typ, den Vcl.Styles selbst registriert
  // (TStyleEngine.ResourceTypeName, Vcl.Styles.pas:145) - die .rc
  // deklariert die Ressource ebenso.
  DARK_RES_TYPE = 'VCLSTYLE';

  REG_PERSONALIZE =
    'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize';
  REG_VALUE   = 'AppsUseLightTheme';
  INI_SECTION = 'UI';
  INI_KEY     = 'Theme';

class function TAppTheme.ModeToStr(AMode: TAppThemeMode): string;
begin
  case AMode of
    atmLight: Result := 'light';
    atmDark:  Result := 'dark';
  else
    Result := 'system';
  end;
end;

class function TAppTheme.StrToMode(const S: string): TAppThemeMode;
var
  L : string;
begin
  L := LowerCase(Trim(S));
  if L = 'light' then
    Result := atmLight
  else if L = 'dark' then
    Result := atmDark
  else
    Result := atmSystem;   // auch fuer leer/unbekannt - der Auslieferwert
end;

class function TAppTheme.ReadSystemDark: Boolean;
var
  Reg : TRegistry;
begin
  Result := False;
  Reg := TRegistry.Create(KEY_READ);
  try
    Reg.RootKey := HKEY_CURRENT_USER;
    if Reg.OpenKeyReadOnly(REG_PERSONALIZE) and Reg.ValueExists(REG_VALUE) then
      Result := Reg.ReadInteger(REG_VALUE) = 0;   // 0 = dunkel, 1 = hell
  finally
    Reg.Free;
  end;
end;

class function TAppTheme.SystemPrefersDark: Boolean;
begin
  // Eine unlesbare Registry darf den Start nicht verhindern - dann eben
  // hell. Pauschaler Fang mit Absicht: die konkrete Ursache aendert an
  // der Reaktion nichts, und dieser Aufruf liegt im Startpfad.
  try
    Result := ReadSystemDark;
  except
    Result := False;
  end;
end;

class function TAppTheme.EffectiveDark: Boolean;
begin
  case FMode of
    atmLight: Result := False;
    atmDark:  Result := True;
  else
    Result := SystemPrefersDark;
  end;
end;

class function TAppTheme.ActiveStyleIsDark: Boolean;
begin
  Result := Assigned(TStyleManager.ActiveStyle)
            and not SameText(TStyleManager.ActiveStyle.Name, STYLE_LIGHT);
end;

class procedure TAppTheme.ApplyStyle;
var
  Applied : Boolean;
begin
  // Re-Entranz: ein Style-Wechsel loest selbst Nachrichten aus, und
  // HandleSystemThemeChanged haengt an einer davon.
  if FApplying then Exit;
  FApplying := True;
  try
    Applied := False;
    if EffectiveDark then
    begin
      // Einmal aus der eingebetteten Ressource laden; das Handle bleibt
      // fuer die Prozesslebensdauer gueltig (TStyleManager besitzt es).
      if not Assigned(FDarkHandle) then
        if not TStyleManager.TryLoadFromResource(HInstance, DARK_RESOURCE,
                 PChar(DARK_RES_TYPE), FDarkHandle) then
          FDarkHandle := nil;
      if Assigned(FDarkHandle) then
        // noinspection NestedTry
        // Aeusseres try/finally gehoert dem FApplying-Flag, dieses
        // try/except der Politik "kein Absturz, nur kein Dunkelmodus" -
        // dieselbe begruendete Paarung wie in PersistMode.
        try
          TStyleManager.SetStyle(FDarkHandle);
          Applied := True;
        except
          // Politik der Unit: kein Absturz, nur kein Dunkelmodus. Handle
          // verwerfen, damit kein weiterer Versuch mit demselben kaputten
          // Zustand laeuft; unten faellt es sichtbar auf hell zurueck.
          FDarkHandle := nil;
        end;
    end;
    // Hell - oder die Ressource fehlt (dann bleibt es sichtbar hell
    // statt still kaputt).
    if not Applied then
      TStyleManager.TrySetStyle(STYLE_LIGHT, False);
  finally
    FApplying := False;
  end;

  if Assigned(FOnChanged) then
    FOnChanged(nil);
end;

type
  // Color/Font/StyleElements sind auf TControl protected - der Zugriff
  // laeuft ueber einen Class-Cracker, wie im Plugin (uIDETheme).
  TControlAccess = class(TControl);

class procedure TAppTheme.ResolveSystemColors(ARoot: TWinControl);

  procedure Walk(AC: TControl);
  var
    Cur, Orig : TAppThemeColors;
    C         : TColor;
    Svc       : TCustomStyleServices;
    i         : Integer;
  begin
    if not Assigned(AC) then Exit;
    Svc := StyleServices;

    Cur.Color     := TControlAccess(AC).Color;
    Cur.FontColor := TControlAccess(AC).Font.Color;
    if not FOrigColors.TryGetValue(Pointer(AC), Orig) then
    begin
      Orig := Cur;
      FOrigColors.Add(Pointer(AC), Orig);
    end;

    // Nur was der Style NICHT selbst faerbt.
    if not (seClient in TControlAccess(AC).StyleElements) then
    begin
      C := Orig.Color;
      if (C <> clNone) and ((C and clSystemColor) <> 0) then
        TControlAccess(AC).Color := Svc.GetSystemColor(C);
    end;
    if not (seFont in TControlAccess(AC).StyleElements) then
    begin
      C := Orig.FontColor;
      if (C <> clNone) and ((C and clSystemColor) <> 0) then
        TControlAccess(AC).Font.Color := Svc.GetSystemColor(C);
    end;

    if AC is TWinControl then
      for i := 0 to TWinControl(AC).ControlCount - 1 do
        Walk(TWinControl(AC).Controls[i]);
  end;

begin
  if not Assigned(ARoot) then Exit;
  if not Assigned(FOrigColors) then
    FOrigColors := TDictionary<Pointer, TAppThemeColors>.Create;
  Walk(ARoot);
end;

class procedure TAppTheme.Initialize;
begin
  FMode := StrToMode(
    TRepoSettings.QuickReadStr(INI_SECTION, INI_KEY, 'system'));
  ApplyStyle;
end;

class procedure TAppTheme.PersistMode(AMode: TAppThemeMode);
var
  Ini : TIniFile;
begin
  // Die Verschachtelung ist hier die richtige Form, nicht ein Versehen:
  // das innere try/finally gehoert der RESSOURCE (TIniFile muss auch bei
  // einem Schreibfehler freigegeben werden), das aeussere try/except der
  // POLITIK (ein nicht schreibbares Ziel darf die Umschaltung nicht
  // verhindern - die Wahl gilt dann nur fuer diese Sitzung). Beides in
  // einen Block zu ziehen hiesse, eines von beidem aufzugeben.
  try
    Ini := TIniFile.Create(TRepoSettings.ResolvedConfigPath);
    // noinspection NestedTry
    try
      Ini.WriteString(INI_SECTION, INI_KEY, ModeToStr(AMode));
    finally
      Ini.Free;
    end;
  except
    // Nur diese Sitzung - siehe Deklaration.
    Ini := nil;
  end;
end;

class procedure TAppTheme.SetMode(AMode: TAppThemeMode);
begin
  if AMode = FMode then Exit;
  FMode := AMode;
  PersistMode(AMode);   // schlaegt sie fehl, gilt die Wahl nur fuer jetzt
  ApplyStyle;
end;

class procedure TAppTheme.HandleSystemThemeChanged;
begin
  if FMode <> atmSystem then Exit;
  // Nur bei echter Aenderung neu setzen: Windows sendet WM_SETTINGCHANGE
  // fuer viele Anlaesse, und ein Style-Wechsel ist ein Voll-Repaint.
  if ActiveStyleIsDark = SystemPrefersDark then Exit;
  ApplyStyle;
end;

initialization

finalization
  // Der Cache haelt nur Zeiger als Schluessel, keine Objekte - er
  // besitzt nichts und muss nur selbst freigegeben werden.
  TAppTheme.FOrigColors.Free;

end.
