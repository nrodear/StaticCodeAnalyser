unit uRdxCompilerTraces;

// reDelphix - Spuren alter Compiler in einer Datei, OHNE ToolsAPI und ohne
// Parser (laeuft auch im FPC-Pruefstand). Ein Baustein fuer Hilfen, die
// Sprachmittel schreiben, die es erst ab einer Compilerversion gibt:
//   SCA121 Default(T)              ab Delphi 2009 bzw. FPC 3.0
//                                  (FLOOR_DEFAULT_FN, uRdxResultFixes)
//   SCA014 Inline-Konstante        ab Delphi 10.3 Rio, in FPC 3.2 gar
//          'const X = 42;' im Rumpf nicht (FLOOR_INLINE_DECL,
//                                  uRdxMagicFixes, Charge Q14)
//   SCA069 Zifferntrenner          ab Delphi 11 Alexandria, in FPC 3.2
//          '1_800_000'             nicht (FLOOR_DIGIT_SEP,
//                                  uRdxDigitGroupingFix, Charge QF10)
// Eine Datei, die nach einer aelteren Version fragt, baut auch mit ihr -
// dort braeche die eingefuegte Form den Bau.
//
// WARUM eine eigene Unit (Charge Q14): bis dahin stand die Heuristik in
// uRdxResultFixes, fest auf Delphi 2009 (Gegen-Review H5, Minor 4: 96 der
// 132 SCA121-Angebote lagen in JVCL/CnWizards, die ab Delphi 5/6 bauen).
// SCA014 braucht dieselbe Suche mit einer hoeheren Schwelle; eine zweite
// Kopie mit anderen Zahlen waere die naechste Drift. Die Schwelle ist
// jetzt ein Record (TRdxCompilerFloor), die Suche ist eine.
//
// WAS als Spur zaehlt - je in einer Direktive (Kommentare und Strings nicht):
//   * ein Include der Kits, die vor beiden Schwellen bauen: JEDI/JCL/JVCL,
//     CnPack/CnWizards, Indy (KIT_INCLUDES; der Dateiname ohne Pfad);
//   * in einer Bedingung ({$IFDEF}, {$IFNDEF}, {$IF}, {$ELSEIF}) ein
//     Versionssymbol bis zur Schwelle (VERnnn, DELPHIn, DELPHI20nn,
//     COMPILERn, BCBn, RTLnnn) oder ein Vergleich 'CompilerVersion|
//     RTLVersion <op> n' bzw. 'FPC_FULLVERSION <op> n' bis zur Schwelle.
//     Wer nach Version n fragt, unterscheidet sie von der davor - die Datei
//     baut also auch mit einer Version bis n. Deshalb zaehlt die Schwelle
//     SELBST mit ('CompilerVersion >= 33' schuetzt gerade die Inline-
//     Deklaration fuer aeltere Compiler), nur VERnnn nicht (ein
//     '{$IFDEF VER330}' nennt die Version, die die Form kennt) - so schon
//     bei SCA121 (VER200, CompilerVersion 20).
// Ein Treffer zu viel kostet nur ein Angebot (lieber keine Hilfe als eine
// falsche). Die Schwelle 10.3 sperrt mehr als die von Delphi 2009: auch
// DELPHIn bis 26 (JEDI zaehlt DELPHI26 = 10.3; DELPHI10_3_UP, DELPHI11 und
// DELPHI12 anderer Bibliotheken fallen mit darunter - vorsichtig) und die
// Namen XE..XE8, SEATTLE..RIO. Korpus Q14: 1.275 SCA014-Funde in Dateien
// mit Spur (jvcl.inc 552, jedi.inc 236, IdCompilerDefines.inc 199 ...),
// dazu 108 ueber ein Include (dmvcframework.inc 86: 'CompilerVersion <=
// 29' - DMVC baut ab Delphi 10.0).
//
// Dazu ScriptReason: eine Datei, die kein Compiler uebersetzt.
//
// mORMot (Realworld-Test rwE30 Stufe 2): mORMot 2 baut ab Delphi 7 und
// fragt mit eigenen Symbolen aus mormot.defines.inc nach der Version -
// ISDELPHI7, ISDELPHI2005ANDUP .. ISDELPHI2010, ISDELPHI20062007,
// ISDELPHIXE .. ISDELPHIXE8, ISDELPHI10/101..104, ISDELPHI11..14,
// ISDELPHIUNICODE und FPC_OR_UNICODE (beides: Delphi ab 2009). Sie zaehlen
// mit ihrer CompilerVersion bis AFloor.Version wie 'CompilerVersion <op> n'
// (OldMormotWord) - fuer jede Schwelle, auch die von Default(T): eine
// Datei, die so fragt, baut mit dem aelteren Delphi. mormot.defines.inc
// selbst steht bei den Kit-Includes (Fundstellen: mormot.core.base.pas
// '{$ifndef ISDELPHI2007ANDUP}', 'FPC_OR_UNICODE'; mormot.core.i18n.pas
// '{$ifdef ISDELPHIXE} .. {$else} // old Delphi 7-2010').
//
// GEGENBEWEIS (ModernProof, rwE30 Stufe 2): eine Sprachform AUSSERHALB
// jedes Bedingungsblocks, die nur ein neuer Delphi uebersetzt, beweist den
// Compiler - eine Inline-Variable ('for var I', 'var X := ..', ab Delphi
// 10.3, FPC 3.2 kennt sie nicht) bzw. ein Unit-Name mit RTL-Praefix im
// uses ('System.SysUtils', 'Winapi.Windows', 'Vcl.Forms', 'FMX.Types' -
// ab Delphi XE2). Was die Spuren alter Compiler (hier, im Include, in der
// Projekt-Nachbarschaft) behaupten, widerlegt er bis zu seiner Version:
// die Datei uebersetzt mit keinem aelteren Compiler. Die Aufrufer fragen
// ihn selbst (uRdxFormatSettingsFix, uRdxRawExceptionFix, uRdxMagicFixes.
// ProjectReason); OldCompilerTrace bleibt, wie er war.
// Seit rwE31 Stufe 3 schliesst ein FMX-Unit-Name im uses ('FMX.Types')
// FPC aus (NoFpc): FireMonkey gibt es nur in Delphi (python4delphi
// Source\fmx\WrapFmxTypes.pas - die FPC-Weiche im gemeinsamen
// Definition.Inc betrifft die Unit nicht).
// Seit rwE32 Stufe 4 beweist auch 'Generics.Collections' bzw.
// 'Generics.Defaults' ohne Namensraum im uses Delphi 2009 (PROOF_GENERICS;
// FPC 3.2 hat sie auch) - genug fuer die Ausnahmeklassen ab 2009 (Dev-Cpp
// SynHighlighterSQL.pas:2373: TDictionary, die VER140-Kylix-Frage im
// generischen SynEditJedi.inc belegt dort kein altes Delphi).
// Die Bedingungsbloecke liest ConditionalDirectives einmal je Frage
// (UnconditionalAt, FpcExcludedAt, NewOnlyAt).
//
// rwE33 Stufe 5:
//   * Versionssymbole mit Bibliotheks-Praefix zaehlen wie COMPILERn, wenn
//     ein Zusatz "ab" folgt (PrefixedCompilerNumber): SynEdit.inc
//     'SYN_COMPILER_6_UP' (Dev-Cpp SynGen\SynGenUnit.pas:245 - SCA128
//     bot die globale FormatSettings an, die es erst ab XE gibt; JCL
//     'COMPILER6_UP' sperrte schon).
//   * Der Grund nennt den TREFFENDEREN Beleg (OldCompilerTraceOf): eine
//     Weiche, die nur fuer NEUE Compiler gilt ('{$IFDEF COMPILER12_UP}',
//     '{$IF CompilerVersion >= 20}'), zeigt nur, dass die Datei die Version
//     unterscheidet; '{$IFNDEF COMPILER12_UP}', 'CompilerVersion < 15' und
//     '{$IFDEF VER130}' nennen den alten Zweig selbst. Die erste solche
//     Spur geht vor, sonst die erste schwache - gesperrt wird wie bisher
//     (jvcl install\JVCLInstall\Compile.pas:512 nannte 'COMPILERVERSION >=
//     20.0' aus Zeile 32, Zeile 182 traegt '{$IFNDEF COMPILER12_UP}').

interface

uses
  uRdxCodeMap;

type
  // Bis zu welcher Version eine Spur "alt" ist (s. Kopf). VERnnn zaehlt
  // UNTER Ver, alle anderen Zahlen bis einschliesslich.
  //   Ver          VERnnn            (200 = Delphi 2009, 330 = 10.3)
  //   Version      CompilerVersion/RTLVersion (20 bzw. 33)
  //   Compiler     COMPILERn und BCBn der JEDI-Zaehlung (12 bzw. 26)
  //   DelphiNumber DELPHIn der JEDI-Zaehlung, ab 1 (12 bzw. 26 - JEDI
  //                zaehlt nach DELPHI8 als DELPHI9 = 2005 weiter, DELPHI12
  //                ist Delphi 2009 wie COMPILER12; andere Bibliotheken
  //                nennen Delphi 10/11/12 so - dort sperrt die Zahl nur
  //                vorsichtig)
  //   DelphiYear   DELPHI2005..DELPHIn (2009 bzw. 2010)
  //   Rtl          RTLnnn            (200 bzw. 330)
  //   FpcFull      FPC_FULLVERSION UNTER diesem Wert (30000; MaxInt: jede
  //                FPC-Version ist alt)
  //   XeNames      dazu die Namen DELPHIXE.. (XE bis XE8),
  //                DELPHIX_SEATTLE .. DELPHIX_ALEXANDRIA (10 bis 11, je
  //                bis einschliesslich Version - SYDNEY und ALEXANDRIA also
  //                erst fuer FLOOR_DIGIT_SEP) und CONDITIONALEXPRESSIONS
  //                (fragt nach Delphi 6) - fuer SCA121 aus (dort nie
  //                gemessen, die Angebote sollen sich mit dieser Unit nicht
  //                bewegen)
  //   ProjectVersion  die <ProjectVersion> einer .dproj in Zehnteln, UNTER
  //                der ein Projekt alt ist (Delphi 2009 = 12.0, 10.3 =
  //                18.5). Nur der Plattenblick liest sie
  //                (uRdxMagicFixes.FileReason, Gegen-Review Q14, Major 3):
  //                SCA014, SCA069, SCA111/SCA112 und seit dem Realworld-
  //                Test rwE29 SCA128/SCA059 (FLOOR_INLINE_DECL fuer den
  //                Invariant-Weg, FLOOR_SETTINGS_VAR fuer den Hauptweg),
  //                seit rwE30 Stufe 2 auch SCA127 (FLOOR_DEFAULT_FN, 12.0 =
  //                Delphi 2009; lfExceptionClasses - nur ein Beleg sperrt).
  //                SCA121 (dieselbe Schwelle, nur die Spuren in der Datei)
  //                hat keinen - der braeuchte eine eigene Messung.
  TRdxCompilerFloor = record
    Ver            : Integer;
    Version        : Integer;
    Compiler       : Integer;
    DelphiNumber   : Integer;
    DelphiYear     : Integer;
    Rtl            : Integer;
    FpcFull        : Integer;
    XeNames        : Boolean;
    ProjectVersion : Integer;
  end;

const
  // SCA121 Default(T): Delphi 2009 (VER200, CompilerVersion 20, COMPILER12,
  // DELPHI12, RTL200), FPC 3.0 - die Zahlen, die bis Charge Q14 fest in
  // uRdxResultFixes standen, bis auf DelphiNumber: dort stand 8, und
  // '{$IFDEF DELPHI12_UP}' (JEDI: ab Delphi 2009) sperrte nicht, obwohl
  // COMPILER12_UP aus demselben jedi.inc sperrt - eine Datei, die so nach
  // 2009 fragt, baut auch mit 2007, und Default(T) braeche dort den Bau
  // (Review Woche G05-18; Angebotsverlust in Dateien mit DELPHI9..DELPHI12
  // ohne Kit-Include, am Korpus zu messen).
  FLOOR_DEFAULT_FN: TRdxCompilerFloor = (Ver: 200; Version: 20; Compiler: 12;
    DelphiNumber: 12; DelphiYear: 2009; Rtl: 200; FpcFull: 30000;
    XeNames: False; ProjectVersion: 120);
  // SCA014 Inline-Konstante: Delphi 10.3 Rio (VER330, CompilerVersion 33,
  // COMPILER26/DELPHI26 der JEDI-Zaehlung, RTL330); FPC kennt keine.
  FLOOR_INLINE_DECL: TRdxCompilerFloor = (Ver: 330; Version: 33; Compiler: 26;
    DelphiNumber: 26; DelphiYear: 2010; Rtl: 330; FpcFull: MaxInt;
    XeNames: True; ProjectVersion: 185);
  // SCA069 Zifferntrenner: Delphi 11 Alexandria (VER350, CompilerVersion 35,
  // COMPILER28 und DELPHI28 der JEDI-Zaehlung - DELPHI27 ist dort 10.4 -,
  // RTL350, ProjectVersion 19.3); FPC kennt sie nicht. Bis zur Integration
  // QFI2 in uRdxDigitGroupingFix - hier, weil der Plattenblick von SCA014
  // (uRdxMagicFixes.FileReason/IncludeReason) sie jetzt auch liest.
  FLOOR_DIGIT_SEP: TRdxCompilerFloor = (Ver: 350; Version: 35; Compiler: 28;
    DelphiNumber: 28; DelphiYear: 2010; Rtl: 350; FpcFull: MaxInt;
    XeNames: True; ProjectVersion: 193);
  // SCA128/SCA059, Hauptweg: die globale Variable FormatSettings gibt es ab
  // Delphi XE (VER220, CompilerVersion 22, COMPILER15/DELPHI15 der JEDI-
  // Zaehlung, RTL220; .dproj ProjectVersion 12.2 - Delphi 2009/2010
  // schrieben 12.0), in FPC ab 2.6. Bis zum Realworld-Test rwE29 in
  // uRdxFormatSettingsFix (dort ohne ProjectVersion); seitdem liest auch
  // der Plattenblick (uRdxMagicFixes, lfFormatSettingsVar) die Schwelle.
  FLOOR_SETTINGS_VAR: TRdxCompilerFloor = (Ver: 220; Version: 22;
    Compiler: 15; DelphiNumber: 15; DelphiYear: 2010; Rtl: 220;
    FpcFull: 20600; XeNames: False; ProjectVersion: 122);
  // SCA127 EArgumentException/EInvalidOpException, SCA020.2 ENotImplemented,
  // SCA168.2 EInvalidOpException (lfExceptionClasses): Delphi 2009 wie
  // FLOOR_DEFAULT_FN, aber FPC kennt alle drei Klassen - eine FPC-Abfrage
  // ('{$IF FPC_FULLVERSION >= 020501}') ist kein Beleg fuer ein altes Delphi
  // (Nico-Entscheid "Sperre nur bei Beleg"; rwE32 Stufe 4, doublecmd
  // src\umaincommands.pas:4399 - bis dahin teilten sie FLOOR_DEFAULT_FN, und
  // FPC_FULLVERSION unter 30000 sperrte). FpcFull 0: keine FPC-Version ist alt.
  FLOOR_EXCEPTION_CLASSES: TRdxCompilerFloor = (Ver: 200; Version: 20;
    Compiler: 12; DelphiNumber: 12; DelphiYear: 2009; Rtl: 200; FpcFull: 0;
    XeNames: False; ProjectVersion: 120);
  // SCA144 Math.IsZero/Math.SameValue: ab Delphi 6 (VER140, CompilerVersion
  // 14, COMPILER6/DELPHI6 der JEDI-Zaehlung, RTL140); FPC kennt beide, eine
  // .dproj gibt es erst ab Delphi 2007 (ProjectVersion 0: keine ist alt).
  // Nur die Bedingungen der Datei fragen danach (OldTraceAtSite) - ein
  // Kit-Include wie jvcl.inc zaehlt hier nicht: die Kits bauen mit vielen
  // Versionen, ihre Versionsleiter belegt kein Delphi vor 6 (rwE32 Stufe 4,
  // jvcl tests\archive\jvcl\source\JvSpin.pas:2157 'COMPILER4_UP', tests\
  // RxLib\Source\JvSpin.pas:1144 'Delphi4_Up', cnwizards CnMsgFiler.pas:505
  // 'COMPILER6_UP').
  FLOOR_MATH_TOLERANCE: TRdxCompilerFloor = (Ver: 140; Version: 14;
    Compiler: 6; DelphiNumber: 6; DelphiYear: 0; Rtl: 140; FpcFull: 0;
    XeNames: False; ProjectVersion: 0);

type
  // Eine Bedingungs-Direktive der Datei (ConditionalDirectives): das Wort
  // klein ('ifdef', 'ifndef', 'if', 'ifopt', 'elseif', 'else', 'endif',
  // 'ifend'), die Argumente gross und ohne Leerraum ('NOTDEFINED(FPC)'),
  // die Stelle ihres '{' bzw. '('.
  TRdxCondDirective = record
    Word : string;
    Args : string;
    Line : Integer;
    Col  : Integer;
  end;
  TRdxCondDirectives = TArray<TRdxCondDirective>;

  // Der Gegenbeweis einer Datei (ModernProof, s. Kopf): die bewiesene
  // CompilerVersion (33 Inline-Variable, 23 RTL-Unit-Name, seit rwE32
  // Stufe 4 20 Generics.Collections bzw. Generics.Defaults; 0 ohne), ob FPC
  // 3.2 die Datei uebersetzt (NoFpc: nein - die Inline-Variable und seit
  // rwE31 Stufe 3 ein FMX-Unit-Name), die Form wie im Text ('for var',
  // 'var X :=', 'System.SysUtils', 'FMX.Types') und ihre Zeile.
  TRdxModernProof = record
    Version : Integer;
    NoFpc   : Boolean;
    What    : string;
    Line    : Integer;
  end;

const
  // Die CompilerVersion, die ModernProof je Form beweist.
  PROOF_INLINE_VAR = 33;   // Delphi 10.3 Rio
  PROOF_RTL_SCOPE  = 23;   // Delphi XE2 (Unit-Namensraeume der RTL)
  PROOF_GENERICS   = 20;   // Delphi 2009 (Generics.Collections, rwE32)

// Die erste Spur alter Compiler (bis AFloor) in den Direktiven der Datei:
// das Symbol, der Vergleich ('COMPILERVERSION >= 33') bzw. der Name der
// Include-Datei, ALine ihre Zeile; '' und 0 ohne Spur. Seit rwE33 Stufe 5
// die erste, die den alten Zweig selbst nennt (s. Kopf), und nur ohne eine
// solche die erste Weiche fuer neue Compiler.
function OldCompilerTrace(AMap: TRdxCodeMap; const AFloor: TRdxCompilerFloor;
  out ALine: Integer): string;
// Die Spur alter Compiler (bis AFloor) in den BEDINGUNGEN der Datei
// (OldCompilerTraceOf ohne Kit-Includes), die die Stelle (ALine, ACol)
// betrifft - '' und ATraceLine 0, wenn der Gegenbeweis die Schwelle deckt
// (ModernProof/ProofCovers) oder die Stelle in einem Zweig liegt, den nur
// Compiler ab der Schwelle uebersetzen (NewOnlyAt: '{$IFDEF COMPILER6_UP}'
// - die Datei baut mit Delphi 5, aber nicht diese Zeile). SCA144 (Math ab
// Delphi 6, rwE32 Stufe 4).
function OldTraceAtSite(AMap: TRdxCodeMap; const AFloor: TRdxCompilerFloor;
  ALine, ACol: Integer; out ATraceLine: Integer): string;
// Wie OldCompilerTrace, aber nur die Spuren einer Art: AConditions die
// Versionssymbole und Vergleiche in Bedingungen, AKits die Kit-Includes
// (KIT_INCLUDES). Seit rwE31 Stufe 3 trennt der Hauptweg von SCA128/SCA059
// beide: die Bedingungen der Datei sperren im Planer, ein Kit-Include
// widerlegt der Plattenblick mit dem Projekt der Unit
// (uRdxMagicFixes.ProjectReason).
function OldCompilerTraceOf(AMap: TRdxCodeMap;
  const AFloor: TRdxCompilerFloor; AConditions, AKits: Boolean;
  out ALine: Integer): string;

// Die Bedingungs-Direktiven der Datei in ihrer Reihenfolge (s.
// TRdxCondDirective) - ein Lauf ueber alle Direktiven (NextDirective).
function ConditionalDirectives(AMap: TRdxCodeMap): TRdxCondDirectives;
// Steht (ALine, ACol) in keinem Bedingungsblock ({$IF..} bis {$ENDIF}/
// {$IFEND}, auch nicht im {$ELSE}-Teil)? ADirs aus ConditionalDirectives.
function UnconditionalAt(const ADirs: TRdxCondDirectives;
  ALine, ACol: Integer): Boolean;
// Liegt (ALine, ACol) in einem Zweig, den FPC nie uebersetzt - '{$IFNDEF
// FPC}', '{$IF NOT DEFINED(FPC)}' bzw. der {$ELSE}-Teil von '{$IFDEF FPC}',
// '{$IF DEFINED(FPC)}'? Nur diese Formen; ein {$ELSEIF} macht den Block
// unbekannt (nein).
function FpcExcludedAt(const ADirs: TRdxCondDirectives;
  ALine, ACol: Integer): Boolean;
// Liegt (ALine, ACol) in einem Zweig, den nur Compiler ab der Schwelle
// AFloor uebersetzen? '{$IFDEF S}' bzw. der {$ELSE}-Teil von '{$IFNDEF S}'
// mit einem Versionssymbol S ab der Schwelle (COMPILER6_UP, DELPHI6_UP,
// VER140, RTL140_UP, CONDITIONALEXPRESSIONS ..., NewVersionWord), '{$IF
// CompilerVersion >= n}' (auch RTLVersion, '>') bzw. '{$IF DEFINED(S)}'
// allein. Ein {$ELSEIF} macht den Block unbekannt (nein).
function NewOnlyAt(const ADirs: TRdxCondDirectives; ALine, ACol: Integer;
  const AFloor: TRdxCompilerFloor): Boolean;
// Der Gegenbeweis der Datei (s. Kopf und TRdxModernProof): die staerkste
// Form ausserhalb jedes Bedingungsblocks; Version = 0 ohne.
function ModernProof(AMap: TRdxCodeMap): TRdxModernProof;
// Widerlegt der Gegenbeweis AProof die Schwelle AFloor - beweist er
// mindestens ihre Version (AFloor.Version)?
function ProofCovers(const AProof: TRdxModernProof;
  const AFloor: TRdxCompilerFloor): Boolean;
// Die erste Zeile mit 'TFormatSettings.Invariant' ausserhalb jedes
// Bedingungsblocks (auch 'SysUtils.TFormatSettings.Invariant'); 0 ohne.
// Wer es so schreibt, baut nur mit Compilern, die es kennen (rwE30 Stufe
// 2: TemplatePro.pas, LoggerPro.Renderers.pas).
function UnconditionalInvariantLine(AMap: TRdxCodeMap): Integer;
// Die erste Zeile, in der die Datei die globale FormatSettings fuer Datum
// und Uhrzeit selbst einstellt: 'FormatSettings.ShortDateFormat := ..',
// 'FormatSettings.LongMonthNames[1] := ..' (DATE_FIELDS; Zahlenfelder wie
// DecimalSeparator nicht) oder ganz 'FormatSettings := ..', auch mit
// 'SysUtils.' davor - nicht 'X.FormatSettings' (ein Member); 0 ohne.
// AField: das Feld wie geschrieben bzw. 'FormatSettings'. Wer sie so einstellt, will dieses
// Format (rwE30 Stufe 2: HeidiSQL heidisql.dpr setzt ShortDateFormat
// 'yyyy/mm/dd'); TFormatSettings.Invariant liefe daran vorbei.
function GlobalSettingsWriteLine(AMap: TRdxCodeMap; out AField: string): Integer;
// Der erste Eintrag einer uses-Klausel AUSSERHALB jedes Bedingungsblocks,
// dessen Name (klein, Glieder mit '.') in ALowNames steht - wie im Text
// geschrieben; '' ohne. rwE32 Stufe 4: die FPC-only-Units eines Programms
// (uRdxMagicFixes.FpcOnlyProgram - doublecmd Zip.dpr 'FPCAdds',
// SevenZipWcx.dpr 'CMem').
function UnconditionalUsesOf(AMap: TRdxCodeMap;
  const ALowNames: array of string): string;

// Uebersetzt ein Compiler die Datei? Skript-Units ('unit X;' ohne
// implementation-Teil: xEdit-Skripte, JvInterpreter-Beispiele) und
// Include-Dateien nicht - ihre Interpreter kennen AFeature ('Default()',
// 'eine Inline-Konstante') nicht. '' oder der Grund. Bis Charge Q14 in
// uRdxResultFixes (SCA121); SCA014 braucht dieselbe Sperre (Korpus: die
// xEdit-Skripte unter 'Edit Scripts'). AFeature kommt schon uebersetzt
// (Code wie 'Default()' bleibt, wie er ist) und steht als %s im Satz -
// der Aufrufer uebersetzt, was er uebergibt (Entscheid E29; ein _(AFeature)
// hier haette keine msgid).
function ScriptReason(AMap: TRdxCodeMap; const AFeature: string): string;

implementation

uses
  System.SysUtils,
  uRdxText;             // _ (Gruende in der Sprache der SCA, E29)

const
  // Die Includes der Kits, die vor beiden Schwellen bauen (JEDI/JCL/JVCL,
  // CnPack/CnWizards, Indy, seit rwE30 Stufe 2 mORMot 2 - ab Delphi 7) ...
  KIT_INCLUDES: array[0..6] of string = ('jedi.inc', 'jvcl.inc', 'jcl.inc',
    'cnpack.inc', 'cnwizards.inc', 'idcompilerdefines.inc',
    'mormot.defines.inc');
  // ... und die Bedingungen, in denen ein Versionssymbol steht.
  CONDITION_WORDS: array[0..3] of string = ('ifdef', 'ifndef', 'if',
    'elseif');
  FIRST_DELPHI_YEAR = 2005;   // DELPHI2005: ab hier Jahreszahlen
  // VERnnn von Delphi beginnt bei VER80 (Delphi 1); darunter sind es die
  // Versionssymbole von FPC ('VER3_2_4' = FPC 3.2.4, rwE32 Stufe 4 - mORMot2
  // test\test.core.base.pas zaehlte bis dahin als Delphi vor 2009). Sie
  // zaehlen wie 'FPC_FULLVERSION < n' (FpcVerVersion, AFloor.FpcFull).
  // Nur die Form von FPC (einstellige Hauptversion, nur Ziffern und '_'):
  // 'VER5X' (kascrypt std.inc: Delphi 5), 'VER9X' (gifimage.pas: Delphi
  // 2/3), 'VER70' (Borland Pascal 7) bleiben alte Spuren wie bis dahin
  // (Review e/HilfeFixP).
  FIRST_DELPHI_VER = 80;
  FPC_MAX_MAJOR = 9;
  // XeNames: Delphi XE bis XE8 (immer, alle vor 10.3) und 10 bis 11 mit
  // Namen (jedi.inc und andere) - diese mit ihrer CompilerVersion, sie
  // zaehlen bis AFloor.Version wie die Zahlen (Integration QFI2: bis dahin
  // endete die Liste bei RIO, der Schwelle von SCA014; fuer FLOOR_DIGIT_SEP
  // fehlten 10.4 SYDNEY und 11 ALEXANDRIA) -, dazu die D6-Frage
  // CONDITIONALEXPRESSIONS.
  XE_PREFIX = 'DELPHIXE';
  NAMED_PREFIXES: array[0..5] of string = ('DELPHIX_SEATTLE',
    'DELPHIX_BERLIN', 'DELPHIX_TOKYO', 'DELPHIX_RIO', 'DELPHIX_SYDNEY',
    'DELPHIX_ALEXANDRIA');
  NAMED_VERSIONS: array[0..5] of Integer = (30, 31, 32, 33, 34, 35);
  D6_QUESTION = 'CONDITIONALEXPRESSIONS';
  // Die CompilerVersion dieser Namen fuer NewVersionWord: Delphi XE und 6.
  XE_VERSION = 22;
  D6_VERSION = 14;
  // Die Zusaetze hinter der Versionszahl, die "ab" heissen (UpSuffix, ohne
  // '_'): keiner ('VER140', 'COMPILER6'), 'COMPILER6_UP', 'DELPHI6UP',
  // 'DELPHI2005_PLUS', '_OR_HIGHER' (Korpus rwE32), 'ANDUP'.
  UP_SUFFIXES: array[0..5] of string = ('', 'UP', 'ANDUP', 'PLUS',
    'ORHIGHER', 'ORNEWER');
  // ConditionTokens: Zeichen eines Worts bzw. eines Vergleichs.
  WORD_CHARS: TSysCharSet = ['A'..'Z', '0'..'9', '_', '.'];
  COMPARE_CHARS: TSysCharSet = ['<', '>', '='];
  // Damit beginnt eine Datei, die der Compiler uebersetzt (ScriptReason).
  PROGRAM_WORDS: array[0..2] of string = ('program', 'library', 'package');
  // mORMot-Symbole (OldMormotWord, s. Kopf): ISDELPHI.. und die beiden
  // Fragen nach Delphi 2009 (Unicode), deren CompilerVersion 20 ist.
  MORMOT_PREFIX = 'ISDELPHI';
  MORMOT_XE = 'XE';
  MORMOT_UNICODE: array[0..1] of string = ('ISDELPHIUNICODE',
    'FPC_OR_UNICODE');
  UNICODE_VERSION = 20;
  // Die Bedingungs-Direktiven (ConditionalDirectives) - oeffnend, Zweig,
  // schliessend.
  COND_OPEN: array[0..3] of string = ('if', 'ifdef', 'ifndef', 'ifopt');
  COND_BRANCH: array[0..1] of string = ('else', 'elseif');
  COND_CLOSE: array[0..1] of string = ('endif', 'ifend');
  FPC_SYMBOL = 'FPC';
  FPC_DEFINED = 'DEFINED(FPC)';
  FPC_NOT_DEFINED = 'NOTDEFINED(FPC)';
  // ModernProof: Unit-Namensraeume der RTL ab Delphi XE2 (klein, mit
  // Punkt) und so weit liest die Probe 'var X: T := ..' bis zum ':='.
  RTL_SCOPES: array[0..3] of string = ('system.', 'winapi.', 'vcl.', 'fmx.');
  // ... davon nur in Delphi (NoFpc; FireMonkey hat FPC nie).
  FMX_SCOPE = 'fmx.';
  // Die Generics der RTL ohne Namensraum (ScopeProof, PROOF_GENERICS): ab
  // Delphi 2009; FPC 3.2 hat sie auch (kein NoFpc).
  GENERICS_UNITS: array[0..1] of string = ('generics.collections',
    'generics.defaults');
  MAX_INLINE_DECL_TOKENS = 40;
  // Die globale Variable (GlobalSettingsWriteLine) und ihre Felder fuer
  // Datum und Uhrzeit - nur sie zaehlen: ein Programm, das
  // DecimalSeparator auf '.' setzt, will meist, was Invariant schreibt
  // (xEdit.dpr; rwE30 Stufe 2), ShortDateFormat 'yyyy/mm/dd' dagegen nicht
  // (HeidiSQL).
  SETTINGS_LOW = 'formatsettings';
  DATE_FIELDS: array[0..12] of string = ('dateseparator', 'timeseparator',
    'shortdateformat', 'longdateformat', 'shorttimeformat', 'longtimeformat',
    'timeamstring', 'timepmstring', 'shortmonthnames', 'longmonthnames',
    'shortdaynames', 'longdaynames', 'twodigityearcenturywindow');

// Die Zahl direkt hinter APrefix am Anfang von AUpper ('DELPHI2007_UP',
// 'DELPHI' -> 2007); -1 ohne Ziffer dahinter.
function NumberAfter(const AUpper, APrefix: string): Integer;
var
  i : Integer;
begin
  Result := -1;
  if Copy(AUpper, 1, Length(APrefix)) <> APrefix then Exit;
  i := Length(APrefix) + 1;
  while (i <= Length(AUpper)) and CharInSet(AUpper[i], ['0'..'9']) do
    Inc(i);
  if i > Length(APrefix) + 1 then
    Result := StrToIntDef(Copy(AUpper, Length(APrefix) + 1,
      i - Length(APrefix) - 1), -1);
end;

// Ein Name aus XeNames (DELPHIXE.., DELPHIX_SEATTLE.. bis AFloor.Version,
// CONDITIONALEXPRESSIONS) - auch mit Zusatz ('DELPHIXE2_UP',
// 'DELPHIX_TOKYO_UP').
function OldNamedWord(const AUpper: string;
  const AFloor: TRdxCompilerFloor): Boolean;
var
  i : Integer;
begin
  Result := (Copy(AUpper, 1, Length(XE_PREFIX)) = XE_PREFIX)
    or (Copy(AUpper, 1, Length(D6_QUESTION)) = D6_QUESTION);
  for i := 0 to High(NAMED_PREFIXES) do
    Result := Result or ((NAMED_VERSIONS[i] <= AFloor.Version)
      and (Copy(AUpper, 1, Length(NAMED_PREFIXES[i])) = NAMED_PREFIXES[i]));
end;

// Die CompilerVersion eines mORMot-Symbols (s. Kopf); -1 ohne. Hinter der
// Zahl darf ein Zusatz stehen ('ISDELPHI2007ANDUP',
// 'ISDELPHI2010_OR_FPC_NEWRTTI'); acht Ziffern sind ein Paar von Jahren
// ('ISDELPHI20062007' - das spaetere zaehlt).
function MormotVersion(const AUpper: string): Integer;
var
  N, Rest : Integer;
begin
  Result := -1;
  if InList(AUpper, MORMOT_UNICODE) then
    Exit(UNICODE_VERSION);
  if Copy(AUpper, 1, Length(MORMOT_PREFIX)) <> MORMOT_PREFIX then Exit;
  Rest := Length(MORMOT_PREFIX) + 1;
  if Copy(AUpper, Rest, Length(MORMOT_XE)) = MORMOT_XE then
  begin
    N := NumberAfter(Copy(AUpper, Rest, MaxInt), MORMOT_XE);
    if N < 0 then
      Exit(22)                       // ISDELPHIXE = Delphi XE
    else if (N >= 2) and (N <= 8) then
      Exit(21 + N);                  // XE2 = 23 .. XE8 = 29
    Exit;
  end;
  N := NumberAfter(AUpper, MORMOT_PREFIX);
  if N > 9999 then
    N := N mod 10000;                // 20062007 -> 2007
  case N of
    7:          Result := 15;        // Delphi 7
    10:         Result := 30;        // 10 Seattle
    11..14:     Result := 24 + N;    // 11 = 35 .. 14 = 38
    101..104:   Result := N - 70;    // 10.1 = 31 .. 10.4 = 34
    2005:       Result := 17;
    2006, 2007: Result := 18;
    2009:       Result := 20;
    2010:       Result := 21;
  end;
end;

// Ein mORMot-Symbol bis zur Schwelle (AFloor.Version, die Schwelle selbst
// zaehlt mit wie bei 'CompilerVersion <op> n').
function OldMormotWord(const AUpper: string;
  const AFloor: TRdxCompilerFloor): Boolean;
var
  V : Integer;
begin
  V := MormotVersion(AUpper);
  Result := (V >= 0) and (V <= AFloor.Version);
end;

// Ein FPC-Versionssymbol ('VER3', 'VER2_6', 'VER3_2_4' - FPC definiert sie
// mit einstelliger Hauptversion) als FPC_FULLVERSION (30204); -1 sonst.
function FpcVerVersion(const AUpper: string): Integer;
var
  Rest     : string;
  i, P, V  : Integer;
begin
  Result := -1;
  if Copy(AUpper, 1, Length('VER')) <> 'VER' then Exit;
  Rest := Copy(AUpper, Length('VER') + 1, MaxInt) + '_';
  Result := 0;
  // Haupt-, Unter-, Patchversion, je bis '_' (fehlende zaehlen 0).
  for i := 1 to 3 do
  begin
    V := 0;
    P := Pos('_', Rest);
    if P > 0 then
    begin
      V := StrToIntDef(Copy(Rest, 1, P - 1), -1);
      Delete(Rest, 1, P);
    end;
    if (V < 0) or (V > 99) or ((i = 1) and (V > FPC_MAX_MAJOR)) then
      Exit(-1);
    Result := Result * 100 + V;
  end;
  if Rest <> '' then
    Result := -1;
end;

// Die Zahl n eines Versionssymbols der JEDI-Zaehlung mit Bibliotheks-
// Praefix bzw. '_' vor der Zahl (rwE33 Stufe 5): '<X>COMPILERn_UP',
// '<X>_COMPILER_n_UP' (SynEdit.inc 'SYN_COMPILER_6_UP'), auch
// 'COMPILER_6_UP' - nur mit einem Zusatz "ab" (UP_SUFFIXES ohne den
// leeren); -1 sonst. Ohne Zahl ('MYCOMPILER_CHECK') oder ohne Zusatz
// ('X_COMPILER_64' - eher 64 Bit als Delphi 64) nicht.
function PrefixedCompilerNumber(const AUpper: string): Integer;
const
  KEY = 'COMPILER';
var
  P, i, j : Integer;
  Rest    : string;
begin
  Result := -1;
  P := Pos(KEY, AUpper);
  if P = 0 then Exit;
  i := P + Length(KEY);
  if (i <= Length(AUpper)) and (AUpper[i] = '_') then
    Inc(i);
  j := i;
  while (j <= Length(AUpper)) and CharInSet(AUpper[j], ['0'..'9']) do
    Inc(j);
  if j = i then Exit;
  Rest := StringReplace(Copy(AUpper, j, MaxInt), '_', '', [rfReplaceAll]);
  if (Rest <> '') and InList(Rest, UP_SUFFIXES) then
    Result := StrToIntDef(Copy(AUpper, i, j - i), -1);
end;

// Ein Versionssymbol bis zur Schwelle AFloor (s. TRdxCompilerFloor). VERn
// unter VER80: ein FPC-Symbol (FpcVerVersion) zaehlt mit FpcFull, jedes
// andere wie VERnnn (Review e/HilfeFixP: 'VER5X', 'VER9X').
// VERnnn, DELPHIn, DELPHI2005.., COMPILERn, BCBn, RTLnnn, mit XeNames
// dazu die Namen, seit rwE30 Stufe 2 die mORMot-Symbole, seit rwE33 Stufe
// 5 COMPILERn mit Praefix (PrefixedCompilerNumber) - wer danach fragt,
// baut auch mit dem aelteren Compiler.
function OldVersionWord(const AUpper: string;
  const AFloor: TRdxCompilerFloor): Boolean;
var
  N, Fpc : Integer;
begin
  if OldMormotWord(AUpper, AFloor) then
    Exit(True);
  N := NumberAfter(AUpper, 'DELPHI');
  Result := ((N >= 1) and (N <= AFloor.DelphiNumber))
    or ((N >= FIRST_DELPHI_YEAR) and (N <= AFloor.DelphiYear));
  N := NumberAfter(AUpper, 'VER');
  if N >= FIRST_DELPHI_VER then
    Result := Result or (N < AFloor.Ver)
  else if N >= 0 then
  begin
    Fpc := FpcVerVersion(AUpper);
    if Fpc >= 0 then
      Result := Result or (Fpc < AFloor.FpcFull)
    else
      Result := Result or (N < AFloor.Ver);
  end;
  N := NumberAfter(AUpper, 'COMPILER');
  Result := Result or ((N >= 0) and (N <= AFloor.Compiler));
  N := PrefixedCompilerNumber(AUpper);
  Result := Result or ((N >= 0) and (N <= AFloor.Compiler));
  N := NumberAfter(AUpper, 'BCB');
  Result := Result or ((N >= 0) and (N <= AFloor.Compiler));
  N := NumberAfter(AUpper, 'RTL');
  Result := Result or ((N >= 0) and (N <= AFloor.Rtl));
  if AFloor.XeNames then
    Result := Result or OldNamedWord(AUpper, AFloor);
end;

// Die Woerter und Vergleichszeichen eines Bedingungstexts, gross
// ('CompilerVersion >= 20.0' -> COMPILERVERSION, >=, 20.0).
function ConditionTokens(const AArgs: string): TArray<string>;
var
  U       : string;
  i, j, N : Integer;
  Chars   : TSysCharSet;
begin
  U := UpperCase(AArgs);
  SetLength(Result, Length(U));
  N := 0;
  i := 1;
  while i <= Length(U) do
  begin
    Chars := WORD_CHARS;
    if CharInSet(U[i], COMPARE_CHARS) then
      Chars := COMPARE_CHARS;
    j := i;
    while (j <= Length(U)) and CharInSet(U[j], Chars) do
      Inc(j);
    if j > i then
    begin
      Result[N] := Copy(U, i, j - i);
      Inc(N);
      i := j;
    end
    else
      Inc(i);
  end;
  SetLength(Result, N);
end;

// Die Zahl vor dem ersten '.' von AWord ('20.0' -> 20); -1 ohne Zahl.
function LeadingNumber(const AWord: string): Integer;
var
  P : Integer;
begin
  P := Pos('.', AWord + '.');
  Result := StrToIntDef(Copy(AWord, 1, P - 1), -1);
end;

// Ein Vergleich 'CompilerVersion|RTLVersion <op> n' mit n bis
// AFloor.Version bzw. 'FPC_FULLVERSION <op> n' mit n unter AFloor.FpcFull
// an AToks[i]?
function OldComparisonAt(const AToks: TArray<string>; i: Integer;
  const AFloor: TRdxCompilerFloor): Boolean;
var
  N : Integer;
begin
  Result := False;
  if (i + 2 > High(AToks)) or not CharInSet(AToks[i + 1][1], ['<', '>', '='])
  then
    Exit;
  N := LeadingNumber(AToks[i + 2]);
  if (AToks[i] = 'COMPILERVERSION') or (AToks[i] = 'RTLVERSION') then
    Result := (N >= 0) and (N <= AFloor.Version)
  else if AToks[i] = 'FPC_FULLVERSION' then
    Result := (N >= 0) and (N < AFloor.FpcFull);
end;

// Heisst das Versionssymbol AUpper "ab dieser Version" (WeakTraceAt)? Ein
// Zusatz aus UP_SUFFIXES (nicht der leere) direkt hinter der letzten
// Ziffer ('COMPILER12_UP', 'DELPHIXE2_UP', 'ISDELPHI2005ANDUP') bzw. - ohne
// Ziffer - am Ende ('DELPHIX_TOKYO_UP'); dazu CONDITIONALEXPRESSIONS (ab
// Delphi 6) und die Unicode-Fragen von mORMot (ab 2009).
function UpWord(const AUpper: string): Boolean;
var
  i    : Integer;
  Rest : string;
  S    : string;
begin
  if (AUpper = D6_QUESTION) or InList(AUpper, MORMOT_UNICODE) then
    Exit(True);
  i := Length(AUpper);
  while (i >= 1) and not CharInSet(AUpper[i], ['0'..'9']) do
    Dec(i);
  Rest := StringReplace(Copy(AUpper, i + 1, MaxInt), '_', '', [rfReplaceAll]);
  Result := False;
  for S in UP_SUFFIXES do
    if (S <> '') and ((Rest = S) or ((i = 0) and (Length(Rest) > Length(S))
       and (Copy(Rest, Length(Rest) - Length(S) + 1, MaxInt) = S))) then
      Exit(True);
end;

// Gilt die Spur an AToks[i] in einer Direktive AWord nur fuer einen Zweig
// NEUER Compiler (rwE33 Stufe 5, s. Kopf)? Ein "ab"-Symbol (UpWord) in
// '{$IFDEF}' bzw. 'DEFINED(..)' und ein Vergleich '>=' bzw. '>'
// (AComparison: AToks[i] beginnt einen Vergleich, OldComparisonAt) - nicht
// in '{$IFNDEF}' und nicht hinter 'NOT'. Sie belegt nur, dass die Datei die
// Version unterscheidet; der Grund nennt lieber eine Spur, die den alten
// Zweig selbst nennt.
function WeakTraceAt(const AWord: string; const AToks: TArray<string>;
  i: Integer; AComparison: Boolean): Boolean;
var
  j : Integer;
begin
  if AWord = 'ifndef' then
    Exit(False);
  j := i - 1;
  if (j >= 0) and (AToks[j] = 'DEFINED') then
    Dec(j);
  if (j >= 0) and (AToks[j] = 'NOT') then
    Exit(False);
  if AComparison then
    Result := (AToks[i + 1] = '>=') or (AToks[i + 1] = '>')
  else
    Result := UpWord(AToks[i]);
end;

// Eine Spur alter Compiler im Bedingungstext AArgs der Direktive AWord
// ('{$IFDEF DELPHI2007_UP}', '{$IF CompilerVersion < 20}') - das Symbol
// bzw. der Vergleich; '' ohne. Die erste, die den alten Zweig nennt, sonst
// die erste schwache (AWeak, WeakTraceAt).
function OldSymbolIn(const AWord, AArgs: string;
  const AFloor: TRdxCompilerFloor; out AWeak: Boolean): string;
var
  Toks : TArray<string>;
  i    : Integer;
  S    : string;
  Weak : Boolean;
begin
  Result := '';
  AWeak := False;
  Toks := ConditionTokens(AArgs);
  for i := 0 to High(Toks) do
  begin
    if OldVersionWord(Toks[i], AFloor) then
    begin
      S := Toks[i];
      Weak := WeakTraceAt(AWord, Toks, i, False);
    end
    else if OldComparisonAt(Toks, i, AFloor) then
    begin
      S := Toks[i] + ' ' + Toks[i + 1] + ' ' + Toks[i + 2];
      Weak := WeakTraceAt(AWord, Toks, i, True);
    end
    else
      Continue;
    if not Weak then
    begin
      AWeak := False;
      Exit(S);
    end;
    if Result = '' then
    begin
      Result := S;
      AWeak := True;
    end;
  end;
end;

// Die Spur alter Compiler in der Direktive an (ALine, ACol): ein
// Kit-Include (KIT_INCLUDES, klein ohne Pfad) oder ein Versionssymbol in
// einer Bedingung; '' ohne. AWeak: nur eine Weiche fuer neue Compiler
// (OldSymbolIn; ein Kit-Include nie).
function OldTraceAt(AMap: TRdxCodeMap; ALine, ACol: Integer;
  const AFloor: TRdxCompilerFloor; AConditions, AKits: Boolean;
  out AWeak: Boolean): string;
var
  W   : string;
  Arg : Boolean;
begin
  Result := '';
  AWeak := False;
  W := DirectiveWord(AMap, ALine, ACol, Arg);
  if AKits and InList(W, INCLUDE_WORDS) then
  begin
    Result := LowerCase(IncludeFileAt(AMap, ALine, ACol));
    Result := Copy(Result, LastDelimiter('\/', Result) + 1, MaxInt);
    if not InList(Result, KIT_INCLUDES) then
      Result := '';
  end
  else if AConditions and InList(W, CONDITION_WORDS) then
    Result := OldSymbolIn(W, DirectiveArgs(AMap, ALine, ACol), AFloor, AWeak);
end;

// Der Lauf ueber alle Direktiven: NextDirective (uRdxCodeMap; bis zur
// Folgewelle des Wochen-Reviews, G08-01, hier ausgeschrieben).
function OldCompilerTrace(AMap: TRdxCodeMap; const AFloor: TRdxCompilerFloor;
  out ALine: Integer): string;
begin
  Result := OldCompilerTraceOf(AMap, AFloor, True, True, ALine);
end;

// Ob eine Spur da ist, entscheidet wie bis rwE33 jede Direktive; nur die
// GENANNTE ist die erste starke (OldTraceAt, AWeak) - bis dahin endete der
// Lauf an der ersten Spur. Ohne starke liest er die ganze Datei.
function OldCompilerTraceOf(AMap: TRdxCodeMap;
  const AFloor: TRdxCompilerFloor; AConditions, AKits: Boolean;
  out ALine: Integer): string;
var
  Li, Co : Integer;
  S      : string;
  Weak   : Boolean;
begin
  Result := '';
  ALine := 0;
  Li := 1;
  Co := 1;
  while NextDirective(AMap, Li, Co) do
  begin
    S := OldTraceAt(AMap, Li, Co, AFloor, AConditions, AKits, Weak);
    if (S <> '') and not Weak then
    begin
      ALine := Li;
      Exit(S);
    end;
    if (S <> '') and (Result = '') then
    begin
      Result := S;
      ALine := Li;
    end;
    Inc(Co);
  end;
end;

function OldTraceAtSite(AMap: TRdxCodeMap; const AFloor: TRdxCompilerFloor;
  ALine, ACol: Integer; out ATraceLine: Integer): string;
begin
  ATraceLine := 0;
  if ProofCovers(ModernProof(AMap), AFloor) then
    Exit('');
  Result := OldCompilerTraceOf(AMap, AFloor, True, False, ATraceLine);
  if (Result <> '')
     and NewOnlyAt(ConditionalDirectives(AMap), ALine, ACol, AFloor) then
  begin
    Result := '';
    ATraceLine := 0;
  end;
end;

function ScriptReason(AMap: TRdxCodeMap; const AFeature: string): string;
var
  T, P : TRdxToken;
begin
  T := NextToken(AMap, 1, 1);
  if InList(T.Low, PROGRAM_WORDS) then
    Exit('');
  if T.Low <> 'unit' then
    Exit(_('the file does not start with unit/program/library (include or '
      + 'script?) - only the compiler knows %s', [AFeature]));
  P := T;
  T := After(AMap, T);
  while T.Low <> '' do
  begin
    if (T.Low = 'implementation') and IsKeywordAfter(T, P) then
      Exit('');
    P := T;
    T := After(AMap, T);
  end;
  Result := _('unit without an implementation part (script?) - only the '
    + 'compiler knows %s', [AFeature]);
end;

{ ---- Bedingungsbloecke und Gegenbeweis (rwE30 Stufe 2) ---- }

function ConditionalDirectives(AMap: TRdxCodeMap): TRdxCondDirectives;
var
  Li, Co, N : Integer;
  W         : string;
  Arg       : Boolean;
begin
  Result := nil;
  N := 0;
  Li := 1;
  Co := 1;
  while NextDirective(AMap, Li, Co) do
  begin
    W := DirectiveWord(AMap, Li, Co, Arg);
    if InList(W, COND_OPEN) or InList(W, COND_BRANCH)
       or InList(W, COND_CLOSE) then
    begin
      if N = Length(Result) then
        SetLength(Result, 2 * N + 8);
      Result[N].Word := W;
      Result[N].Args := UpperCase(Squeezed(DirectiveArgs(AMap, Li, Co)));
      Result[N].Line := Li;
      Result[N].Col := Co;
      Inc(N);
    end;
    Inc(Co);
  end;
  SetLength(Result, N);
end;

// Steht die Direktive ADir vor (ALine, ACol)?
function DirBefore(const ADir: TRdxCondDirective; ALine, ACol: Integer): Boolean;
begin
  Result := (ADir.Line < ALine) or ((ADir.Line = ALine) and (ADir.Col < ACol));
end;

function UnconditionalAt(const ADirs: TRdxCondDirectives;
  ALine, ACol: Integer): Boolean;
var
  i, Depth : Integer;
begin
  Depth := 0;
  for i := 0 to High(ADirs) do
  begin
    if not DirBefore(ADirs[i], ALine, ACol) then Break;
    if InList(ADirs[i].Word, COND_OPEN) then
      Inc(Depth)
    else if InList(ADirs[i].Word, COND_CLOSE) and (Depth > 0) then
      Dec(Depth);
  end;
  Result := Depth = 0;
end;

type
  // Ein offener Bedingungsblock fuer FpcExcludedAt: fragt er nach FPC
  // (Fpc), mit welcher Polaritaet (Neg: '{$IFNDEF FPC}', 'NOT DEFINED'),
  // im {$ELSE}-Teil, unbekannt ({$ELSEIF}, andere Bedingung).
  TFpcFrame = record
    Fpc, Neg, InElse : Boolean;
  end;

function FpcExcludedAt(const ADirs: TRdxCondDirectives;
  ALine, ACol: Integer): Boolean;
var
  Stack : array of TFpcFrame;
  i, N  : Integer;
  D     : TRdxCondDirective;
begin
  Result := False;
  SetLength(Stack, Length(ADirs) + 1);
  N := 0;
  for i := 0 to High(ADirs) do
  begin
    D := ADirs[i];
    if not DirBefore(D, ALine, ACol) then Break;
    if InList(D.Word, COND_OPEN) then
    begin
      Stack[N] := Default(TFpcFrame);
      if (D.Word = 'ifdef') or (D.Word = 'ifndef') then
      begin
        Stack[N].Fpc := D.Args = FPC_SYMBOL;
        Stack[N].Neg := D.Word = 'ifndef';
      end
      else if D.Word = 'if' then
      begin
        Stack[N].Fpc := (D.Args = FPC_DEFINED) or (D.Args = FPC_NOT_DEFINED);
        Stack[N].Neg := D.Args = FPC_NOT_DEFINED;
      end;
      Inc(N);
    end
    else if N = 0 then
      Continue
    else if D.Word = 'else' then
      Stack[N - 1].InElse := True
    else if D.Word = 'elseif' then
      Stack[N - 1].Fpc := False
    else
      Dec(N);
  end;
  for i := 0 to N - 1 do
    if Stack[i].Fpc and (Stack[i].Neg <> Stack[i].InElse) then
      Exit(True);
end;

// Ein Versionssymbol AB der Schwelle AFloor (das Gegenstueck zu
// OldVersionWord fuer NewOnlyAt): VERnnn ab Ver, COMPILERn/BCBn ab
// Compiler, DELPHIn ab DelphiNumber, RTLnnn ab Rtl, die mORMot-Symbole ab
// Version, DELPHIXE.. (22) und CONDITIONALEXPRESSIONS (14) ab Version.
// Jahreszahlen (DELPHI2005..) nur fuer eine Schwelle vor 2005 (DelphiYear
// darunter) - die Zaehlung der anderen Schwellen ist dort "bis
// einschliesslich" und belegt kein "ab".
// Hinter Praefix und Zahl nur ein Zusatz, der "ab" heisst (UpSuffix,
// Review e/HilfeFixP): 'DELPHI7OROLDER' (JvGnugettext.pas), 'BCB5OR6',
// 'DELPHI64_TEMPORARY' oder '_DOWN' sind kein Zweig nur fuer neue
// Compiler - nein.
function UpSuffix(const AUpper, APrefix: string): Boolean;
var
  i : Integer;
begin
  i := Length(APrefix) + 1;
  while (i <= Length(AUpper)) and CharInSet(AUpper[i], ['0'..'9']) do
    Inc(i);
  Result := InList(StringReplace(Copy(AUpper, i, MaxInt), '_', '',
    [rfReplaceAll]), UP_SUFFIXES);
end;

function NewVersionWord(const AUpper: string;
  const AFloor: TRdxCompilerFloor): Boolean;
var
  N : Integer;
begin
  N := MormotVersion(AUpper);
  if N >= 0 then
    Exit(N >= AFloor.Version);
  if Copy(AUpper, 1, Length(XE_PREFIX)) = XE_PREFIX then
    Exit(UpSuffix(AUpper, XE_PREFIX) and (XE_VERSION >= AFloor.Version));
  if AUpper = D6_QUESTION then
    Exit(D6_VERSION >= AFloor.Version);
  N := NumberAfter(AUpper, 'DELPHI');
  if (N >= 1) and not UpSuffix(AUpper, 'DELPHI') then
    Exit(False);
  if N >= FIRST_DELPHI_YEAR then
    Exit(AFloor.DelphiYear < FIRST_DELPHI_YEAR);
  if N >= 1 then
    Exit(N >= AFloor.DelphiNumber);
  N := NumberAfter(AUpper, 'VER');
  if N >= FIRST_DELPHI_VER then
    Exit(UpSuffix(AUpper, 'VER') and (N >= AFloor.Ver));
  if N >= 0 then
    Exit(False);
  N := NumberAfter(AUpper, 'COMPILER');
  if N >= 0 then
    Exit(UpSuffix(AUpper, 'COMPILER') and (N >= AFloor.Compiler));
  // Mit Praefix ('SYN_COMPILER_6_UP', rwE33 Stufe 5) - wie OldVersionWord,
  // sonst sperrte die Spur auch Zeilen in ihrem Zweig fuer neue Compiler.
  N := PrefixedCompilerNumber(AUpper);
  if N >= 0 then
    Exit(N >= AFloor.Compiler);
  N := NumberAfter(AUpper, 'BCB');
  if N >= 0 then
    Exit(UpSuffix(AUpper, 'BCB') and (N >= AFloor.Compiler));
  N := NumberAfter(AUpper, 'RTL');
  Result := (N >= 0) and UpSuffix(AUpper, 'RTL') and (N >= AFloor.Rtl);
end;

// Gilt die Bedingung AArgs ({$IF}, gross ohne Leerraum) nur fuer Compiler
// ab AFloor? 'COMPILERVERSION>=n', 'RTLVERSION>n' bzw. 'DEFINED(S)' allein.
function NewOnlyCondition(const AArgs: string;
  const AFloor: TRdxCompilerFloor): Boolean;
var
  Toks : TArray<string>;
  N    : Integer;
begin
  Result := False;
  Toks := ConditionTokens(AArgs);
  if (Length(Toks) = 2) and (Toks[0] = 'DEFINED') then
    Exit(NewVersionWord(Toks[1], AFloor));
  if (Length(Toks) <> 3)
     or ((Toks[0] <> 'COMPILERVERSION') and (Toks[0] <> 'RTLVERSION')) then
    Exit;
  N := LeadingNumber(Toks[2]);
  if Toks[1] = '>=' then
    Result := N >= AFloor.Version
  else if Toks[1] = '>' then
    Result := (N >= 0) and (N + 1 >= AFloor.Version);
end;

type
  // Ein offener Bedingungsblock fuer NewOnlyAt: sein Teil fuer Compiler ab
  // der Schwelle - der Then-Teil (nwThen), der {$ELSE}-Teil (nwElse) oder
  // keiner (nwNone, auch nach {$ELSEIF}).
  TNewWay = (nwNone, nwThen, nwElse);
  TNewFrame = record
    Kind   : TNewWay;
    InElse : Boolean;
  end;

function NewOnlyAt(const ADirs: TRdxCondDirectives; ALine, ACol: Integer;
  const AFloor: TRdxCompilerFloor): Boolean;
var
  Stack : array of TNewFrame;
  i, N  : Integer;
  D     : TRdxCondDirective;
  Toks  : TArray<string>;
begin
  Result := False;
  SetLength(Stack, Length(ADirs) + 1);
  N := 0;
  for i := 0 to High(ADirs) do
  begin
    D := ADirs[i];
    if not DirBefore(D, ALine, ACol) then Break;
    if InList(D.Word, COND_OPEN) then
    begin
      Stack[N] := Default(TNewFrame);
      if (D.Word = 'ifdef') or (D.Word = 'ifndef') then
      begin
        Toks := ConditionTokens(D.Args);
        if (Length(Toks) > 0) and NewVersionWord(Toks[0], AFloor) then
          if D.Word = 'ifdef' then
            Stack[N].Kind := nwThen
          else
            Stack[N].Kind := nwElse;
      end
      else if (D.Word = 'if') and NewOnlyCondition(D.Args, AFloor) then
        Stack[N].Kind := nwThen;
      Inc(N);
    end
    else if N = 0 then
      Continue
    else if D.Word = 'else' then
      Stack[N - 1].InElse := True
    else if D.Word = 'elseif' then
      Stack[N - 1].Kind := nwNone
    else
      Dec(N);
  end;
  for i := 0 to N - 1 do
    if ((Stack[i].Kind = nwThen) and not Stack[i].InElse)
       or ((Stack[i].Kind = nwElse) and Stack[i].InElse) then
      Exit(True);
end;

// Eine Inline-Variable an T ('var' als Schluesselwort): 'for var',
// 'var X :=' bzw. 'var X: T :=' (bis ';' oder ')' auf Klammertiefe 0 ein
// ':='); die Form als Text, '' ohne.
function InlineVarAt(AMap: TRdxCodeMap; const T: TRdxToken): string;
var
  N     : TRdxToken;
  Depth : Integer;
  Count : Integer;
begin
  Result := '';
  if Before(AMap, T).Low = 'for' then
    Exit('for var');
  N := After(AMap, T);
  if not N.IsWord then Exit;
  N := After(AMap, N);
  if N.Low = ':=' then
    Exit('var ' + TokText(AMap, Before(AMap, N)) + ' :=');
  if N.Low <> ':' then Exit;
  Depth := 0;
  Count := 0;
  while (N.Low <> '') and (Count < MAX_INLINE_DECL_TOKENS) do
  begin
    Depth := Depth + ParenDelta(N);
    if (Depth < 0) or ((Depth = 0) and ((N.Low = ';') or (N.Low = '=')))
    then
      Exit;
    if (Depth = 0) and (N.Low = ':=') then
      Exit('var ' + TokText(AMap, After(AMap, T)) + ': .. :=');
    N := After(AMap, N);
    Inc(Count);
  end;
end;

// Der Name eines uses-Eintrags ab AFirst bis vor ',', ';' oder 'in' -
// klein, Glieder mit '.'; AStop: das Token dahinter.
function UsesEntry(AMap: TRdxCodeMap; const AFirst: TRdxToken;
  out AStop: TRdxToken): string;
begin
  Result := '';
  AStop := AFirst;
  while (AStop.Low <> '') and (AStop.Low <> ',') and (AStop.Low <> ';')
        and (AStop.Low <> 'in') do
  begin
    Result := Result + AStop.Low;
    AStop := After(AMap, AStop);
  end;
end;

// Ein RTL-Namensraum im uses ausserhalb jedes Bedingungsblocks: der Name
// wie geschrieben und seine Zeile in AProof (Version PROOF_RTL_SCOPE). Seit
// rwE31 Stufe 3 liest die Probe weiter bis zu einem FMX-Namen: er setzt
// NoFpc und steht dann in What und Line.
procedure ScopeProof(AMap: TRdxCodeMap; const ADirs: TRdxCondDirectives;
  var AProof: TRdxModernProof);
var
  T, E, Stop : TRdxToken;
  Name, S    : string;
begin
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), 'uses');
  while T.Low <> '' do
  begin
    if (T.Low = 'uses') and IsKeywordAfter(T, Before(AMap, T)) then
    begin
      E := After(AMap, T);
      while (E.Low <> '') and (E.Low <> ';') do
      begin
        Name := UsesEntry(AMap, E, Stop);
        // Generics.Collections ohne Namensraum (Delphi 2009 bis XE, rwE32
        // Stufe 4: Dev-Cpp SynHighlighterSQL.pas - TDictionary).
        if InList(Name, GENERICS_UNITS) and (AProof.Version < PROOF_GENERICS)
           and UnconditionalAt(ADirs, E.Line, E.Col) then
        begin
          AProof.Version := PROOF_GENERICS;
          AProof.What := Copy(AMap.Raw(E.Line), E.Col, Length(Name));
          AProof.Line := E.Line;
        end;
        for S in RTL_SCOPES do
          if (Copy(Name, 1, Length(S)) = S)
             and ((AProof.Version < PROOF_RTL_SCOPE) or (S = FMX_SCOPE))
             and UnconditionalAt(ADirs, E.Line, E.Col) then
          begin
            AProof.Version := PROOF_RTL_SCOPE;
            AProof.What := Copy(AMap.Raw(E.Line), E.Col, Length(Name));
            AProof.Line := E.Line;
            if S = FMX_SCOPE then
            begin
              AProof.NoFpc := True;
              Exit;
            end;
          end;
        // Hinter 'in' der Pfad, dann ',' oder ';'.
        while (Stop.Low <> '') and (Stop.Low <> ',') and (Stop.Low <> ';') do
          Stop := After(AMap, Stop);
        if Stop.Low = ',' then
          E := After(AMap, Stop)
        else
          E := Stop;
      end;
    end;
    T := NextTokenOnLineWith(AMap, T, 'uses');
  end;
end;

function ModernProof(AMap: TRdxCodeMap): TRdxModernProof;
var
  Dirs : TRdxCondDirectives;
  T    : TRdxToken;
  Form : string;
begin
  Result := Default(TRdxModernProof);
  Dirs := ConditionalDirectives(AMap);
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), 'var');
  while T.Low <> '' do
  begin
    if (T.Low = 'var') and IsKeywordAfter(T, Before(AMap, T))
       and UnconditionalAt(Dirs, T.Line, T.Col) then
    begin
      Form := InlineVarAt(AMap, T);
      if Form <> '' then
      begin
        Result.Version := PROOF_INLINE_VAR;
        Result.NoFpc := True;
        Result.What := Form;
        Result.Line := T.Line;
        Exit;
      end;
    end;
    T := NextTokenOnLineWith(AMap, T, 'var');
  end;
  ScopeProof(AMap, Dirs, Result);
end;

function ProofCovers(const AProof: TRdxModernProof;
  const AFloor: TRdxCompilerFloor): Boolean;
begin
  Result := (AProof.Version > 0) and (AProof.Version >= AFloor.Version);
end;

function UnconditionalInvariantLine(AMap: TRdxCodeMap): Integer;
var
  Dirs    : TRdxCondDirectives;
  T, D, P : TRdxToken;
  Read    : Boolean;
begin
  Result := 0;
  Read := False;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), 'invariant');
  while T.Low <> '' do
  begin
    D := Before(AMap, T);
    P := Before(AMap, D);
    if (T.Low = 'invariant') and (D.Low = '.')
       and (P.Low = 'tformatsettings') then
    begin
      if not Read then
      begin
        Dirs := ConditionalDirectives(AMap);
        Read := True;
      end;
      if UnconditionalAt(Dirs, T.Line, T.Col) then
        Exit(T.Line);
    end;
    T := NextTokenOnLineWith(AMap, T, 'invariant');
  end;
end;

function UnconditionalUsesOf(AMap: TRdxCodeMap;
  const ALowNames: array of string): string;
var
  Dirs       : TRdxCondDirectives;
  T, E, Stop : TRdxToken;
  Name       : string;
  i          : Integer;
  Read       : Boolean;
begin
  Result := '';
  Read := False;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), 'uses');
  while T.Low <> '' do
  begin
    if (T.Low = 'uses') and IsKeywordAfter(T, Before(AMap, T)) then
    begin
      E := After(AMap, T);
      while (E.Low <> '') and (E.Low <> ';') do
      begin
        Name := UsesEntry(AMap, E, Stop);
        for i := Low(ALowNames) to High(ALowNames) do
          if Name = ALowNames[i] then
          begin
            if not Read then
            begin
              Dirs := ConditionalDirectives(AMap);
              Read := True;
            end;
            if UnconditionalAt(Dirs, E.Line, E.Col) then
              Exit(Copy(AMap.Raw(E.Line), E.Col, Length(Name)));
          end;
        // Hinter 'in' der Pfad, dann ',' oder ';' (wie ScopeProof).
        while (Stop.Low <> '') and (Stop.Low <> ',') and (Stop.Low <> ';') do
          Stop := After(AMap, Stop);
        if Stop.Low = ',' then
          E := After(AMap, Stop)
        else
          E := Stop;
      end;
    end;
    T := NextTokenOnLineWith(AMap, T, 'uses');
  end;
end;

function GlobalSettingsWriteLine(AMap: TRdxCodeMap; out AField: string): Integer;
var
  T, P, N, F : TRdxToken;
begin
  Result := 0;
  AField := '';
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), SETTINGS_LOW);
  while T.Low <> '' do
  begin
    P := Before(AMap, T);
    if (T.Low = SETTINGS_LOW)
       and ((P.Low <> '.') or (Before(AMap, P).Low = 'sysutils')) then
    begin
      N := After(AMap, T);
      if N.Low = ':=' then
      begin
        AField := TokText(AMap, T);
        Exit(T.Line);
      end;
      if N.Low = '.' then
      begin
        F := After(AMap, N);
        N := After(AMap, F);
        if N.Low = '[' then
          N := AfterClose(AMap, N);
        if F.IsWord and (N.Low = ':=') and InList(F.Low, DATE_FIELDS) then
        begin
          AField := TokText(AMap, F);
          Exit(T.Line);
        end;
      end;
    end;
    T := NextTokenOnLineWith(AMap, T, SETTINGS_LOW);
  end;
end;

end.
