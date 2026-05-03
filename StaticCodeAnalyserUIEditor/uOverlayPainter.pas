unit uOverlayPainter;

// Optional: zeichnet farbige Rahmen um problematische Komponenten direkt
// auf der Designer-Surface. Skelett-Implementierung - der eigentliche
// Paint-Hook ist IDE-versionsabhaengig (Subclassing der Designer-HWND
// via SetWindowsHookEx oder Eingriff in TWinControl.Perform). Hier
// wird nur die Datenstruktur gepflegt; die Zeichenroutine bleibt als
// TODO bestehen, da fuer die Grundfunktion nicht erforderlich.

interface

uses
  Winapi.Windows,
  System.Classes, System.SysUtils, System.Types, System.Generics.Collections,
  Vcl.Graphics, Vcl.Controls,
  uDfmIssues;

type
  TOverlayPainter = class
  private
    FHighlights : TDictionary<string, TUISeverity>; // Komponentenname -> Severity
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetIssues(Issues: TUIIssueList);
    procedure Clear;
    function  ColorFor(Severity: TUISeverity): TColor;
    function  IsHighlighted(const ComponentName: string;
      out Severity: TUISeverity): Boolean;
    // Wird vom Paint-Hook aufgerufen (siehe Header). Default-Impl. malt
    // einen 2px-Rahmen in ColorFor(Severity) um das ClientRect.
    procedure PaintBorder(ACanvas: TCanvas; const R: TRect;
      Severity: TUISeverity);
  end;

implementation

{ TOverlayPainter }

constructor TOverlayPainter.Create;
begin
  inherited;
  FHighlights := TDictionary<string, TUISeverity>.Create;
end;

destructor TOverlayPainter.Destroy;
begin
  FHighlights.Free;
  inherited;
end;

procedure TOverlayPainter.SetIssues(Issues: TUIIssueList);
var
  i  : Integer;
  Ex : TUISeverity;
begin
  FHighlights.Clear;
  if Issues = nil then Exit;
  for i := 0 to Issues.Count - 1 do
    if Issues[i].ComponentName <> '' then
    begin
      // Hoechste Severity je Komponente gewinnt.
      if FHighlights.TryGetValue(Issues[i].ComponentName, Ex) then
      begin
        if Issues[i].Severity > Ex then
          FHighlights[Issues[i].ComponentName] := Issues[i].Severity;
      end
      else
        FHighlights.Add(Issues[i].ComponentName, Issues[i].Severity);
    end;
end;

procedure TOverlayPainter.Clear;
begin
  FHighlights.Clear;
end;

function TOverlayPainter.ColorFor(Severity: TUISeverity): TColor;
begin
  case Severity of
    uisError:   Result := clRed;
    uisWarning: Result := $00007BCC; // orange-ish
  else          Result := clGray;
  end;
end;

function TOverlayPainter.IsHighlighted(const ComponentName: string;
  out Severity: TUISeverity): Boolean;
begin
  Result := FHighlights.TryGetValue(ComponentName, Severity);
end;

procedure TOverlayPainter.PaintBorder(ACanvas: TCanvas; const R: TRect;
  Severity: TUISeverity);
begin
  ACanvas.Pen.Color := ColorFor(Severity);
  ACanvas.Pen.Width := 2;
  ACanvas.Brush.Style := bsClear;
  ACanvas.Rectangle(R.Left, R.Top, R.Right, R.Bottom);
end;

end.
