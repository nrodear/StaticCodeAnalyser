unit uTestCrashDiag;

// Tests fuer uCrashDiag. Der Punkt der Unit ist, dass eine abgefangene
// Zugriffsverletzung SPAETER noch auswertbar ist - also wird genau das
// geprueft: Exception-Klasse, NT-Statuscode und die modulRELATIVE Adresse.
//
// Der Hardware-Fall braucht keinen echten Absturz: EAccessViolation ist ein
// EExternal, und dessen ExceptionRecord laesst sich fuer den Test mit einem
// kuenstlichen Satz Werte belegen. Damit ist die Adressarithmetik pruefbar,
// ohne den Prozess zu beschaedigen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestCrashDiag = class
  public
    [Test] procedure Describe_Plain_NamesClassAndMessage;
    [Test] procedure Describe_Plain_ReportsModuleBase;
    [Test] procedure Describe_External_ReportsNtStatus;
    [Test] procedure Describe_External_ReportsModuleRelativeAddress;
    [Test] procedure Describe_AddressBelowBase_SaysSo;
    [Test] procedure Describe_AddressAboveImage_SaysSo;
    [Test] procedure Describe_Nil_DoesNotCrash;
  end;

implementation

uses
  System.SysUtils,
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

procedure TTestCrashDiag.Describe_Plain_ReportsModuleBase;
var S: string;
begin
  // Innerhalb eines except-Blocks liefert ExceptAddr eine Adresse, also
  // muss die Modulbasis mitkommen - ohne sie ist die Adresse wertlos.
  try
    raise EListError.Create('egal');
  except
    on E: EListError do
      S := DescribeException(E);
  end;
  Assert.IsTrue(Pos('Modulbasis', S) > 0,
                'Modulbasis fehlt - Adresse waere nicht aufloesbar: ' + S);
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

initialization
  TDUnitX.RegisterTestFixture(TTestCrashDiag);

end.
