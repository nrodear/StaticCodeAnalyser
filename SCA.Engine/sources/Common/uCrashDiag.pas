unit uCrashDiag;

// Auswertbarer Diagnosetext fuer abgefangene Exceptions.
//
// ANLASS (2026-08-04): im Voll-Korpus-Lauf riss genau eine Datei mit einer
// Zugriffsverletzung ab. Die festgehaltene Meldung war NICHT auswertbar:
//
//   'Zugriffsverletzung bei Adresse 0000000000D15F7A in Modul
//    'StaticCodeAnalyser.d12.exe'. Schreiben von Adresse 0000000000DD613C'
//
// Beide Schwaechen sitzen in der RTL (System.SysUtils, CreateAVObject):
//
//  1. Die Adresse ist ABSOLUT. Das Image wird per ASLR bei jedem Start
//     woanders geladen - im PE-Header steht $400000, gemessen wurde
//     $840000. Ohne die Basisadresse GENAU DIESES Laufs laesst sich die
//     Adresse gegen keine Map-Datei aufloesen. Sie ist wertlos.
//
//  2. Der Modulname ist unzuverlaessig. Die RTL nimmt
//     VirtualQuery(Adresse).AllocationBase als Modul-Handle; fuer
//     MEM_FREE-Regionen ist AllocationBase NULL, und
//     GetModuleFileName(NULL) liefert den Namen der EIGENEN Exe. Eine
//     Adresse, die in GAR KEINEM Modul liegt, wird dadurch faelschlich uns
//     zugeschrieben - man jagt einen Fehler im eigenen Code, den es dort
//     nicht gibt.
//
// Describe() haengt deshalb an:
//   * die Exception-KLASSE (die RTL-Message nennt sie nicht),
//   * bei EXTERNEN Exceptions die modulRELATIVE Adresse, gegen eine
//     Detailed-Map aufloesbar. Zwei Einschraenkungen, beide aus
//     Abnahmen gelernt: die absolute Modulbasis steht seit I3
//     (2026-09-20) nicht mehr im Text (ASLR - derselbe Fehler war in
//     zwei Laeufen zwei verschiedene FUNDE), und seit O1 (2026-09-21)
//     entfaellt die Adresse bei GEWORFENEN Exceptions ganz: sie ist
//     zwar je Build konstant, wandert aber mit jedem Neubau, und der
//     Text bildet als SCA006-Meldung die Identitaet eines Fundes.
//     Begruendung an ModuleRelative und in DescribeException,
//   * bei Hardware-Exceptions den NT-Statuscode. Der unterscheidet die
//     Ursachen, die dieselbe Meldung erzeugen koennen - vor allem
//     $C0000005 (echte Zugriffsverletzung) von $C00000FD (Stapel
//     erschoepft, z.B. zu tiefe Parser-Rekursion).
//
// Bewusst KEIN Stack-Trace IM MELDETEXT: der Text bildet die Identitaet
// eines SCA006-Fundes, eine Adressliste darin machte jeden Lauf zu neuen
// Funden. Modulrelative Adresse + Map-Datei leisten das fuer den einen
// Frame, der bei einem echten Absturz zaehlt.
//
// NACHTRAG 2026-10-25 - Diagnose-Stapel (SCA_CRASH_STACK): einer von 22
// Realworld-Volllaeufen (Win64 Release, seriell) lieferte zwei
// SCA006-Lesefehler mit EAccessViolation TIEF IN DER SPEICHERVERWALTUNG
// (DynArraySetLength mit newP=nil, TStringBuilder.Create mit VMT=0) -
// Opfer einer frueheren Heap-Korruption. Der eine Frame nennt dort nur
// den Ort, an dem das Opfer starb, nicht den Weg dorthin. Fuer solche
// Jagden gibt es den abschaltbaren Diagnose-Stapel (Abschnitt unten,
// CrashStackInstall): die Rahmen gehen in eine EIGENE Datei, nie in den
// Meldetext. Ohne die Umgebungsvariable ist er aus und kostet nichts.

interface

uses
  System.SysUtils;

type
  /// <summary>
  ///   Stapel erschoepft. Alias auf die RTL-Klasse, damit der
  ///   deprecated-Marker an EINER Stelle steht statt an jedem der 13
  ///   Fangpunkte, die einen Stack-Overflow nicht verschlucken duerfen.
  /// </summary>
  /// <remarks>
  ///   Delphi 12 markiert EStackOverflow als deprecated - vermutlich weil
  ///   ein erschoepfter Stapel nicht zuverlaessig behandelbar ist (Windows
  ///   stellt die Guard-Page nicht wieder her, und die RTL hat kein
  ///   Gegenstueck zu _resetstkoflw). GEWORFEN wird die Klasse aber
  ///   weiterhin: System.Internal.ExcUtils bildet ExceptMap[14]
  ///   (reStackOverflow) auf etStackOverflow ab, und System.pas setzt
  ///   STATUS_STACK_OVERFLOW ($C00000FD) auf genau diesen Code. Ein
  ///   Ausweichen auf eine andere Klasse waere heute also schlicht falsch.
  ///
  ///   Sollte die RTL die Klasse eines Tages entfernen, ist der Ersatz eine
  ///   Pruefung von EExternal.ExceptionRecord^.ExceptionCode gegen
  ///   $C00000FD - die Bausteine dafuer stehen in dieser Unit.
  /// </remarks>
  {$WARN SYMBOL_DEPRECATED OFF}
  EStackExhausted = EStackOverflow;
  {$WARN SYMBOL_DEPRECATED ON}

/// <summary>
///   Exception-Klasse und Meldung, bei EXTERNEN Exceptions zusaetzlich
///   NT-Statuscode und - soweit ermittelbar - die modulrelative
///   Fehleradresse. Eine im Code geworfene Exception bekommt KEINE
///   Adresse: sie wandert bei jedem Bau, und dieser Text bildet die
///   Identitaet eines SCA006-Fundes (s. Rumpf).
///   Nie leer, nie werfend: diese Funktion laeuft in Fehlerpfaden und
///   darf den Fehler nicht ersetzen.
/// </summary>
function DescribeException(E: Exception): string;

// ---------------------------------------------------------------------------
// Diagnose-Stapel (SCA_CRASH_STACK, 2026-10-25)
// ---------------------------------------------------------------------------
// Eingeschaltet nur, wenn die Standalone-Exe beim Start
// CrashStackInstallFromEnv ruft UND die Umgebungsvariable gesetzt ist
// (1 = Datei <Exe ohne Endung>.crashstack.log neben der Exe, sonst ein
// Dateipfad). Dann haengen zwei Haken:
//
//  * Exception.GetExceptionStackInfoProc (System.SysUtils). Die RTL ruft
//    ihn in Exception.RaisingException: bei einem raise VOR dem
//    eigentlichen Ausloesen, bei einer Hardware-Ausnahme (AV) beim
//    Erzeugen des Exception-Objekts - in beiden Faellen noch auf dem
//    Stapel des Fehlers. Der Haken haelt bis zu 62 Ruecksprungadressen
//    fest (RtlCaptureStackBackTrace; auf Win64 tabellengestuetzt und
//    damit auch durch den Ausnahme-Dispatcher hindurch vollstaendig).
//    Speicher kommt vom Prozess-Heap des Betriebssystems, NICHT vom
//    Delphi-Speichermanager - genau der kann im Jagdfall kaputt sein.
//  * ein Vectored Exception Handler als Rueckfall. Fuer EHeapException
//    (EOutOfMemory, EInvalidPointer - z.B. ein von FastMM-FullDebugMode
//    erkannter Blockschaden) ruft die RTL den Haken absichtlich NICHT
//    (EHeapException.RaisingException); der VEH merkt sich die Rahmen
//    der LETZTEN Ausnahme je Thread.
//
// CrashStackReport schreibt an den Fangpunkten (Detektor, Parser,
// Top-Level der CLI) Ort, Datei, DescribeException und die Rahmen als
// 'Modul+$RVA' in die Diagnosedatei. tools/map_resolve.py loest sie gegen
// die Detailed-Map (DCC_MapFile=3) zu Unit/Routine/Zeile auf.
//
// Grenzen: Win32 laeuft der Stapelgang ueber die EBP-Kette - ohne
// Stack-Frames (Release) bricht er frueh ab; massgeblich ist Win64. Bei
// erschoepftem Stapel ($C00000FD) wird nichts erfasst - der Unwinder
// braucht selbst Stapel, ein Doppelfehler beendete den Prozess.

const
  /// Umgebungsvariable, die den Diagnose-Stapel einschaltet.
  CRASH_STACK_ENV = 'SCA_CRASH_STACK';

/// <summary>
///   Pfad der Diagnosedatei zu einem Wert von SCA_CRASH_STACK. Leer, '0',
///   'off', 'false', 'nein' -> '' (aus). '1', 'on', 'true', 'ja' ->
///   AExeName mit Endung '.crashstack.log'. Jeder andere Wert ist selbst
///   der Dateipfad (unveraendert, nicht expandiert). Rein, ohne Seiteneffekt.
/// </summary>
function CrashStackLogPathFor(const AEnvValue, AExeName: string): string;

/// <summary>
///   Eine Rahmenzeile: '  ' + ALabel + ' $' + absolute Adresse (volle
///   Zeigerbreite) + ' ' + AModule + '+$' + RVA. Ohne Modul (AModule leer
///   oder Adresse unter AModuleBase) steht ' ?' statt Modul+RVA. Rein.
/// </summary>
function FormatStackFrame(const ALabel: string; AAddr: UIntPtr;
  const AModule: string; AModuleBase: UIntPtr): string;

/// <summary>
///   Haengt die Haken ein und schreibt den Kopf (Exe, Modulbasis,
///   Bildgroesse) in ALogFile. Zweiter Aufruf ohne Uninstall: wirkungslos.
///   Nur beim Start aufrufen - nicht threadsicher gegen laufende Scans.
/// </summary>
procedure CrashStackInstall(const ALogFile: string);

/// <summary>
///   Liest SCA_CRASH_STACK und ruft bei gesetztem Wert CrashStackInstall.
///   Ergebnis: der (expandierte) Pfad der Diagnosedatei, '' wenn aus.
/// </summary>
function CrashStackInstallFromEnv: string;

/// <summary>
///   Haengt den Erfassungs-Haken und den VEH wieder aus. Text- und
///   Aufraeum-Haken bleiben: Exception-Objekte aus der aktiven Zeit
///   tragen noch einen Block dieser Unit und muessen ihn freigeben koennen.
/// </summary>
procedure CrashStackUninstall;

function CrashStackActive: Boolean;

/// <summary>
///   Die beim Ausloesen von E erfassten Ruecksprungadressen; leer, wenn E
///   keinen Block dieser Unit traegt (Diagnose aus, EHeapException, nil).
/// </summary>
function CrashStackFrames(E: Exception): TArray<Pointer>;

/// <summary>
///   Ausloeseadresse aus dem Block von E (ExceptionAddress des Satzes:
///   bei einer AV der fehlerhafte Befehl, bei raise die raise-Stelle);
///   nil ohne Block.
/// </summary>
function CrashStackFault(E: Exception): Pointer;

/// <summary>
///   Schreibt Ort, Datei, DescribeException(E) und die Rahmen in die
///   Diagnosedatei. Ohne aktiven Diagnose-Stapel sofort zurueck. Nie
///   werfend, threadsicher. Im except-Block aufrufen (ExceptAddr).
/// </summary>
procedure CrashStackReport(const AWhere, AFileName: string; E: Exception);

implementation

uses
  // PImageDosHeader/PImageNtHeaders + Signaturen (OwnImageSize). Die
  // Unit ist ohnehin Windows-gebunden (ExceptionRecord ist 'platform').
  Winapi.Windows;

// Groesse des eigenen Moduls aus dem eigenen PE-Header. Kein API-Call,
// keine Allokation - nur zwei Lesezugriffe auf garantiert gemappte
// Seiten des eigenen Images; im Crash-Kontext genau richtig.
function OwnImageSize: UIntPtr;
var
  Dos : PImageDosHeader;
  Nt  : PImageNtHeaders;
begin
  Dos := PImageDosHeader(HInstance);
  if Dos^.e_magic <> IMAGE_DOS_SIGNATURE then Exit(0);
  Nt := PImageNtHeaders(UIntPtr(HInstance) + UIntPtr(Dos^._lfanew));
  if Nt^.Signature <> IMAGE_NT_SIGNATURE then Exit(0);
  Result := Nt^.OptionalHeader.SizeOfImage;
end;

function AddressInfo(AAddr: Pointer): string;
var
  Base : UIntPtr;
  Addr : UIntPtr;
  Size : UIntPtr;
begin
  Result := '';
  if not Assigned(AAddr) then Exit;
  Base := UIntPtr(HInstance);
  Addr := UIntPtr(AAddr);
  Size := OwnImageSize;
  // Ausserhalb von [Base, Base+SizeOfImage) kann die Adresse nicht zu
  // DIESEM Modul gehoeren. Die erste Fassung pruefte nur die
  // UNTERGRENZE - eine Adresse in ntdll oder einer BPL (laedt oberhalb)
  // wurde als 'modulrelativ' ZUM EIGENEN MODUL ausgegeben: exakt die
  // Fehlattribution, die diese Unit der RTL vorwirft. Basis trotzdem
  // nennen - der Leser sieht sofort, dass eine RTL-Modulangabe nicht
  // stimmen kann.
  // I3 (2026-09-20): Die Modulbasis steht NICHT MEHR im Text. Sie ist
  // die einzige laufabhaengige Zahl hier (ASLR laedt das Modul bei
  // jedem Start woandershin), und dieser Text wird zum MELDETEXT eines
  // Fundes: SCA006 traegt ihn eins zu eins. Zahlen im Meldetext sind
  // Teil der Fund-Identitaet - mit der Basis darin war derselbe Fehler
  // in zwei Laeufen zwei verschiedene Funde. Beleg: die G-Abnahme
  // (20.09.) zeigte drei SCA006-Funde als Drop+Add-Paar, allein weil
  // '$370000' zu '$960000' geworden war; Baselines und Byte-A/B
  // konnten diese Funde nie halten.
  //
  // Der DIAGNOSTISCHE Wert bleibt: aufloesbar gegen eine Detailed-Map
  // ist ohnehin nur die modulRELATIVE Adresse, und die steht weiter da
  // (ebenso die Bildgroesse - auch sie ist je Build konstant).
  // NACHTRAG O1 (2026-09-21): "je Build konstant" hat sich als zu
  // schwach erwiesen - ueber zwei Builds wandert auch sie, und die
  // N-Abnahme zeigte dadurch 2 Drops + 2 Adds je Lazarus-Lauf. Diese
  // Funktion ist unveraendert, aber ihr Aufrufer ruft sie nur noch
  // fuer EExternal; bei geworfenen Exceptions gibt es gar keine
  // Adresse mehr im Text. Fuer die
  // beiden Ausserhalb-Faelle gibt es keine deterministische Zahl: die
  // Adresse gehoert dann einem FREMDEN Modul, dessen Lage ebenfalls
  // ASLR bestimmt. Dort zaehlt die Aussage, nicht der Zahlenwert.
  if Addr < Base then
    Result := ' [Adresse liegt DARUNTER (unter der Modulbasis) - nicht dieses Modul]'
  else if (Size > 0) and (Addr >= Base + Size) then
    Result := Format(' [Bildgroesse $%x, Adresse liegt DARUEBER - nicht dieses Modul]',
                     [Size])
  else
    Result := Format(' [modulrelativ $%x]', [Addr - Base]);
end;

// EExternal.ExceptionRecord ist als 'platform' markiert (Windows-only).
// Der Bestand klammert solche Zugriffe mit dem WARN-Schalter - hier
// genauso, statt die Warnung projektweit abzuschalten.
function StatusInfo(E: Exception): string;
begin
  Result := '';
  if not (E is EExternal) then Exit;
  {$WARN SYMBOL_PLATFORM OFF}
  if not Assigned(EExternal(E).ExceptionRecord) then Exit;
  Result := Format(' [NT-Status $%.8x]',
                   [EExternal(E).ExceptionRecord^.ExceptionCode]);
  {$WARN SYMBOL_PLATFORM ON}
end;

function FaultAddress(E: Exception): Pointer;
begin
  // Bei Hardware-Exceptions ist die Adresse im ExceptionRecord die des
  // fehlerhaften Befehls - genau die, die auch in der RTL-Message steht.
  // Sonst die Ausloeseadresse des laufenden Handlers; ausserhalb eines
  // except-Blocks liefert ExceptAddr nil, was AddressInfo abfaengt.
  {$WARN SYMBOL_PLATFORM OFF}
  if (E is EExternal) and Assigned(EExternal(E).ExceptionRecord) then
    Result := EExternal(E).ExceptionRecord^.ExceptionAddress
  else
    Result := ExceptAddr;
  {$WARN SYMBOL_PLATFORM ON}
end;

function DescribeException(E: Exception): string;
begin
  if not Assigned(E) then
    Exit('Unbekannter Fehler (keine Exception-Instanz)');
  // Bewusst ein nacktes except ohne Filter: ein Fehler BEIM Beschreiben des
  // Fehlers darf den Fehlerpfad nicht sprengen, und die neue Exception
  // interessiert hier nicht - nur dass die urspruengliche Meldung
  // durchkommt. Genau der Fall, fuer den ein pauschaler Fang richtig ist.
  try
    // O1 (2026-09-21): Adresse NUR bei EExternal - dieselbe Grenze,
    // die StatusInfo schon zieht.
    //
    // I3 hat die ASLR-Basis aus dem Text genommen und die
    // modulRELATIVE Adresse mit der Begruendung "je Build konstant"
    // stehen lassen. Genau da liegt der Rest: je Build konstant ist
    // eben NICHT ueber Builds stabil. Der Text ist der MELDETEXT
    // eines Fundes (SCA006) und bildet dessen Identitaet - mit einer
    // Zahl darin, die jeder Neubau verschiebt, gilt derselbe Befund
    // nach jedem Bau als neu. GEMESSEN an der N-Abnahme (21.09.):
    // beide Lazarus-Laeufe trugen 2 Drops + 2 Adds, Datei und Zeile
    // identisch, allein weil $514152 zu $514202 geworden war.
    //
    // Warum die Unterscheidung nach EExternal die richtige ist:
    // bei einem Absturz (AV, Stack Overflow) ist die Adresse das
    // EINZIGE, was die Stelle eingrenzt - dort bleibt sie. Bei einer
    // im Code GEWORFENEN Exception nennt die Meldung die Ursache
    // bereits ("Parser-Watchdog: ueber 200000 Token-Aufrufe"), und
    // ExceptAddr zeigt nur auf die raise-Zeile. Am Korpus gemessen
    // stammt JEDER Fund mit Adresse aus genau diesem Fall - kein
    // einziger echter Absturz.
    if E is EExternal then
      Result := Format('%s: %s%s%s',
                       [E.ClassName, E.Message,
                        StatusInfo(E), AddressInfo(FaultAddress(E))])
    else
      Result := Format('%s: %s', [E.ClassName, E.Message]);
  except
    Result := E.ClassName + ': ' + E.Message;
  end;
end;

// ===========================================================================
// Diagnose-Stapel (SCA_CRASH_STACK) - Begruendung im Interface-Abschnitt
// ===========================================================================

const
  CS_MAGIC          = Cardinal($53434153);   // 'SCAS' - Block dieser Unit
  CS_MAX_FRAMES     = 62;                    // Win7+: Skip+Capture beliebig
  CS_STACK_OVERFLOW = Cardinal($C00000FD);   // STATUS_STACK_OVERFLOW
  CS_DELPHI_RAISE   = Cardinal($0EEDFADE);   // System.cDelphiException
  CS_SEVERITY_ERROR = Cardinal($C0000000);   // NT-Status, Schwere 'Fehler'
  // GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS / _UNCHANGED_REFCOUNT
  CS_MODULE_FROM_ADDRESS   = $00000004;
  CS_MODULE_UNCHANGED_REF  = $00000002;
  CS_FILE_APPEND_DATA      = $00000004;
  CS_EXCEPTION_CONTINUE_SEARCH = 0;
  {$IFDEF CPUX64}
  CS_PLATFORM = 'Win64';
  {$ELSE}
  CS_PLATFORM = 'Win32';
  {$ENDIF}

type
  PCrashStackInfo = ^TCrashStackInfo;
  TCrashStackInfo = record
    Magic  : Cardinal;
    Code   : Cardinal;   // ExceptionCode des Satzes ($0EEDFADE = raise)
    Fault  : Pointer;    // ExceptionAddress des Satzes
    Count  : Integer;
    Frames : array[0..CS_MAX_FRAMES - 1] of Pointer;
  end;

  // Eigene Fassung statt System/Winapi.Windows.TExceptionPointers: beide
  // Units deklarieren den Namen, mit verschiedenen Satztypen dahinter.
  PCsExceptionPointers = ^TCsExceptionPointers;
  TCsExceptionPointers = record
    ExceptionRecord : System.PExceptionRecord;
    ContextRecord   : Pointer;
  end;

  TCsVectoredHandler = function(AInfo: PCsExceptionPointers): Integer; stdcall;

// Keine dieser vier steht in Winapi.Windows (D12 nachgesehen); kaeme eine
// dazu, verdeckt die eigene Deklaration sie hier ohne Konflikt.
function RtlCaptureStackBackTrace(FramesToSkip, FramesToCapture: DWORD;
  BackTrace: Pointer; BackTraceHash: PDWORD): Word; stdcall;
  external kernel32 name 'RtlCaptureStackBackTrace';
function GetModuleHandleExW(dwFlags: DWORD; lpModuleName: Pointer;
  var phModule: HMODULE): BOOL; stdcall;
  external kernel32 name 'GetModuleHandleExW';
function AddVectoredExceptionHandler(First: ULONG;
  Handler: TCsVectoredHandler): Pointer; stdcall;
  external kernel32 name 'AddVectoredExceptionHandler';
function RemoveVectoredExceptionHandler(Handle: Pointer): ULONG; stdcall;
  external kernel32 name 'RemoveVectoredExceptionHandler';

var
  GCsInstalled     : Boolean = False;
  GCsHooked        : Boolean = False;   // Text-/Aufraeum-Haken (bleiben)
  GCsLogFile       : string  = '';
  GCsVeh           : Pointer = nil;
  GCsWriteFailures : Integer = 0;       // nur fuer den Debugger
  GCsLock          : TRTLCriticalSection;
  GCsPrevGetInfo   : function (P: System.PExceptionRecord): Pointer = nil;
  GCsPrevGetString : function (Info: Pointer): string = nil;
  GCsPrevCleanUp   : procedure (Info: Pointer) = nil;

threadvar
  // Rueckfall des VEH: Rahmen der letzten Ausnahme DIESES Threads.
  GCsLastRaise: TCrashStackInfo;

function CrashStackLogPathFor(const AEnvValue, AExeName: string): string;
var
  V : string;
begin
  V := Trim(AEnvValue);
  if (V = '') or (V = '0') or SameText(V, 'off') or SameText(V, 'false')
     or SameText(V, 'nein') then
    Exit('');
  if (V = '1') or SameText(V, 'on') or SameText(V, 'true')
     or SameText(V, 'ja') then
    Exit(ChangeFileExt(AExeName, '.crashstack.log'));
  Result := V;
end;

function FormatStackFrame(const ALabel: string; AAddr: UIntPtr;
  const AModule: string; AModuleBase: UIntPtr): string;
begin
  Result := '  ' + ALabel + ' $' + IntToHex(UInt64(AAddr), SizeOf(Pointer) * 2);
  if (AModule <> '') and (AAddr >= AModuleBase) then
    Result := Result + ' ' + AModule + '+$' + IntToHex(UInt64(AAddr - AModuleBase), 1)
  else
    Result := Result + ' ?';
end;

function IsOwnInfo(AInfo: Pointer): Boolean;
begin
  // Ein fremder Block (anderer Anbieter vor uns) ist mindestens 4 Byte
  // gross - das Lesen der Marke ist also in jedem Fall zulaessig.
  Result := Assigned(AInfo) and (PCrashStackInfo(AInfo)^.Magic = CS_MAGIC);
end;

// Rahmen 0 waere diese Routine selbst - uebersprungen. Kein Delphi-Heap,
// keine Strings: laeuft mitten im Ausnahme-Dispatch.
procedure CaptureInto(var AInfo: TCrashStackInfo; P: System.PExceptionRecord);
begin
  AInfo.Magic := CS_MAGIC;
  if Assigned(P) then
  begin
    AInfo.Code  := P^.ExceptionCode;
    AInfo.Fault := P^.ExceptionAddress;
  end
  else
  begin
    AInfo.Code  := 0;
    AInfo.Fault := nil;
  end;
  AInfo.Count := RtlCaptureStackBackTrace(1, CS_MAX_FRAMES, @AInfo.Frames[0], nil);
end;

function CsGetStackInfo(P: System.PExceptionRecord): Pointer;
var
  Info : PCrashStackInfo;
begin
  Result := nil;
  if Assigned(P) and (P^.ExceptionCode = CS_STACK_OVERFLOW) then Exit;
  Info := HeapAlloc(GetProcessHeap, 0, SizeOf(TCrashStackInfo));
  if Info = nil then Exit;
  CaptureInto(Info^, P);
  Result := Info;
end;

procedure CsCleanUpStackInfo(Info: Pointer);
begin
  if Info = nil then Exit;
  if IsOwnInfo(Info) then
  begin
    PCrashStackInfo(Info)^.Magic := 0;
    HeapFree(GetProcessHeap, 0, Info);
  end
  else if Assigned(GCsPrevCleanUp) then
    GCsPrevCleanUp(Info);
end;

function ModuleOf(AAddr: Pointer; out ABase: UIntPtr): string;
var
  H   : HMODULE;
  Buf : array[0..MAX_PATH] of Char;
  N   : DWORD;
begin
  Result := '';
  ABase := 0;
  if AAddr = nil then Exit;
  H := 0;
  if not GetModuleHandleExW(CS_MODULE_FROM_ADDRESS or CS_MODULE_UNCHANGED_REF,
                            AAddr, H) then
    Exit;
  N := GetModuleFileName(H, @Buf[0], Length(Buf));
  if N = 0 then Exit;
  SetString(Result, PChar(@Buf[0]), N);
  Result := ExtractFileName(Result);
  ABase := UIntPtr(H);
end;

function FrameLine(const ALabel: string; AAddr: Pointer): string;
var
  Base : UIntPtr;
  Name : string;
begin
  Name := ModuleOf(AAddr, Base);
  Result := FormatStackFrame(ALabel, UIntPtr(AAddr), Name, Base);
end;

function FramesText(const AInfo: TCrashStackInfo; const ASource: string): string;
var
  i, N : Integer;
  SB   : TStringBuilder;
begin
  N := AInfo.Count;
  if N > CS_MAX_FRAMES then N := CS_MAX_FRAMES;
  if N < 0 then N := 0;
  SB := TStringBuilder.Create;
  try
    SB.Append(FrameLine('Ausloeser', AInfo.Fault))
      .Append(Format(' (Code $%.8x)', [AInfo.Code])).Append(sLineBreak)
      .Append(Format('Stapel (%s, %d Rahmen):', [ASource, N])).Append(sLineBreak);
    for i := 0 to N - 1 do
      SB.Append(FrameLine(Format('#%.2d', [i]), AInfo.Frames[i])).Append(sLineBreak);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function CsGetStackInfoString(Info: Pointer): string;
begin
  if IsOwnInfo(Info) then
    Result := FramesText(PCrashStackInfo(Info)^, 'beim Ausloesen erfasst')
  else if Assigned(GCsPrevGetString) then
    Result := GCsPrevGetString(Info)
  else
    Result := '';
end;

function CsVectoredHandler(AInfo: PCsExceptionPointers): Integer; stdcall;
var
  Code : Cardinal;
  Slot : PCrashStackInfo;
begin
  Result := CS_EXCEPTION_CONTINUE_SEARCH;
  if (AInfo = nil) or (AInfo^.ExceptionRecord = nil) then Exit;
  Code := AInfo^.ExceptionRecord^.ExceptionCode;
  // Delphi-raise und NT-Fehler (AV & Co.); Stapel-Ueberlauf nie (s. o.),
  // Informations-Codes (OutputDebugString, Threadnamen) nie.
  if (Code = CS_DELPHI_RAISE) or
     (((Code and CS_SEVERITY_ERROR) = CS_SEVERITY_ERROR) and
      (Code <> CS_STACK_OVERFLOW)) then
  begin
    // Ueber die Adresse statt als var-Parameter: @threadvar liefert die
    // Instanz des laufenden Threads.
    Slot := @GCsLastRaise;
    CaptureInto(Slot^, AInfo^.ExceptionRecord);
  end;
end;

procedure CsAppend(const AText: string);
var
  H       : THandle;
  Bytes   : TBytes;
  Written : DWORD;
begin
  if GCsLogFile = '' then Exit;
  Bytes := TEncoding.UTF8.GetBytes(AText);
  EnterCriticalSection(GCsLock);
  try
    // Je Eintrag oeffnen und schliessen: stirbt der Prozess danach hart,
    // steht der Eintrag schon auf der Platte.
    H := CreateFile(PChar(GCsLogFile), CS_FILE_APPEND_DATA,
                    FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_ALWAYS,
                    FILE_ATTRIBUTE_NORMAL, 0);
    if H = INVALID_HANDLE_VALUE then
    begin
      AtomicIncrement(GCsWriteFailures);
      Exit;
    end;
    try
      if (Length(Bytes) > 0) and
         not WriteFile(H, Bytes[0], Length(Bytes), Written, nil) then
        AtomicIncrement(GCsWriteFailures);
    finally
      CloseHandle(H);
    end;
  finally
    LeaveCriticalSection(GCsLock);
  end;
end;

function Stamp: string;
begin
  // Invariant: ':' ist in FormatDateTime der LANDES-Zeittrenner; die
  // Diagnosedatei soll ueberall gleich aussehen (av_stress.py liest sie).
  Result := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now, TFormatSettings.Invariant);
end;

procedure CrashStackInstall(const ALogFile: string);
var
  Base : UIntPtr;
  Name : string;
begin
  if GCsInstalled then Exit;
  GCsLogFile := ALogFile;
  // Aufraeumen und Text ZUERST und nur einmal: ab dem Moment, in dem der
  // Erfassungs-Haken haengt, muss jeder Block auch freigegeben werden.
  if not GCsHooked then
  begin
    GCsPrevCleanUp   := Exception.CleanUpStackInfoProc;
    GCsPrevGetString := Exception.GetStackInfoStringProc;
    Exception.CleanUpStackInfoProc   := CsCleanUpStackInfo;
    Exception.GetStackInfoStringProc := CsGetStackInfoString;
    GCsHooked := True;
  end;
  GCsPrevGetInfo := Exception.GetExceptionStackInfoProc;
  Exception.GetExceptionStackInfoProc := CsGetStackInfo;
  GCsVeh := AddVectoredExceptionHandler(0, CsVectoredHandler);
  GCsInstalled := True;
  Name := ModuleOf(Pointer(HInstance), Base);
  CsAppend(Format('=== SCA_CRASH_STACK aktiv %s PID %d ===', [Stamp, GetCurrentProcessId])
           + sLineBreak
           + 'Exe    : ' + ParamStr(0) + sLineBreak
           + Format('Modul  : %s Basis $%s Bildgroesse $%x (%s)',
                    [Name, IntToHex(UInt64(Base), SizeOf(Pointer) * 2),
                     UInt64(OwnImageSize), CS_PLATFORM]) + sLineBreak
           + 'Aufloesen: python -I tools\map_resolve.py <Exe-Pfad ohne Endung>.map --log <diese Datei>'
           + sLineBreak + sLineBreak);
end;

function CrashStackInstallFromEnv: string;
begin
  // Qualifiziert: Winapi.Windows.GetEnvironmentVariable (API-Fassung)
  // verdeckt in diesem Implementationsteil die SysUtils-Funktion.
  Result := CrashStackLogPathFor(
              System.SysUtils.GetEnvironmentVariable(CRASH_STACK_ENV),
              ParamStr(0));
  if Result = '' then Exit;
  Result := ExpandFileName(Result);
  CrashStackInstall(Result);
end;

procedure CrashStackUninstall;
begin
  if not GCsInstalled then Exit;
  GCsInstalled := False;
  if GCsVeh <> nil then
  begin
    RemoveVectoredExceptionHandler(GCsVeh);
    GCsVeh := nil;
  end;
  Exception.GetExceptionStackInfoProc := GCsPrevGetInfo;
  GCsPrevGetInfo := nil;
  GCsLogFile := '';
end;

function CrashStackActive: Boolean;
begin
  Result := GCsInstalled;
end;

function CrashStackFrames(E: Exception): TArray<Pointer>;
var
  Info : PCrashStackInfo;
  i, N : Integer;
begin
  Result := nil;
  if not Assigned(E) or not IsOwnInfo(E.StackInfo) then Exit;
  Info := PCrashStackInfo(E.StackInfo);
  N := Info^.Count;
  if N > CS_MAX_FRAMES then N := CS_MAX_FRAMES;
  if N <= 0 then Exit;
  SetLength(Result, N);
  for i := 0 to N - 1 do
    Result[i] := Info^.Frames[i];
end;

function CrashStackFault(E: Exception): Pointer;
begin
  Result := nil;
  if Assigned(E) and IsOwnInfo(E.StackInfo) then
    Result := PCrashStackInfo(E.StackInfo)^.Fault;
end;

procedure CrashStackReport(const AWhere, AFileName: string; E: Exception);
var
  S     : string;
  Local : TCrashStackInfo;
begin
  if not GCsInstalled then Exit;
  // Fehlerpfad: ein Fehler BEIM Protokollieren darf den urspruenglichen
  // nicht ersetzen (gleiche Begruendung wie in DescribeException).
  try
    S := Format('=== %s Thread %d ===', [Stamp, GetCurrentThreadId]) + sLineBreak
         + 'Ort    : ' + AWhere + sLineBreak
         + 'Datei  : ' + AFileName + sLineBreak
         + 'Fehler : ' + DescribeException(E) + sLineBreak;
    if Assigned(E) and IsOwnInfo(E.StackInfo) then
      S := S + FramesText(PCrashStackInfo(E.StackInfo)^, 'beim Ausloesen erfasst')
    else
    begin
      // Kopie zuerst: jede weitere Ausnahme dieses Threads (auch eine
      // intern abgefangene) ueberschriebe den VEH-Satz waehrend des Lesens.
      Local := GCsLastRaise;
      if (Local.Magic = CS_MAGIC) and (Local.Count > 0) then
      begin
        if Assigned(E) and (Local.Fault = FaultAddress(E)) then
          S := S + FramesText(Local, 'VEH, letzte Ausnahme im Thread, '
                                   + 'Ausloeseadresse stimmt ueberein')
        else
          S := S + FramesText(Local, 'VEH, letzte Ausnahme im Thread - '
                                   + 'Zuordnung NICHT gesichert');
      end
      else
        S := S + 'Stapel : keiner erfasst' + sLineBreak;
    end;
    CsAppend(S + sLineBreak);
  except
    AtomicIncrement(GCsWriteFailures);
  end;
end;

initialization
  InitializeCriticalSection(GCsLock);

finalization
  CrashStackUninstall;
  // Liegt die Unit in einem Paket (Engine-BPL), waeren die Haken nach dem
  // Entladen tote Zeiger. Noch lebende Bloecke bleiben dann liegen - beim
  // Beenden harmlos, sie stammen vom Prozess-Heap.
  if GCsHooked then
  begin
    Exception.CleanUpStackInfoProc   := GCsPrevCleanUp;
    Exception.GetStackInfoStringProc := GCsPrevGetString;
    GCsHooked := False;
  end;
  DeleteCriticalSection(GCsLock);

end.
