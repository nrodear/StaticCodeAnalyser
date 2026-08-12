unit uTestClaudePrompt;

// Tests fuer uClaudePrompt (SCA.Engine, Output-Schicht).
//
// Der Kern-Test ist Build_ReflectsFileChangesAfterEdit. Er haelt fest, was
// der Modul-LRU urspruenglich falsch machte: der Cache war rein
// pfad-basiert und lebte fuer die Prozess-Lebenszeit - nach "Befund
// klicken -> Datei fixen -> neu scannen -> Befund klicken" stand der ALTE
// Code mit falsch sitzendem >>>-Marker im Prompt, genau das Artefakt, das
// der Nutzer einer AI vorlegt. Seit dem Fix traegt jeder Cache-Slot
// LastWriteTime + Groesse der Quelldatei und wird beim Treffer validiert.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils, System.Classes, System.IOUtils,
  uSCAConsts, uMethodd12, uFixHint, uClaudePrompt;

type
  [TestFixture]
  TTestClaudePromptSnippet = class
  strict private
    FDir  : string;   // eigenes Temp-Verzeichnis, TearDown raeumt ab
    FPath : string;   // die eine Quelldatei der Tests
    procedure WriteSource(const AMarker: string);
    function  BuildForLine6: string;
  public
    [Setup]    procedure Setup;
    [TearDown] procedure TearDown;
    [Test] procedure Build_SnippetContainsMarkedLine;
    [Test] procedure Build_ReflectsFileChangesAfterEdit;
    [Test] procedure Build_DeletedFileDropsSnippet;
  end;

implementation

const
  // Marker-Inhalte der Probedatei. Bewusst verschieden LANG - der Cache
  // validiert ueber LastWriteTime UND Groesse, beide Achsen sollen im
  // Regressionstest real variieren.
  CONTENT_A     = 'OriginalInhalt_A';
  CONTENT_B     = 'GeaenderterInhalt_Laenger_B';
  // 12 Zeilen mit dem Marker in Zeile 6: der Befund liegt mittig, damit
  // der +/-5-Zeilen-Auszug ihn samt Kontext sicher enthaelt.
  PROBE_LINES   = 12;
  MARKED_LINE   = 6;

procedure TTestClaudePromptSnippet.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath,
    'sca_claudeprompt_' + TGUID.NewGuid.ToString.Trim(['{', '}']));
  TDirectory.CreateDirectory(FDir);
  FPath := TPath.Combine(FDir, 'Probe.pas');
end;

procedure TTestClaudePromptSnippet.TearDown;
begin
  try
    if TDirectory.Exists(FDir) then
    begin
      TDirectory.Delete(FDir, True);
    end;
  // noinspection EmptyExcept
  except
    // Aufraeumen darf keinen Testlauf kippen (gesperrte Datei o.ae.) -
    // das Temp-Verzeichnis raeumt das OS im Zweifel selbst ab.
  end;
end;

procedure TTestClaudePromptSnippet.WriteSource(const AMarker: string);
// Schreibt die Probedatei: PROBE_LINES Zeilen, AMarker in MARKED_LINE.
var
  SL : TStringList;
  i  : Integer;
begin
  SL := TStringList.Create;
  try
    for i := 1 to PROBE_LINES do
    begin
      if i = MARKED_LINE then
      begin
        SL.Add('  ' + AMarker + ';');
      end
      else
      begin
        SL.Add(Format('  Zeile%.2d := %d;', [i, i]));
      end;
    end;
    SL.SaveToFile(FPath, TEncoding.UTF8);
  finally
    SL.Free;
  end;
end;

function TTestClaudePromptSnippet.BuildForLine6: string;
// Prompt fuer einen Befund in MARKED_LINE der Probedatei; Hint bewusst
// leer, damit die Assertions nur am Snippet haengen (keine lokalisierten
// Hint-Texte im Spiel).
var
  F : TLeakFinding;
begin
  F := TLeakFinding.New(FPath, 'DoWork', MARKED_LINE, 'probe', fkMemoryLeak);
  try
    Result := TClaudePrompt.Build(F, Default(TFixHint));
  finally
    F.Free;
  end;
end;

procedure TTestClaudePromptSnippet.Build_SnippetContainsMarkedLine;
var
  Prompt : string;
begin
  WriteSource(CONTENT_A);
  Prompt := BuildForLine6;
  Assert.IsTrue(Prompt.Contains(CONTENT_A),
    'Der Code-Auszug muss die Befund-Zeile enthalten');
  Assert.IsTrue(Prompt.Contains('>>> '),
    'Die Befund-Zeile muss den >>>-Marker tragen');
end;

procedure TTestClaudePromptSnippet.Build_ReflectsFileChangesAfterEdit;
// DER KERN-TEST (Regression, Review-Blocker 2026-08-12): zweiter Build
// nach einer Datei-Aenderung muss den NEUEN Inhalt zeigen.
var
  Prompt : string;
begin
  WriteSource(CONTENT_A);
  BuildForLine6;                       // fuellt den LRU mit dem Altstand

  WriteSource(CONTENT_B);
  Prompt := BuildForLine6;
  Assert.IsTrue(Prompt.Contains(CONTENT_B),
    'Nach einer Datei-Aenderung muss der Prompt den NEUEN Code zeigen');
  Assert.IsFalse(Prompt.Contains(CONTENT_A),
    'Der alte Code darf nicht mehr aus dem Cache kommen');
end;

procedure TTestClaudePromptSnippet.Build_DeletedFileDropsSnippet;
// Geloeschte Datei: der Cache darf nicht weiter deren Zeilen liefern -
// der Prompt kommt dann ohne Code-Auszug.
var
  Prompt : string;
begin
  WriteSource(CONTENT_A);
  BuildForLine6;                       // fuellt den LRU

  TFile.Delete(FPath);
  Prompt := BuildForLine6;
  Assert.IsFalse(Prompt.Contains(CONTENT_A),
    'Zeilen einer geloeschten Datei duerfen nicht aus dem Cache kommen');
end;

end.
