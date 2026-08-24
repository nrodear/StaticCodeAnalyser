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
// STYLE-VERFUEGBARKEIT: der dunkle Style liegt als Ressource SCADARK
// (Typ VCLSTYLE) IN der EXE - gelinkt ueber {$R 'styles\sca_styles.RES'}
// im .dpr, Details in styles/README.md. Ein Projektoptionen-Haken ist
// weder noetig noch erwuenscht (der schriebe IDE-spezifische .dproj-
// Eintraege). Fehlt die Ressource oder laedt sie nicht, bleibt die
// Anwendung beim hellen Systemstil - kein Absturz, nur kein Dunkelmodus.
//
// Windows-Erkennung: HKCU\...\Themes\Personalize\AppsUseLightTheme
// (DWORD, 0 = dunkel). Der Wert fehlt auf Windows 8.1 und aelter - dann
// gilt hell. Die RTL kennt diesen Schluessel nicht, das ist Handarbeit.

interface

uses
  System.Classes, System.Generics.Collections,
  Vcl.Graphics,   // TColor
  Vcl.Controls,   // TWinControl (ResolveSystemColors)
  Vcl.Themes;     // TStyleManager (ApplyStyle, ActiveStyleIsDark)

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
    // Der REGISTRY-NAME des dunklen Styles (der interne Name aus dem
    // .vsf, nicht 'SCADARK'). Leer = noch nicht registriert.
    //
    // Warum ein Name und kein TStyleServicesHandle: das Handle ist der
    // rohe Zeiger auf den Ressourcen-TMemoryStream (Vcl.Themes.pas:1771
    // '= type Pointer', Rueckgabe 5595), und SetStyle(Handle) baut bei
    // JEDEM Aufruf eine neue Style-Instanz aus DIESEM Stream, ohne die
    // Position zurueckzusetzen (6153; einziges Position:=0 steht bei der
    // Registrierung, 5592). Die zweite Aktivierung las ab Stream-Ende,
    // LoadFromStream lieferte nil, und SetStyle(nil) schaltete STILL auf
    // den hellen Systemstil - 'Dark' machte hell. TrySetStyle(Name)
    // bedient sich dagegen zuerst aus dem Instanz-Cache FStyles
    // (6204-6209) und fasst den Stream nach der Erst-Instanziierung nie
    // wieder an.
    class var FDarkName: string;
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

    /// <summary>Faerbt die FENSTERRAHMEN-Leiste (Titelzeile). Das
    /// erledigt weder ein VCL-Style noch das IDE-Theming: die Titelzeile
    /// malt Windows selbst und folgt nur den DWM-Attributen.</summary>
    /// <param name="ADark">Hell/Dunkel-Schalter. Auf Windows 10 ist das
    /// alles, was geht - die Leiste wird dann Windows-schwarz.</param>
    /// <param name="ACaption">Exakte Farbe der Leiste, clNone = keine
    /// Vorgabe. Wirkt erst ab Windows 11 (Build 22000); davor faellt es
    /// still auf ADark zurueck.</param>
    /// <param name="AText">Exakte Farbe des Titeltexts, sonst wie
    /// ACaption.</param>
    /// <remarks>Fehlschlaege sind bewusst folgenlos - dann bleibt die
    /// Leiste, wie Windows sie malt, und das Fenster funktioniert.</remarks>
    /// <remarks>Nimmt das Control, nicht das Fensterhandle: HWND stammt
    /// aus Winapi.Windows, das erst im implementation-uses steht - in der
    /// Deklaration gaebe es E2003. TWinControl ist ohnehin sichtbar, und
    /// der Aufrufer muss sich nicht um die Handle-Erzeugung kuemmern.</remarks>
    class procedure ApplyTitleBarTheme(AControl: TWinControl; ADark: Boolean;
      ACaption: TColor = clNone; AText: TColor = clNone); static;

    /// <summary>Chrome-Farben des AKTIVEN VCL-Styles, aufgeloest. Fuer
    /// die Standalone die passende Vorgabe an ApplyTitleBarTheme - das
    /// IDE-Plugin nimmt stattdessen TIDETheme.FrameBg/FrameFg.</summary>
    class function StyleChromeBg: TColor; static;
    class function StyleChromeFg: TColor; static;

    /// <summary>Haengt eine Diagnosezeile an
    /// %APPDATA%\StaticCodeAnalyser\StaticCodeAnalyser_theme.log und
    /// schickt sie zusaetzlich an OutputDebugString.</summary>
    /// <remarks>Warum eine Datei: aus bds.exe kommt bei DebugView nichts
    /// an, aus der Standalone schon. Ohne gemeinsame Ablage laesst sich
    /// "der Code laeuft nicht" nicht von "die Ausgabe kommt nicht an"
    /// unterscheiden - und genau daran haengt die Suche nach der
    /// Titelzeilenfarbe im Plugin (2026-08-24). Fehler beim Schreiben
    /// werden geschluckt: eine Diagnose darf nichts kaputt machen.</remarks>
    class procedure LogLine(const AText: string); static;

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
  Winapi.Dwmapi,  // DwmSetWindowAttribute - Titelzeile hell/dunkel
  Vcl.Styles,
  uIgnoreList,    // ConfigDir - gemeinsame Ablage der Diagnosedatei
  uRepoSettings;

const
  // Der native Windows-Stil. Bewusst NICHT 'Windows10': ohne gesetzten
  // Style zeichnet die VCL nativ, und genau so sieht die Anwendung heute
  // im hellen Fall aus. 'Windows10' waere ein VCL-gezeichneter Nachbau -
  // eine sichtbare Aenderung fuer alle, die gar keinen Dunkelmodus wollen.
  STYLE_LIGHT = 'Windows';

  // Der dunkle Style liegt als Ressource in der EXE
  // (styles\sca_styles.RES, gelinkt im .dpr). Aktiviert wird er ueber
  // das HANDLE aus TryLoadFromResource - der INTERNE Name eines .vsf ist
  // nicht garantiert gleich dem Dateinamen, und ein Namensraten waere
  // genau die stille Fehlerquelle, die die erste Fassung hatte: ohne
  // gelinkten Style lieferte TrySetStyle('Windows10Dark') False, und die
  // EXE startete auf dunklem Windows hell (Abnahme-Befund 2026-08-05).
  // Inhaltlich seit 2026-08-08 'SCA VSDark' (styles\SCADark.vsf): das
  // Original Windows10Dark stand woertlich auf clBlack (Window, Panel,
  // Grid, Edit, Menu) und wirkte erdrueckend - User-Auflage war das
  // VS-Code-Dark-Modern-Grau. SCADark.vsf ist das per Skript umgefaerbte
  // Windows10Dark (Palette + Entstehung: styles\README.md).
  DARK_RESOURCE = 'SCADARK';

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

  // Discovery ist aus (s. Initialize) - StyleNames ist damit die reine
  // Registrierungsliste (Vcl.Themes.pas 5777-5792): Systemstil plus
  // alles, was WIR geladen haben. Der einzige Nicht-Systemname IST der
  // dunkle Style; sein Registry-Schluessel ist der interne .vsf-Name
  // (5594), nicht der Ressourcenname SCADARK.
  function FirstNonSystemName: string;
  var
    S : string;
  begin
    Result := '';
    for S in TStyleManager.StyleNames do
      if not SameText(S, STYLE_LIGHT) then
        Exit(S);
  end;

var
  Applied : Boolean;
  LH      : TStyleManager.TStyleServicesHandle;
begin
  // Re-Entranz: ein Style-Wechsel loest selbst Nachrichten aus, und
  // HandleSystemThemeChanged haengt an einer davon.
  if FApplying then Exit;
  FApplying := True;
  try
    // noinspection NestedTry
    // Aeusseres try/finally gehoert dem FApplying-Flag, dieses
    // try/except der Politik "kein Absturz, nur kein Dunkelmodus".
    try
      Applied := False;
      if EffectiveDark then
      begin
        if FDarkName = '' then
        begin
          // Erst nachsehen, ob schon etwas registriert ist - dann laden.
          // Ein zweites TryLoadFromResource nach erfolgreicher
          // Registrierung scheiterte am Namens-Duplikat (5590/5598),
          // deshalb ist der Name das Gedaechtnis, nicht das Handle.
          FDarkName := FirstNonSystemName;
          if FDarkName = '' then
            if TStyleManager.TryLoadFromResource(HInstance, DARK_RESOURCE,
                 PChar(DARK_RES_TYPE), LH) then
              FDarkName := FirstNonSystemName;
        end;
        if FDarkName <> '' then
          // Erstaktivierung liest den frisch registrierten Stream
          // (Position 0 seit 5592), jede weitere kommt aus FStyles
          // (6204-6209). Beliebig oft hin- und herschaltbar.
          Applied := TStyleManager.TrySetStyle(FDarkName, False);
      end;
      // Hell - oder die Ressource fehlt/laedt nicht (dann bleibt es
      // sichtbar hell statt still kaputt).
      if not Applied then
        TStyleManager.TrySetStyle(STYLE_LIGHT, False);
    // noinspection EmptyExcept
    // BEWUSST leer - Politik der Unit: kein Absturz, nur kein
    // Dunkelmodus. Mit abgeschalteter Discovery ist dieser Pfad
    // praktisch unerreichbar (TrySetStyle(..., False) zeigt keinen
    // Dialog und wirft im Namenszweig nicht mehr, 6222-6224) - Gurt
    // und Hosentraeger.
    except
    end;
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

class procedure TAppTheme.LogLine(const AText: string);
var
  Zeile : string;
  Datei : string;
  F     : TextFile;
begin
  Zeile := Format('%s  %-28s %s',
    [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now),
     ExtractFileName(ParamStr(0)), AText]);
  OutputDebugString(PChar('SCA ' + AText));
  try
    Datei := TIgnoreList.ConfigDir + 'StaticCodeAnalyser_theme.log';
    ForceDirectories(ExtractFilePath(Datei));
    AssignFile(F, Datei);
    if FileExists(Datei) then Append(F) else Rewrite(F);
    try
      Writeln(F, Zeile);
    finally
      CloseFile(F);
    end;
  except
    // Eine Diagnose darf nichts kaputtmachen.
    on E: Exception do ;
  end;
end;

// Farbe fuer die Diagnosezeile: 'clNone' oder $00BBGGRR.
function IfThenColor(C: TColor): string;
begin
  if C = clNone then
    Result := 'clNone'
  else
    Result := Format('$%.6x', [ColorToRGB(C) and $00FFFFFF]);
end;

class function TAppTheme.StyleChromeBg: TColor;
begin
  Result := StyleServices.GetSystemColor(clBtnFace);
end;

class function TAppTheme.StyleChromeFg: TColor;
begin
  Result := StyleServices.GetSystemColor(clBtnText);
end;

class procedure TAppTheme.ApplyTitleBarTheme(AControl: TWinControl;
  ADark: Boolean; ACaption, AText: TColor);
var
  H      : HWND;
  Flag   : BOOL;
  Farb   : COLORREF;
  HrDark : HResult;
  HrCap  : HResult;
  HrTxt  : HResult;
begin
  if not Assigned(AControl) then Exit;
  // Handle lesen erzeugt es, falls noetig - das Fenster darf hier noch
  // unsichtbar sein, die Attribute gelten ab dem ersten Anzeigen.
  H := AControl.Handle;
  Flag := ADark;
  HrDark := S_FALSE;
  HrCap  := S_FALSE;
  HrTxt  := S_FALSE;
  try
    // 1) Hell/Dunkel. Attribut 20 gibt es seit Windows 10 2004, davor
    //    trug dieselbe Bedeutung die 19. Failed() statt "<> S_OK":
    //    HResult ist vorzeichenbehaftet, der blanke Vergleich brachte
    //    W1023.
    HrDark := DwmSetWindowAttribute(H, DWMWA_USE_IMMERSIVE_DARK_MODE,
                                    @Flag, SizeOf(Flag));
    if Failed(HrDark) then
      HrDark := DwmSetWindowAttribute(H, 19, @Flag, SizeOf(Flag));

    // 2) Die EXAKTEN Farben. Erst ab Windows 11 (Build 22000); davor
    //    schlagen die Aufrufe fehl und es bleibt bei 1) - also dunkel
    //    statt themenfarben. Genau der Unterschied, den man sieht.
    //    TColor und COLORREF haben beide das Format $00BBGGRR, deshalb
    //    genuegt ColorToRGB.
    if ACaption <> clNone then
    begin
      Farb := ColorToRGB(ACaption);
      HrCap := DwmSetWindowAttribute(H, DWMWA_CAPTION_COLOR, @Farb, SizeOf(Farb));
    end;
    if AText <> clNone then
    begin
      Farb := ColorToRGB(AText);
      HrTxt := DwmSetWindowAttribute(H, DWMWA_TEXT_COLOR, @Farb, SizeOf(Farb));
    end;
  except
    // dwmapi.dll wird verzoegert geladen. Fehlt sie oder ist die
    // Desktop-Komposition aus, ist eine unpassende Titelzeile das
    // kleinere Uebel gegenueber einer Ausnahme beim Oeffnen.
    on E: Exception do ;
  end;

  // Selbstauskunft. Die Titelzeile laesst sich nicht von aussen messen -
  // ob eine Farbe ankam, sagt sonst niemand. Sichtbar in DebugView oder
  // im Ereignisprotokoll der IDE; ohne Zuhoerer kostet es nichts.
  // Dieselbe Begruendung wie bei den OutputDebugString-Meldungen in
  // TRuleCatalog.
  LogLine(Format(
    'TitleBar: dark=%d caption=%s(hr=%.8x) text=%s(hr=%.8x) darkhr=%.8x',
    [Ord(ADark),
     IfThenColor(ACaption), HrCap,
     IfThenColor(AText),    HrTxt,
     HrDark]));
end;

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
  // ALS ERSTES, vor jedem Kontakt mit der Style-API: die automatische
  // Ressourcen-Erkennung abschalten. Sie haette die eingebettete
  // Ressource beim ersten TrySetStyle selbst registriert - danach
  // scheiterte unser TryLoadFromResource dauerhaft am Namens-Duplikat
  // (hell gestartete Sitzung: Dunkel nie aktivierbar), und in dunkel
  // gestarteten Sitzungen warf der erste Hell-Wechsel die gesammelte
  // EDuplicateStyleException aus DiscoverStyleResources (5548-5551)
  // unbehandelt zum Nutzer. Der Guard sitzt an fuenf Stellen, u.a. in
  // TrySetStyle (6201) und StyleNames (5782); mit False ist keine davon
  // mehr erreichbar. Nebenwirkung: per Projektoptionen gelinkte Styles
  // wuerden nicht mehr auto-gefunden - dieses Projekt linkt bewusst
  // keine (styles/README.md), der einzige Style laeuft ueber diese Unit.
  TStyleManager.AutoDiscoverStyleResources := False;
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
  // noinspection EmptyExcept
  // BEWUSST leer: eine nicht schreibbare Konfiguration ist kein Fehler,
  // den diese Unit behandeln koennte oder muesste - die Wahl gilt dann
  // eben nur fuer diese Sitzung (so in der Deklaration zugesagt). Die
  // Vorgaengerfassung wies hier 'Ini := nil' zu, nur um den Block nicht
  // leer zu lassen; der Compiler hat das zu Recht als ungenutzten Wert
  // gemeldet (H2077). Ein Fuellwort ist keine Fehlerbehandlung.
  except
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
