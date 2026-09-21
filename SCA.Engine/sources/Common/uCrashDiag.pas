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
///   Exception-Klasse und Meldung, bei EXTERNEN Exceptions zusaetzlich
///   NT-Statuscode und - soweit ermittelbar - die modulrelative
///   Fehleradresse. Eine im Code geworfene Exception bekommt KEINE
///   Adresse: sie wandert bei jedem Bau, und dieser Text bildet die
///   Identitaet eines SCA006-Fundes (s. Rumpf).
///   Nie leer, nie werfend: diese Funktion laeuft in Fehlerpfaden und
///   darf den Fehler nicht ersetzen.
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

end.
