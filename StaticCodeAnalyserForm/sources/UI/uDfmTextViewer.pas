unit uDfmTextViewer;

// Modaler Read-Only-Viewer fuer eine DFM-Datei. Zeigt die Datei als Text
// und scrollt zur Befund-Zeile (1-basiert). Wird vom Resultat-Grid auf-
// gerufen, wenn der User auf einen DFM-Befund doppelklickt - damit der
// User die Zeile sieht, ohne erst den Form-Designer mit Alt+F12 in den
// Text-View bringen zu muessen.
//
// Bewusst leichtgewichtig: keine .dfm-Resource fuer den Viewer selbst,
// Form wird zur Laufzeit komponiert. So muss nichts ans Projekt-Layout
// angeschlossen werden und der Viewer hat keine eigene UI-Decke.

interface

procedure ShowDfmAsText(const FileName: string; HighlightLine: Integer);

implementation

// noinspection-file LongMethod, NestedTry, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.SysUtils, System.Classes, System.IOUtils,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.Buttons, Vcl.Graphics,
  Winapi.Windows, Winapi.Messages;

procedure ShowDfmAsText(const FileName: string; HighlightLine: Integer);
var
  Dlg      : TForm;
  Memo     : TMemo;
  Lines    : TStringList;
  // LRESULT, nicht Integer: SendMessage liefert NativeInt - auf Win64
  // 8 Byte. Mit 'Integer' (immer 4 Byte) wirft der Compiler W1057
  // Truncation. EM_LINEINDEX-Werte passen praktisch immer in 4 Byte,
  // aber typisch korrekt deklarieren ist sauberer als die Warning zu
  // unterdruecken.
  StartPos : LRESULT;
begin
  if not TFile.Exists(FileName) then
  begin
    Application.MessageBox(PChar('Datei nicht gefunden:'#13#10 + FileName),
                           'DFM Viewer', 0);
    Exit;
  end;

  Dlg := TForm.Create(nil);
  try
    Dlg.Caption     := ExtractFileName(FileName);
    Dlg.Position    := poMainFormCenter;
    Dlg.BorderStyle := bsSizeable;
    Dlg.Width       := 900;
    Dlg.Height      := 700;
    Dlg.KeyPreview  := True;

    Memo := TMemo.Create(Dlg);
    Memo.Parent      := Dlg;
    Memo.Align       := alClient;
    Memo.ReadOnly    := True;
    Memo.ScrollBars  := ssBoth;
    Memo.WordWrap    := False;
    Memo.Font.Name   := 'Consolas';
    Memo.Font.Size   := 10;
    Memo.HideSelection := False;          // Highlight auch bei Inactive-Memo

    // Datei laden. UTF-8 ohne BOM ist die typische DFM-Codierung; wenn
    // das schief geht, fuellt TStringList nichts und der Viewer zeigt
    // einen leeren Memo - das ist OK.
    Lines := TStringList.Create;
    try
      try
        Lines.LoadFromFile(FileName, TEncoding.UTF8);
      except
        // Fallback: System-Default-Encoding (alte DFMs koennten ANSI sein)
        Lines.LoadFromFile(FileName);
      end;
      Memo.Lines.Assign(Lines);
    finally
      Lines.Free;
    end;

    // Zur Befund-Zeile scrollen + Zeile selektieren. EM_LINEINDEX liefert
    // den korrekten Char-Offset fuer eine Zeile direkt aus dem RichEdit
    // unter dem TMemo - das vermeidet den klassischen Off-by-1-Bug, der
    // beim manuellen Aufsummieren von Length(Line) + Length(sLineBreak)
    // entsteht (RichEdit zaehlt intern oft LF-only statt CRLF).
    if (HighlightLine > 0) and (HighlightLine <= Memo.Lines.Count) then
    begin
      StartPos := SendMessage(Memo.Handle, EM_LINEINDEX, HighlightLine - 1, 0);
      if StartPos >= 0 then
      begin
        // Cast auf Integer: Memo.SelStart ist Integer, StartPos ist
        // LRESULT (NativeInt). Auf Win64 ohne Cast W1057. EM_LINEINDEX-
        // Werte passen sicher in Integer.
        Memo.SelStart  := Integer(StartPos);
        Memo.SelLength := Length(Memo.Lines[HighlightLine - 1]);
        SendMessage(Memo.Handle, EM_SCROLLCARET, 0, 0);
      end;
    end;

    // Unsichtbarer Cancel-Button macht Escape funktional - TButton mit
    // Cancel=True bekommt automatisch den ESC-Trigger der Form.
    var CancelBtn := TButton.Create(Dlg);
    CancelBtn.Parent       := Dlg;
    CancelBtn.Cancel       := True;
    CancelBtn.ModalResult  := mrCancel;
    CancelBtn.Width        := 0;
    CancelBtn.Height       := 0;
    CancelBtn.Visible      := False;

    Dlg.ShowModal;
  finally
    Dlg.Free;
  end;
end;

end.
