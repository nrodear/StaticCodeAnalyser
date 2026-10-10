unit uMethodd12;

// Stub fuer den FPC-Pruefstand: TLeakFinding nur mit den Feldern, die die
// geprueften Units und Tests lesen (uFindingActions, uTestFindingActions).
// Kein RefactorInfo-Feld mehr - der Push-Kanal ist verworfen.

interface

type
  TLeakFinding = class
  public
    FileName   : string;
    MethodName : string;
    LineNumber : string;
    MissingVar : string;
  end;

implementation

end.
