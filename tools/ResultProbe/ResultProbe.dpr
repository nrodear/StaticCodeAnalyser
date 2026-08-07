program ResultProbe;

// Messprogramm: Wie verhaelt sich ein Funktionsergebnis, das NICHT
// zugewiesen wird?
//
// WOZU: Grundlage fuer die geplante Regel SCA196
// (ManagedResultNotInitialized). Aus dem RTL-Quelltext ist belegt, dass
// ein Ergebnis bestimmter Typen ueber einen versteckten Zeiger auf
// AUFRUFER-Speicher zurueckkommt und beim Eintritt NICHT geleert wird:
//
//   System.Rtti.pas:2117   UseResultPointer - die massgebliche Typliste
//   System.Variants.pas:6724  function Unassigned: Variant;
//                             begin _VarClear(TVarData(Result)); end;
//                             (der GANZE Rumpf ist Aufraeumen - waere
//                              Result leer, waere die Funktion sinnlos)
//   System.SysUtils.pas:13019  Result := '';
//                              // prevent copying of existing data
//
// Was daraus NICHT folgt und deshalb hier gemessen wird:
//   * ob bei 'A := F;' wirklich @A durchgereicht wird (oder ein Temp),
//   * ob das in einer Schleife ueber Durchlaeufe stehenbleibt,
//   * ob ein for-in-Temp wiederverwendet wird,
//   * ob 'Result := G;' den Zeiger durchreicht,
//   * WO GENAU W1035 (NO_RETVAL) feuert - und wo eben nicht.
//
// BEDIENUNG
//   1. Diese .dpr in der IDE oeffnen (Datei > Oeffnen). Delphi legt das
//      Projekt automatisch an - eine .dproj wird bewusst nicht
//      mitgeliefert, die waere nur eine Fehlerquelle.
//   2. Fuer Win32 UND Win64 bauen. BEIDE Ausgaben vergleichen: die
//      Aufrufkonvention unterscheidet sich, und genau darum geht es.
//   3. WICHTIG: Die Compiler-Meldungen MITSCHREIBEN. Der Abschnitt
//      'W1035-Proben' unten existiert nur dafuer - welche der Funktionen
//      eine Warnung bekommt und welche nicht, ist die halbe Messung.
//      In der IDE: Meldungsfenster > Rechtsklick > Alles kopieren.
//   4. Ausgabe + Warnungsliste zurueckmelden.
//
// ABBRUCHKRITERIUM
//   Zeigt Probe 2a NICHT den Altwert ['ALT'], ist die Praemisse der
//   geplanten Regel hinfaellig. Dann bitte zuerst melden - dann wird
//   nichts gebaut.

{$APPTYPE CONSOLE}

// Ausdruecklich NICHT abschalten - die Warnungen sind das Messergebnis.
{$WARN NO_RETVAL ON}

uses
  System.SysUtils,
  System.Variants;

type
  TA  = TArray<string>;
  TRM = record S: string; N: Integer; end;   // record MIT verwaltetem Feld
  TRU = record X, Y: Integer; end;           // record OHNE verwaltetes Feld

// ---------------------------------------------------------------------
// Anzeige-Helfer
// ---------------------------------------------------------------------
function D(const A: TA): string;
begin
  if A = nil then Exit('<nil>');
  Result := '[' + string.Join(',', A) + '] len=' + IntToStr(Length(A));
end;

procedure FillArr(var A: TA);
begin
  A := ['VIA-VAR'];
end;

// =====================================================================
//  W1035-PROBEN
//  Diese Routinen weisen Result NIE oder nur teilweise zu. Frage an den
//  Compiler: bei WELCHEN kommt W1035? Erwartung nach Aktenlage: nur bei
//  den unverwalteten (Integer, kleiner record) - genau darin liegt die
//  Luecke, die die Regel schliessen soll.
// =====================================================================
function A_Never:  TA;          begin end;
function S_Never:  string;      begin end;
function SS_Never: ShortString; begin end;
function RM_Never: TRM;         begin end;
function RU_Never: TRU;         begin end;
function I_Never:  Integer;     begin end;
function V_Never:  Variant;     begin end;
function If_Never: IInterface;  begin end;

// Teil-Zuweisung: nur in einem Zweig
function A_IfOnly(B: Boolean): TA;
begin
  if B then Result := ['NEU'];
end;

function I_IfOnly(B: Boolean): Integer;
begin
  if B then Result := 42;
end;

// Ausstieg OHNE Wert (blankes Exit) - fuer die Regel der Kernfall
function A_ExitBare(B: Boolean): TA;
begin
  if not B then Exit;
  Result := ['NEU'];
end;

// Zuweisung ueber SetLength statt ':=' - darf NICHT als fehlend gelten
function A_ViaSetLen: TA;
begin
  SetLength(Result, 1);
  Result[0] := 'X';
end;

// Zuweisung ueber var-Parameter - darf NICHT als fehlend gelten
function A_ViaVarArg: TA;
begin
  FillArr(Result);
end;

// Weiterreichung: gibt das Ergebnis einer anderen Funktion zurueck
function A_Fwd(B: Boolean): TA;
begin
  Result := A_IfOnly(B);
end;

// =====================================================================
//  MESSUNGEN
// =====================================================================

procedure T2a;
// Kernfrage: wird @A durchgereicht? Dann behaelt A seinen Altwert.
var
  A : TA;
begin
  A := ['ALT'];
  A := A_Never;
  Writeln('2a direkt      : ', D(A), '      (erwartet: [ALT])');
end;

procedure T2b;
// Der praxisrelevante Fall: Schleife, dieselbe Zielvariable.
var
  A : TA;
  I : Integer;
begin
  for I := 1 to 3 do
  begin
    A := A_IfOnly(I = 1);
    Writeln('2b schleife i=', I, '  : ', D(A),
            '      (i>1 erwartet: [NEU] = abgestanden)');
  end;
end;

procedure T2c;
// Wird der Temp einer for-in-Quelle ueber Durchlaeufe wiederverwendet?
var
  S : string;
  I, N : Integer;
begin
  for I := 1 to 2 do
  begin
    N := 0;
    for S in A_IfOnly(I = 1) do Inc(N);
    Writeln('2c for-in i=', I, '   : n=', N,
            '      (i=2 mit n>0 = Temp wiederverwendet)');
  end;
end;

procedure T2d;
// Reicht 'Result := G;' den Ergebniszeiger durch?
var
  A : TA;
begin
  A := ['ALT'];
  A := A_Fwd(False);
  Writeln('2d verkettet   : ', D(A), '      (erwartet: [ALT])');
end;

procedure T2e;
// Gegenprobe: erzwungener Zwischenwert. Hier sollte KEIN Altwert stehen.
var
  A : TA;
begin
  A := ['ALT'];
  A := Copy(A_Never, 0, MaxInt);
  Writeln('2e ueber Temp  : ', D(A), '      (erwartet: <nil>)');
end;

procedure T2f;
// Gilt dasselbe fuer die uebrigen Zeigertypen? Und was macht der
// unverwaltete record (der laut UseResultPointer im Register kommt)?
var
  RM : TRM;
  RU : TRU;
  V  : Variant;
  F  : IInterface;
  SS : ShortString;
begin
  RM.S := 'ALT'; RM.N := 7;
  RM := RM_Never;
  Writeln('2f record(mgd) : ', RM.S, '/', RM.N, '      (erwartet: ALT/7)');

  RU.X := 11; RU.Y := 22;
  RU := RU_Never;
  Writeln('2f record(roh) : ', RU.X, '/', RU.Y,
          '      (Gegenprobe - hier ist Altwert NICHT zugesichert)');

  V := 'ALT';
  V := V_Never;
  Writeln('2f variant     : ', VarToStr(V), '      (erwartet: ALT)');

  SS := 'ALT';
  SS := SS_Never;
  Writeln('2f shortstring : ', SS, '      (erwartet: ALT)');

  F := TInterfacedObject.Create;
  F := If_Never;
  Writeln('2f interface   : ', BoolToStr(Assigned(F), True),
          '      (erwartet: True = Altreferenz gehalten)');
end;

procedure T2g;
// Die drei Formen, die NICHT als 'fehlt' gelten duerfen.
var
  A : TA;
begin
  A := A_ViaSetLen;
  Writeln('2g via SetLength: ', D(A), '      (erwartet: [X])');
  A := A_ViaVarArg;
  Writeln('2g via var-Param: ', D(A), '      (erwartet: [VIA-VAR])');
  A := ['ALT'];
  A := A_ExitBare(False);
  Writeln('2g Exit ohne Wert: ', D(A), '      (erwartet: [ALT])');
end;

procedure TouchUnused;
// Ruft die reinen W1035-Proben einmal auf, damit der Compiler ihre
// Ruempfe garantiert uebersetzt (und die Warnungen wirklich kommen).
// Die Werte selbst interessieren hier nicht.
var
  Dummy : Integer;
begin
  Dummy := I_Never + I_IfOnly(False);
  if Dummy = MaxInt then Writeln('unerreichbar');
  S_Never;
end;

begin
  Writeln('ResultProbe - Zielplattform: ',
          {$IFDEF WIN64} 'Win64' {$ELSE} 'Win32' {$ENDIF});
  Writeln('-------------------------------------------------------------');
  try
    TouchUnused;
    T2a;
    T2b;
    T2c;
    T2d;
    T2e;
    T2f;
    T2g;
  except
    on E: Exception do
      Writeln('AUSNAHME: ', E.ClassName, ': ', E.Message);
  end;
  Writeln('-------------------------------------------------------------');
  Writeln('Bitte AUSGABE und COMPILER-WARNUNGEN zurueckmelden.');
  Readln;
end.
