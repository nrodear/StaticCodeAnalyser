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
//   * die Modulbasis dieses Laufs und die modulRELATIVE Adresse - stabil
//     ueber Laeufe hinweg und gegen eine Detailed-Map aufloesbar,
//   * bei Hardware-Exceptions den NT-Statuscode. Der unterscheidet die
//     Ursachen, die dieselbe Meldung erzeugen koennen - vor allem
//     $C0000005 (echte Zugriffsverletzung) von $C00000FD (Stapel
//     erschoepft, z.B. zu tiefe Parser-Rekursion).
//
// Bewusst KEIN Stack-Trace: der braucht eine Fremdbibliothek (JCL/madExcept)
// oder Debug-Infos im Release-Build. Modulrelative Adresse + Map-Datei
// leisten dasselbe fuer den einen Frame, der zaehlt.

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
///   Exception-Klasse, Meldung und - soweit ermittelbar - modulrelative
///   Fehleradresse samt NT-Statuscode. Nie leer, nie werfend: diese
///   Funktion laeuft in Fehlerpfaden und darf den Fehler nicht ersetzen.
/// </summary>
function DescribeException(E: Exception): string;

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
  if Addr < Base then
    Result := Format(' [Modulbasis $%x, Adresse liegt DARUNTER - nicht dieses Modul]',
                     [Base])
  else if (Size > 0) and (Addr >= Base + Size) then
    Result := Format(' [Modulbasis $%x, Bildgroesse $%x, Adresse liegt DARUEBER - nicht dieses Modul]',
                     [Base, Size])
  else
    Result := Format(' [Modulbasis $%x, modulrelativ $%x]', [Base, Addr - Base]);
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
    Result := Format('%s: %s%s%s',
                     [E.ClassName, E.Message,
                      StatusInfo(E), AddressInfo(FaultAddress(E))]);
  except
    Result := E.ClassName + ': ' + E.Message;
  end;
end;

end.
