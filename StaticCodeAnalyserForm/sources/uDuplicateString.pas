unit uDuplicateString;

// Detektor fuer mehrfach vorkommende String-Literale.
// Strings die >= MIN_OCCURRENCES Mal im Quelltext auftauchen, sollten
// als Konstante extrahiert werden.

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TDuplicateStringDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  private
    class procedure ExtractStrings(const Text: string; Lst: TStringList); static;
    class function IsTrivial(const S: string): Boolean; static;
  end;

implementation

const
  MIN_OCCURRENCES = 3;
  MIN_LENGTH      = 4;

class function TDuplicateStringDetector.IsTrivial(const S: string): Boolean;
// Sehr kurze oder formatierungs-Strings ueberspringen
begin
  if Length(S) < MIN_LENGTH then Exit(True);
  // Reine Whitespace, einzelne Sonderzeichen
  if Trim(S) = '' then Exit(True);
  // Format-Specifier ('%s', '%d')
  if (Length(S) = 2) and (S[1] = '%') then Exit(True);
  // Pfad-Separatoren / sehr generische Werte
  if (S = 'true') or (S = 'false') or (S = 'null') or (S = 'nil') then
    Exit(True);
  Result := False;
end;

class procedure TDuplicateStringDetector.ExtractStrings(const Text: string;
  Lst: TStringList);
// Findet alle '...'-Literale im Text. Verdoppelte ''-Anfuehrungszeichen werden
// als Teil des Strings behandelt.
var
  i      : Integer;
  Inside : Boolean;
  Buf    : string;
begin
  i      := 1;
  Inside := False;
  Buf    := '';
  while i <= Length(Text) do
  begin
    if Text[i] = '''' then
    begin
      if not Inside then
      begin
        Inside := True;
        Buf    := '';
      end
      else
      begin
        // Doppeltes '' = maskiertes Anfuehrungszeichen innerhalb des Strings
        if (i < Length(Text)) and (Text[i + 1] = '''') then
        begin
          Buf := Buf + '''';
          Inc(i, 2);
          Continue;
        end;
        // Schliessendes Anfuehrungszeichen
        Inside := False;
        if not IsTrivial(Buf) then
          Lst.Add(Buf);
      end;
    end
    else if Inside then
      Buf := Buf + Text[i];
    Inc(i);
  end;
end;

class procedure TDuplicateStringDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Counts    : TDictionary<string, Integer>;
  FirstLine : TDictionary<string, Integer>;
  AllNodes  : TList<TAstNode>;
  N         : TAstNode;
  Lst       : TStringList;
  S         : string;
  Cnt       : Integer;
  F         : TLeakFinding;
  Pair      : TPair<string, Integer>;
  Display   : string;
begin
  Counts    := nil;
  FirstLine := nil;
  Lst       := nil;
  try
    Counts    := TDictionary<string, Integer>.Create;
    FirstLine := TDictionary<string, Integer>.Create;
    Lst       := TStringList.Create;
    // Alle Knoten-Texte sammeln und Strings extrahieren
    for var Kind in [nkAssign, nkCall] do
    begin
      AllNodes := UnitNode.FindAll(Kind);
      try
        for N in AllNodes do
        begin
          Lst.Clear;
          if Kind = nkAssign then
            ExtractStrings(N.TypeRef, Lst)
          else
            ExtractStrings(N.Name, Lst);

          for S in Lst do
          begin
            if Counts.ContainsKey(S) then
              Counts[S] := Counts[S] + 1
            else
            begin
              Counts.Add(S, 1);
              FirstLine.Add(S, N.Line);
            end;
          end;
        end;
      finally
        AllNodes.Free;
      end;
    end;

    // Strings mit >= MIN_OCCURRENCES melden
    for Pair in Counts do
    begin
      if Pair.Value < MIN_OCCURRENCES then Continue;
      Cnt := Pair.Value;
      // Anzeige-Text kuerzen
      Display := Pair.Key;
      if Length(Display) > 30 then
        Display := Copy(Display, 1, 27) + '...';

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := '';
      F.LineNumber := IntToStr(FirstLine[Pair.Key]);
      F.MissingVar := Format('"%s" %dx - Konstante extrahieren',
                             [Display, Cnt]);
      F.Severity   := lsHint;
      F.Kind       := fkDuplicateString;
      Results.Add(F);
    end;
  finally
    Counts.Free;
    FirstLine.Free;
    Lst.Free;
  end;
end;

end.
