unit ConcatToFormatSample;

// Sample-Unit fuer den Detektor uConcatToFormat.
//
// Erwartete Treffer (ConcatToFormat-Hint, roter Balken am Zeilenanfang
// im IDE-Editor):
//
//   * GreetVerbose  - klassisches Mehrfach-Concat mit IntToStr
//   * BuildLine     - Mix aus Literal + Variable + IntToStr
//   * BuildDebug    - drei Konkatenationen mit FloatToStr
//   * BuildMail     - 'Subject: ' + name + ' (' + IntToStr(id) + ')'
//
// Erwartet KEINE Treffer (Negativ-Faelle):
//
//   * AlreadyFormat - nutzt bereits Format()
//   * SingleConcat  - nur ein '+', kein Refactoring-Bedarf
//   * LiteralOnly   - reine Literal-Konkat (Multiline-String)
//   * SqlBuild      - SQL-Property -> uSQLInjection ist zustaendig

interface

uses
  System.SysUtils;

type
  TSample = class
  public
    function GreetVerbose(const AName: string; AAge: Integer): string;
    function BuildLine(const AKey: string; ACount: Integer): string;
    function BuildDebug(const ATag: string; AValue: Double): string;
    function BuildMail(const AName: string; AId: Integer): string;

    function AlreadyFormat(const AName: string; AAge: Integer): string;
    function SingleConcat(const AName: string): string;
    function LiteralOnly: string;
    procedure SqlBuild(Query: TObject; const AId: string);
  end;

implementation

// --- POSITIV: Erwartete Treffer ----------------------------------------

function TSample.GreetVerbose(const AName: string; AAge: Integer): string;
begin
  // Treffer: 3x '+', mischt Literal mit Identifier und IntToStr-Call
  Result := 'Hallo ' + AName + ', du bist ' + IntToStr(AAge) + ' Jahre alt';
end;

function TSample.BuildLine(const AKey: string; ACount: Integer): string;
begin
  // Treffer: Literal + Variable + Literal + Call
  Result := 'Key=' + AKey + '; Count=' + IntToStr(ACount);
end;

function TSample.BuildDebug(const ATag: string; AValue: Double): string;
begin
  // Treffer: drei Konkatenationen mit FloatToStr
  Result := '[' + ATag + '] value=' + FloatToStr(AValue) + ' done';
end;

function TSample.BuildMail(const AName: string; AId: Integer): string;
begin
  // Treffer: typisches Subject-Building
  Result := 'Subject: ' + AName + ' (' + IntToStr(AId) + ')';
end;

// --- NEGATIV: Keine Treffer --------------------------------------------

function TSample.AlreadyFormat(const AName: string; AAge: Integer): string;
begin
  // Kein Treffer: nutzt bereits Format
  Result := Format('Hallo %s, du bist %d Jahre alt', [AName, AAge]);
end;

function TSample.SingleConcat(const AName: string): string;
begin
  // Kein Treffer: nur ein '+', kein Refactoring-Bedarf
  Result := 'Hallo ' + AName;
end;

function TSample.LiteralOnly: string;
begin
  // Kein Treffer: reine Literal-Konkat (Multiline-Stringaufbau)
  Result := 'Line A ' +
            'Line B ' +
            'Line C';
end;

procedure TSample.SqlBuild(Query: TObject; const AId: string);
begin
  // Kein Treffer hier (uSQLInjection.pas ist fuer diesen Pfad zustaendig).
  // Belassen, damit visuell klar wird wo die Trennlinie liegt.
  // Query.SQL.Text := 'SELECT * FROM t WHERE id = ' + AId;
end;

end.
