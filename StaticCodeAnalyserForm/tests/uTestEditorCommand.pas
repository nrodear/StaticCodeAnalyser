unit uTestEditorCommand;

// Platzhalter-Ersetzung fuer die Kommandozeile eines externen Editors.
//
// Warum das Tests wert ist: ein Fehler hier ist nicht sichtbar. Der Editor
// geht auf - nur eben mit der falschen Datei, der falschen Zeile oder mit
// leerem Fenster. Genau die Faelle, die man beim Ausprobieren mit einem
// kurzen Pfad ohne Leerzeichen nie bemerkt, stehen hier.

// noinspection-file GodClass
// 23 Testmethoden in einer Vorrichtung sind kein Gottobjekt, sondern
// Abdeckung - dieselbe Einordnung wie in den uebrigen Testunits.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestEditorCommand = class
  public
    // --- die vier Platzhalter ---
    [Test] procedure File_Wird_Eingesetzt;
    [Test] procedure Line_Wird_Eingesetzt;
    [Test] procedure Col_Wird_Eingesetzt;
    [Test] procedure Dir_Ohne_Abschliessenden_Trenner;
    [Test] procedure Grossschreibung_Egal;

    // --- Zeilennummern ---
    [Test] procedure Zeile_Null_Wird_Zu_Eins;
    [Test] procedure Zeile_Negativ_Wird_Zu_Eins;

    // --- Anfuehrungszeichen ---
    [Test] procedure Pfad_Mit_Leerzeichen_Wird_Gequotet;
    [Test] procedure Pfad_Ohne_Leerzeichen_Bleibt_Nackt;
    [Test] procedure Bereits_Gequotet_Nicht_Doppelt;

    // --- was NICHT angefasst werden darf ---
    [Test] procedure Doppeltes_Prozent_Wird_Woertlich;
    [Test] procedure Unbekannter_Platzhalter_Bleibt_Stehen;
    [Test] procedure Einzelnes_Prozent_Am_Ende_Bleibt;
    [Test] procedure Prozent_Im_Pfad_Wird_Nicht_Nochmal_Ersetzt;
    [Test] procedure Leere_Vorlage_Bleibt_Leer;

    // --- die vier dokumentierten Editor-Aufrufe ---
    [Test] procedure Vorlage_VSCode;
    [Test] procedure Vorlage_NotepadPlusPlus;
    [Test] procedure Vorlage_Sublime;

    // --- Programmpruefung ---
    [Test] procedure NichtExistierendeDatei_IstNichtStartbar;
    [Test] procedure LeererPfad_IstNichtStartbar;
    [Test] procedure TextDatei_IstNichtStartbar;

    // --- DfmTarget ---
    [Test] procedure DfmTarget_HinUndZurueck;
    [Test] procedure DfmTarget_UnbekanntIstIde;
  end;

implementation

uses
  System.SysUtils, System.IOUtils,
  uEditorCommand;

const
  // Ein Pfad MIT Leerzeichen - der Normalfall unter Windows und genau der,
  // der bei fehlenden Anfuehrungszeichen kaputtgeht.
  F_SPC = 'C:\Program Files\My App\src\uMain.pas';
  F_NOSPC = 'C:\src\uMain.pas';
  // Der Schalter, mit dem VS Code eine Zeile anspringt. Als Konstante,
  // weil er in mehreren Tests vorkommt - der eigene Scan meldete ihn
  // sonst als DuplicateString.
  A_VSC   = '-g ';

{ --- die vier Platzhalter --- }

procedure TTestEditorCommand.File_Wird_Eingesetzt;
begin
  Assert.AreEqual('"' + F_SPC + '"', TEditorCommand.Expand('%file%', F_SPC, 42));
end;

procedure TTestEditorCommand.Line_Wird_Eingesetzt;
begin
  Assert.AreEqual('-n42', TEditorCommand.Expand('-n%line%', F_NOSPC, 42));
end;

procedure TTestEditorCommand.Col_Wird_Eingesetzt;
begin
  Assert.AreEqual('7', TEditorCommand.Expand('%col%', F_NOSPC, 42, 7));
end;

procedure TTestEditorCommand.Dir_Ohne_Abschliessenden_Trenner;
begin
  // Kein '\' am Ende - sonst wird aus "%dir%" ein maskiertes Anfuehrungs-
  // zeichen, wenn jemand die Vorlage quotet.
  Assert.AreEqual('C:\src', TEditorCommand.Expand('%dir%', F_NOSPC, 1));
end;

procedure TTestEditorCommand.Grossschreibung_Egal;
begin
  Assert.AreEqual('9', TEditorCommand.Expand('%LINE%', F_NOSPC, 9));
  Assert.AreEqual('9', TEditorCommand.Expand('%Line%', F_NOSPC, 9));
end;

{ --- Zeilennummern --- }

procedure TTestEditorCommand.Zeile_Null_Wird_Zu_Eins;
begin
  // Ein Fund ohne Zeilennummer darf den Editor nicht auf Zeile 0 schicken:
  // manche lesen das als Fehler, andere als "letzte Zeile".
  Assert.AreEqual('1', TEditorCommand.Expand('%line%', F_NOSPC, 0));
end;

procedure TTestEditorCommand.Zeile_Negativ_Wird_Zu_Eins;
begin
  Assert.AreEqual('1', TEditorCommand.Expand('%line%', F_NOSPC, -5));
end;

{ --- Anfuehrungszeichen --- }

procedure TTestEditorCommand.Pfad_Mit_Leerzeichen_Wird_Gequotet;
begin
  // Vorlage OHNE Anfuehrungszeichen, Pfad MIT Leerzeichen: das ist die
  // haeufigste Fehlbedienung, und sie wird still abgefangen.
  Assert.AreEqual(A_VSC + '"' + F_SPC + '":13',
    TEditorCommand.Expand(A_VSC + '%file%:%line%', F_SPC, 13));
end;

procedure TTestEditorCommand.Pfad_Ohne_Leerzeichen_Bleibt_Nackt;
begin
  // Ohne Leerzeichen keine Anfuehrungszeichen - sonst saehe jede
  // Kommandozeile anders aus als das, was der Nutzer hingeschrieben hat.
  Assert.AreEqual(A_VSC + F_NOSPC + ':13',
    TEditorCommand.Expand(A_VSC + '%file%:%line%', F_NOSPC, 13));
end;

procedure TTestEditorCommand.Bereits_Gequotet_Nicht_Doppelt;
begin
  // Steht der Platzhalter schon zwischen Anfuehrungszeichen, darf nicht
  // noch ein Paar dazukommen - ""C:\...\x.pas"" oeffnet nichts.
  Assert.AreEqual(A_VSC + '"' + F_SPC + ':13"',
    TEditorCommand.Expand(A_VSC + '"%file%:%line%"', F_SPC, 13));
end;

{ --- was NICHT angefasst werden darf --- }

procedure TTestEditorCommand.Doppeltes_Prozent_Wird_Woertlich;
begin
  Assert.AreEqual('100%', TEditorCommand.Expand('100%%', F_NOSPC, 1));
end;

procedure TTestEditorCommand.Unbekannter_Platzhalter_Bleibt_Stehen;
begin
  // Ein Editor koennte eigene %...%-Formen kennen; die duerfen wir nicht
  // verschlucken.
  Assert.AreEqual('%unknown%', TEditorCommand.Expand('%unknown%', F_NOSPC, 1));
end;

procedure TTestEditorCommand.Einzelnes_Prozent_Am_Ende_Bleibt;
begin
  Assert.AreEqual('abc%', TEditorCommand.Expand('abc%', F_NOSPC, 1));
end;

procedure TTestEditorCommand.Prozent_Im_Pfad_Wird_Nicht_Nochmal_Ersetzt;
const
  TRICKY = 'C:\tmp\%line%\u.pas';
begin
  // Der EINGESETZTE Wert darf nicht selbst noch einmal durch die
  // Ersetzung laufen. Mit mehreren StringReplace nacheinander waere aus
  // dem Verzeichnisnamen hier die Zeilennummer geworden.
  Assert.AreEqual(TRICKY + ' 5', TEditorCommand.Expand('%file% %line%', TRICKY, 5));
end;

procedure TTestEditorCommand.Leere_Vorlage_Bleibt_Leer;
begin
  Assert.AreEqual('', TEditorCommand.Expand('', F_NOSPC, 1));
end;

{ --- die dokumentierten Editor-Aufrufe --- }

procedure TTestEditorCommand.Vorlage_VSCode;
begin
  Assert.AreEqual(A_VSC + '"' + F_SPC + ':13"',
    TEditorCommand.Expand(TEditorCommand.DEFAULT_ARGS, F_SPC, 13));
end;

procedure TTestEditorCommand.Vorlage_NotepadPlusPlus;
begin
  Assert.AreEqual('-n13 "' + F_SPC + '"',
    TEditorCommand.Expand('-n%line% "%file%"', F_SPC, 13));
end;

procedure TTestEditorCommand.Vorlage_Sublime;
begin
  Assert.AreEqual('"' + F_SPC + ':13:7"',
    TEditorCommand.Expand('"%file%:%line%:%col%"', F_SPC, 13, 7));
end;

{ --- Programmpruefung --- }

procedure TTestEditorCommand.NichtExistierendeDatei_IstNichtStartbar;
begin
  Assert.IsFalse(TEditorCommand.IsLaunchableExe('C:\gibtesnicht\xyz.exe'));
end;

procedure TTestEditorCommand.LeererPfad_IstNichtStartbar;
begin
  Assert.IsFalse(TEditorCommand.IsLaunchableExe(''));
  Assert.IsFalse(TEditorCommand.IsLaunchableExe('   '));
end;

procedure TTestEditorCommand.TextDatei_IstNichtStartbar;
var
  Tmp : string;
begin
  // Existiert, ist aber kein Programm - die Endungspruefung muss greifen.
  Tmp := TPath.Combine(TPath.GetTempPath, 'sca_editor_probe.txt');
  TFile.WriteAllText(Tmp, 'x');
  try
    Assert.IsFalse(TEditorCommand.IsLaunchableExe(Tmp));
  finally
    TFile.Delete(Tmp);
  end;
end;

{ --- DfmTarget --- }

procedure TTestEditorCommand.DfmTarget_HinUndZurueck;
begin
  // Dritter Parameter False = Gross-/Kleinschreibung MIT vergleichen.
  // DUnitX vergleicht Zeichenketten sonst ohne (fIgnoreCaseDefault=True) -
  // ein Abrutschen auf 'Ide' bliebe unbemerkt, und in der INI steht
  // kleingeschrieben.
  Assert.AreEqual('ide',    TEditorCommand.DfmTargetToStr(dtIde),    False);
  Assert.AreEqual('viewer', TEditorCommand.DfmTargetToStr(dtViewer), False);
  Assert.IsTrue(TEditorCommand.StrToDfmTarget('viewer') = dtViewer);
  Assert.IsTrue(TEditorCommand.StrToDfmTarget('VIEWER') = dtViewer);
  Assert.IsTrue(TEditorCommand.StrToDfmTarget(' ide ')  = dtIde);
end;

procedure TTestEditorCommand.DfmTarget_UnbekanntIstIde;
begin
  // Ein Tippfehler in der INI darf nicht stillschweigend den eingebauten
  // Betrachter erzwingen - die Vorgabe gewinnt.
  Assert.IsTrue(TEditorCommand.StrToDfmTarget('vieuwer') = dtIde);
  Assert.IsTrue(TEditorCommand.StrToDfmTarget('')        = dtIde);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestEditorCommand);

end.
