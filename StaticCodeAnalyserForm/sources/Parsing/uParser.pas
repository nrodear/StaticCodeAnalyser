unit uParser;

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections,
  System.RegularExpressions,
  uMethodd12;

type
  TParser = class

    // Laedt Datei selbst und parst sie (Original-API, bleibt kompatibel)
    class procedure ParseFile(const FileName: string;
      out methodsList: TObjectList<TMethodInfo>); static;

    // Parst bereits geladene Zeilen (kein Datei-I/O) --
    // wird von TStaticAnalyzer verwendet um doppeltes Laden zu vermeiden.
    class procedure ParseLines(Lines: TStringList;
      out methodsList: TObjectList<TMethodInfo>); static;

  end;

implementation

uses
  uRegExMatches;

class procedure TParser.ParseFile(const FileName: string;
  out methodsList: TObjectList<TMethodInfo>);
var
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(FileName);
    ParseLines(Lines, methodsList);
  finally
    Lines.Free;
  end;
end;

class procedure TParser.ParseLines(Lines: TStringList;
  out methodsList: TObjectList<TMethodInfo>);
var
  line, nextLine: string;
  CurrentMethod: TMethodInfo;
  I, J: Integer;
  signatur: string;
  isSectionSignatur, isSectionMethod: boolean;
  isSectionComment: boolean;
  isSectionVar: boolean;
  isSectionImplementation: boolean;
  foundMatch : string;
begin
  isSectionImplementation := false;
  isSectionSignatur := false;
  isSectionComment := false;
  isSectionMethod := false;
  isSectionVar := false;
  signatur := '';
  CurrentMethod := nil;

  for I := 0 to Lines.Count - 1 do
  begin
    line := Trim(Lines[I]);
    if (Pos('implementation', line) = 1) then
    begin
      isSectionImplementation := true;
      Continue;
    end;

    if (Pos('end.', line) = 1) then
    begin
      Continue;
    end;

    // nix los implementation
    if (line = '') or not isSectionImplementation then
      Continue;

    // Kommentar: do skip
    // Start des Kommentar erkennen
    if TRegExMatches.IsCommentOf(line) then
    begin
      if (Pos('//', line) = 1) then
        Continue;
      // comment only or (code + comment)
      // comment only
      if TRegExMatches.GetCodeOnly(line) = line then
      begin
        isSectionComment := true;
        Continue;
      end;
    end;
    // Ende des Kommentar erkennen
    if (isSectionComment and TRegExMatches.IsCommentOf(line, false)) then
    begin
      isSectionComment := false;
      Continue;
    end;
    if (Pos('//', line) = 1) or isSectionComment then
      Continue;

    ///
    /// isSectionSignatur
    ///
    if TRegExMatches.MatchString('procedure|function|constructor|destructor', line) then
    begin
      isSectionSignatur := true;
      CurrentMethod := TMethodInfo.Create;
      CurrentMethod.SourceBody.Clear;
      CurrentMethod.Variables.Clear;
      CurrentMethod.LineNumber := IntToStr(I + 1);  // Zeile der Signatur merken
      methodsList.Add(CurrentMethod);
    end;

    if (isSectionSignatur and TRegExMatches.MatchOnlyString('var|begin|const', line.ToLower, foundMatch))
    then
    begin
      isSectionSignatur := false;
      // Defensiv: isSectionSignatur wird zwar mit CurrentMethod-Create
      // gemeinsam in Z. 110-115 gesetzt - aber ein Lookahead-Pfad weiter
      // unten kann CurrentMethod nillen ohne dass isSectionSignatur mit
      // ihn synchron geht. Crash-frei statt halb-konsistente Methode.
      if Assigned(CurrentMethod) then
      begin
        CurrentMethod.signatur := signatur;
        CurrentMethod.Name := TRegExMatches.GetName(signatur);
        // LineNumber wurde bereits bei der Signatur gesetzt -- nicht überschreiben
      end;
      signatur := '';
      isSectionMethod := false;
    end;

    if isSectionSignatur then
    begin
      signatur := signatur + line;
      Continue
    end;

    ///
    /// var section
    ///
    if TRegExMatches.MatchOnlyString('var', line, foundMatch) then
    begin
      isSectionVar := true;
      Continue;
    end;

    if isSectionVar and TRegExMatches.MatchOnlyString('begin', line, foundMatch) then
    begin
      isSectionVar := false;
      isSectionMethod := true;
    end;

    if Assigned(CurrentMethod) and isSectionVar then
    begin
      CurrentMethod.Variables.Add(line);
      Continue;
    end;

    ///
    /// rest body section
    ///
    // Defensiver Assigned-Check: isSectionMethod wird in Z. 144-148 alleine
    // gesetzt (`if isSectionVar and ... begin ... isSectionMethod:=true`),
    // ohne dass CurrentMethod gleichzeitig (re-)assigned wird. Wenn der
    // vorherige Lookahead-Pfad CurrentMethod genullt hat (Z. 178), kann
    // isSectionMethod=true mit CurrentMethod=nil zusammentreffen
    // (Trigger z.B. globaler `var`-Block in implementation gefolgt von
    // `begin`-Initialization-Block, oder weiter geistert isSectionVar
    // ueber Method-Boundary hinweg). Vorher: AV bei realen mORMot-Files
    // (z.B. mormot.crypt.x509.pas).
    if isSectionMethod and Assigned(CurrentMethod) then
      CurrentMethod.SourceBody.Add(line.ToLower);

    // Lookahead: naechste nicht-leere/nicht-`end.`-Zeile inspizieren.
    J := I;
    nextLine := '';
    while (J < Lines.Count) and ((nextLine = '') or (nextLine = 'end.')) do
    begin
      if (J + 1 < Lines.Count) then
        nextLine := Trim(Lines[J + 1])
      else
        nextLine := '';
      Inc(J);
    end;

    if TRegExMatches.MatchString('procedure|function|constructor|destructor|operator',
      nextLine) then
    begin
      isSectionMethod := false;
      isSectionVar    := false; // mit zuruecksetzen, sonst kann ein
                                // spaeteres `begin` isSectionMethod auf
                                // einem nilligen CurrentMethod re-aktivieren.
      CurrentMethod   := nil;
    end;

  end;
end;

end.
