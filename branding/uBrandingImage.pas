unit uBrandingImage;

// Shared Branding-Loader fuer StaticCodeAnalyser-Standalone + IDE-Plugin.
//
// Beide Builds binden die selbe RC-Datei (branding\sca_branding.rc) ein,
// die das PNG als RCDATA mit dem Resource-Namen 'SCA_APP_PNG' kapselt.
// Diese Unit kapselt den Resource-Load und liefert wahlweise das rohe
// TPngImage (transparenz-treu) oder ein TBitmap (fuer die IOTA-API die
// HBITMAP-Handles will).
//
// Aufrufer:
//   * Standalone: Application.Icon ueber `LoadSCABitmap` + Assign zum
//     Application.Icon-Empfaenger.
//   * IDE-Plugin: HBITMAP via `LoadSCABitmap.Handle` an
//     SplashScreenServices.AddPluginBitmap und
//     IOTAAboutBoxServices.AddPluginInfo.
//
// Memory-Ownership: beide Loader liefern frisch allokierte Instanzen -
// Aufrufer muss .Free aufrufen. Die IOTA-API kopiert den HBITMAP intern,
// das TBitmap kann sofort danach freigegeben werden.

interface

uses
  System.Classes, Vcl.Graphics, Vcl.Imaging.pngimage;

// Liefert das eingebettete PNG als TPngImage (transparenz-treu).
// Caller is responsible for Free.
function LoadSCAPng: TPngImage;

// Liefert das eingebettete PNG als 32-bit TBitmap (fuer IOTA-API und
// klassische TImage.Picture-Empfaenger). Caller is responsible for Free.
function LoadSCABitmap: TBitmap;

implementation

uses
  Winapi.Windows;

function LoadSCAPng: TPngImage;
var
  Stream : TResourceStream;
begin
  Result := TPngImage.Create;
  try
    Stream := TResourceStream.Create(HInstance, 'SCA_APP_PNG', RT_RCDATA);
    try
      Result.LoadFromStream(Stream);
    finally
      Stream.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function LoadSCABitmap: Vcl.Graphics.TBitmap;
// TBitmap MUSS qualifiziert werden: Winapi.Windows (impl-uses) bringt einen
// Record-Typ 'TBITMAP' mit - Pascal ist case-insensitiv, also kollidieren
// die beiden. Ohne Qualifier resolved der Compiler auf die WinAPI-Struct,
// die keine .Create-Methode hat -> E2003 + E2037.
var
  Png : TPngImage;
begin
  Png := LoadSCAPng;
  try
    Result := Vcl.Graphics.TBitmap.Create;
    try
      Result.PixelFormat := pf32bit;
      Result.SetSize(Png.Width, Png.Height);
      // Transparenz-Pass-through: Canvas.Draw mit Alpha-Channel
      Result.Canvas.Draw(0, 0, Png);
    except
      Result.Free;
      raise;
    end;
  finally
    Png.Free;
  end;
end;

end.
