unit uMethodd12;

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections,
  uSCAConsts, uLocalization;  // _() — SeverityText/TypeText lokalisierbar

type
  TMethodInfo = class
  public
    Name: string;
    Signatur: string;
    LineNumber: string;
    Variables: TStringList;
    SourceBody: TStringList;

    constructor Create;
    destructor Destroy; override;
    procedure GetVarNamesByFilter(const myClazz: string; out vars: TStringList);
    procedure GetVarNamesByClasses(const classes: TStringList; out vars: TStringList);
  end;

  TLeakFinding = class
  public
    FileName:   string;
    MethodName: string;
    LineNumber: string;
    MissingVar: string;
    Severity:   TLeakSeverity;
    Kind:       TFindingKind;
    // Konfidenz des Befundes (FP-Wahrscheinlichkeit). Default fcHigh - im
    // Constructor gesetzt, damit JEDER Befund (auch ohne SetKind) als
    // hochkonfident startet. Detektoren mit heuristischen Treffern setzen
    // .Confidence danach explizit herab (z.B. := fcLow). Der Post-Filter
    // uConfidenceFilter wirft Befunde unter FindingMinConfidence raus.
    Confidence: TFindingConfidence;
    // Optionale Custom-Rule-ID (z.B. 'PROJ001'). Bei built-in-Rules leer
    // gelassen - SARIF-Export holt dann die ID aus TRuleCatalog via Kind.
    // Wenn gesetzt, gewinnt RuleID gegen den Catalog-Lookup.
    RuleID:     string;
    // Setzt Confidence := fcHigh (Default). Bestehende Detektoren erzeugen
    // Befunde binaer und gelten damit als hochkonfident.
    constructor Create;
    // Setzt Kind UND Severity in einem Schritt - Severity wird aus
    // KIND_META.DefaultSeverity gezogen (single source of truth). Detektoren
    // die einen kontext-abhaengigen Severity brauchen (z.B. uLeakDetector2,
    // uDivByZero - Confidence-basiert) setzen .Severity weiterhin manuell.
    procedure SetKind(K: TFindingKind); overload;
    // Wie SetKind(K), aber mit explizit gesetzter Confidence statt
    // KindDefaultConfidence. Schuetzt vor der fragilen Reihenfolge
    //   F.SetKind(K);                 // -> Confidence aus KIND_META
    //   F.Confidence := fcLow;        // muss DANACH passieren, sonst weg
    // die heute in uCommandInjection und uDivByZero implizit gilt.
    procedure SetKind(K: TFindingKind; AConfidence: TFindingConfidence);
      overload;
    function SeverityText: string;
    function FindingType: TFindingType;
    function TypeText: string;

    // ---- Phase-1 API-Komfort (additiv, 2026-06-26) -----------------------
    // Sprechende Aliase fuer die Legacy-Feldnamen, damit ein Fremd-Consumer
    // die Datengrenze ohne Quelltext-Studium versteht
    // (Konzept_EngineApiSchnittstelle.md, Luecken G4/G8). Bestehende Felder
    // bleiben unveraendert - rein additiv.
    //
    // 'Message' = die Befund-/Detailmeldung (Legacy-Feld 'MissingVar').
    property Message: string read MissingVar write MissingVar;
    // 'LineInt' = LineNumber als Integer (das Legacy-Feld ist ein String).
    function LineInt: Integer;
    // Aufgeloeste SCAxxx-Regel-ID: das explizite RuleID-Feld falls gesetzt
    // (Custom-Rule), sonst der Catalog-Lookup ueber Kind. Damit muss der
    // Consumer nicht selbst TRuleCatalog.GetRule(Kind).ID aufrufen.
    function ResolvedRuleId: string;

    // Convenience-Constructor: kapselt das 7-Zeilen-Boilerplate-Pattern
    // (Create + 5 Field-Sets + SetKind) das in 30+ Detector-Files
    // dupliziert war. Vorher:
    //   F := TLeakFinding.Create;
    //   F.FileName := FN; F.MethodName := M;
    //   F.LineNumber := IntToStr(L);
    //   F.MissingVar := Msg;
    //   F.SetKind(K);
    //   Results.Add(F);
    // Jetzt:
    //   Results.Add(TLeakFinding.New(FN, M, L, Msg, K));
    class function New(const AFileName, AMethodName: string; ALine: Integer;
      const AMissingVar: string; AKind: TFindingKind): TLeakFinding; overload; static;
    // Variante mit expliziter Confidence (z.B. fcLow fuer heuristische
    // Treffer in uLeakDetector2 / uDivByZero).
    class function New(const AFileName, AMethodName: string; ALine: Integer;
      const AMissingVar: string; AKind: TFindingKind;
      AConfidence: TFindingConfidence): TLeakFinding; overload; static;
  end;

implementation

// noinspection-file AvoidOut, CanBeClassMethod, CanBeStrictPrivate, ClassPerFile, GroupedDeclaration, LowercaseKeyword, MissingUnitHeader, PublicField, PublicMemberWithoutDoc, TooLongLine, UnsortedUses, UnusedPublicMember
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  // Nur fuer ResolvedRuleId (Kind -> SCAxxx). Bewusst in der IMPLEMENTATION,
  // damit das Interface uMethodd12 schlank bleibt und kein Interface-Zyklus
  // entsteht (uRuleCatalog nutzt uMethodd12 NICHT).
  uRuleCatalog;

{ TMethodInfo }

constructor TMethodInfo.Create;
begin
  inherited;
  Name := '';
  SourceBody := TStringList.Create;
  Variables := TStringList.Create;
  Variables.clear;
  SourceBody.clear;
end;

destructor TMethodInfo.Destroy;
begin
  freeAndNil(SourceBody);
  freeAndNil(Variables);
  inherited;
end;

procedure TMethodInfo.GetVarNamesByFilter(const myClazz: string;
  out vars: TStringList);
var
  temps: TStringList;
  line, inputString: string;

begin
  temps := TStringList.Create;
  try
    for line in Variables do
    begin
      if line.Contains(myClazz) then
      begin
        inputString := Trim(Copy(line, 1, Pos(':', line) - 1));
        temps.clear;
        temps.Delimiter     := ',';
        temps.DelimitedText := inputString;
        for var t := 0 to temps.Count - 1 do
          temps[t] := Trim(temps[t]);
        vars.AddStrings(temps);
      end;
    end;
  finally
    FreeAndNil(temps);
  end;
end;

procedure TMethodInfo.GetVarNamesByClasses(const classes: TStringList;
  out vars: TStringList);
var
  clazz: string;
begin
  for clazz in classes do
    GetVarNamesByFilter(clazz, vars);
end;

constructor TLeakFinding.Create;
begin
  inherited Create;
  Confidence := fcHigh; // sicherer Default - Detektoren senken bei Bedarf
end;

procedure TLeakFinding.SetKind(K: TFindingKind);
// Setzt Kind + Severity + Confidence aus KIND_META / KindDefaultConfidence.
// Detektoren die einen anderen Confidence-Level brauchen, nutzen die
// SetKind(K, AConfidence)-Overload um Override + Default-Reihenfolge
// nicht zu verwechseln.
begin
  Kind       := K;
  Severity   := KindDefaultSeverity(K);
  Confidence := KindDefaultConfidence(K);
end;

procedure TLeakFinding.SetKind(K: TFindingKind;
  AConfidence: TFindingConfidence);
begin
  Kind       := K;
  Severity   := KindDefaultSeverity(K);
  Confidence := AConfidence;
end;

class function TLeakFinding.New(const AFileName, AMethodName: string;
  ALine: Integer; const AMissingVar: string;
  AKind: TFindingKind): TLeakFinding;
begin
  Result := TLeakFinding.Create;
  Result.FileName   := AFileName;
  Result.MethodName := AMethodName;
  Result.LineNumber := IntToStr(ALine);
  Result.MissingVar := AMissingVar;
  Result.SetKind(AKind);
end;

class function TLeakFinding.New(const AFileName, AMethodName: string;
  ALine: Integer; const AMissingVar: string; AKind: TFindingKind;
  AConfidence: TFindingConfidence): TLeakFinding;
begin
  Result := TLeakFinding.Create;
  Result.FileName   := AFileName;
  Result.MethodName := AMethodName;
  Result.LineNumber := IntToStr(ALine);
  Result.MissingVar := AMissingVar;
  Result.SetKind(AKind, AConfidence);
end;

function TLeakFinding.SeverityText: string;
// Liefert lokalisierten Severity-Text fuer UI-Anzeige (Grid, Hover-Overlay,
// Export). Source-Strings sind ENGLISCH (Konvention von uLocalization),
// uLocalization._() mappt bei aktiver DE-Sprache auf 'Fehler'/'Warnung'/etc.
// uAnalyserTypes.SeverityFromText akzeptiert beide Sprachen parallel,
// daher bleiben Sort + Grid-Filter intakt.
begin
  // FileReadError ist ein Sonderfall: kein Code-Befund sondern Parser-Fehler.
  if Kind = fkFileReadError then
    Exit(_('Read Error'));

  case Severity of
    lsError   : Result := _('Error');
    lsWarning : Result := _('Warning');
    lsHint    : Result := _('Hint');
  else
    Result := '';
  end;
end;

function TLeakFinding.FindingType: TFindingType;
// Delegiert an KIND_META in uSCAConsts (single source of truth fuer
// Kind -> Sonar-Type-Mapping). Vorher: case-Statement das gegen die
// Mappings in uExport/uClaudePrompt/uSuppression driften konnte.
begin
  Result := KindFindingType(Kind);
end;

function TLeakFinding.TypeText: string;
// SonarQube-typische Type-Bezeichnungen — Source-Strings englisch (etabliert),
// fuer DE-UI via _() uebersetzbar (default Pass-Through bleibt englisch
// solange kein DE-Mapping fuer 'Bug'/'Code Smell' im Dictionary steht).
begin
  case FindingType of
    ftBug             : Result := _('Bug');
    ftCodeSmell       : Result := _('Code Smell');
    ftVulnerability   : Result := _('Vulnerability');
    ftSecurityHotspot : Result := _('Security Hotspot');
    ftCodeDuplication : Result := _('Code Duplication');
    ftFileError       : Result := _('Read Error');
  else
    Result := '';
  end;
end;

function TLeakFinding.LineInt: Integer;
begin
  Result := StrToIntDef(LineNumber, 0);
end;

function TLeakFinding.ResolvedRuleId: string;
begin
  if RuleID <> '' then
    Result := RuleID                       // explizite Custom-Rule-ID gewinnt
  else
    Result := TRuleCatalog.GetRule(Kind).ID;  // Built-in: Catalog-Lookup ueber Kind
end;

end.
