unit uTestVcsChanges;

// Tests fuer den nil-Vertrag von TVcsChanges (G7-1, 2026-08-25).
//
// DER VERTRAG: nil = Fehler (kein Repo, kein git/svn, Range nicht
// aufloesbar; AInfo sagt warum), leere Liste = ehrlich nichts geaendert.
//
// WARUM ER EINEN ANKER BRAUCHT: der Kontrakt stand seit jeher im
// Interface-Kommentar von GetChangedPasFilesDiff - gehalten hat ihn die
// Implementierung nie. Jeder VCS-Fehler kam als leere Liste zurueck, die
// CLI machte daraus "nichts geaendert" und Exit 0: ein CI-Gate auf einem
// Shallow-Clone (GitHub-Actions-Default fetch-depth=1) war gruen, ohne
// eine einzige Datei gescannt zu haben. Faellt der Vertrag zurueck auf
// "leere Liste bei Fehler", wird KEIN Test rot ausser diesen hier.
//
// Die Tests brauchen bewusst KEIN git und KEIN Repo: der Nicht-Repo-Fall
// ist mit einem frischen %TEMP%-Verzeichnis herstellbar und ist genau
// der Fall, der vorher falsch beantwortet wurde.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestVcsChanges = class
  public
    [Test] procedure AutoOnNonRepo_ReturnsNilWithReason;
    [Test] procedure DiffOnNonRepo_ReturnsNilWithReason;
    [Test] procedure GetChangedWithVkNone_ReturnsNil;
  end;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  uVcsChanges;

function FrischesNichtRepo: string;
// Ein garantiert repo-freies Verzeichnis: eigener GUID-Ordner unter
// %TEMP%. DetectRepo wandert von dort nach OBEN - sollte ein Entwickler
// seinen Temp-Pfad tatsaechlich in ein Repo gelegt haben, faende es
// eines. Der Ordner selbst stellt nur sicher, dass unterhalb nichts ist.
begin
  Result := TPath.Combine(TPath.GetTempPath, 'sca_kein_repo_' +
    TGuid.NewGuid.ToString.Replace('{', '').Replace('}', ''));
  TDirectory.CreateDirectory(Result);
end;

procedure TTestVcsChanges.AutoOnNonRepo_ReturnsNilWithReason;
var
  Dir   : string;
  Info  : string;
  Files : TStringList;
begin
  Dir := FrischesNichtRepo;
  try
    Files := TVcsChanges.GetChangedPasFilesAuto(Dir, Info);
    try
      Assert.IsNull(Files,
        'Nicht-Repo muss nil liefern (Fehler), nicht eine leere Liste ' +
        '("nichts geaendert") - daran haengt der CLI-Exit-Code');
      Assert.IsNotEmpty(Info,
        'ohne Grund in AInfo kann kein Aufrufer eine Fehlermeldung zeigen');
    finally
      Files.Free;   // nil-sicher
    end;
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestVcsChanges.DiffOnNonRepo_ReturnsNilWithReason;
var
  Dir   : string;
  Info  : string;
  Files : TStringList;
begin
  Dir := FrischesNichtRepo;
  try
    Files := TVcsChanges.GetChangedPasFilesDiff(Dir, 'main..HEAD', Info);
    try
      Assert.IsNull(Files,
        '--diff auf Nicht-Repo muss nil liefern - das ist der ' +
        'Interface-Vertrag, der vor G7-1 nie gehalten wurde');
      Assert.IsNotEmpty(Info);
    finally
      Files.Free;
    end;
  finally
    TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestVcsChanges.GetChangedWithVkNone_ReturnsNil;
var
  Info  : string;
  Files : TStringList;
begin
  Files := TVcsChanges.GetChangedPasFiles(TPath.GetTempPath, vkNone, Info);
  try
    Assert.IsNull(Files, 'vkNone ist ein Aufruf-Fehler, keine leere Menge');
    Assert.IsNotEmpty(Info);
  finally
    Files.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestVcsChanges);

end.
