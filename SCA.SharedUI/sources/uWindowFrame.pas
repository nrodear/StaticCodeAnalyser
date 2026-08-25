unit uWindowFrame;

// Fensterrahmen-Helfer: was Windows selbst malt und weder ein VCL-Style
// noch das IDE-Theming erreicht.
//
// Genau EINE Sache steht heute darin, und die ist beiden Oberflaechen
// gemeinsam: die Titelzeile. Sie folgt nicht den Control-Farben und
// nicht dem Style, sondern allein den DWM-Attributen des Fensters.
//
// WARUM EINE EIGENE UNIT (2026-08-24): der Aufruf stand zuerst in
// uAppTheme. Das ist die Unit, die den globalen VCL-Style der
// STANDALONE verwaltet - ihr Kopfkommentar sagt ausdruecklich, dass das
// IDE-Plugin TStyleManager nie anfassen darf. Genau dieses Plugin rief
// sie dann aber, um an drei DwmSetWindowAttribute-Aufrufe zu kommen, und
// zog sich damit System.Win.Registry, System.IniFiles, uRepoSettings und
// TStyleManager in seinen Bindungsgraphen.
//
// Hier ist nichts davon noetig. Die Unit kennt keinen Wirt, keine
// Einstellungen und keinen Style - nur ein Fenster und zwei Farben.

interface

uses
  Vcl.Controls,   // TWinControl - Parametertyp, kein HWND (s. unten)
  Vcl.Graphics;   // TColor

/// <summary>Faerbt die Titelzeile eines Fensters. Das erledigt weder ein
/// VCL-Style noch das IDE-Theming: die Titelzeile malt Windows selbst
/// und folgt nur den DWM-Attributen.</summary>
/// <param name="AControl">Das Fenster. Nimmt bewusst das Control und
/// nicht das HWND: HWND stammt aus Winapi.Windows, das erst im
/// implementation-uses steht - in der Deklaration gaebe es E2003. Der
/// Aufrufer muss sich so ausserdem nicht um die Handle-Erzeugung
/// kuemmern, das Lesen von .Handle erledigt sie.</param>
/// <param name="ADark">Hell/Dunkel-Schalter. Auf Windows 10 ist das
/// alles, was geht - die Leiste wird dann Windows-schwarz.</param>
/// <param name="ACaption">Exakte Farbe der Leiste, clNone = keine
/// Vorgabe. Wirkt erst ab Windows 11 (Build 22000); davor faellt es
/// still auf ADark zurueck.</param>
/// <param name="AText">Exakte Farbe des Titeltexts, sonst wie
/// ACaption.</param>
/// <param name="ADiagContext">Freitext des Aufrufers fuer die Diagnose -
/// etwa der Name des aktiven IDE-Themes. Wird nur ausgewertet, wenn die
/// Diagnose eingeschaltet ist (s. ThemeDiagActive).</param>
/// <remarks>WICHTIG: ein Erfolg heisst nicht, dass man etwas sieht.
/// DwmSetWindowAttribute quittiert mit S_OK, sobald das Attribut
/// gespeichert ist. Hat der VCL-Style-Hook die Nicht-Client-Flaeche
/// uebernommen (Vcl.Forms.TFormStyleHook.IsStyleBorder), malt er die
/// Leiste selbst und das Attribut bleibt folgenlos. Genau deshalb sagt
/// die Diagnosezeile "malt=" mit dazu.</remarks>
/// <remarks>Fehlschlaege sind bewusst folgenlos - dann bleibt die
/// Leiste, wie Windows sie malt, und das Fenster funktioniert.</remarks>
procedure ApplyTitleBarTheme(AControl: TWinControl; ADark: Boolean;
  ACaption: TColor = clNone; AText: TColor = clNone;
  const ADiagContext: string = '');

/// <summary>Ist die Titelzeilen-Diagnose eingeschaltet? Sie ist es,
/// wenn EINES von beiden zutrifft:
///   * die Umgebungsvariable SCA_THEME_LOG ist gesetzt - Wert '1', 'on'
///     oder 'true' schreibt in die Standarddatei, jeder andere Wert gilt
///     als Pfad
///   * die Datei %APPDATA%\StaticCodeAnalyser\theme-debug.on existiert
/// Standarddatei ist %APPDATA%\StaticCodeAnalyser\theme-debug.log.
/// </summary>
/// <remarks>Der Schalter wird bei JEDEM Aufruf frisch geprueft, nicht
/// gecacht: die Marker-Datei laesst sich damit bei laufender IDE
/// anlegen und wieder loeschen. Ein FileExists pro geoeffnetem Fenster
/// faellt nicht ins Gewicht.</remarks>
/// <remarks>AUS ist die Vorgabe, und das ist Absicht. Eine Vorfassung
/// hat am 2026-08-24 bei jedem gethemten Fenster ungefragt in eine
/// unbegrenzt wachsende Datei geschrieben - im Release-Pfad.</remarks>
function ThemeDiagActive: Boolean;

/// <summary>Pfad der Diagnosedatei, oder '' wenn die Diagnose aus
/// ist.</summary>
function ThemeDiagPath: string;

/// <summary>Die Farben, mit denen ein Style eine TITELZEILE malen
/// wuerde - Fuellung und Text des Elements twCaptionActive.</summary>
/// <remarks>Das ist die Quelle, die auch Vcl.Forms.TFormStyleHook.PaintNC
/// benutzt. Wer stattdessen clWindow nimmt, bekommt die INHALTSfarbe:
/// dunkel zwar, aber ein anderer Ton als die Titelzeilen ringsum. Genau
/// daran ist der erste Anlauf am 2026-08-24 gescheitert.</remarks>
/// <param name="AStyle">Die zu befragende Style-Quelle. Im IDE-Plugin
/// IOTAIDEThemingServices.StyleServices, in der Standalone die
/// globale.</param>
/// <returns>False, wenn der Style keine Auskunft gibt - dann muss der
/// Aufrufer bei seinem bisherigen Wert bleiben.</returns>
function StyleCaptionColors(AStyle: TObject;
  out ABg, AFg: TColor): Boolean;

implementation

uses
  System.SysUtils,
  Winapi.Windows,
  Winapi.Dwmapi,   // DwmSetWindowAttribute + die drei Attributnummern
  Vcl.Forms,       // TCustomForm.CustomTitleBar - eine der drei Bedingungen
  Vcl.Themes;      // TStyleManager.FormBorderStyle / IsCustomStyleActive

const
  // Dokumentierter Reset-Wert fuer DWMWA_CAPTION_COLOR/TEXT_COLOR:
  // "specify DWMWA_COLOR_DEFAULT to reset to the system default".
  DWMWA_COLOR_DEFAULT = COLORREF($FFFFFFFF);

  DIAG_ENV    = 'SCA_THEME_LOG';
  DIAG_MARKER = 'theme-debug.on';
  DIAG_LOG    = 'theme-debug.log';

// ZWILLING von TIgnoreList.ConfigDir (uIgnoreList, Engine): dasselbe
// Verzeichnis, hier absichtlich nachgebildet statt importiert - diese
// Unit soll wirt- und schichtfrei bleiben. Wer die Ablage verschiebt,
// muss BEIDE Stellen anfassen.
function ConfigDir: string;
var
  AppData : string;
begin
  AppData := GetEnvironmentVariable('APPDATA');
  if AppData = '' then
    AppData := GetEnvironmentVariable('TEMP');
  if AppData = '' then Exit('');
  Result := IncludeTrailingPathDelimiter(AppData) + 'StaticCodeAnalyser' +
            PathDelim;
end;

function ThemeDiagPath: string;
var
  Env : string;
  Dir : string;
begin
  Result := '';
  Dir := ConfigDir;

  Env := Trim(GetEnvironmentVariable(DIAG_ENV));
  if Env <> '' then
  begin
    if SameText(Env, '1') or SameText(Env, 'on') or SameText(Env, 'true') then
    begin
      if Dir <> '' then Result := Dir + DIAG_LOG;
    end
    else
      Result := Env;   // ein Pfad
    Exit;
  end;

  if (Dir <> '') and FileExists(Dir + DIAG_MARKER) then
    Result := Dir + DIAG_LOG;
end;

function ThemeDiagActive: Boolean;
begin
  Result := ThemeDiagPath <> '';
end;

function StyleCaptionColors(AStyle: TObject; out ABg, AFg: TColor): Boolean;
// AStyle ist als TObject deklariert, damit die Schnittstelle dieser Unit
// ohne Vcl.Themes auskommt - der Aufrufer reicht seine
// TCustomStyleServices herein, hier wird geprueft und gecastet.
var
  Svc : TCustomStyleServices;
begin
  Result := False;
  ABg    := clNone;
  AFg    := clNone;
  if not (AStyle is TCustomStyleServices) then Exit;
  Svc := TCustomStyleServices(AStyle);
  // Der NATIVE Systemstil beantwortet GetSystemColor mit
  // Vcl.Graphics.ColorToRGB, also GetSysColor(COLOR_ACTIVECAPTION) -
  // das ist seit Windows 8 eine eingefrorene Legacy-Farbe und NIE
  // clNone. "Keine Auskunft" konnte diese Funktion fuer ihn also nie
  // melden, und der Aufrufer strich der hellen Titelzeile die
  // Altlast-Farbe statt sie Windows zu ueberlassen (G5-2).
  if Svc.IsSystemStyle then Exit;
  try
    // ZUERST die vom Style DEKLARIERTEN Titelzeilenfarben. Am
    // 2026-08-24 aus den .vsf ausgelesen, damit hier keine Vermutung
    // steht:
    //   Win10IDE_Dark   clActiveCaption $00A36215 (#1562A3, blau)
    //                   clCaptionText   clWhite
    //   Win10IDE_Light  clActiveCaption $00A16217 (#1762A1, blau)
    //   SCADark (EXE)   clActiveCaption $00262525 (#252526, grau)
    //                   clCaptionText   $00CCCCCC
    //
    // Das Blau der IDE-Titelzeilen ist also das THEME, nicht der
    // Windows-Akzent - eine Zeitlang die naheliegende Fehlannahme.
    // clWindow des IDE-Themes ist $00322F2D; genau diesen Wert hat der
    // erste Anlauf geschickt, und deshalb sah die Leiste zwar dunkel,
    // aber falsch aus.
    ABg := Svc.GetSystemColor(clActiveCaption);
    AFg := Svc.GetSystemColor(clCaptionText);
    Result := (ABg <> clNone) and (AFg <> clNone);

    // Rueckfall auf das gezeichnete Element - das ist die Quelle, aus
    // der TFormStyleHook.PaintNC malt (Vcl.Forms.pas ~19456/19485). Ein
    // Style, der clActiveCaption nicht setzt, kann sie trotzdem haben.
    if not Result then
      Result := Svc.GetElementColor(Svc.GetElementDetails(twCaptionActive),
                                    ecFillColor, ABg)
            and Svc.GetElementColor(Svc.GetElementDetails(twCaptionActive),
                                    ecTextColor, AFg)
            and (ABg <> clNone) and (AFg <> clNone);
  except
    // Ein Style, der die Elemente nicht kennt, ist kein Fehlerfall - der
    // Aufrufer bleibt dann bei seiner bisherigen Farbe.
    on E: Exception do
      Result := False;
  end;
end;

// Farbe fuer die Diagnosezeile: 'clNone' oder $00BBGGRR.
function FarbText(C: TColor): string;
begin
  if C = clNone then
    Result := 'clNone'
  else
    Result := Format('$%.6x', [ColorToRGB(C) and $00FFFFFF]);
end;

// WER malt die Titelzeile dieses Fensters?
//
// Vcl.Forms.TFormStyleHook uebernimmt die Nicht-Client-Flaeche nur, wenn
// er ueberhaupt existiert (das haengt am GLOBALEN
// TStyleManager.IsCustomStyleActive) UND wenn IsStyleBorder gilt:
//   (TStyleManager.FormBorderStyle = fbsCurrentStyle)
//   and (seBorder in Form.StyleElements)
//   and (Form.CustomTitleBar.Enabled = False)
//
// Genau diese Frage war am 2026-08-24 strittig: die DWM-Aufrufe meldeten
// S_OK und die Leiste blieb weiss. Deshalb steht die Antwort jetzt in
// der Zeile, statt sie aus zwei Vermutungen zu erschliessen.
function WerMalt(AControl: TWinControl; out ADetails: string): string;
var
  Global   : Boolean;
  Rahmen   : Boolean;
  Border   : Boolean;
  TitleBar : Boolean;
begin
  Global   := TStyleManager.IsCustomStyleActive;
  Rahmen   := TStyleManager.FormBorderStyle = fbsCurrentStyle;
  Border   := seBorder in AControl.StyleElements;
  TitleBar := (AControl is TCustomForm) and
              TCustomForm(AControl).CustomTitleBar.Enabled;

  ADetails := Format('customstyleactive=%d fbsCurrentStyle=%d seBorder=%d ' +
                     'customtitlebar=%d',
                     [Ord(Global), Ord(Rahmen), Ord(Border), Ord(TitleBar)]);

  if Global and Rahmen and Border and (not TitleBar) then
    Result := 'STYLE'     // der VCL-Style-Hook - DWM bleibt folgenlos
  else
    Result := 'WINDOWS';  // DefWindowProc - die DWM-Farbe wird sichtbar
end;

procedure DiagSchreiben(const AText: string);
var
  Pfad : string;
  F    : TextFile;
begin
  Pfad := ThemeDiagPath;
  if Pfad = '' then Exit;
  try
    ForceDirectories(ExtractFilePath(Pfad));
    AssignFile(F, Pfad);
    if FileExists(Pfad) then Append(F) else Rewrite(F);
    try
      Writeln(F, Format('%s  %-14s %s',
        [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now),
         ExtractFileName(ParamStr(0)), AText]));
    finally
      CloseFile(F);
    end;
  except
    // Eine Diagnose darf nichts kaputtmachen. Bewusst leer - Politik,
    // kein Versehen.
    on E: Exception do ;
  end;
  OutputDebugString(PChar('SCA ' + AText));
end;

procedure ApplyTitleBarTheme(AControl: TWinControl; ADark: Boolean;
  ACaption, AText: TColor; const ADiagContext: string);
var
  H       : HWND;
  Flag    : BOOL;
  Farb    : COLORREF;
  HrDark  : HResult;
  HrCap   : HResult;
  HrTxt   : HResult;
  Maler   : string;
  Details : string;
  Anhang  : string;
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
    //    statt themenfarben. TColor und COLORREF haben beide das Format
    //    $00BBGGRR, deshalb genuegt ColorToRGB.
    // clNone heisst RESET AUF WINDOWS-STANDARD, nicht "Aufruf
    // ueberspringen": DWMWA_CAPTION_COLOR ist ein PERSISTENTES
    // Fensterattribut. Wer nach einem dunklen Theme auf hell wechselt,
    // behielte sonst die explizit gesetzte dunkle Farbe an der hellen
    // Form - genau das hat die Zwischenfassung vom 2026-08-25 gebaut
    // (finales Review, R4). DWMWA_COLOR_DEFAULT ist der dokumentierte
    // Reset-Wert; auf Fenstern, an denen nie eine Farbe gesetzt war,
    // ist er ein No-op.
    if ACaption <> clNone then
      Farb := ColorToRGB(ACaption)
    else
      Farb := DWMWA_COLOR_DEFAULT;
    HrCap := DwmSetWindowAttribute(H, DWMWA_CAPTION_COLOR, @Farb, SizeOf(Farb));
    if AText <> clNone then
      Farb := ColorToRGB(AText)
    else
      Farb := DWMWA_COLOR_DEFAULT;
    HrTxt := DwmSetWindowAttribute(H, DWMWA_TEXT_COLOR, @Farb, SizeOf(Farb));
  except
    // dwmapi.dll wird verzoegert geladen. Fehlt sie oder ist die
    // Desktop-Komposition aus, ist eine unpassende Titelzeile das
    // kleinere Uebel gegenueber einer Ausnahme beim Oeffnen eines
    // Fensters. Bewusst leer - Politik, kein Versehen.
    on E: Exception do ;
  end;

  // Erst hier, und nur wenn eingeschaltet: die teuren Abfragen
  // (WerMalt, Format, Dateizugriff) laufen sonst gar nicht.
  if not ThemeDiagActive then Exit;
  Maler := WerMalt(AControl, Details);
  if ADiagContext = '' then
    Anhang := ''
  else
    Anhang := ' | ' + ADiagContext;
  DiagSchreiben(Format(
    '%s hwnd=$%.8x malt=%s (%s) dark=%d caption=%s(hr=%.8x) ' +
    'text=%s(hr=%.8x) immersive(hr=%.8x)%s',
    [AControl.ClassName, NativeUInt(H), Maler, Details, Ord(ADark),
     FarbText(ACaption), HrCap, FarbText(AText), HrTxt, HrDark, Anhang]));
end;

end.
