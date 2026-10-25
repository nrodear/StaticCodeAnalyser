unit uTestCrashDiag;

// Tests fuer uCrashDiag. Der Punkt der Unit ist, dass eine abgefangene
// Zugriffsverletzung SPAETER noch auswertbar ist - also wird genau das
// geprueft: Exception-Klasse, NT-Statuscode und die modulRELATIVE Adresse.
//
// Der Hardware-Fall braucht keinen echten Absturz: EAccessViolation ist ein
// EExternal, und dessen ExceptionRecord laesst sich fuer den Test mit einem
// kuenstlichen Satz Werte belegen. Damit ist die Adressarithmetik pruefbar,
// ohne den Prozess zu beschaedigen.
//
// Ausnahme seit 2026-10-25: der Diagnose-Stapel (SCA_CRASH_STACK) wird mit
// EINER echten AV geprueft (Schreiben nach nil) - ob der Haken bei einer
// Hardware-Ausnahme greift, laesst sich mit einem kuenstlichen Satz nicht
// zeigen, die RTL erzeugt das Objekt dann selbst.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCrashDiag = class
  public
    [Test] procedure Describe_Plain_NamesClassAndMessage;
    [Test] procedure Describe_Plain_HasNoAddressAtAll;
    [Test] procedure Describe_External_ReportsNtStatus;
    [Test] procedure Describe_External_ReportsModuleRelativeAddress;
    [Test] procedure Describe_AddressBelowBase_SaysSo;
    [Test] procedure Describe_AddressAboveImage_SaysSo;
    [Test] procedure Describe_Nil_DoesNotCrash;
    // Diagnose-Stapel (SCA_CRASH_STACK, 2026-10-25)
    [Test] procedure CrashStack_LogPath_OffValues_GiveEmpty;
    [Test] procedure CrashStack_LogPath_OnValues_GiveFileNextToExe;
    [Test] procedure CrashStack_LogPath_OtherValue_IsThePath;
    [Test] procedure CrashStack_FormatFrame_ModuleRelative;
    [Test] procedure CrashStack_FormatFrame_UnknownModule;
    [Test] procedure CrashStack_Raise_CapturesRaisingFrame;
    [Test] procedure CrashStack_AccessViolation_CapturesFaultAddress;
    [Test] procedure CrashStack_Inactive_ReportIsNoOp;
  end;

implementation

uses
  Winapi.Windows,   // GetCurrentProcessId; vor SysUtils, damit SysUtils-Namen gewinnen
  System.SysUtils,
  System.IOUtils,
  uCrashDiag;

// Baut eine EAccessViolation mit kuenstlichem ExceptionRecord. Der Aufrufer
// besitzt die Instanz; ARec muss ihn ueberleben (daher Parameter, nicht
// lokale Variable dieser Funktion).
function MakeExternal(var ARec: TExceptionRecord; ACode: Cardinal;
  AAddr: Pointer): EAccessViolation;
begin
  FillChar(ARec, SizeOf(ARec), 0);
  ARec.ExceptionCode    := ACode;
  ARec.ExceptionAddress := AAddr;
  Result := EAccessViolation.Create('kuenstlich');
  {$WARN SYMBOL_PLATFORM OFF}
  Result.ExceptionRecord := @ARec;
  {$WARN SYMBOL_PLATFORM ON}
end;

procedure TTestCrashDiag.Describe_Plain_NamesClassAndMessage;
var S: string;
begin
  try
    raise EListError.Create('Testmeldung');
  except
    // Bewusst die konkrete Klasse statt Exception: ein pauschaler Fang
    // waere hier eine echte Ungenauigkeit (und SCA132 hat recht damit).
    on E: EListError do
      S := DescribeException(E);
  end;
  Assert.IsTrue(Pos('EListError', S) > 0,
                'Exception-Klasse fehlt im Text: ' + S);
  Assert.IsTrue(Pos('Testmeldung', S) > 0,
                'Originalmeldung fehlt im Text: ' + S);
end;

procedure TTestCrashDiag.Describe_Plain_HasNoAddressAtAll;
var S: string;
begin
  // Innerhalb eines except-Blocks liefert ExceptAddr eine Adresse, also
  // muss die modulRELATIVE Adresse mitkommen - sie ist der Wert, der
  // gegen eine Detailed-Map aufloesbar ist.
  //
  // Die zweite Zusicherung ist der eigentliche Vertrag seit I3: die
  // absolute Modulbasis darf NICHT mehr im Text stehen. Sie ist die
  // einzige laufabhaengige Zahl (ASLR), und dieser Text wird zum
  // SCA006-MELDETEXT - mit ihr darin war derselbe Fehler in zwei
  // Laeufen zwei verschiedene Funde (G-Abnahme 20.09.: drei
  // SCA006-Funde erschienen als Drop+Add-Paar, allein weil die Basis
  // von $370000 auf $960000 gewandert war).
  // Die Vorfassung dieses Tests forderte das GEGENTEIL - sie stammt
  // aus der Zeit, als der Text nur ins Log ging.
  try
    raise EListError.Create('egal');
  except
    on E: EListError do
      S := DescribeException(E);
  end;
  // O1 (2026-09-21): GEDREHT. I3 forderte hier die modulrelative
  // Adresse; die ist zwar je Build konstant, wandert aber mit JEDEM
  // Neubau - und dieser Text bildet die Identitaet eines SCA006-
  // Fundes. Bei einer GEWORFENEN Exception traegt sie ohnehin nichts
  // bei: sie zeigt auf die raise-Zeile, und die Meldung nennt die
  // Ursache schon. Die Gegenprobe steht in
  // Describe_External_ReportsModuleRelativeAddress - dort, bei einem
  // echten Absturz, MUSS die Adresse weiterhin erscheinen.
  Assert.IsTrue(Pos('modulrelativ', S) = 0,
                'eine geworfene Exception darf keine Adresse tragen - '
                + 'sie wandert bei jedem Bau und macht den Fund '
                + 'instabil: ' + S);
  Assert.IsTrue(Pos('Modulbasis', S) = 0,
                'die ASLR-abhaengige Modulbasis macht den Meldetext '
                + 'laufabhaengig und darf nicht mehr vorkommen: ' + S);
  Assert.IsTrue(Pos('EListError', S) > 0,
                'Klasse und Meldung muessen bleiben - nur die Adresse '
                + 'faellt weg: ' + S);
end;

procedure TTestCrashDiag.Describe_External_ReportsNtStatus;
var
  Rec : TExceptionRecord;
  E   : EAccessViolation;
  S   : string;
begin
  // $C00000FD = STATUS_STACK_OVERFLOW. Genau die Unterscheidung, wegen der
  // der Statuscode im Text steht: eine erschoepfte Stapelgroesse sieht in
  // der RTL-Meldung aus wie eine gewoehnliche Zugriffsverletzung.
  E := MakeExternal(Rec, $C00000FD, Pointer(UIntPtr(HInstance) + $10));
  try
    S := LowerCase(DescribeException(E));
  finally
    E.Free;
  end;
  Assert.IsTrue(Pos('$c00000fd', S) > 0, 'NT-Statuscode fehlt: ' + S);
end;

procedure TTestCrashDiag.Describe_External_ReportsModuleRelativeAddress;
var
  Rec : TExceptionRecord;
  E   : EAccessViolation;
  S   : string;
begin
  E := MakeExternal(Rec, $C0000005, Pointer(UIntPtr(HInstance) + $ABCDE));
  try
    S := LowerCase(DescribeException(E));
  finally
    E.Free;
  end;
  Assert.IsTrue(Pos('modulrelativ $abcde', S) > 0,
                'Modulrelative Adresse falsch oder fehlt: ' + S);
end;

procedure TTestCrashDiag.Describe_AddressBelowBase_SaysSo;
var
  Rec : TExceptionRecord;
  E   : EAccessViolation;
  S   : string;
begin
  // Unter der Modulbasis kann die Adresse nicht zu diesem Modul gehoeren -
  // der Text muss das sagen, statt eine sinnlose Differenz zu rechnen.
  E := MakeExternal(Rec, $C0000005, Pointer(UIntPtr($1000)));
  try
    S := DescribeException(E);
  finally
    E.Free;
  end;
  Assert.IsTrue(Pos('DARUNTER', S) > 0,
                'Adresse unter der Modulbasis nicht als solche erkannt: ' + S);
  Assert.IsTrue(Pos('modulrelativ', S) = 0,
                'Sinnlose Differenz statt Hinweis: ' + S);
end;

procedure TTestCrashDiag.Describe_AddressAboveImage_SaysSo;
var
  Rec : TExceptionRecord;
  E   : EAccessViolation;
  S   : string;
begin
  // OBERHALB von Basis+Bildgroesse (ntdll, BPLs, Heap) gehoert die
  // Adresse ebenso wenig zu diesem Modul. Die erste Fassung pruefte nur
  // die Untergrenze und gab hier eine 'modulrelative' Differenz aus -
  // exakt die Fehlattribution, die die Unit der RTL vorwirft.
  // $40000000 liegt weit ueber jeder realen Bildgroesse dieses Moduls.
  E := MakeExternal(Rec, $C0000005,
         Pointer(UIntPtr(HInstance) + $40000000));
  try
    S := DescribeException(E);
  finally
    E.Free;
  end;
  Assert.IsTrue(Pos('DARUEBER', S) > 0,
                'Adresse oberhalb des Bildes nicht als solche erkannt: ' + S);
  Assert.IsTrue(Pos('modulrelativ', S) = 0,
                'Sinnlose Differenz statt Hinweis: ' + S);
end;

procedure TTestCrashDiag.Describe_Nil_DoesNotCrash;
begin
  // Fehlerpfad-Code darf nie selbst der Fehler sein.
  Assert.IsTrue(DescribeException(nil) <> '',
                'nil-Exception liefert leeren Text');
end;

// ---------------------------------------------------------------------------
// Diagnose-Stapel. Die reinen Funktionen (Pfad, Rahmenzeile) direkt; der
// Erfassungsweg einmal mit raise und einmal mit einer ECHTEN
// Zugriffsverletzung - genau der Fall der AV-Jagd. Beide Male wird der
// Haken nur fuer die Dauer des Tests eingehaengt.
// ---------------------------------------------------------------------------

var
  // Ziel der echten AV. Global statt Literal-nil, damit der Compiler den
  // Schreibzugriff nicht als sinnlos erkennt oder vorab bemaengelt.
  GNilTarget: PInteger = nil;

// Bewusst eigene, kleine Routinen: der Test prueft, dass eine erfasste
// Adresse in GENAU dieser Routine liegt. Ihre Groesse liegt weit unter
// RAISER_SPAN Byte.
const
  RAISER_SPAN = 512;

procedure RaiseListErrorHere;
begin
  raise EListError.Create('Diagnose-Stapel-Test');
end;

procedure WriteThroughNilHere;
begin
  GNilTarget^ := 42;
end;

function InRaiser(AAddr, ARaiser: Pointer): Boolean;
begin
  Result := (UIntPtr(AAddr) >= UIntPtr(ARaiser)) and
            (UIntPtr(AAddr) < UIntPtr(ARaiser) + RAISER_SPAN);
end;

function TempLog: string;
begin
  Result := TPath.Combine(TPath.GetTempPath,
              Format('sca_crashstack_test_%d.log', [GetCurrentProcessId]));
  if TFile.Exists(Result) then
    TFile.Delete(Result);
end;

procedure TTestCrashDiag.CrashStack_LogPath_OffValues_GiveEmpty;
const
  AUS: array[0..5] of string = ('', '   ', '0', 'off', 'FALSE', 'nein');
var
  V: string;
begin
  for V in AUS do
    Assert.AreEqual('', CrashStackLogPathFor(V, 'C:\x\sca.exe'),
                    'Wert "' + V + '" muss AUS bedeuten');
end;

procedure TTestCrashDiag.CrashStack_LogPath_OnValues_GiveFileNextToExe;
const
  AN: array[0..4] of string = ('1', 'on', 'TRUE', 'ja', ' 1 ');
var
  V: string;
begin
  for V in AN do
    Assert.AreEqual('C:\x\StaticCodeAnalyser.d12.crashstack.log',
                    CrashStackLogPathFor(V, 'C:\x\StaticCodeAnalyser.d12.exe'),
                    'Wert "' + V + '" muss die Datei neben der Exe nennen');
end;

procedure TTestCrashDiag.CrashStack_LogPath_OtherValue_IsThePath;
begin
  Assert.AreEqual('D:\stress\run7.crashstack.log',
                  CrashStackLogPathFor('D:\stress\run7.crashstack.log',
                                       'C:\x\sca.exe'));
end;

procedure TTestCrashDiag.CrashStack_FormatFrame_ModuleRelative;
var
  S: string;
begin
  // Genau die Form, die tools/map_resolve.py liest: 'Modul+$RVA'.
  S := FormatStackFrame('#03', $10ABCDE, 'StaticCodeAnalyser.d12.exe', $1000000);
  Assert.IsTrue(Pos('#03 $', S) > 0, 'Bezeichnung fehlt: ' + S);
  Assert.IsTrue(Pos('StaticCodeAnalyser.d12.exe+$ABCDE', S) > 0,
                'Modul+RVA fehlt oder falsch: ' + S);
  // Absolute Adresse in voller Zeigerbreite (ASLR-Basis steht im Kopf
  // der Datei - beides zusammen erlaubt die Gegenrechnung).
  Assert.IsTrue(Pos('$' + IntToHex(UInt64($10ABCDE), SizeOf(Pointer) * 2), S) > 0,
                'absolute Adresse fehlt oder nicht zeigerbreit: ' + S);
end;

procedure TTestCrashDiag.CrashStack_FormatFrame_UnknownModule;
var
  S: string;
begin
  S := FormatStackFrame('#00', $10, '', 0);
  Assert.IsTrue(Pos(' ?', S) > 0, 'ohne Modul muss "?" stehen: ' + S);
  Assert.IsTrue(Pos('+$', S) = 0, 'ohne Modul keine RVA: ' + S);
  // Adresse UNTER der Basis: sinnlose Differenz waere eine Fehlzuordnung.
  S := FormatStackFrame('#01', $10, 'x.dll', $1000);
  Assert.IsTrue(Pos('+$', S) = 0, 'Adresse unter der Basis ohne RVA: ' + S);
end;

procedure TTestCrashDiag.CrashStack_Raise_CapturesRaisingFrame;
var
  LogFile : string;
  Frames  : TArray<Pointer>;
  Hits    : Integer;
  P       : Pointer;
  Fault   : Pointer;
  Text    : string;
begin
  LogFile := TempLog;
  CrashStackInstall(LogFile);
  try
    Assert.IsTrue(CrashStackActive, 'Install hat nicht gewirkt');
    Hits := 0;
    Fault := nil;
    try
      RaiseListErrorHere;
    except
      on E: EListError do
      begin
        Frames := CrashStackFrames(E);
        Fault := CrashStackFault(E);
        for P in Frames do
          if InRaiser(P, @RaiseListErrorHere) then
            Inc(Hits);
        CrashStackReport('Detektor Test', 'unit1.pas', E);
      end;
    end;
    Assert.IsTrue(Length(Frames) > 0,
                  Format('kein Rahmen erfasst (Treffer in der raise-Routine: %d)',
                         [Hits]));
    // Beide Plattformen: die Ausloeseadresse eines raise ist die
    // Ruecksprungadresse hinter dem Aufruf von System._RaiseExcept - also
    // IN der raise-Routine.
    Assert.IsTrue(InRaiser(Fault, @RaiseListErrorHere),
                  'Ausloeseadresse liegt nicht in der raise-Routine');
    {$IFDEF CPUX64}
    // Nur Win64: der tabellengestuetzte Stapelgang sieht jeden Rahmen.
    // Win32 laeuft ueber die EBP-Kette; System._RaiseExcept (asm) legt
    // keinen Rahmen an, die Adresse IN der raise-Routine fehlt dort
    // daher bauartbedingt (der Aufrufer der Routine steht aber da).
    Assert.IsTrue(Hits > 0, 'die raise-Routine fehlt unter den Rahmen - der '
                  + 'Haken laeuft nicht auf dem Stapel des Ausloesers');
    {$ENDIF}
  finally
    CrashStackUninstall;
  end;
  Assert.IsFalse(CrashStackActive, 'Uninstall hat nicht gewirkt');
  Assert.IsTrue(TFile.Exists(LogFile), 'Diagnosedatei fehlt: ' + LogFile);
  Text := TFile.ReadAllText(LogFile, TEncoding.UTF8);
  TFile.Delete(LogFile);
  Assert.IsTrue(Pos('SCA_CRASH_STACK aktiv', Text) > 0, 'Kopf fehlt');
  Assert.IsTrue(Pos('Ort    : Detektor Test', Text) > 0, 'Ort fehlt');
  Assert.IsTrue(Pos('unit1.pas', Text) > 0, 'Datei fehlt');
  Assert.IsTrue(Pos('EListError', Text) > 0, 'Fehlertext fehlt');
  Assert.IsTrue(Pos('beim Ausloesen erfasst', Text) > 0,
                'Rahmen nicht aus dem Ausnahmeobjekt: ' + Text);
  Assert.IsTrue(Pos('+$', Text) > 0, 'keine Modul+RVA-Zeile: ' + Text);
end;

procedure TTestCrashDiag.CrashStack_AccessViolation_CapturesFaultAddress;
var
  LogFile : string;
  Fault   : Pointer;
  Count   : Integer;
begin
  // Der eigentliche Jagdfall: eine Hardware-Ausnahme. Hier erzeugt die
  // RTL das Objekt selbst (SysUtils.GetExceptionObject) - der Haken muss
  // auch dort greifen, und die Ausloeseadresse muss der fehlerhafte
  // Befehl IN der schreibenden Routine sein. Schreiben nach nil
  // beschaedigt nichts (Seite 0 ist nie gemappt); unter dem IDE-Debugger
  // meldet sich die AV wie jede andere Testausnahme - Fortsetzen genuegt.
  LogFile := TempLog;
  Fault := nil;
  Count := 0;
  CrashStackInstall(LogFile);
  try
    try
      WriteThroughNilHere;
    except
      on E: EAccessViolation do
      begin
        Fault := CrashStackFault(E);
        Count := Length(CrashStackFrames(E));
      end;
    end;
  finally
    CrashStackUninstall;
    if TFile.Exists(LogFile) then
      TFile.Delete(LogFile);
  end;
  Assert.IsTrue(Count > 0, 'kein Rahmen bei einer echten AV erfasst');
  Assert.IsTrue(InRaiser(Fault, @WriteThroughNilHere),
                'Ausloeseadresse liegt nicht in der schreibenden Routine');
end;

procedure TTestCrashDiag.CrashStack_Inactive_ReportIsNoOp;
begin
  // Ausgeschaltet darf der Fangpunkt-Aufruf nichts tun und nie werfen -
  // er steht in JEDEM Detektor-Fehlerpfad jedes normalen Scans.
  Assert.IsFalse(CrashStackActive, 'Vorbedingung: Diagnose-Stapel aus');
  try
    raise EListError.Create('aus');
  except
    on E: EListError do
    begin
      Assert.IsTrue(Length(CrashStackFrames(E)) = 0,
                    'ohne Haken darf kein Block am Objekt haengen');
      CrashStackReport('Detektor Test', '', E);
    end;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TTestCrashDiag);

end.
