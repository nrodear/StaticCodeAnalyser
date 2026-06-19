unit uIDEAddInOptionsBase;

// Gemeinsame Basis fuer Tools>Options-Pages des Plugins.
//
// Beide Options-Pages (uIDESCAOptions.TSCAAddInOptions /
// uIDESonarOptions.TSonarAddInOptions) hatten den identischen Cycle:
//   * FFrame + FThemeSub als Felder
//   * OnThemeChanged ruft TIDETheme.Apply(FFrame)
//   * FrameCreated:  Cast + DoLoadFrame + TIDETheme.Apply + Subscribe
//   * DialogClosed:  try DoSaveFrame finally Theme-Cleanup
//   * ValidateContents := True / GetHelpContext := 0 / GetArea := ''
// Das war ~80 Lines, dupliziert. Diese Base-Klasse zieht das auf ein
// Spot zusammen; Konkrete Pages ueberschreiben nur LoadFrame, SaveFrame,
// GetCaption, GetFrameClass.
//
// LIFECYCLE
//   IDE ruft FrameCreated wenn der User die Page oeffnet, DialogClosed
//   wenn er OK/Cancel klickt. Zwischendrin lebt FFrame in der IDE
//   (nicht in uns) — wir halten nur die Referenz. Theme-Subscription
//   wird im DialogClosed aufgeloest, sonst wuerde ein nachtraegliches
//   Theme-Event in einen freigegebenen Frame feuern.

interface

uses
  Vcl.Forms,         // TCustomFrame / TCustomFrameClass
  ToolsAPI;          // INTAAddInOptions

type
  TIDEAddInOptionsBase = class abstract(TInterfacedObject, INTAAddInOptions)
  protected
    FFrame    : TCustomFrame;
    FThemeSub : IInterface;       // RAII: nil = Subscription aus
    // Wird beim Theme-Wechsel gerufen. Default-Impl ruft TIDETheme.Apply
    // auf FFrame. Subklassen koennen ueberschreiben fuer eigene Logik
    // (Cache-Invalidierung etc.); inherited NICHT vergessen.
    procedure OnThemeChanged; virtual;
    // Wird im FrameCreated nach dem Frame-Assign gerufen. Subklasse
    // laedt hier ihre Werte aus der INI in die Controls.
    procedure DoLoadFrame(AFrame: TCustomFrame); virtual; abstract;
    // Wird im DialogClosed(Accepted=True) gerufen. Subklasse persistiert
    // die UI-Werte in die INI.
    procedure DoSaveFrame(AFrame: TCustomFrame); virtual; abstract;
  public
    // INTAAddInOptions — Subklasse liefert Caption + Frame-Klasse.
    function  GetArea: string; virtual;
    function  GetCaption: string; virtual; abstract;
    function  GetFrameClass: TCustomFrameClass; virtual; abstract;
    procedure FrameCreated(AFrame: TCustomFrame); virtual;
    procedure DialogClosed(Accepted: Boolean); virtual;
    function  ValidateContents: Boolean; virtual;
    function  GetHelpContext: Integer; virtual;
    function  IncludeInIDEInsight: Boolean; virtual;
  end;

implementation

uses
  uIDETheme;         // TIDETheme.Apply + Subscribe

function TIDEAddInOptionsBase.GetArea: string;
begin
  // Leerer String -> IDE platziert die Page unter dem sprachabhaengigen
  // Default-Knoten ("Third Party" auf englischer IDE, "Fremdhersteller"
  // auf deutscher IDE). Ein hartes 'Third Party' wuerde stattdessen
  // einen ZWEITEN Top-Level-Knoten daneben erzeugen.
  Result := '';
end;

procedure TIDEAddInOptionsBase.FrameCreated(AFrame: TCustomFrame);
begin
  FFrame := AFrame;
  // Subklasse befuellt die Controls aus der INI.
  DoLoadFrame(AFrame);
  // IDE-Theme uebernehmen - sonst rendert der Frame im VCL-Default
  // (hell) auch wenn die IDE im Dark-Mode laeuft.
  TIDETheme.Apply(FFrame);
  // Theme-Live-Update: falls der User mid-Options-Dialog die
  // "IDE Style"-Option umstellt, aktualisiert OnThemeChanged
  // unseren Frame automatisch.
  FThemeSub := TIDETheme.Subscribe(OnThemeChanged);
end;

procedure TIDEAddInOptionsBase.OnThemeChanged;
begin
  if Assigned(FFrame) then
    TIDETheme.Apply(FFrame);
end;

procedure TIDEAddInOptionsBase.DialogClosed(Accepted: Boolean);
begin
  try
    if not Accepted then Exit;
    if FFrame = nil then Exit;
    DoSaveFrame(FFrame);
  finally
    // Theme-Subscription aufloesen - IDE gibt FFrame nach DialogClosed
    // frei; ein noch lebendes Abo wuerde beim naechsten Theme-Wechsel
    // in die freigegebene Frame-Referenz feuern.
    FThemeSub := nil;
    FFrame := nil;
  end;
end;

function TIDEAddInOptionsBase.ValidateContents: Boolean;
begin
  Result := True;
end;

function TIDEAddInOptionsBase.GetHelpContext: Integer;
begin
  Result := 0;
end;

function TIDEAddInOptionsBase.IncludeInIDEInsight: Boolean;
begin
  // Default ON: beide unserer Pages sollen ueber "Preferences"-Quicksearch
  // findbar sein. Subklassen koennen ueberschreiben.
  Result := True;
end;

end.
