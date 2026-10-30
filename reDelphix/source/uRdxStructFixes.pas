unit uRdxStructFixes;

// reDelphix - Editorhilfen der Stufe 3 (Konzept_Editorhilfen_2026-10-08):
// Planer an Strukturen ueber mehrere Token oder Zeilen, OHNE ToolsAPI und
// ohne Parser. Die Bereiche der uses-Eintraege liefert der Aufrufer
// (TSourcePlaces.UsesEntries); alles andere liest die Code-Sicht.
//   SCA007 UnusedUses: einen Eintrag aus der uses-Klausel loeschen.
//   SCA168 DefaultCaseInCaseStatement: vor das end des case ein else setzen
//          - leer oder mit raise (Nico 2026-10-10: beide als Eintraege).
//   SCA101 BeginEndRequired, SCA099 IfElseBegin: die Anweisung hinter
//          then/else/do in begin..end setzen (Entscheid E7).
//
// GRUNDSATZ wie in uRdxSimpleFixes: lieber keine Hilfe als eine falsche.
// Geloescht wird nichts, was einen Kommentar oder eine Direktive traegt -
// ausser dem '//'-Kommentar hinter einem Eintrag, der allein auf seiner
// Zeile steht (er gehoert zum Eintrag).

interface

uses
  uRefactorInfo,   // TRefactorSpan in TRdxUsesClause
  uRdxBufferMath, uRdxCodeMap;

const
  // Die raise-Variante von SCA168 (Katalog-Beispiel). EInvalidOpException
  // steht in System.SysUtils (Delphi 12 und 13 Zeile 476) und in SysUtils
  // von FPC 3.2.2 (sysutilh.inc) - die Hilfe gilt deshalb auch in Dateien
  // mit FPC-Weiche. Bis 2026-10-22 stand hier
  // EProgrammerError: die Klasse gibt es in keiner RTL (nur
  // EProgrammerNotFound), der Klick brach den Bau (E2003). Eine
  // EArgumentException-Unterklasse waere enger und finge sich in
  // 'on E: EArgumentException' - ein unbehandelter Wert ist aber kein
  // falsches Argument, sondern ein Zustand, den das case nicht vorsieht.
  RAISE_UNHANDLED = 'raise EInvalidOpException.Create(''Unhandled case'');';

type
  // Eine uses-Klausel: die Eintraege (TSourcePlaces.UsesEntries, in
  // Quelltext-Reihenfolge) und die Zeile des Schluesselworts 'uses'.
  TRdxUsesClause = record
    Entries  : TArray<TRefactorSpan>;
    UsesLine : Integer;
  end;

  // Die Planer an Strukturen ueber mehrere Token oder Zeilen (SCA007,
  // SCA168, SCA101/SCA099): reine Textlogik auf der Code-Sicht. Ihre
  // geteilten Bausteine - beginnt an einem Token eine Anweisung, wem gehoert
  // ein else (StartsStatement, ElseBelongsToIf, ElseOwner, FindOwner) -
  // stehen seit der Folgewelle des Wochen-Reviews (G07-13) in uRdxCodeMap;
  // bis dahin banden uRdxFlowFixes und uRdxRaiseFixes dafuer diese Unit
  // ein (StartsStatementAt, ElseBelongsToIf). Die uses-Eintraege,
  // die FPC-Weiche und die uses-Ergaenzung fuer EInvalidOpException liefert
  // bzw. prueft der Aufrufer (uRdxFixRunner: TRdxFixRunner.UnusedUsesFix
  // bzw. CaseRaiseFix).
  TRdxStructFixes = class
  public
    // SCA007: den Eintrag AIndex der Klausel loeschen. Vor dem letzten
    // Eintrag: bis zum Anfang des naechsten (Name, 'in'-Pfad, Komma,
    // Leerraum) - steht er allein auf seiner Zeile, die ganze Zeile samt
    // '//'-Kommentar; steht er als letzter seiner Zeile hinter einem
    // anderen, ab dem Komma davor bis zum Zeilenende (rwE29: sonst kaeme
    // die Folgezeile herauf); der letzte: ab dem Komma davor bis vor das ';'; der
    // einzige: die ganze Klausel ab 'uses' bis hinter ';' - ganze Zeilen,
    // wenn sie allein stehen. Kein Kommentar und keine Direktive im
    // Bereich, und darin steht genau dieser Eintrag mit einem Trenner (ein
    // Eintrag, den UsesEntries ausliess, ginge sonst mit).
    class function RemoveUsesEntry(AMap: TRdxCodeMap;
      const AClause: TRdxUsesClause; AIndex: Integer; out AEdit: TRdxEdit;
      out AReason: string): Boolean; static;

    // SCA007, Bezeichner-Beweis (Nico 2026-10-29, Realworld-Test rwE30
    // Stufe 2: 21 Fehler, alle auf Funden, deren Unit doch gebraucht wurde -
    // mrOk, crHourGlass, fsBold, TShortCut, CN_NOTIFY ... stehen in keiner
    // Bezeichnerliste des Detektors): der erste Bezeichner der Datei im Stil
    // einer Bibliothek, den der Planer keiner Quelle zuordnen kann - '' heisst
    // "Beweis vollstaendig", sonst steht die Hilfe nur im Menue
    // (TRdxFixOutcome.MenuOnly). Im Stil einer Bibliothek: ein Typ (T, I oder
    // E, dann ein Grossbuchstabe: TShortCut, ITaskbarList), ein
    // Aufzaehlungswert (zwei oder drei Kleinbuchstaben, dann ein
    // Grossbuchstabe: mrOk, clNone, akLeft), eine Konstante (GROSS_..:
    // CM_MOUSEENTER, CSIDL_PERSONAL) oder ein Aufruf eines gross beginnenden
    // Namens (InRange(..), ValidParentForm(..)). Zugeordnet ist er, wenn die
    // Datei ihn deklariert (Typ, Konstante, Variable, Feld, Parameter,
    // Routine, Property, Aufzaehlungswert - eine Textregel, s. ScanDecls), ihn
    // AKnown nennt (die bekannten Bezeichner der UEBRIGEN uses-Eintraege,
    // klein; der Aufrufer fragt den Detektor) oder er aus System kommt
    // (SYSTEM_NAMES). Nicht gefragt: Member hinter '.', die uses-Klauseln,
    // Kommentare und Strings. GRENZE: Namen ohne diesen Stil (Screen, Mouse,
    // Application) prueft die Regel nicht - sie stehen meist in den Listen
    // des Detektors. ALine: die Zeile des Bezeichners.
    class function ForeignIdent(AMap: TRdxCodeMap;
      const AKnown: TArray<string>; out ALine: Integer): string; static;

    // SCA007 (rwE30 Stufe 2, Fragwuerdig Indy indyprotocolsfpc.pas:189):
    // besteht die Unit nur aus ihrem Kopf und uses-Klauseln - kein Typ,
    // keine Routine, kein Code? Dann ist die uses-Liste ihr Zweck (die
    // Sammel-Unit eines Lazarus-Pakets uebersetzt so die gelisteten Units);
    // ein Eintrag weniger nimmt die Unit aus dem Bau.
    class function UsesOnlyUnit(AMap: TRdxCodeMap): Boolean; static;

    // SCA007 (rwE31 Stufe 3, CEF4Delphi uChildForm.pas:10,
    // uCEFWindowDelegate.pas:16 ...): der Eintrag AUnit auf ALine aus dem
    // TEXT der uses-Klauseln - fuer einen Eintrag, den
    // TSourcePlaces.UsesEntries nicht liefert. Der Dienst parst mit der
    // Ein-Zweig-Sicht der IDE-Funde (MSWINDOWS, WIN64 ...) ohne die Defines
    // aus Include-Dateien: '{$I cef.inc}' definiert DELPHI16_UP, der Dienst
    // nimmt den {$ELSE}-Zweig, der Fund steht im {$IFDEF}-Zweig - bis dahin
    // "steht nicht mehr auf Zeile 10" (falsch). Der Token-Leser sieht keine
    // Direktiven: eine Klausel ist hier die Folge ALLER Zweige (wie die
    // Doppelzweig-Sicht). RemoveUsesEntry braucht davon nur die Nachbarn des
    // Eintrags; ein Bereich ueber eine Direktive sperrt RangeReason weiter.
    // Eine Klausel, deren Folge nicht 'Name [in], Name [in] .. ;' ist (Zweige
    // mit eigener Kommafolge: '{$IFDEF X} A, B {$ELSE} C {$ENDIF};'), zaehlt
    // nicht. Ergebnis: die Zahl der Treffer (Name gleich, erstes Zeichen auf
    // ALine); bei genau einem die Klausel und der Index.
    class function TextUsesEntry(AMap: TRdxCodeMap; ALine: Integer;
      const AUnit: string; out AClause: TRdxUsesClause;
      out AIndex: Integer): Integer; static;

    // SCA007, Bezeichner-Beweis (rwE31 Stufe 3, Todo_SCA007 "nur-menue-
    // unnoetig": gexperts mPasLex.pas:80 UpperCase, vcl-styles-utils
    // Main.pas:6 IntToStr, issrc BidiUtils.pas:15 TRect): bekannte Exporte
    // der Units, die der Detektor nie meldet (IsAlwaysNeeded) und fuer die er
    // darum keine Liste fuehrt - SysUtils und Types (auch System.-Namen),
    // klein; sonst leer. Nur Namen, die Delphi 13 (Studio 37.0) UND FPC
    // 3.2.2 im interface-Teil fuehren (gegen beide Quellen geprueft): steht
    // die Unit in den uses, kommt der Name aus ihr, nicht aus der entfernten.
    class function AlwaysNeededIdents(const AUnitLow: string): TArray<string>;
      static;

    // SCA168: ein else vor das end des case-Statements auf Zeile ALine
    // (genau ein 'case' im Code der Zeile). AStatement = '': leer ('else'
    // vor 'end', bedeutungsgleich); sonst diese Anweisung im else-Zweig
    // (RAISE_UNHANDLED), eingerueckt wie die Arme. Das end findet ein
    // Token-Lauf (begin/case/try/asm/record zaehlen hoch, end herunter;
    // '&End' und '@@End' nicht). Endet der letzte Arm nicht auf ';', kommt
    // als zweite Ersetzung ein ';' dahinter - sonst bande das else an ein
    // offenes if ('1: if B then DoA' + 'else'). Keine Hilfe bei einer
    // Direktive zwischen case und end, bei einem else oder (FPC) otherwise
    // hinter ';', bei einem case ohne Zweige und bei einem case, das keine
    // Anweisung ist - im Variantenteil eines Records (CaseContextReason).
    class function CaseElse(AMap: TRdxCodeMap; ALine: Integer;
      const AStatement: string; out AEdits: TArray<TRdxEdit>;
      out AReason: string): Boolean; static;

    // SCA168, raise-Variante (rwE31 Stufe 3: vier Fehler - das raise traf
    // Werte ohne Arm, die dort Normalfall sind: aaFailed in abziptyp.pas,
    // mDELETE in mormot.orm.mongodb.pas, oftID im aeusseren Arm von
    // mormot.orm.core.pas): in die Gluehbirne nur, wenn die Arme des case
    // auf ALine JEDEN Wert eines Aufzaehlungstyps nennen, den diese Datei
    // oder - seit rwE32 Stufe 4 - eine Unit ihrer uses-Klauseln neben ihr
    // (AUnitFile, TRdxTypeProof.NeighbourInterfaces) deklariert ('T = (a, b,
    // c)', ohne eigene Zahlen, genau einmal), oder False und True. Dann
    // erreicht das else nur ein Wert ausserhalb des Typs, und raise sichert
    // nur ab. Sonst - eine andere Marke als Namen, der Typ nicht gefunden,
    // ein Wert ohne Arm, eine Direktive im case oder in der Werteliste, ein
    // Selektor, der eine Zahl in den Typ umwandelt ('TKind(Combo.ItemIndex)',
    // Review e/HilfeFixR) - der Grund, warum die Variante nur im Menue steht (TRdxFixOutcome.MenuOnly,
    // uRdxFixRunner.CaseRaiseFix). Nico-Entscheid E5 (rwE32 Stufe 4):
    // ALockReason <> '' sperrt die Variante ganz (das Ergebnis traegt dann
    // denselben Grund) - der Selektor ist keine Aufzaehlung (sein Typ eine
    // Zahl, ein Zeichen oder String; Zahlen oder Konstanten der Datei bzw.
    // einer Unit daneben als Marken), oder das Ergebnis ist vor dem case
    // vorbelegt und nicht jeder Wert hat einen Arm. Ruft der Aufrufer nach
    // einem erfolgreichen CaseElse.
    class function CaseRaiseMenuReason(AMap: TRdxCodeMap; ALine: Integer;
      const AUnitFile: string; out ALockReason: string): string; static;

    // SCA101: das then, else oder do, das an (ALine, ACol) beginnt - die
    // Spalte aus der Meldung.
    class function BranchKeywordAt(AMap: TRdxCodeMap; ALine, ACol: Integer;
      out AKeyword: TRdxToken; out AReason: string): Boolean; static;

    // SCA099: das else hinter dem einen 'end else' auf ALine (das else darf
    // auf einer Folgezeile stehen).
    class function ElseAfterEndOn(AMap: TRdxCodeMap; ALine: Integer;
      out AKeyword: TRdxToken; out AReason: string): Boolean; static;

    // SCA101 und SCA099: die Anweisung hinter AKeyword (then, else, do) in
    // begin..end setzen - bedeutungsgleich. Sie endet mit ';' (das bleibt
    // in ihr, das end bekommt eines) oder vor else/end/until/except/finally
    // (sie bekommt ein ';', das end keines). Hinter dem else eines case
    // oder except steht eine Anweisungsliste: dann alles bis vor dessen end.
    // Form: endet die Zeile des Schluesselworts mit ihm und die letzte Zeile
    // der Anweisung mit ihr, kommen begin und end in eigene Zeilen
    // (eingerueckt wie die Zeile des if/for/while/with/on bzw. des else);
    // steht die Anweisung ganz auf der Zeile des Schluesselworts, kommt sie
    // eine Stufe tiefer in eine eigene Zeile; sonst inline. Keine Hilfe bei
    // einem bedingten Ausdruck (Delphi 13: 'X := if A then B else C'), bei
    // Struktur, anonymer Methode oder Inline-Deklaration in der Anweisung,
    // bei einer Direktive im Bereich, bei schon vorhandenem begin und bei
    // einer leeren Anweisung.
    class function WrapInBlock(AMap: TRdxCodeMap; const AKeyword: TRdxToken;
      out AEdits: TArray<TRdxEdit>; out AReason: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,                // TStringList (Units neben der Datei, SCA168.2)
  System.Generics.Collections,   // TDictionary (ForeignIdent)
  uRdxBlocks, // TypeHasBody (ForeignIdent: Typ mit Rumpf)
  uRdxRaiseFixes, // OldExceptionClassReason (SCA168 raise, rwE31 Stufe 3)
  uRdxTypeProof,  // Selektor-Typ, Units neben der Datei (SCA168.2, rwE32 E5)
  uRdxText;   // _() und die gemeinsamen Texte der Gruende (Entscheid E29)

const
  SPAN_007 = 'sca007';
  SPAN_168 = 'sca168';
  SPAN_101 = 'sca101';
  // Die Klasse in RAISE_UNHANDLED (OldExceptionClassReason).
  CLASS_UNHANDLED = 'EInvalidOpException';
  // Die Zweigwoerter (BRANCH_WORDS) und die Token, vor denen eine
  // Anweisung ohne ';' endet (STATEMENT_STOPS), stehen in uRdxCodeMap - bis
  // zur Folgewelle des Wochen-Reviews hier als BRANCH_KEYWORDS und
  // BRANCH_STOPPERS.
  // In der einfachen Anweisung hinter then/else/do gesperrt: eine Struktur
  // (ihr Ende sucht die Hilfe nicht), ein bedingter Ausdruck (Delphi 13),
  // eine anonyme Methode (ihr Rumpf traegt ';') und eine Inline-
  // Deklaration (begin..end engte ihren Gueltigkeitsbereich ein).
  NOT_IN_BRANCH: array[0..16] of string = ('if', 'then', 'do', 'of',
    'begin', 'case', 'try', 'asm', 'record', 'repeat', 'while', 'for',
    'with', 'procedure', 'function', 'var', 'const');
  // In einer Anweisungsliste (else eines case/except) gesperrt:
  // uRdxCodeMap.INLINE_DECLS (bis zur Hygiene-Welle H1 hier kopiert).
  // Die Besitzer eines do (StatementOwner); die eines then (IF_OWNERS) und
  // die Listen der Rueckwaerts-Suchen stehen bei FindOwner/ElseOwner in
  // uRdxCodeMap.
  DO_OWNERS: array[0..3] of string = ('for', 'while', 'with', 'on');
  // Hinter 'end else' meldet uIfElseBegin diese Woerter nicht.
  SCA099_ALLOWED: array[0..7] of string = ('begin', 'if', 'case', 'try',
    'for', 'while', 'repeat', 'with');
  // Rueckwaerts vor einem case auf oberster Ebene: hier beginnt der
  // Abschnitt einer Unit, in dem Anweisungen stehen (CaseContextReason;
  // begin/try/repeat/asm/case zaehlen als Block).
  STATEMENT_SECTIONS: array[0..1] of string = ('initialization',
    'finalization');
  // Gruende (Entscheid E29): englische msgids, uebersetzt an der Verwendung
  // mit _() - de/fr in i18n/*.po (Block G8). Die uebrigen Gruende stehen
  // als Literal in _() an ihrer einzigen Stelle. R_BRANCH ist der Satz OHNE
  // das gemeinsame Ende ' - Zeile verschoben? ...' - das haengt
  // MsgMovedSuffix an (uRdxText). Der Wortlaut von R_CASE_IN_RECORD bleibt
  // eine eigene Variante ('(Fund verschoben? ...)' in Klammern) - die
  // Umstellung vereinheitlicht keine Wortlaute. Die Gruende von FindOwner
  // und ElseOwner stehen seit der Folgewelle des Wochen-Reviews mit ihnen
  // in uRdxCodeMap (Scan.Reason kommt von dort).
  R_CASE_IN_RECORD = 'the case is in the variant part of a record - not a '
    + 'case statement (finding moved? Analyse the file again)';
  R_CASE_OPEN_PAREN = 'there is a compiler directive between an open ( and '
    + 'the case - a branch can leave the parenthesis open, so it is unclear '
    + 'whether the case is a statement';
  R_BRANCH = 'no then/else/do at the reported place';
  // SCA007, Bezeichner-Beweis (ForeignIdent, ScanDecls). Davor steht ein
  // Name, den die Datei deklariert ...
  NAMING_WORDS: array[0..5] of string = ('procedure', 'function',
    'constructor', 'destructor', 'property', 'operator');
  UNIT_HEADS: array[0..3] of string = ('unit', 'program', 'library',
    'package');
  // ... davor beginnt im Anweisungsteil eine Liste 'A, B: T' (Inline-
  // Variable, 'on E: Exception') ...
  INLINE_DECL_PREV: array[0..4] of string = ('var', 'const', 'out', 'on',
    'threadvar');
  // ... davor beginnt im Deklarationsteil 'Name = ..' (Typ, Konstante).
  EQ_DECL_PREV: array[0..9] of string = (';', 'type', 'const',
    'resourcestring', ']', 'private', 'protected', 'public', 'published',
    'strict');
  // Typen mit Rumpf und end, wenn davor '=' bzw. 'packed' steht.
  BODY_TYPES: array[0..3] of string = ('class', 'object', 'interface',
    'dispinterface');
  BODY_TYPE_PREV: array[0..1] of string = ('=', 'packed');
  STMT_OPENERS: array[0..2] of string = ('begin', 'try', 'asm');
  // Der Stapel der offenen Bloecke (ScanDecls): Anweisungsteil, record, Typ.
  BLOCK_STMT   = 's';
  BLOCK_RECORD = 'r';
  BLOCK_TYPE   = 'd';
  // Aus System (und Compiler-Magie), klein: was die Stil-Regeln von
  // ForeignIdent trifft und nie aus einer uses-Unit kommt - Typen, Routinen,
  // die eingebauten Typen als Umwandlung ('Integer(X)').
  SYSTEM_NAMES: array[0..136] of string = ('tobject', 'tclass', 'tguid',
    'tdatetime', 'tdate', 'ttime', 'tvarrec', 'tarray', 'tmethod',
    'tinterfacedobject', 'iinterface', 'iunknown', 'iinvokable', 'idispatch',
    'tinterfacedclass', 'tvardata', 'tcustomattribute', 'tmonitor', 'tbytes',
    'tfilerec', 'ttextrec', 'tthreadid', 'ioresult', 'tboundarray',
    'tptrwrapper', 'ienumerable', 'ienumerator', 'assigned', 'length',
    'setlength', 'high', 'low', 'inc', 'dec', 'ord', 'chr', 'succ', 'pred',
    'sizeof', 'typeinfo', 'copy', 'delete', 'insert', 'pos', 'trunc',
    'round', 'abs', 'sqr', 'sqrt', 'exit', 'halt', 'new', 'dispose', 'getmem',
    'freemem', 'reallocmem', 'fillchar', 'move', 'include', 'exclude', 'odd',
    'swap', 'lo', 'hi', 'ptr', 'addr', 'val', 'str', 'random', 'randomize',
    'assert', 'concat', 'upcase', 'writeln', 'write', 'readln', 'read',
    'assign', 'assignfile', 'reset', 'rewrite', 'append', 'closefile', 'eof',
    'eoln', 'blockread', 'blockwrite', 'seek', 'filepos', 'filesize',
    'finalize', 'initialize', 'default', 'typeof', 'paramstr', 'paramcount',
    'int', 'frac', 'exp', 'ln', 'sin', 'cos', 'arctan', 'uniquestring',
    'stringofchar', 'setstring', 'slice', 'integer', 'cardinal', 'byte',
    'word', 'longint', 'longword', 'shortint', 'smallint', 'int64', 'uint64',
    'nativeint', 'nativeuint', 'boolean', 'char', 'ansichar', 'widechar',
    'ansistring', 'widestring', 'unicodestring', 'shortstring', 'pointer',
    'pchar', 'pansichar', 'pwidechar', 'single', 'double', 'extended',
    'currency', 'variant', 'olevariant');
  // Exporte von SysUtils bzw. Types (AlwaysNeededIdents): Routinen, Typen,
  // Exceptions und Aufzaehlungswerte im Stil, den ForeignIdent prueft - je in
  // System.SysUtils.pas/System.Types.pas von Delphi 13 und in sysutils
  // (objpas/sysutils/*h.inc, win/sysutils.pp)/types.pp von FPC 3.2.2.
  SYSUTILS_NAMES: array[0..190] of string = ('inttostr', 'strtoint',
    'strtointdef', 'trystrtoint', 'strtoint64', 'strtoint64def', 'inttohex',
    'format', 'formatfloat', 'floattostr', 'strtofloat', 'strtofloatdef',
    'trystrtofloat', 'floattostrf', 'currtostr', 'strtocurr', 'booltostr',
    'strtobool', 'trim', 'trimleft', 'trimright', 'uppercase', 'lowercase',
    'comparetext', 'comparestr', 'sametext', 'samestr', 'quotedstr',
    'ansiquotedstr', 'ansiuppercase', 'ansilowercase', 'ansicomparetext',
    'ansicomparestr', 'ansisametext', 'ansisamestr', 'ansipos',
    'stringreplace', 'wraptext', 'adjustlinebreaks', 'lastdelimiter',
    'isdelimiter', 'ispathdelimiter', 'extractfilepath', 'extractfilename',
    'extractfileext', 'extractfiledir', 'extractfiledrive', 'changefileext',
    'expandfilename', 'extractrelativepath', 'includetrailingpathdelimiter',
    'excludetrailingpathdelimiter', 'includetrailingbackslash',
    'excludetrailingbackslash', 'fileexists', 'directoryexists',
    'forcedirectories', 'createdir', 'removedir', 'deletefile', 'renamefile',
    'fileage', 'filegetattr', 'filesetattr', 'getcurrentdir', 'setcurrentdir',
    'fileopen', 'filecreate', 'fileread', 'filewrite', 'fileclose', 'fileseek',
    'findfirst', 'findnext', 'findclose', 'filesearch', 'diskfree', 'disksize',
    'now', 'date', 'time', 'datetostr', 'timetostr', 'datetimetostr',
    'strtodate', 'strtotime', 'strtodatetime', 'formatdatetime', 'encodedate',
    'decodedate', 'encodetime', 'decodetime', 'dayofweek', 'isleapyear',
    'incmonth', 'tryencodedate', 'tryencodetime', 'datetimetofiledate',
    'filedatetodatetime', 'abort', 'freeandnil', 'supports', 'strpas',
    'strpcopy', 'strlen', 'strcopy', 'strcomp', 'strlcomp', 'stricomp',
    'strend', 'strscan', 'strpos', 'stralloc', 'strdispose', 'strlcopy',
    'strcat', 'strnew', 'comparemem', 'syserrormessage', 'raiselastoserror',
    'beep', 'sleep', 'showexception', 'outofmemoryerror', 'charinset',
    'exceptionerrormessage', 'tformatsettings', 'tsearchrec', 'tsyscharset',
    'tfilename', 'treplaceflags', 'tfloatformat', 'ttimestamp', 'eabort',
    'eaccessviolation', 'econverterror', 'eoutofmemory', 'einouterror',
    'einterror', 'edivbyzero', 'erangeerror', 'eintoverflow', 'ematherror',
    'einvalidop', 'ezerodivide', 'eoverflow', 'eunderflow', 'einvalidpointer',
    'einvalidcast', 'evarianterror', 'eexternal', 'eexternalexception',
    'eoserror', 'estackoverflow', 'eprivilege', 'eintfcasterror',
    'eheapexception', 'eassertionfailed', 'epropreadonly', 'epropwriteonly',
    'eabstracterror', 'esafecallexception', 'eargumentexception',
    'eargumentoutofrangeexception', 'enotimplemented',
    'enotsupportedexception', 'einvalidopexception', 'efilenotfoundexception',
    'edirectorynotfoundexception', 'epathtoolongexception',
    'eargumentnilexception', 'fmopenread', 'fmopenwrite', 'fmopenreadwrite',
    'fmsharedenynone', 'fmsharedenywrite', 'fmshareexclusive',
    'fmsharedenyread', 'faanyfile', 'fadirectory', 'fareadonly', 'fahidden',
    'fasysfile', 'faarchive', 'rfreplaceall', 'rfignorecase', 'ffgeneral',
    'fffixed', 'ffnumber', 'ffexponent', 'ffcurrency');
  TYPES_NAMES: array[0..19] of string = ('trect', 'tpoint', 'tsize',
    'tsmallpoint', 'tpointf', 'trectf', 'rect', 'point', 'bounds', 'ptinrect',
    'intersectrect', 'unionrect', 'offsetrect', 'isrectempty', 'equalrect',
    'centerpoint', 'tduplicates', 'dupignore', 'dupaccept', 'duperror');

type
  // Code-Token eines Bereichs nach Art (CountRangeTokens).
  TRangeTokens = record
    Words  : Integer;   // ohne 'in' und 'uses'
    Dots   : Integer;
    Commas : Integer;
    Semis  : Integer;
    Others : Integer;
  end;

  // Die Anweisung hinter then/else/do (WrapInBlock).
  TRdxBranch = record
    Keyword  : TRdxToken;
    First    : TRdxToken;   // ihr erstes Token
    Stop     : TRdxToken;   // ohne ';': das Token dahinter (else, end ...)
    LastLine : Integer;     // ihr letztes Zeichen aus Code oder String -
    LastCol  : Integer;     //   bei HasSemi das ';'
    HasSemi  : Boolean;
    IsList   : Boolean;     // else eines case/except: Liste bis vor das end
    Indent   : string;      // fuer begin und end
    // Erste Zeile der Direktiven-Pruefung: die des Schluesselworts, beim
    // else die des Tokens, das seinen Besitzer entschied (then, of, except).
    CheckFrom : Integer;
  end;

{ ---- SCA007 ---- }

// Das Token hinter dem uses-Eintrag: ',' oder ';' - ein 'in'-Pfad
// dazwischen ('X in ''x.pas''') wird uebersprungen (Strings sieht der
// Token-Leser nicht).
function SeparatorAfter(AMap: TRdxCodeMap; const AEntry: TRefactorSpan): TRdxToken;
begin
  Result := NextToken(AMap, AEntry.EndLine, AEntry.EndCol);
  if Result.Low = 'in' then
    Result := After(AMap, Result);
end;

// Steht hinter ASemi auf seiner Zeile nur Leerraum oder ein '//'-Kommentar
// ohne Marker (MarkerReason: noinspection, Absichtsmarker - ein
// '// noinspection X' hinter Code gilt der naechsten Zeile und bleibt)?
function TailFreeAfter(AMap: TRdxCodeMap; const ASemi: TRdxToken): Boolean;
var
  L    : string;
  Rest : Integer;
begin
  L := AMap.Raw(ASemi.Line);
  Rest := SkipBlanks(L, ASemi.EndCol);
  Result := (Rest > Length(L))
    or ((Rest = AMap.LineCommentCol(ASemi.Line))
        and (MarkerReason(Copy(L, Rest, MaxInt)) = ''));
end;

// Der einzige Eintrag: die ganze Klausel ab 'uses' (auf Zeile AUsesLine)
// bis hinter ASemi; ACheck ist der Teil, in dem kein Kommentar stehen darf
// ('uses' bis ';'). Folgt ';' nur Leerraum oder ein '//'-Kommentar ohne
// Marker (TailFreeAfter): steht 'uses' am Zeilenanfang, ganze Zeilen - der
// Kommentar beschrieb den Eintrag (bis zur Review Woche G07-23 blieb er
// als Zeile ' // x' stehen); steht davor Code, geht der Leerraum vor
// 'uses' mit ('interface uses A;' -> 'interface', bis dahin 'interface ').
// '' oder der Grund.
function WholeClauseSpan(AMap: TRdxCodeMap; AUsesLine: Integer;
  const ASemi: TRdxToken; out ASpan, ACheck: TRefactorSpan): string;
var
  T   : TRdxToken;
  L   : string;
  Col : Integer;
begin
  Result := '';
  ASpan := Default(TRefactorSpan);
  ACheck := Default(TRefactorSpan);
  T := NextToken(AMap, AUsesLine, 1);
  while (T.Low <> '') and (T.Line = AUsesLine) and (T.Low <> 'uses') do
    T := After(AMap, T);
  if (T.Low <> 'uses') or (T.Line <> AUsesLine) then
    Exit(_('the keyword uses is not on the expected line'));
  ACheck := TRefactorSpan.Make(SPAN_007, T.Line, T.Col, ASemi.Line,
    ASemi.EndCol);
  ASpan := ACheck;
  if not TailFreeAfter(AMap, ASemi) then Exit;
  L := AMap.Raw(T.Line);
  if SkipBlanks(L, 1) = T.Col then
  begin
    if ASemi.Line < AMap.LineCount then
      ASpan := TRefactorSpan.Make(SPAN_007, T.Line, 1, ASemi.Line + 1, 1);
    Exit;
  end;
  Col := T.Col;
  while (Col > 1) and IsBlank(L[Col - 1]) do
    Dec(Col);
  ASpan := TRefactorSpan.Make(SPAN_007, T.Line, Col, ASemi.Line, ASemi.EndCol);
end;

// Der zu loeschende Bereich des Eintrags AIndex (s. RemoveUsesEntry) und
// der Teil davon, in dem kein Kommentar stehen darf (ACheck - nur beim
// einzigen Eintrag kleiner, WholeClauseSpan); ASep ist das Token hinter
// ihm. '' oder der Grund. GRENZE (Review Woche G07-23 c): im Stil 'Komma
// voran' ('  A' / '  , C;') bleibt beim letzten Eintrag '  ;' als eigene
// Zeile - der Schnitt muesste auf dem letzten Zeichen von A beginnen
// (SpanFits) und es neu schreiben; uebersetzt, nur ein Schoenheitsfehler.
function EntrySpan(AMap: TRdxCodeMap; const AClause: TRdxUsesClause;
  AIndex: Integer; const ASep: TRdxToken;
  out ASpan, ACheck: TRefactorSpan): string;
var
  E    : TArray<TRefactorSpan>;
  Prev : TRdxToken;
begin
  Result := '';
  ASpan := Default(TRefactorSpan);
  ACheck := Default(TRefactorSpan);
  E := AClause.Entries;
  if Length(E) = 1 then
  begin
    if ASep.Low <> ';' then
      Exit(_('no ";" after the only entry'));
    Exit(WholeClauseSpan(AMap, AClause.UsesLine, ASep, ASpan, ACheck));
  end;
  if AIndex < High(E) then
  begin
    if ASep.Low <> ',' then
      Exit(_('no "," after the entry'));
    ASpan := TRefactorSpan.Make(SPAN_007, E[AIndex].StartLine,
      E[AIndex].StartCol, E[AIndex + 1].StartLine, E[AIndex + 1].StartCol);
    ACheck := ASpan;
    Exit;
  end;
  Prev := SeparatorAfter(AMap, E[AIndex - 1]);
  if (Prev.Low <> ',') or (ASep.Low <> ';') then
    Exit(_('comma before or semicolon after the last entry not found'));
  ASpan := TRefactorSpan.Make(SPAN_007, Prev.Line, Prev.Col, ASep.Line, ASep.Col);
  ACheck := ASpan;
end;

// Steht der Eintrag allein auf seiner Zeile - davor nur Leerraum, dahinter
// sein ',' und hoechstens ein '//'-Kommentar (Stil 'System.Classes,
// // Grund')?
function OwnLine(AMap: TRdxCodeMap; const AEntry: TRefactorSpan;
  const ASep: TRdxToken): Boolean;
var
  L    : string;
  Rest : Integer;
begin
  L := AMap.Raw(AEntry.StartLine);
  Rest := SkipBlanks(L, ASep.EndCol);
  Result := (SkipBlanks(L, 1) = AEntry.StartCol) and (ASep.Low = ',')
    and (ASep.Line = AEntry.StartLine) and (AEntry.StartLine < AMap.LineCount)
    and ((Rest > Length(L)) or (Rest = AMap.LineCommentCol(AEntry.StartLine)));
end;

// Steht der Eintrag AIndex (weder der erste noch der letzte der Klausel)
// als letzter auf seiner Zeile hinter einem anderen - davor auf derselben
// Zeile das ',' des vorigen Eintrags, dahinter sein ',' und nur Leerraum,
// der naechste Eintrag auf einer spaeteren Zeile (Stil 'A, B,' / '  C;')?
// Dann geht er ab dem Komma des vorigen bis zum Zeilenende ('A, B,' ->
// 'A,'). Der Schnitt bis vor den naechsten Eintrag zoege sonst die
// Folgezeile samt Einrueckung herauf (rwE29, delphimvcframework
// MainFormU.pas:30: 'System.Classes, Vcl.Graphics,' + '  Vcl.Controls, ...'
// wurde eine Zeile von ~150 Zeichen).
function LineEndSpan(AMap: TRdxCodeMap; const AClause: TRdxUsesClause;
  AIndex: Integer; const ASep: TRdxToken; out ASpan: TRefactorSpan): Boolean;
var
  E    : TArray<TRefactorSpan>;
  Prev : TRdxToken;
  L    : string;
begin
  Result := False;
  ASpan := Default(TRefactorSpan);
  E := AClause.Entries;
  if (AIndex < 1) or (AIndex >= High(E)) then Exit;
  if (ASep.Low <> ',') or (ASep.Line <> E[AIndex].StartLine)
     or (E[AIndex + 1].StartLine <= ASep.Line) then Exit;
  L := AMap.Raw(ASep.Line);
  if SkipBlanks(L, ASep.EndCol) <= Length(L) then Exit;
  Prev := SeparatorAfter(AMap, E[AIndex - 1]);
  if (Prev.Low <> ',') or (Prev.Line <> ASep.Line) then Exit;
  ASpan := TRefactorSpan.Make(SPAN_007, Prev.Line, Prev.EndCol, ASep.Line,
    Length(L) + 1);
  Result := True;
end;

// Die Code-Token im Bereich nach Art gezaehlt (Strings und Kommentare
// sieht der Token-Leser nicht).
function CountRangeTokens(AMap: TRdxCodeMap;
  const ASpan: TRefactorSpan): TRangeTokens;
var
  T : TRdxToken;
begin
  Result := Default(TRangeTokens);
  T := NextToken(AMap, ASpan.StartLine, ASpan.StartCol);
  while (T.Low <> '') and ((T.Line < ASpan.EndLine)
     or ((T.Line = ASpan.EndLine) and (T.Col < ASpan.EndCol))) do
  begin
    if T.Low = '.' then
      Inc(Result.Dots)
    else if T.Low = ',' then
      Inc(Result.Commas)
    else if T.Low = ';' then
      Inc(Result.Semis)
    else if not T.IsWord then
      Inc(Result.Others)
    else if (T.Low <> 'in') and (T.Low <> 'uses') then
      Inc(Result.Words);
    T := After(AMap, T);
  end;
end;

// Darf ASpan geloescht werden? Kein Kommentar und keine Direktive in
// ACheck, und in ASpan steht genau der Eintrag AName (seine Namensteile)
// mit einem Trenner. '' oder der Grund.
function RangeReason(AMap: TRdxCodeMap; const ASpan, ACheck: TRefactorSpan;
  const AName: string): string;
var
  C        : TRangeTokens;
  Parts, i : Integer;
begin
  Result := '';
  if CommentInRange(AMap, ACheck) then
    Exit(_('comment or directive in the range to be deleted'));
  Parts := 1;
  for i := 1 to Length(AName) do
    if AName[i] = '.' then
      Inc(Parts);
  C := CountRangeTokens(AMap, ASpan);
  if (C.Words <> Parts) or (C.Dots <> Parts - 1) or (C.Others <> 0)
     or (C.Commas + C.Semis <> 1) then
    Result := _('the range contains more than this entry - would another '
      + 'one be deleted with it? Analyse the file again');
end;

class function TRdxStructFixes.RemoveUsesEntry(AMap: TRdxCodeMap;
  const AClause: TRdxUsesClause; AIndex: Integer; out AEdit: TRdxEdit;
  out AReason: string): Boolean;
var
  E           : TRefactorSpan;
  Sep         : TRdxToken;
  Span, Check : TRefactorSpan;
  LineEnd     : TRefactorSpan;   // eigene Variable: LineEndSpan setzt sein
                                 // out-Argument auch bei False zurueck
begin
  Result := False;
  AEdit := Default(TRdxEdit);
  if (AIndex < 0) or (AIndex > High(AClause.Entries)) then
  begin
    AReason := _('no such uses entry');
    Exit;
  end;
  E := AClause.Entries[AIndex];
  Sep := SeparatorAfter(AMap, E);
  AReason := EntrySpan(AMap, AClause, AIndex, Sep, Span, Check);
  if AReason <> '' then Exit;
  if (AIndex < High(AClause.Entries)) and OwnLine(AMap, E, Sep) then
  begin
    Span := TRefactorSpan.Make(SPAN_007, E.StartLine, 1, E.StartLine + 1, 1);
    Check := TRefactorSpan.Make(SPAN_007, E.StartLine, 1, E.StartLine,
      Sep.EndCol);
  end
  else if LineEndSpan(AMap, AClause, AIndex, Sep, LineEnd) then
  begin
    Span := LineEnd;
    Check := LineEnd;
  end;
  AReason := RangeReason(AMap, Span, Check, E.Resolved);
  if AReason <> '' then Exit;
  AEdit.Span := Span;
  AEdit.Expected := RangeText(AMap, Span);
  AEdit.NewText := '';
  Result := True;
end;

{ ---- SCA007: Bezeichner-Beweis (ForeignIdent) ---- }

// Alle Code-Token der Datei der Reihe nach (Strings und Kommentare sieht der
// Token-Leser nicht).
function AllCodeTokens(AMap: TRdxCodeMap): TArray<TRdxToken>;
var
  T : TRdxToken;
  n : Integer;
begin
  SetLength(Result, 256);
  n := 0;
  T := NextToken(AMap, 1, 1);
  while T.Low <> '' do
  begin
    if n = Length(Result) then
      SetLength(Result, 2 * n);
    Result[n] := T;
    Inc(n);
    T := After(AMap, T);
  end;
  SetLength(Result, n);
end;

// Low des Tokens Nummer AIndex; '' ausserhalb.
function LowOf(const AToks: TArray<TRdxToken>; AIndex: Integer): string;
begin
  if (AIndex < 0) or (AIndex > High(AToks)) then
    Result := ''
  else
    Result := AToks[AIndex].Low;
end;

// Ein Wort, das die Datei als Schluesselwort liest: reserviert und nicht
// hinter '&', '@' oder '.'.
function ReservedAt(const AToks: TArray<TRdxToken>; AIndex: Integer): Boolean;
begin
  Result := AToks[AIndex].IsWord and InList(AToks[AIndex].Low, RESERVED)
    and not InList(LowOf(AToks, AIndex - 1), IDENT_PREFIXES);
end;

// Die Aufzaehlungswerte '(a, b, c)' ab der '(' Nummer AOpen als deklariert.
procedure AddEnumValues(const AToks: TArray<TRdxToken>; AOpen: Integer;
  ADecl: TDictionary<string, Boolean>);
var
  j, Depth : Integer;
begin
  Depth := 1;
  j := AOpen + 1;
  while (j <= High(AToks)) and (Depth > 0) do
  begin
    if AToks[j].Low = '(' then
      Inc(Depth)
    else if AToks[j].Low = ')' then
      Dec(Depth)
    else if (Depth = 1) and AToks[j].IsWord
       and ((LowOf(AToks, j - 1) = '(') or (LowOf(AToks, j - 1) = ',')) then
      ADecl.AddOrSetValue(AToks[j].Low, True);
    Inc(j);
  end;
end;

// Eine Liste 'A, B: T' ab dem Wort Nummer k: True, wenn hinter dem letzten
// Namen ein ':' steht (kein ':=' - das ist ein eigenes Token); AEnd ist das
// letzte Wort.
function ColonList(const AToks: TArray<TRdxToken>; k: Integer;
  out AEnd: Integer): Boolean;
begin
  AEnd := k;
  while (LowOf(AToks, AEnd + 1) = ',') and (AEnd + 2 <= High(AToks))
     and AToks[AEnd + 2].IsWord do
    Inc(AEnd, 2);
  Result := LowOf(AToks, AEnd + 1) = ':';
end;

// Ein Schritt des Blockstapels (ScanDecls) am Schluesselwort Nummer k:
// begin/try/asm und ein case ausserhalb eines records oeffnen einen
// Anweisungsteil, record und ein Typ mit Rumpf einen Deklarationsblock,
// end schliesst den innersten.
procedure StepBlocks(AMap: TRdxCodeMap; const AToks: TArray<TRdxToken>;
  k: Integer; var AStack: string);
var
  W : string;
begin
  W := AToks[k].Low;
  if InList(W, STMT_OPENERS) then
    AStack := AStack + BLOCK_STMT
  else if W = 'case' then
  begin
    // 'case' im record ist der Variantenteil - er endet mit dem record.
    if Copy(AStack, Length(AStack), 1) <> BLOCK_RECORD then
      AStack := AStack + BLOCK_STMT;
  end
  else if W = 'record' then
    AStack := AStack + BLOCK_RECORD
  else if InList(W, BODY_TYPES) and InList(LowOf(AToks, k - 1), BODY_TYPE_PREV)
     and TypeHasBody(AMap, AToks[k]) then
    AStack := AStack + BLOCK_TYPE
  else if (W = 'end') and (AStack <> '') then
    SetLength(AStack, Length(AStack) - 1);
end;

// Die Namen, die die Datei deklariert (klein, nach ADecl) - eine Textregel:
//   - hinter procedure/function/constructor/destructor/property/operator und
//     unit/program/library/package (bei 'TFoo.Bar' beide Glieder),
//   - eine Liste 'A, B: T' in Klammern (Parameter), im Deklarationsteil
//     (Variable, Feld, Konstante mit Typ) oder hinter var/const/out/on/
//     threadvar (Inline-Variable, 'on E: Exception'); im Anweisungsteil
//     sonst nicht - 'mrOk:' ist dort die Marke eines case-Zweigs,
//   - 'Name =' bzw. 'Name<' im Deklarationsteil hinter ';', type, const,
//     resourcestring, ']' oder einem Abschnittswort (Typ, Konstante) samt
//     der Aufzaehlungswerte '= (a, b)',
//   - im Anweisungsteil das Wort hinter var/const (Inline 'var X := ..').
// Ein Wort zu viel hiesse hier "deklariert", also eine Gluehbirne zu viel -
// darum die Strenge im Anweisungsteil. "In Klammern" zaehlt ab dem
// innersten offenen Block (Bases): eine anonyme Methode als Argument
// ('MessageDialog(.., procedure(const R: TModalResult) begin case R of
// mrYes: ..') steht zwar in der Klammer des Aufrufs, ihr 'mrYes:' ist aber
// eine case-Marke ihres Anweisungsteils, ihre Parameterliste dagegen eine
// eigene Klammer (Review e/HilfeFixH).
procedure ScanDecls(AMap: TRdxCodeMap; const AToks: TArray<TRdxToken>;
  ADecl: TDictionary<string, Boolean>);
var
  k, q, Last, Paren : Integer;
  Opened            : Integer;
  Bases             : TArray<Integer>;   // Paren beim Oeffnen je Block
  Stack, P, N       : string;
  InUses, Stmt      : Boolean;
  InParen           : Boolean;
begin
  Stack := '';
  Paren := 0;
  Bases := nil;
  InUses := False;
  for k := 0 to High(AToks) do
  begin
    P := LowOf(AToks, k - 1);
    N := LowOf(AToks, k + 1);
    if InUses then
    begin
      InUses := AToks[k].Low <> ';';
      Continue;
    end;
    if (AToks[k].Low = '(') or (AToks[k].Low = '[') then
      Inc(Paren)
    else if ((AToks[k].Low = ')') or (AToks[k].Low = ']')) and (Paren > 0) then
      Dec(Paren);
    Stmt := Pos(BLOCK_STMT, Stack) > 0;
    if ReservedAt(AToks, k) then
    begin
      InUses := AToks[k].Low = 'uses';
      Opened := Length(Stack);
      StepBlocks(AMap, AToks, k, Stack);
      SetLength(Bases, Length(Stack));
      if Length(Stack) > Opened then
        Bases[High(Bases)] := Paren;
      Continue;
    end;
    if Length(Bases) > 0 then
      InParen := Paren > Bases[High(Bases)]
    else
      InParen := Paren > 0;
    if not AToks[k].IsWord or InList(P, IDENT_PREFIXES) then Continue;
    if InList(P, NAMING_WORDS) or InList(P, UNIT_HEADS) then
    begin
      ADecl.AddOrSetValue(AToks[k].Low, True);
      if (N = '.') and (k + 2 <= High(AToks)) then
        ADecl.AddOrSetValue(AToks[k + 2].Low, True);
      Continue;
    end;
    if Stmt and ((P = 'var') or (P = 'const')) then
      ADecl.AddOrSetValue(AToks[k].Low, True);
    if ((N = ',') or (N = ':')) and (P <> ',') and ColonList(AToks, k, Last)
       and (InParen or not Stmt or InList(P, INLINE_DECL_PREV)) then
    begin
      q := k;
      while q <= Last do
      begin
        ADecl.AddOrSetValue(AToks[q].Low, True);
        Inc(q, 2);
      end;
    end;
    if ((N = '=') or (N = '<')) and (Paren = 0) and not Stmt
       and InList(P, EQ_DECL_PREV) then
    begin
      ADecl.AddOrSetValue(AToks[k].Low, True);
      if (N = '=') and (LowOf(AToks, k + 2) = '(') then
        AddEnumValues(AToks, k + 2, ADecl);
    end;
  end;
end;

function IsUpperAZ(C: Char): Boolean;
begin
  Result := (C >= 'A') and (C <= 'Z');
end;

function IsLowerAZ(C: Char): Boolean;
begin
  Result := (C >= 'a') and (C <= 'z');
end;

// Traegt S den Stil eines Bibliotheks-Bezeichners (s. ForeignIdent)?
// ACall: dahinter steht '('.
function LibraryStyle(const S: string; ACall: Boolean): Boolean;
var
  i, n, Bar : Integer;
  Prefix    : Boolean;
begin
  Result := False;
  n := Length(S);
  if n < 2 then Exit;
  // Typ: T/I/E, Grossbuchstabe, irgendwo ein Kleinbuchstabe (nicht 'TRUE').
  if (n >= 3) and CharInSet(S[1], ['T', 'I', 'E']) and IsUpperAZ(S[2]) then
    for i := 3 to n do
      if IsLowerAZ(S[i]) then
        Exit(True);
  // Aufzaehlungswert: zwei oder drei Kleinbuchstaben, ein Grossbuchstabe,
  // mindestens ein Zeichen dahinter.
  i := 1;
  while (i <= n) and IsLowerAZ(S[i]) do
    Inc(i);
  if (i >= 3) and (i <= 4) and (i < n) and IsUpperAZ(S[i]) then
    Exit(True);
  // Konstante: mindestens zwei Grossbuchstaben/Ziffern vor dem ersten '_'.
  Bar := Pos('_', S);
  if (Bar >= 3) and (Bar < n) and IsUpperAZ(S[1]) then
  begin
    Prefix := True;
    for i := 1 to Bar - 1 do
      if not (IsUpperAZ(S[i]) or CharInSet(S[i], ['0'..'9'])) then
        Prefix := False;
    if Prefix then
      Exit(True);
  end;
  Result := ACall and IsUpperAZ(S[1]);
end;

class function TRdxStructFixes.ForeignIdent(AMap: TRdxCodeMap;
  const AKnown: TArray<string>; out ALine: Integer): string;
var
  Toks   : TArray<TRdxToken>;
  Decl   : TDictionary<string, Boolean>;
  k      : Integer;
  P, S   : string;
  InUses : Boolean;
begin
  Result := '';
  ALine := 0;
  Toks := AllCodeTokens(AMap);
  Decl := TDictionary<string, Boolean>.Create;
  try
    for S in SYSTEM_NAMES do
      Decl.AddOrSetValue(S, True);
    for S in AKnown do
      Decl.AddOrSetValue(LowerCase(S), True);
    ScanDecls(AMap, Toks, Decl);
    InUses := False;
    for k := 0 to High(Toks) do
    begin
      if InUses then
      begin
        InUses := Toks[k].Low <> ';';
        Continue;
      end;
      if ReservedAt(Toks, k) then
      begin
        InUses := Toks[k].Low = 'uses';
        Continue;
      end;
      P := LowOf(Toks, k - 1);
      if not Toks[k].IsWord or (P = '.') or (P = '&') or (P = 'inherited')
         or Decl.ContainsKey(Toks[k].Low) then
        Continue;
      S := TokText(AMap, Toks[k]);
      if LibraryStyle(S, LowOf(Toks, k + 1) = '(') then
      begin
        ALine := Toks[k].Line;
        Exit(S);
      end;
    end;
  finally
    Decl.Free;
  end;
end;

class function TRdxStructFixes.UsesOnlyUnit(AMap: TRdxCodeMap): Boolean;
var
  Toks   : TArray<TRdxToken>;
  k      : Integer;
  InHead : Boolean;
  InUses : Boolean;
begin
  Toks := AllCodeTokens(AMap);
  Result := (Length(Toks) > 0) and (Toks[0].Low = 'unit');
  if not Result then Exit;
  InHead := False;
  InUses := False;
  for k := 0 to High(Toks) do
  begin
    if InHead or InUses then
    begin
      if Toks[k].Low = ';' then
      begin
        InHead := False;
        InUses := False;
      end;
      Continue;
    end;
    if Toks[k].Low = 'unit' then
      InHead := True
    else if Toks[k].Low = 'uses' then
      InUses := True
    else if not InList(Toks[k].Low, ['interface', 'implementation', 'end',
       '.']) then
      Exit(False);
  end;
end;

class function TRdxStructFixes.AlwaysNeededIdents(
  const AUnitLow: string): TArray<string>;
var
  i : Integer;
begin
  Result := nil;
  if (AUnitLow = 'sysutils') or (AUnitLow = 'system.sysutils') then
  begin
    SetLength(Result, Length(SYSUTILS_NAMES));
    for i := 0 to High(SYSUTILS_NAMES) do
      Result[i] := SYSUTILS_NAMES[i];
  end
  else if (AUnitLow = 'types') or (AUnitLow = 'system.types') then
  begin
    SetLength(Result, Length(TYPES_NAMES));
    for i := 0 to High(TYPES_NAMES) do
      Result[i] := TYPES_NAMES[i];
  end;
end;

// Die Eintraege einer uses-Klausel aus dem Text, ab dem ersten Token hinter
// 'uses' (T): je Eintrag die Namensteile ohne Luecke auf einer Zeile (wie
// TSourcePlaces.UsesEntries), ein 'in'-Pfad (der String ist kein Code-
// Token), dann ',' oder ';'. False bei jeder anderen Folge.
function ReadTextClause(AMap: TRdxCodeMap; T: TRdxToken;
  out AEntries: TArray<TRefactorSpan>): Boolean;
var
  Last, N : TRdxToken;
  E       : TRefactorSpan;
begin
  Result := False;
  AEntries := nil;
  while T.IsWord do
  begin
    E := TRefactorSpan.Make(ROLE_UNIT, T.Line, T.Col, T.Line, T.EndCol);
    E.Resolved := TokText(AMap, T);
    Last := T;
    T := After(AMap, T);
    while (T.Low = '.') and (T.Line = Last.Line) and (T.Col = Last.EndCol) do
    begin
      N := After(AMap, T);
      if not N.IsWord or (N.Line <> T.Line) or (N.Col <> T.EndCol) then
        Exit;
      E.Resolved := E.Resolved + '.' + TokText(AMap, N);
      E.EndCol := N.EndCol;
      Last := N;
      T := After(AMap, N);
    end;
    SetLength(AEntries, Length(AEntries) + 1);
    AEntries[High(AEntries)] := E;
    if T.Low = 'in' then
      T := After(AMap, T);
    if T.Low = ';' then
      Exit(True);
    if T.Low <> ',' then
      Exit;
    T := After(AMap, T);
  end;
end;

class function TRdxStructFixes.TextUsesEntry(AMap: TRdxCodeMap;
  ALine: Integer; const AUnit: string; out AClause: TRdxUsesClause;
  out AIndex: Integer): Integer;
var
  T       : TRdxToken;
  Entries : TArray<TRefactorSpan>;
  k       : Integer;
begin
  Result := 0;
  AClause := Default(TRdxUsesClause);
  AIndex := -1;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), 'uses');
  while T.Low <> '' do
  begin
    if (T.Low = 'uses') and IsKeywordAfter(T, Before(AMap, T))
       and ReadTextClause(AMap, After(AMap, T), Entries) then
      for k := 0 to High(Entries) do
        if (Entries[k].StartLine = ALine)
           and SameText(Entries[k].Resolved, AUnit) then
        begin
          Inc(Result);
          AClause.Entries := Entries;
          AClause.UsesLine := T.Line;
          AIndex := k;
        end;
    T := NextTokenOnLineWith(AMap, T, 'uses');
  end;
end;

{ ---- SCA168 ---- }

// Das Wort 'case' als Schluesselwort (OneTokenOnLine, CaseTokenOn) -
// 'Obj.&Case(1)' und 'X.Case' sind Bezeichner (IsKeywordAfter, wie die
// Haken der Bilanz; bis zur Review Woche G07-24 zaehlte jedes 'case', und
// ein verschobener Fund auf 'Obj.&Case(1);' schrieb ein else vor das end
// der Routine).
function IsCaseWord(AMap: TRdxCodeMap; const T: TRdxToken;
  const AArg: string): Boolean;
begin
  Result := (T.Low = 'case') and IsKeywordAfter(T, Before(AMap, T));
end;

// Das eine 'case' im Code der Zeile ALine. '' oder der Grund.
function CaseTokenOn(AMap: TRdxCodeMap; ALine: Integer;
  out ACase: TRdxToken): string;
var
  S : TRdxLineSearch;
begin
  // What und ManyFmt uebersetzt der Aufrufer (OneTokenReason setzt sie in
  // seinen Satz; README, "Texte umstellen"); ManyFmt bleibt ein Muster -
  // _() ohne Argumente formatiert nicht.
  S := Default(TRdxLineSearch);
  S.Test    := IsCaseWord;
  S.What    := _('no case');
  S.ManyFmt := _('%d case statements');
  Result := OneTokenOnLine(AMap, ALine, S, ACase);
end;

// Auf oberster Ebene des case: ein else, das dem case gehoert (ElseOwner:
// eoList - auch OHNE ';' davor, 'case K of 1: Foo else Bar end'; Review
// Quick-Fix-Units 2026-10-14), ist schon sein Zweig; ein else zu einem if
// in einem Arm (eoIf) nicht; ist der Besitzer unklar, keine Hilfe.
// 'otherwise' auf oberster Ebene ist der FPC-Zweig - auch OHNE ';' davor:
// FPC liest 'case K of 1: Foo otherwise Bar end' wie die else-Form (nach
// der Grammatik des FPC-Handbuchs: ohne ';' hinter dem Arm endet die
// Armliste, dann else bzw. otherwise; eine FPC-Mikroprobe steht aus), und
// uDefaultCaseInCaseStatement kennt otherwise nicht, meldet
// also auch solche case. Bis zur Review Woche G07-06 sperrte nur '; otherwise'
// - sonst kaeme 'otherwise Bar; else end', zwei Default-Zweige. Ein
// Bezeichner Otherwise als Arm-Anweisung (Delphi) sperrt so mit - die
// sichere Richtung. '' oder der Grund.
function TopLevelReason(AMap: TRdxCodeMap; const T, APrev: TRdxToken): string;
var
  Scan : TRdxElseScan;
begin
  Result := '';
  if T.Low = 'else' then
  begin
    Scan := ElseOwner(AMap, T);
    // Scan.Reason kommt aus uRdxCodeMap (ElseOwner) - dort uebersetzt.
    if Scan.Owner = eoList then
      Result := _('the case already has an else branch')
    else if Scan.Owner = eoUnknown then
      Result := _('else in the case, owner unclear: %s', [Scan.Reason]);
  end
  else if T.Low = 'otherwise' then
    Result := _('the case has an otherwise branch (FPC) - or an arm calls an '
      + 'identifier Otherwise; %s', [MsgCheckByHand]);
end;

// Der Haken der end-Bilanz von SCA168 (BlockEnd, MatchingEnd): auf der
// obersten Ebene des case ein Schluesselwort gegen TopLevelReason halten.
// '&Else' und 'X.Else' sind Bezeichner (IsKeywordAfter), kein Zweig.
function CaseTopHook(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
  ADepth: Integer): string;
begin
  Result := '';
  if (ADepth = 1) and IsKeywordAfter(T, APrev) then
    Result := TopLevelReason(AMap, T, APrev);
end;

// Das end zum case ACase und das Token davor (ALast). '' oder der Grund.
function MatchingEnd(AMap: TRdxCodeMap; const ACase: TRdxToken;
  out AEnd, ALast: TRdxToken): string;
begin
  Result := BlockEnd(AMap, ACase, CaseTopHook, AEnd, ALast);
  if (Result = '') and (AEnd.Low = '') then
    Result := _('no end found for the case');
end;

// Der Ersatz fuer das end: steht es am Zeilenanfang, das else in eigener
// Zeile mit derselben Einrueckung (AStatement eine Stufe tiefer), sonst
// inline vor dem end.
function ElseText(const ALine: string; const AEnd: TRdxToken;
  const AStatement, AArmLine: string): string;
var
  Indent, EndText : string;
begin
  EndText := Copy(ALine, AEnd.Col, AEnd.Len);
  if SkipBlanks(ALine, 1) <> AEnd.Col then
  begin
    Result := 'else ';
    if AStatement <> '' then
      Result := Result + AStatement + ' ';
    Exit(Result + EndText);
  end;
  Indent := Copy(ALine, 1, AEnd.Col - 1);
  Result := 'else' + #10;
  if AStatement <> '' then
    Result := Result + Indent + IndentStep(Indent, AArmLine) + AStatement + #10;
  Result := Result + Indent + EndText;
end;

// Die Zeile, nach der sich die Stufe der Anweisung im else richtet
// (ElseText): die des ersten Arms - das Token hinter dem 'of' des case
// ACase -, wenn er seine Zeile beginnt; sonst AFallback (die Zeile des
// letzten Tokens vor dem end). Bis rwE29 galt immer die letzte Zeile -
// endet der letzte Arm tief in einem begin..end, rueckte das raise mit
// ein (skia4delphi Vcl.Styles.UxTheme.pas:1098: Spalte 57 statt 33).
// Das erste Zeichen aus Code oder String hinter dem 'of' des case ACase
// (die erste Arm-Marke): False ohne 'of' oder am Dateiende. Ein String ist
// kein Token der Code-Sicht - bis rwE30 nahm ArmLineOf das erste TOKEN
// hinter dem 'of' und sah bei einem Zeichen-Arm ("'.':") nur den ':'
// mitten auf der Zeile.
function FirstArmChar(AMap: TRdxCodeMap; const ACase: TRdxToken;
  out ALine, ACol: Integer): Boolean;
var
  T : TRdxToken;
begin
  ALine := 0;
  ACol := 0;
  T := After(AMap, ACase);
  while (T.Low <> '') and (T.Low <> 'of') do
    T := After(AMap, T);
  Result := (T.Low <> '') and FirstCharAfter(AMap, T, ALine, ACol);
end;

function ArmLineOf(AMap: TRdxCodeMap; const ACase: TRdxToken;
  const AFallback: string): string;
var
  Li, Co : Integer;
begin
  Result := AFallback;
  // Das erste Zeichen der ersten Arm-Marke - auch ein String ("'.':",
  // rwE30 cnwizards mwBCBTokenList.pas:1518: das raise stand vier statt
  // zwei Spalten unter dem else, nach der Fortsetzungszeile des letzten
  // Arms).
  if FirstArmChar(AMap, ACase, Li, Co)
     and (SkipBlanks(AMap.Raw(Li), 1) = Co) then
    Result := AMap.Raw(Li);
end;

// Steht an (ALine, ACol) ein Zeichen- oder String-Literal ("'.'", '#13')?
function LiteralCharAt(AMap: TRdxCodeMap; ALine, ACol: Integer): Boolean;
begin
  Result := CharInSet(CharAt(AMap.Raw(ALine), ACol), ['''', '#']);
end;

// SCA168, raise-Variante: waehlt das case nach Zeichen oder Strings - die
// erste Arm-Marke ist ein Literal ("'.':", '#13:') oder eine Umwandlung
// eines Zeichens (CHAR_WRAPPERS: "Ord('-'):" auf einem Byte-Zeiger, 'Chr(13):')?
// Dann ist jeder andere Wert gewoehnliche Eingabe (ein Lexer, ein
// Highlighter, ein Parser), und raise braeche ihn (rwE30: cnwizards
// mwBCBTokenList.pas:1518, Dev-Cpp SynHighlighterCpp.pas:1051 - jede Ziffer
// bzw. jedes Zeichen loeste die Exception aus; rwE31 Stufe 3:
// JsonDataObjects.pas:7695 'case P^ of Ord('-'): .. Ord('+'): ..' - jeder
// Exponent ohne Vorzeichen loeste sie aus, bis dahin sah die Sperre nur
// das Literal am Anfang der Marke). '' oder der Grund.
function CharSelectorReason(AMap: TRdxCodeMap; const ACase: TRdxToken): string;
const
  CHAR_WRAPPERS: array[0..6] of string = ('ord', 'chr', 'byte', 'word',
    'char', 'ansichar', 'widechar');
var
  Li, Co : Integer;
  W, P   : TRdxToken;
  IsChar : Boolean;
begin
  Result := '';
  if not FirstArmChar(AMap, ACase, Li, Co) then Exit;
  IsChar := LiteralCharAt(AMap, Li, Co);
  if not IsChar and AMap.IsCode(Li, Co) and IsIdentStart(CharAt(AMap.Raw(Li), Co))
  then
  begin
    W := TokenAt(AMap, Li, Co);
    P := After(AMap, W);
    // 'Chr(..)' ist immer ein Zeichen, die anderen nur um ein Literal.
    if InList(W.Low, CHAR_WRAPPERS) and (P.Low = '(') then
      IsChar := (W.Low = 'chr')
        or (FirstCharAfter(AMap, P, Li, Co) and LiteralCharAt(AMap, Li, Co));
  end;
  if IsChar then
    Result := _('the case selects on characters or strings - every other '
      + 'value is normal input there (a lexer, a parser); raise would break '
      + 'it');
end;

// Bedingte Direktiven im case (CaseElse): harmlos, wenn jeder bedingte
// Bereich ({$IF..}..{$ENDIF}) zwischen case und end vollstaendig darin
// liegt, kein Wort enthaelt, das die end-Bilanz verschiebt (begin, end,
// case, try, asm, record, repeat, until, class, object), kein Include
// ({$I ..}) im case steht, und der letzte Arm nicht in einem Bereich endet,
// es sei denn, er und das Token vor dem Bereich enden auf ';' (sonst
// traefe das neue else je Zweig ein anderes Ende - 'if A then B
// {$IFDEF X};{$ENDIF}' + 'else'). Dann sieht jede Variante dieselbe
// Bilanz, und das else vor dem end passt in jeder (rwE30, Todo_SCA168
// "verpasst-direktive": mormot.core.rtti.pas:7170 - ein ganzer Arm unter
// {$ifdef HASVARUSTRING}, mormot.db.rad.pas:1074 - je eine Zuweisung in
// {$ifdef UNICODE}..{$else}..{$endif}, JvRegAuto.pas:615 - ein Label in
// der Liste). Andere Direktiven ({$R-}, {$REGION}) aendern den Code nicht.
function CaseDirectivesHarmless(AMap: TRdxCodeMap;
  const ACase, AEnd, ALast: TRdxToken): Boolean;
const
  COND_OPEN: array[0..3] of string = ('if', 'ifdef', 'ifndef', 'ifopt');
  COND_MID: array[0..1] of string = ('else', 'elseif');
  COND_CLOSE: array[0..1] of string = ('endif', 'ifend');
  BALANCE_WORDS: array[0..9] of string = ('begin', 'end', 'case', 'try',
    'asm', 'record', 'repeat', 'until', 'class', 'object');
var
  T, Prev, RegionPrev, LastRegionPrev : TRdxToken;
  Li, Co, Depth                       : Integer;
  HaveDir, Arg, LastInRegion          : Boolean;
  W                                   : string;
begin
  Result := False;
  Li := ACase.Line;
  Co := 1;
  HaveDir := NextDirective(AMap, Li, Co);
  Depth := 0;
  Prev := Before(AMap, ACase);
  RegionPrev := Default(TRdxToken);
  LastRegionPrev := Default(TRdxToken);
  LastInRegion := False;
  T := ACase;
  while True do
  begin
    // Die Direktiven vor T (bzw. vor dem end).
    while HaveDir and ((Li < T.Line) or ((Li = T.Line) and (Co < T.Col))) do
    begin
      if IncludeFileAt(AMap, Li, Co) <> '' then Exit;
      W := DirectiveWord(AMap, Li, Co, Arg);
      if InList(W, COND_OPEN) then
      begin
        if Depth = 0 then
          RegionPrev := Prev;
        Inc(Depth);
      end
      else if InList(W, COND_CLOSE) then
      begin
        Dec(Depth);
        if Depth < 0 then Exit;
      end
      else if InList(W, COND_MID) and (Depth = 0) then
        Exit;
      Inc(Co);
      HaveDir := NextDirective(AMap, Li, Co);
    end;
    if SameTok(T, AEnd) then Break;
    if (Depth > 0) and IsKeywordAfter(T, Prev)
       and InList(T.Low, BALANCE_WORDS) then
      Exit;
    if SameTok(T, ALast) then
    begin
      LastInRegion := Depth > 0;
      LastRegionPrev := RegionPrev;
    end;
    Prev := T;
    T := After(AMap, T);
    if T.Low = '' then Exit;
  end;
  if Depth <> 0 then Exit;
  if LastInRegion and ((ALast.Low <> ';') or (LastRegionPrev.Low <> ';')) then
    Exit;
  Result := True;
end;

// Endet der letzte Arm vor AEnd nicht auf ';' (im Code), ein ';' hinter
// sein letztes Zeichen - als eigene Ersetzung (das Zeichen wird mit ';'
// dahinter neu geschrieben, ein leerer Erwartungstext ist nicht erlaubt).
procedure AppendSemicolon(AMap: TRdxCodeMap; const AEnd: TRdxToken;
  var AEdits: TArray<TRdxEdit>);
var
  Li, Co : Integer;
  E      : TRdxEdit;
begin
  if not LastCharBefore(AMap, AEnd, Li, Co) then Exit;
  E := Default(TRdxEdit);
  E.Expected := Copy(AMap.Raw(Li), Co, 1);
  if (E.Expected = ';') and AMap.IsCode(Li, Co) then Exit;
  E.Span := TRefactorSpan.Make(SPAN_168, Li, Co, Li, Co + 1);
  E.NewText := E.Expected + ';';
  SetLength(AEdits, Length(AEdits) + 1);
  AEdits[High(AEdits)] := E;
end;

// CaseContextReason, ein Schluesselwort rueckwaerts (ADepth: offene
// Bloecke, TRdxBackBalance - sie zaehlt end/until und die Oeffner darin):
// rsFound - das case ist eine Anweisung (ein Oeffner auf oberster Ebene);
// rsStop - ein record (Variantenteil, auf jeder Tiefe); sonst rsGoOn.
function CaseBlockStep(const T: TRdxToken; ADepth: Integer): TRdxStep;
begin
  Result := rsGoOn;
  if T.Low = 'record' then
    Result := rsStop
  else if (ADepth = 0) and (IsEndOpener(T.Low) or (T.Low = 'repeat')) then
    Result := rsFound
  else if (ADepth = 0) and InList(T.Low, STATEMENT_SECTIONS) then
    Result := rsFound;
end;

// CaseContextReason, ein Token rueckwaerts: eine offene '(' ist die
// Feldliste eines Variantenzweigs (rsStop); Schluesselwoerter fragt
// CaseBlockStep (auch in Klammern).
function CaseScanStep(const T, APrev: TRdxToken; ADepth: Integer;
  var AParen: Integer): TRdxStep;
begin
  Result := rsGoOn;
  if T.Low = ')' then
    Inc(AParen)
  else if T.Low = '(' then
  begin
    Dec(AParen);
    if AParen < 0 then
      Result := rsStop;
  end
  else if IsKeywordAfter(T, APrev) then
    Result := CaseBlockStep(T, ADepth);
end;

// Ist das case ACase eine Anweisung? Der Detektor meldet nur case-
// Anweisungen; ein verschobener Fund (Zeilen eingefuegt, die Birne auf
// einer alten Zeile) kann aber auf dem Variantenteil eines Records landen
// - das else kaeme dann in die Typdeklaration und uebersetzte nicht
// (Review R3-04, Charge FC). Rueckwaerts bis zum innersten offenen Block,
// ganze Bloecke (end..begin/case/try/asm, until..repeat) uebersprungen: ein
// offenes begin/try/repeat/asm/case oder initialization/finalization auf
// oberster Ebene heisst Anweisung (''); ein 'record' - auf jeder Tiefe: ein
// case in seinem Variantenteil hat kein eigenes end, die Bilanz stimmt dort
// nicht (wie TRdxElseScan.StepWord) - oder eine offene '(' (Feldliste eines
// Variantenzweigs, 'case Tag of 0: (case ..') heisst Variantenteil. Steht
// zwischen der offenen '(' und dem case eine Direktive, kann auch ein Zweig
// die Klammer offen lassen ('{$IFDEF A} Foo( {$ELSE} Bar( {$ENDIF} 1);' vor
// einer case-Anweisung) - dann ist die Lage unklar (bis zur Nachpruefung FC
// hiess auch das Variantenteil). Ohne offenen Block bis zum Dateianfang (ein
// Fragment) ist die Lage ebenso unklar. Alles das sperrt. '' oder der Grund.
function CaseContextReason(AMap: TRdxCodeMap; const ACase: TRdxToken): string;
var
  W     : TRdxBackBalance;
  Paren : Integer;
  Step  : TRdxStep;
begin
  Paren := 0;
  W.Start(AMap, ACase);
  while W.Next do
  begin
    Step := CaseScanStep(W.Tok, W.Prev, W.Depth, Paren);
    if Step = rsFound then
      Exit('');
    if (Step = rsStop) and (W.Tok.Low = '(')
       and DirectiveBetween(AMap, W.Tok, ACase.Line, ACase.Col) then
      Exit(_(R_CASE_OPEN_PAREN));
    if Step = rsStop then
      Exit(_(R_CASE_IN_RECORD));
    W.Balance;
  end;
  Result := _('no block found around the case (fragment?) - it is unclear '
    + 'whether it is a statement');
end;

class function TRdxStructFixes.CaseElse(AMap: TRdxCodeMap; ALine: Integer;
  const AStatement: string; out AEdits: TArray<TRdxEdit>;
  out AReason: string): Boolean;
var
  CaseTok, EndTok, LastTok : TRdxToken;
  L                        : string;
begin
  Result := False;
  AEdits := nil;
  EndTok := Default(TRdxToken);
  LastTok := Default(TRdxToken);
  AReason := CaseTokenOn(AMap, ALine, CaseTok);
  if AReason = '' then
    AReason := MatchingEnd(AMap, CaseTok, EndTok, LastTok);
  if (AReason = '') and (LastTok.Low = 'of') then
    AReason := _('the case has no branches');
  if AReason = '' then
    AReason := CaseContextReason(AMap, CaseTok);
  if (AReason = '') and DirectiveBefore(AMap, CaseTok.Line, EndTok)
     and not CaseDirectivesHarmless(AMap, CaseTok, EndTok, LastTok) then
    AReason := _('compiler directive in the case - a branch could shift the '
      + 'end count');
  if (AReason = '') and (AStatement <> '') then
    AReason := CharSelectorReason(AMap, CaseTok);
  // Alte Compiler kennen EInvalidOpException nicht (rwE31 Stufe 3, wie
  // SCA020 mit ENotImplemented).
  if (AReason = '') and (AStatement <> '') then
    AReason := OldExceptionClassReason(AMap, CLASS_UNHANDLED);
  if AReason <> '' then Exit;
  L := AMap.Raw(EndTok.Line);
  SetLength(AEdits, 1);
  AEdits[0].Span := TRefactorSpan.Make(SPAN_168, EndTok.Line, EndTok.Col,
    EndTok.Line, EndTok.EndCol);
  AEdits[0].Expected := Copy(L, EndTok.Col, EndTok.Len);
  AEdits[0].NewText := ElseText(L, EndTok, AStatement,
    ArmLineOf(AMap, CaseTok, AMap.Raw(LastTok.Line)));
  AppendSemicolon(AMap, EndTok, AEdits);
  Result := True;
end;

// CaseRaiseMenuReason: die Marken der Arme des case ACase bis AEnd, wie
// geschrieben - Namen ('aaNone'), qualifizierte Namen ('TFoo.A') und
// Bereiche ('a..c'),
// je Marke ein Eintrag. False, sobald eine Marke etwas anderes ist (Zahl,
// Ausdruck, Schluesselwort); ein Zeichen oder String hinterlaesst eine
// leere Marke (die Code-Sicht liest sie nicht als Token) - ebenso False.
// ANumber: die Marke, an der das scheiterte, beginnt mit einer Zahl ('2:',
// '-1:', '$10:', '34560..34562:' - rwE32 Stufe 4: Dev-Cpp main.pas:3822,
// HeidiSQL main.pas:14255 'case GetACP of 437:'); dann waehlt das case
// nach einer Zahl, nicht nach einer Aufzaehlung (Nico-Entscheid E5).
// Eine Marke beginnt hinter dem 'of' und hinter jedem ';' auf oberster Ebene
// (Bloecke begin/case/try/asm/record..end und repeat..until, Klammern
// zaehlen) und endet am ':'.
function CaseLabels(AMap: TRdxCodeMap; const ACase, AEnd: TRdxToken;
  out ALabels: TArray<string>; out ANumber: Boolean): Boolean;
var
  T, P          : TRdxToken;
  Depth, Paren  : Integer;
  AtLabel       : Boolean;
  Item          : string;
begin
  Result := False;
  ALabels := nil;
  ANumber := False;
  T := After(AMap, ACase);
  while (T.Low <> '') and (T.Low <> 'of') do
    T := After(AMap, T);
  if T.Low = '' then Exit;
  T := After(AMap, T);
  Depth := 0;
  Paren := 0;
  AtLabel := True;
  Item := '';
  while (T.Low <> '') and not SameTok(T, AEnd) do
  begin
    P := Before(AMap, T);
    if AtLabel then
    begin
      if (T.Low = ':') or (T.Low = ',') then
      begin
        if (Item = '') or (Item[1] = '.') or (Item[Length(Item)] = '.') then
          Exit;
        AddText(ALabels, Item);
        Item := '';
        AtLabel := T.Low = ',';
      end
      else if (T.Low = '.') or (T.Low = '..') then
        Item := Item + T.Low
      // Zwei Woerter ohne Punkt dazwischen sind kein Name.
      else if T.IsWord and not IsKeyword(T.Low)
         and ((Item = '') or (Item[Length(Item)] = '.')) then
        Item := Item + TokText(AMap, T)
      else
      begin
        // '$10' sind zwei Token ('$', '10'), '-1' auch.
        ANumber := (Item = '') and (CharInSet(T.Low[1], ['0'..'9'])
          or InList(T.Low, ['$', '-', '+']));
        Exit;
      end;
    end
    else if IsKeywordAfter(T, P) and (IsEndOpener(T.Low) or (T.Low = 'repeat'))
    then
      Inc(Depth)
    else if IsKeywordAfter(T, P) and ((T.Low = 'end') or (T.Low = 'until')) then
      Dec(Depth)
    else if (T.Low = '(') or (T.Low = '[') then
      Inc(Paren)
    else if (T.Low = ')') or (T.Low = ']') then
      Dec(Paren)
    else if (T.Low = ';') and (Depth = 0) and (Paren = 0) then
      AtLabel := True;
    T := After(AMap, T);
  end;
  Result := (T.Low <> '') and (Item = '') and (Length(ALabels) > 0);
end;

// Die Werteliste ab der '(' AOpen eines Aufzaehlungstyps, wie geschrieben:
// nur Namen mit Kommas, mindestens zwei, keine eigene Zahl ('a = 1' - die
// Werte dazwischen gehoerten zum Typ, haetten aber keinen Namen) und keine
// Direktive in der Liste. False sonst.
function ReadEnumValues(AMap: TRdxCodeMap; const AOpen: TRdxToken;
  out AValues: TArray<string>): Boolean;
var
  T, N : TRdxToken;
begin
  Result := False;
  AValues := nil;
  T := After(AMap, AOpen);
  while T.IsWord do
  begin
    AddText(AValues, TokText(AMap, T));
    N := After(AMap, T);
    if N.Low = ')' then
      Exit((Length(AValues) >= 2)
        and not DirectiveBetween(AMap, AOpen, N.Line, N.Col));
    if N.Low <> ',' then Exit;
    T := After(AMap, N);
  end;
end;

// Der eine Aufzaehlungstyp der Datei ('Name = (a, b, ..)' hinter ';',
// 'type' oder ']' - nicht 'X: array[..] of T = (..)', eine Konstante), dessen
// Werte AValue nennen (Gross/klein egal): sein Name und seine Werte wie
// geschrieben. False ohne Treffer und bei mehr als einem (zwei
// Deklarationen in $IFDEF-Zweigen koennen verschiedene Werte haben).
function EnumOf(AMap: TRdxCodeMap; const AValue: string; out ATypeName: string;
  out AValues: TArray<string>): Boolean;
var
  T, Name : TRdxToken;
  Vals    : TArray<string>;
  V       : string;
  Count   : Integer;
begin
  ATypeName := '';
  AValues := nil;
  Count := 0;
  T := NextToken(AMap, 1, 1);
  while T.Low <> '' do
  begin
    if (T.Low = '(') and (Before(AMap, T).Low = '=') then
    begin
      Name := Before(AMap, Before(AMap, T));
      if Name.IsWord and InList(Before(AMap, Name).Low, [';', 'type', ']'])
         and ReadEnumValues(AMap, T, Vals) then
        for V in Vals do
          if SameText(V, AValue) then
          begin
            Inc(Count);
            ATypeName := TokText(AMap, Name);
            AValues := Vals;
            Break;
          end;
    end;
    T := After(AMap, T);
  end;
  Result := Count = 1;
end;

// Der Wert einer Marke ohne den Typnamen davor ('TFoo.A' -> 'A', wenn
// der Typ ATypeName heisst, Gross/klein egal); '' bei einem anderen
// Praefix.
function LabelValue(const AItem, ATypeName: string): string;
var
  p : Integer;
begin
  p := Pos('.', AItem);
  if p = 0 then
    Result := AItem
  else if SameText(Copy(AItem, 1, p - 1), ATypeName) then
    Result := Copy(AItem, p + 1, MaxInt)
  else
    Result := '';
  if Pos('.', Result) > 0 then
    Result := '';
end;

// Der Index von AName in AValues (Gross/klein egal); -1 ohne.
function ValueIndex(const AValues: TArray<string>; const AName: string): Integer;
var
  i : Integer;
begin
  Result := -1;
  if AName = '' then Exit;
  for i := 0 to High(AValues) do
    if SameText(AValues[i], AName) then
      Exit(i);
end;

// Markiert in AHit die Werte der Marke AItem (ein Wert oder ein Bereich
// 'a..c'). False, wenn ein Glied kein Wert des Typs ist.
function MarkLabel(const AItem, ATypeName: string;
  const AValues: TArray<string>; var AHit: TArray<Boolean>): Boolean;
var
  p, Lo, Hi, i : Integer;
begin
  p := Pos('..', AItem);
  if p = 0 then
  begin
    Lo := ValueIndex(AValues, LabelValue(AItem, ATypeName));
    Hi := Lo;
  end
  else
  begin
    Lo := ValueIndex(AValues, LabelValue(Copy(AItem, 1, p - 1), ATypeName));
    Hi := ValueIndex(AValues, LabelValue(Copy(AItem, p + 2, MaxInt),
      ATypeName));
  end;
  Result := (Lo >= 0) and (Hi >= Lo);
  if Result then
    for i := Lo to Hi do
      AHit[i] := True;
end;

// Die Werte ohne Arm, hoechstens drei, dahinter ' ...'.
function MissingValues(const AValues: TArray<string>;
  const AHit: TArray<Boolean>): string;
var
  i, n : Integer;
begin
  Result := '';
  n := 0;
  for i := 0 to High(AValues) do
    if not AHit[i] then
    begin
      Inc(n);
      if n > 3 then
        Exit(Result + ' ...');
      if Result <> '' then
        Result := Result + ', ';
      Result := Result + AValues[i];
    end;
end;

// ---- SCA168.2, Nico-Entscheid E5 (rwE32 Stufe 4) ----
// Waehlt das case nicht nach einer Aufzaehlung - der Selektor ist eine Zahl,
// ein Zeichen oder String (Integer-, Word-, Char-, String-Konstanten als
// Marken: MBI_NORMAL, VK_BACK bei 'Key: Word', Msg.Msg in einer WndProc,
// GetACP-Codepages, NativeUInt(..)) -, oder hat das Ergebnis vor dem case
// schon seinen Wert (Result := TYPE_ERROR, ChildCount := 0), dann sind die
// Werte ohne Arm dort gewoehnlich, und raise braeche diesen Weg: SCA168.2
// gesperrt, SCA168 (leeres else) bleibt. Bis rwE32 standen solche case nur
// im Menue, der Hinweis nannte die Konstante "Aufzaehlung".

const
  // Selektor-Typen, die keine Aufzaehlung sind (klein): ganze Zahlen,
  // Zeichen, Strings; 'ord' als Umwandlung 'Ord(..)'.
  NON_ENUM_TYPES: array[0..44] of string = ('integer', 'cardinal', 'word',
    'byte', 'shortint', 'smallint', 'longint', 'longword', 'int64', 'uint64',
    'nativeint', 'nativeuint', 'dword', 'qword', 'uint', 'uint8', 'uint16',
    'uint32', 'int8', 'int16', 'int32', 'ptrint', 'ptruint', 'sizeint',
    'sizeuint', 'wparam', 'lparam', 'lresult', 'hresult', 'uint_ptr',
    'dword_ptr', 'ord', 'char', 'ansichar', 'widechar', 'utf8char',
    'string', 'ansistring', 'widestring', 'unicodestring', 'shortstring',
    'rawbytestring', 'utf8string', 'longbool', 'wordbool');
  // Davor beginnt die Deklaration einer Konstante 'Name = Wert'.
  CONST_DECL_PREV: array[0..3] of string = (';', 'const', 'resourcestring',
    ']');
  // Rueckwaerts vor einer Deklaration: der Abschnitt ist ein const-Teil ...
  CONST_SECTIONS: array[0..1] of string = ('const', 'resourcestring');
  // ... oder etwas anderes (Typ, Variable, Rumpf, Routine, Klassenteil).
  OTHER_SECTIONS: array[0..20] of string = ('type', 'var', 'threadvar',
    'begin', 'end', 'procedure', 'function', 'constructor', 'destructor',
    'operator', 'property', 'implementation', 'interface', 'uses', 'label',
    'private', 'protected', 'public', 'published', 'record', 'class');
  // Rechenzeichen im Wert: 'WM_USER + 1' ist eine Zahl, kein
  // Aufzaehlungswert (mit Aufzaehlungen rechnet Delphi nicht).
  CONST_OPERATORS: array[0..11] of string = ('+', '-', '*', '/', 'div',
    'mod', 'shl', 'shr', 'or', 'and', 'xor', 'not');
  // Hier beginnt eine Anweisung (PresetLockReason) - ausser hinter ';'.
  STATEMENT_OPENERS: array[0..5] of string = ('begin', 'try', 'repeat',
    'finally', 'except', 'initialization');
  // Rueckwaerts bis zum Kopf der Routine (PresetLockReason).
  PRESET_STOPS: array[0..7] of string = ('procedure', 'function',
    'constructor', 'destructor', 'operator', 'implementation', 'interface',
    'type');
  // So viele Token liest PresetLockReason bzw. ConstDeclLine rueckwaerts.
  MAX_PRESET_BACK = 100000;
  MAX_SECTION_BACK = 20000;
  // Units der uses-Klauseln bis zu so vielen Verzeichnissen ueber der
  // Datei (TRdxTypeProof.NeighbourInterfaces): doublecmd src\filesources\
  // shellfolder\ushellfilesourceutil.pas -> src\ulog.pas.
  NEIGHBOUR_UP_LEVELS = 2;
  // Ganzzahl-Konstanten der RTL, die als case-Marken vorkommen (rwE32,
  // Korpus: 'WM_KEYUP', 'mrYes' (TModalResult = Integer), 'IDOK'): die
  // Nachrichten- und Tastenkonstanten nach ihrem Praefix (Winapi.Messages,
  // Vcl.Controls, LCL LMessages, Winapi.Windows) ...
  RTL_CONST_PREFIXES: array[0..4] of string = ('wm_', 'cm_', 'cn_', 'lm_',
    'vk_');
  // ... und die Rueckgabewerte von MessageDlg/MessageBox.
  RTL_CONST_NAMES: array[0..24] of string = ('mrnone', 'mrok', 'mrcancel',
    'mrabort', 'mrretry', 'mrignore', 'mryes', 'mrno', 'mrall', 'mrnotoall',
    'mryestoall', 'mrclose', 'mrhelp', 'mrtryagain', 'mrcontinue', 'idok',
    'idcancel', 'idabort', 'idretry', 'idignore', 'idyes', 'idno', 'idclose',
    'idhelp', 'idtryagain');

// Das erste Glied einer Marke ohne Typnamen ('TFoo.A' -> 'A', 'a..c' ->
// 'a').
function LabelHead(const AItem: string): string;
begin
  Result := AItem;
  if Pos('..', Result) > 0 then
    Result := Copy(Result, 1, Pos('..', Result) - 1);
  while Pos('.', Result) > 0 do
    Result := Copy(Result, Pos('.', Result) + 1, MaxInt);
end;

// Steht die Deklaration an ATok (dem Namen) in einem const-Abschnitt?
// Rueckwaerts bis zum ersten Abschnittswort (Schluesselwort, nicht hinter
// '.'): const/resourcestring ja, alles andere nein.
function InConstSection(AMap: TRdxCodeMap; const ATok: TRdxToken): Boolean;
var
  T, P  : TRdxToken;
  Steps : Integer;
begin
  Result := False;
  T := Before(AMap, ATok);
  Steps := 0;
  while (T.Low <> '') and (Steps < MAX_SECTION_BACK) do
  begin
    P := Before(AMap, T);
    if T.IsWord and IsKeywordAfter(T, P) then
    begin
      if InList(T.Low, CONST_SECTIONS) then
        Exit(True);
      if InList(T.Low, OTHER_SECTIONS) then
        Exit;
    end;
    T := P;
    Inc(Steps);
  end;
end;

// Ist der Wert hinter dem '=' AEq eine Zahl, ein Zeichen oder String
// ('2', '$10', '-1', '''MSG_REQUEST_DOM''', '#13') oder ein Ausdruck mit
// einem Rechenzeichen bis zum ';' ('WM_USER + 1')? Ein blosser Name
// ('cDefault = eA') nicht - er kann ein Aufzaehlungswert sein.
function NumberOrStringValue(AMap: TRdxCodeMap; const AEq: TRdxToken): Boolean;
var
  Li, Co, Paren : Integer;
  T, P          : TRdxToken;
begin
  Result := False;
  if not FirstCharAfter(AMap, AEq, Li, Co) then Exit;
  if CharInSet(CharAt(AMap.Raw(Li), Co), ['0'..'9', '$', '''', '#', '-', '+',
    '%']) then
    Exit(True);
  Paren := 0;
  P := AEq;
  T := After(AMap, AEq);
  while (T.Low <> '') and not ((T.Low = ';') and (Paren = 0)) do
  begin
    if (T.Low = '(') or (T.Low = '[') then
      Inc(Paren)
    else if (T.Low = ')') or (T.Low = ']') then
      Dec(Paren)
    else if InList(T.Low, CONST_OPERATORS)
       and (not T.IsWord or IsKeywordAfter(T, P)) then
      Exit(True)
    else if T.IsWord and IsKeywordAfter(T, P) and IsKeyword(T.Low) then
      Exit;   // ein Abschnittswort: kein Wert mehr
    P := T;
    T := After(AMap, T);
  end;
end;

// Die Zeile, auf der AMap AName als Konstante mit Zahl-, Zeichen- oder
// String-Wert deklariert ('const X = 2;', auch in einer Klasse: 'const
// HelperNodeColumns = 0;' - HeidiSQL main.pas:76); 0 ohne.
function ConstDeclLine(AMap: TRdxCodeMap; const AName: string): Integer;
var
  T, V    : TRdxToken;
  NameLow : string;
begin
  Result := 0;
  NameLow := LowerCase(AName);
  if NameLow = '' then Exit;
  T := NextTokenOnLineWith(AMap, Default(TRdxToken), NameLow);
  while T.Low <> '' do
  begin
    if T.Low = NameLow then
    begin
      V := After(AMap, T);
      if (V.Low = '=') and InList(Before(AMap, T).Low, CONST_DECL_PREV)
         and InConstSection(AMap, T) and NumberOrStringValue(AMap, V) then
        Exit(T.Line);
    end;
    T := NextTokenOnLineWith(AMap, T, NameLow);
  end;
end;

// Der Name der Unit ('unit Name;' am Anfang der Code-Sicht), '' ohne.
function UnitNameOf(AMap: TRdxCodeMap): string;
var
  T : TRdxToken;
begin
  Result := '';
  T := NextToken(AMap, 1, 1);
  if T.Low <> 'unit' then Exit;
  T := After(AMap, T);
  while T.IsWord or (T.Low = '.') do
  begin
    Result := Result + TokText(AMap, T);
    T := After(AMap, T);
  end;
end;

// Ist AName (klein) eine Ganzzahl-Konstante der RTL (RTL_CONST_PREFIXES,
// RTL_CONST_NAMES)?
function IsRtlIntConst(const ALow: string): Boolean;
var
  Prefix : string;
begin
  Result := InList(ALow, RTL_CONST_NAMES);
  for Prefix in RTL_CONST_PREFIXES do
    if Copy(ALow, 1, Length(Prefix)) = Prefix then
      Exit(Length(ALow) > Length(Prefix));
end;

// Gehoert ATypeLow zu den Nachrichten-Records (TMessage, TWMKey, TCMHitTest,
// LCL TLMessage ...)? Deren Feld Msg ist die Nachrichtennummer (Cardinal).
function IsMessageRecord(const ATypeLow: string): Boolean;
begin
  Result := (Copy(ATypeLow, 1, 3) = 'twm') or (Copy(ATypeLow, 1, 3) = 'tcm')
    or (Copy(ATypeLow, 1, 3) = 'tlm')
    or ((Length(ATypeLow) >= 7)
      and (Copy(ATypeLow, Length(ATypeLow) - 6, 7) = 'message'));
end;

// Der Typ des Namens ANameTok an der Stelle ACase (klein), '' ohne Beweis:
// Parameter oder lokale Variable einer umschliessenden Routine, sonst ein
// Feld der Klasse der Methode (OwnFieldType) oder eine Variable auf Unit-
// Ebene der Datei - die nicht, wenn die Datei eine Property dieses Namens
// deklariert; Aliasse der Datei aufgeloest ('TFoo = Integer').
function NameTypeAt(AMap: TRdxCodeMap; const ACase, ANameTok: TRdxToken): string;
var
  Bind       : TRdxLocalFind;
  Base, Name : string;
  p          : Integer;
begin
  Result := '';
  Name := TokText(AMap, ANameTok);
  Bind := TRdxTypeProof.LocalBinding(AMap, ACase, Name);
  if Bind.Kind = lkVar then
    Result := Bind.TypeLow
  // uRdxCodeMap kennt ein anderes lkNone (TRdxLiteralKind).
  else if Bind.Kind = uRdxTypeProof.lkNone then
  begin
    p := LastDelimiter('.', Bind.OuterName);
    if p > 0 then
      Result := TRdxTypeProof.OwnFieldType(AMap, Copy(Bind.OuterName, 1,
        p - 1), Name);
    if (Result = '') and not TRdxTypeProof.DeclaresProperty(AMap, Name) then
      Result := TRdxTypeProof.UnitVarType(AMap, Name);
  end;
  if Result = '' then Exit;
  Base := TRdxTypeProof.UniqueAliasBase(AMap, Result);
  if Base <> '' then
    Result := Base;
end;

// Die Token des Selektors zwischen case und of (hoechstens 64); False ohne
// 'of' oder ohne Selektor.
function SelectorTokens(AMap: TRdxCodeMap; const ACase: TRdxToken;
  out AToks: TArray<TRdxToken>): Boolean;
var
  T     : TRdxToken;
  Paren : Integer;
begin
  Result := False;
  AToks := nil;
  Paren := 0;
  T := After(AMap, ACase);
  while (T.Low <> '') and not ((T.Low = 'of') and (Paren = 0)) do
  begin
    if T.Low = '(' then
      Inc(Paren)
    else if T.Low = ')' then
      Dec(Paren);
    AddToken(AToks, T);
    if Length(AToks) > 64 then Exit;
    T := After(AMap, T);
  end;
  Result := (T.Low <> '') and (Length(AToks) > 0);
end;

// Ist der Selektor ein Name mit einer Klammer, die bis zum Ende reicht
// ('NativeUInt(lpIconName)', 'TKind(Combo.ItemIndex)')? Die ')' am Ende
// schliesst die '(' hinter dem Namen: dazwischen kehrt die Klammertiefe
// nicht auf 0 zurueck.
function IsWholeCall(const AToks: TArray<TRdxToken>): Boolean;
var
  Paren, n, i : Integer;
begin
  Result := False;
  n := Length(AToks);
  if (n < 3) or not AToks[0].IsWord or (AToks[1].Low <> '(')
     or (AToks[n - 1].Low <> ')') then
    Exit;
  Paren := 0;
  for i := 1 to n - 2 do
  begin
    if AToks[i].Low = '(' then
      Inc(Paren)
    else if AToks[i].Low = ')' then
      Dec(Paren);
    if Paren = 0 then Exit;
  end;
  Result := True;
end;

// Der Selektor wie geschrieben (mit Strings: 'Integer(X.V[''Type''])'),
// ueber Zeilen die Token.
function SelectorText(AMap: TRdxCodeMap;
  const AToks: TArray<TRdxToken>): string;
var
  T : TRdxToken;
  n : Integer;
begin
  n := Length(AToks);
  if AToks[0].Line = AToks[n - 1].Line then
    Exit(Copy(AMap.Raw(AToks[0].Line), AToks[0].Col,
      AToks[n - 1].EndCol - AToks[0].Col));
  Result := '';
  for T in AToks do
    Result := Result + TokText(AMap, T);
end;

// E5 a, nach dem Selektor: der Typ des Ausdrucks zwischen case und of, wenn
// er beweisbar keine Aufzaehlung ist - ein Name mit solchem Typ ('iStateId:
// Integer', 'var Key: Word'), eine Umwandlung ('NativeUInt(lpIconName)',
// 'Ord(..)') oder das Feld Msg eines Nachrichten-Records ('Msg.Msg' mit
// 'var Msg: TMessage'). '' oder der Grund.
function SelectorLockReason(AMap: TRdxCodeMap; const ACase: TRdxToken): string;
var
  Toks : TArray<TRdxToken>;
  n    : Integer;
  Ty   : string;
begin
  Result := '';
  if not SelectorTokens(AMap, ACase, Toks) or not Toks[0].IsWord then Exit;
  n := Length(Toks);
  Ty := '';
  if n = 1 then
    Ty := NameTypeAt(AMap, ACase, Toks[0])
  else if IsWholeCall(Toks) and InList(Toks[0].Low, NON_ENUM_TYPES) then
    Ty := Toks[0].Low
  else if (n = 3) and (Toks[1].Low = '.') and (Toks[2].Low = 'msg')
     and IsMessageRecord(NameTypeAt(AMap, ACase, Toks[0])) then
    Ty := 'cardinal';
  if (Ty = '') or not InList(Ty, NON_ENUM_TYPES) then Exit;
  Result := _('the case selector %s is of type %s, not an enumeration - '
    + 'values without an arm are normal there, and raise would break that '
    + 'path', [SelectorText(AMap, Toks), Ty]);
end;

// Review e/HilfeFixR: wandelt der Selektor einen Wert in den Aufzaehlungstyp
// ATypeName um ('THotKeySortOrder(cbCommandSortOrder.ItemIndex)' - doublecmd
// foptionshotkeys.pas:759, ItemIndex -1 ohne Auswahl; 'TViewerPaintTool(
// btnPenMode.Tag)' - fviewer.pas:1399), erreicht ein Wert ausserhalb der
// Aufzaehlung das else auf gewoehnlichem Weg - auch wenn jeder Wert des
// Typs einen Arm hat. Der Name vor der Klammer ist der Typ selbst oder ein
// Typ, den die Datei deklariert (ein Alias: dann ist es eine Umwandlung,
// kein Funktionsaufruf). '' oder der Grund (nur im Menue).
function CastSelectorReason(AMap: TRdxCodeMap; const ACase: TRdxToken;
  const ATypeName: string): string;
var
  Toks : TArray<TRdxToken>;
begin
  Result := '';
  if (ATypeName = '') or not SelectorTokens(AMap, ACase, Toks)
     or not IsWholeCall(Toks) then
    Exit;
  if not SameText(Toks[0].Low, ATypeName)
     and (TRdxTypeProof.UniqueAliasBase(AMap, TokText(AMap, Toks[0])) = '')
  then
    Exit;
  Result := _('the case selector %s converts a value to %s - a value outside '
    + 'the enumeration reaches the else, and raise would break that path',
    [SelectorText(AMap, Toks), ATypeName]);
end;

// E5 a, nach den Marken: AName ist in der Datei (AUnit = '') bzw. in der
// Unit AUnit als Konstante mit Zahl- oder String-Wert deklariert (Zeile
// ALine).
function ConstLockReason(const AName, AUnit: string; ALine: Integer): string;
begin
  if AUnit = '' then
    Result := _('the arm label %s is a constant (line %d), not a value of an '
      + 'enumeration - values without an arm are normal there, and raise '
      + 'would break that path', [AName, ALine])
  else
    Result := _('the arm label %s is a constant in the unit %s, not a value '
      + 'of an enumeration - values without an arm are normal there, and '
      + 'raise would break that path', [AName, AUnit]);
end;

// Die Namen, denen die Arme des case ACase bis AEnd etwas zuweisen ('X :='
// am Anfang einer Anweisung, auch geschachtelt; nicht 'A.X :=', 'X[i] :='),
// klein.
function AssignedInCase(AMap: TRdxCodeMap;
  const ACase, AEnd: TRdxToken): TArray<string>;
var
  T, P : TRdxToken;
begin
  Result := nil;
  P := ACase;
  T := After(AMap, ACase);
  while (T.Low <> '') and not SameTok(T, AEnd) do
  begin
    // Nicht die Laufvariable ('for I :=') und keine Inline-Variable.
    if T.IsWord and not IsKeyword(T.Low) and (After(AMap, T).Low = ':=')
       and not InList(P.Low, ['.', '^', '@', '&', 'for', 'var', 'const'])
       and not InList(T.Low, Result) then
      AddText(Result, T.Low);
    P := T;
    T := After(AMap, T);
  end;
end;

// E5 b: bekommt ein Name, dem ein Arm des case etwas zuweist, VOR dem case
// schon seinen Wert - als eigene Anweisung im selben oder einem
// umschliessenden Anweisungsteil, so dass sie das case immer erreicht
// (ISPP.IdentMan.pas:945 'Result := TYPE_ERROR;' am Anfang der Routine,
// HeidiSQL main.pas:14676 'ChildCount := 0;' vor 'if .. then case')? Dann
// behalten die Werte ohne Arm diesen Wert, das ist dort der normale Weg.
// Rueckwaerts bis zum Kopf der Routine; ganze Bloecke davor (begin..end,
// auch die Zweige eines if) zaehlen nicht, ebenso eine Zuweisung im then-
// oder else-Zweig ohne begin (sie steht nicht hinter ';' bzw. einem
// Blockanfang). '' oder der Grund.
function PresetLockReason(AMap: TRdxCodeMap;
  const ACase, AEnd: TRdxToken): string;
var
  Names : TArray<string>;
  W     : TRdxBackBalance;
  N     : TRdxToken;
  Steps : Integer;
begin
  Result := '';
  Names := AssignedInCase(AMap, ACase, AEnd);
  if Names = nil then Exit;
  Steps := 0;
  W.Start(AMap, ACase);
  while W.Next do
  begin
    Inc(Steps);
    if Steps > MAX_PRESET_BACK then Exit;
    if W.Depth = 0 then
    begin
      if W.Tok.IsWord and IsKeywordAfter(W.Tok, W.Prev)
         and InList(W.Tok.Low, PRESET_STOPS) then
        Exit;
      if (W.Tok.Low = ';') or (W.Tok.IsWord and IsKeywordAfter(W.Tok, W.Prev)
         and InList(W.Tok.Low, STATEMENT_OPENERS)) then
      begin
        N := After(AMap, W.Tok);
        if N.IsWord and InList(N.Low, Names) and (After(AMap, N).Low = ':=')
        then
          Exit(_('%s gets a value before the case (line %d) - values without '
            + 'an arm keep it, that is the normal path there; raise would '
            + 'break it', [TokText(AMap, N), N.Line]));
      end;
    end;
    W.Balance;
  end;
end;

// Der Aufzaehlungstyp der Marke AFirst aus den Units neben AUnitFile
// (TRdxTypeProof.NeighbourInterfaces): genau eine Deklaration ueber alle
// (EnumOf je Unit). AConstUnit: die Unit, die AFirst stattdessen als
// Konstante deklariert ('' ohne). False ohne Aufzaehlung.
function NeighbourEnumOf(AMap: TRdxCodeMap; const AUnitFile, AFirst: string;
  out ATypeName: string; out AValues: TArray<string>;
  out AConstUnit: string): Boolean;
var
  Texts    : TArray<string>;
  Body, Tn : string;
  Vals     : TArray<string>;
  SL       : TStringList;
  M        : TRdxCodeMap;
  Hits     : Integer;
begin
  ATypeName := '';
  AValues := nil;
  AConstUnit := '';
  Hits := 0;
  Texts := TRdxTypeProof.NeighbourInterfaces(AMap, AUnitFile, AFirst,
    NEIGHBOUR_UP_LEVELS);
  for Body in Texts do
  begin
    SL := TStringList.Create;
    M := nil;
    try
      SL.Text := Body;
      M := TRdxCodeMap.Create(SL);
      if EnumOf(M, AFirst, Tn, Vals) then
      begin
        Inc(Hits);
        ATypeName := Tn;
        AValues := Vals;
      end
      else if ConstDeclLine(M, AFirst) > 0 then
        AConstUnit := UnitNameOf(M);
    finally
      M.Free;
      SL.Free;
    end;
  end;
  Result := (Hits = 1) and (AConstUnit = '');
  if Hits > 0 then
    AConstUnit := '';
end;

class function TRdxStructFixes.CaseRaiseMenuReason(AMap: TRdxCodeMap;
  ALine: Integer; const AUnitFile: string; out ALockReason: string): string;
var
  CaseTok, EndTok, LastTok : TRdxToken;
  Labels, Values           : TArray<string>;
  Hit                      : TArray<Boolean>;
  TypeName, First, Item    : string;
  Missing, ConstUnit       : string;
  Number, Known            : Boolean;
  Li                       : Integer;
begin
  ALockReason := '';
  Result := CaseTokenOn(AMap, ALine, CaseTok);
  if Result = '' then
    Result := MatchingEnd(AMap, CaseTok, EndTok, LastTok);
  if Result <> '' then Exit;
  // E5 a: der Selektor ist keine Aufzaehlung.
  ALockReason := SelectorLockReason(AMap, CaseTok);
  if ALockReason <> '' then Exit(ALockReason);
  Known := CaseLabels(AMap, CaseTok, EndTok, Labels, Number);
  if not Known and Number then
  begin
    ALockReason := _('the arm labels are numbers - the case selects on an '
      + 'integer, values without an arm are normal there, and raise would '
      + 'break that path');
    Exit(ALockReason);
  end;
  // E5 a: eine Marke ist eine Konstante der Datei.
  if Known then
    for Item in Labels do
    begin
      Li := ConstDeclLine(AMap, LabelHead(Item));
      if Li > 0 then
      begin
        ALockReason := ConstLockReason(LabelHead(Item), '', Li);
        Exit(ALockReason);
      end;
    end;
  // Die Aufzaehlung nach der ersten Marke: in der Datei, sonst in einer
  // Unit daneben (rwE32 Stufe 4, "nur-Menue unnoetig": HeidiSQL
  // dbconnection.pas:1677 'ngMySQL' aus dbstructures.pas).
  Values := nil;
  if Known then
  begin
    First := LabelHead(Labels[0]);
    if SameText(First, 'False') or SameText(First, 'True') then
    begin
      TypeName := 'Boolean';
      AddText(Values, 'False');
      AddText(Values, 'True');
    end
    else if not EnumOf(AMap, First, TypeName, Values)
       and not NeighbourEnumOf(AMap, AUnitFile, First, TypeName, Values,
         ConstUnit) then
    begin
      TypeName := '';
      if ConstUnit <> '' then
      begin
        ALockReason := ConstLockReason(First, ConstUnit, 0);
        Exit(ALockReason);
      end;
      if IsRtlIntConst(LowerCase(First)) then
      begin
        ALockReason := _('the arm label %s is an integer constant of the RTL '
          + '(messages, keys, dialog results), not a value of an enumeration '
          + '- values without an arm are normal there, and raise would break '
          + 'that path', [First]);
        Exit(ALockReason);
      end;
    end;
  end;
  // Ein bedingter Arm oder eine bedingte Marke: welche Werte einen Arm
  // haben, haengt vom Zweig ab.
  if DirectiveBefore(AMap, CaseTok.Line, EndTok) then
    Result := _('compiler directive in the case - which values have an arm '
      + 'is not provable')
  else if not Known then
    Result := _('the arm labels are not all names of one enumeration - '
      + 'whether the values without an arm occur normally is not provable')
  else if TypeName = '' then
    // Kein Beweis, weder Aufzaehlung noch Konstante: neutral (bis rwE32
    // "die Aufzaehlung von MBI_NORMAL" - eine Integer-Konstante der RTL).
    Result := _('%s is declared neither in this file nor in a unit next to '
      + 'it - whether the values without an arm occur normally is not '
      + 'provable', [First])
  else
  begin
    SetLength(Hit, Length(Values));
    for Item in Labels do
      if not MarkLabel(Item, TypeName, Values, Hit) then
        Result := _('the arm labels are not all names of one enumeration - '
          + 'whether the values without an arm occur normally is not '
          + 'provable');
    Missing := MissingValues(Values, Hit);
    if (Result = '') and (Missing <> '') then
      Result := _('values of %s without an arm: %s - they may be normal here, '
        + 'and raise would break that path', [TypeName, Missing]);
    // Jeder Wert hat einen Arm, aber der Selektor wandelt eine Zahl um
    // (Review e/HilfeFixR): Werte ausserhalb des Typs sind dort gewoehnlich.
    if Result = '' then
      Result := CastSelectorReason(AMap, CaseTok, TypeName);
  end;
  // E5 b: nicht jeder Wert hat einen Arm, und das Ergebnis ist vorbelegt.
  if Result <> '' then
  begin
    ALockReason := PresetLockReason(AMap, CaseTok, EndTok);
    if ALockReason <> '' then
      Result := ALockReason;
  end;
end;

{ ---- SCA101 / SCA099 ---- }

class function TRdxStructFixes.BranchKeywordAt(AMap: TRdxCodeMap; ALine,
  ACol: Integer; out AKeyword: TRdxToken; out AReason: string): Boolean;
var
  L : string;
begin
  AKeyword := Default(TRdxToken);
  AReason := '';
  L := AMap.Raw(ALine);
  if ACol <= 0 then
    AReason := MsgNoColumn
  else if not AMap.IsCode(ALine, ACol) or not IsIdentStart(L[ACol])
     or ((ACol > 1) and IsIdentChar(L[ACol - 1])) then
    AReason := MsgMovedSuffix(_(R_BRANCH))
  else
  begin
    AKeyword := TokenAt(AMap, ALine, ACol);
    if not InList(AKeyword.Low, BRANCH_WORDS)
       or InList(Before(AMap, AKeyword).Low, IDENT_PREFIXES) then
      AReason := MsgMovedSuffix(_(R_BRANCH));
  end;
  Result := AReason = '';
end;

// Das end eines Paars 'end else', das uIfElseBegin meldet - nicht 'end
// else if' usw. (OneTokenOnLine, ElseAfterEndOn).
function IsEndElsePair(AMap: TRdxCodeMap; const T: TRdxToken;
  const AArg: string): Boolean;
var
  N : TRdxToken;
begin
  Result := False;
  N := After(AMap, T);
  if (T.Low <> 'end') or (N.Low <> 'else') then Exit;
  Result := not InList(Before(AMap, T).Low, IDENT_PREFIXES)
    and not InList(After(AMap, N).Low, SCA099_ALLOWED);
end;

class function TRdxStructFixes.ElseAfterEndOn(AMap: TRdxCodeMap;
  ALine: Integer; out AKeyword: TRdxToken; out AReason: string): Boolean;
var
  S      : TRdxLineSearch;
  EndTok : TRdxToken;
begin
  AKeyword := Default(TRdxToken);
  S := Default(TRdxLineSearch);
  S.Test    := IsEndElsePair;
  S.What    := _('no "end else"');           // wie CaseTokenOn
  S.ManyFmt := _('%d times "end else"');
  AReason := OneTokenOnLine(AMap, ALine, S, EndTok);
  Result := AReason = '';
  if Result then
    AKeyword := After(AMap, EndTok);
end;

// Der Besitzer muss eine Anweisung beginnen (StartsStatement).
function StatementOwner(AMap: TRdxCodeMap; const AKeyword: TRdxToken;
  const AOwners: array of string; out AOwner: TRdxToken): string;
begin
  Result := FindOwner(AMap, AKeyword, AOwners, AOwner);
  if (Result = '') and not StartsStatement(AMap, AOwner) then
    Result := _('the %s is in an expression (conditional expression, Delphi '
      + '13) - not a branch of a statement', [AOwner.Low]);
end;

// Besitzer und Einrueckung der Anweisung hinter ABranch.Keyword: then ->
// if, do -> for/while/with/on (eingerueckt wie deren Zeile); else -> if-else
// oder Liste (eingerueckt wie die else-Zeile). '' oder der Grund.
function BranchOwner(AMap: TRdxCodeMap; var ABranch: TRdxBranch): string;
var
  Kw, Owner : TRdxToken;
  Scan      : TRdxElseScan;
  L         : string;
begin
  Kw := ABranch.Keyword;
  ABranch.CheckFrom := Kw.Line;
  if Kw.Low = 'then' then
    Result := StatementOwner(AMap, Kw, IF_OWNERS, Owner)
  else if Kw.Low = 'do' then
    Result := StatementOwner(AMap, Kw, DO_OWNERS, Owner)
  else
  begin
    Scan := ElseOwner(AMap, Kw);
    Result := Scan.Reason;
    ABranch.IsList := Scan.Owner = eoList;
    ABranch.CheckFrom := Scan.Decider.Line;
    if (Result = '') and (Scan.Owner = eoIf) then
      Result := StatementOwner(AMap, Scan.Decider, IF_OWNERS, Owner);
    Owner := Kw;
  end;
  L := AMap.Raw(Owner.Line);
  ABranch.Indent := IndentOf(L);
end;

// StatementEnd, ein Token: Klammertiefe fortschreiben; rsFound an einem
// ';' oder Stopper ausserhalb von Klammern, rsStop mit AReason an einem
// gesperrten Wort.
function StatementStep(const T, APrev: TRdxToken; var AParen: Integer;
  out AReason: string): TRdxStep;
var
  IsKw  : Boolean;   // nicht 'Word': verdeckte System.Word (Review R3-06)
  Delta : Integer;
begin
  Result := rsGoOn;
  AReason := '';
  IsKw := IsKeywordAfter(T, APrev);
  Delta := ParenDelta(T);
  if Delta <> 0 then
    Inc(AParen, Delta)
  else if (AParen = 0)
     and ((T.Low = ';') or (IsKw and InList(T.Low, STATEMENT_STOPS))) then
    Result := rsFound
  else if IsKw and (InList(T.Low, NOT_IN_BRANCH)
     or InList(T.Low, STATEMENT_STOPS)) then
  begin
    AReason := _('"%s" in the statement - structure, conditional '
      + 'expression, anonymous method or inline declaration', [T.Low]);
    Result := rsStop;
  end;
end;

// Das Ende der einfachen Anweisung ab ABranch.First, ausserhalb von
// Klammern: ein ';' (HasSemi, LastLine/LastCol) oder ein Stopper (Stop).
// '' oder der Grund.
function StatementEnd(AMap: TRdxCodeMap; var ABranch: TRdxBranch): string;
var
  T, Prev : TRdxToken;
  Paren   : Integer;
  Step    : TRdxStep;
begin
  Paren := 0;
  Prev := ABranch.Keyword;
  T := ABranch.First;
  while (T.Low <> '') and (Paren >= 0) do
  begin
    Step := StatementStep(T, Prev, Paren, Result);
    if Step = rsStop then Exit;
    if Step = rsFound then
    begin
      ABranch.HasSemi := T.Low = ';';
      ABranch.Stop := T;
      ABranch.LastLine := T.Line;
      ABranch.LastCol := T.Col;
      Exit;
    end;
    Prev := T;
    T := After(AMap, T);
  end;
  Result := MsgStatementEndNotFound;
end;

// Der Haken der end-Bilanz von ListEnd (BlockEnd): eine Inline-
// Deklaration im else-Zweig sperrt.
function ListDeclHook(AMap: TRdxCodeMap; const T, APrev: TRdxToken;
  ADepth: Integer): string;
begin
  Result := '';
  if IsKeywordAfter(T, APrev) and InList(T.Low, INLINE_DECLS) then
    Result := _('inline declaration (%s) in the else branch - begin..end '
      + 'would narrow its scope', [T.Low]);
end;

// Das Ende der Anweisungsliste hinter dem else eines case oder except: das
// end, das den case bzw. try schliesst (end-Bilanz BlockEnd ab dem else).
// Endet die Liste auf ';', HasSemi. '' oder der Grund.
function ListEnd(AMap: TRdxCodeMap; var ABranch: TRdxBranch): string;
var
  EndTok, Last : TRdxToken;
begin
  Result := BlockEnd(AMap, ABranch.Keyword, ListDeclHook, EndTok, Last);
  if Result <> '' then Exit;
  if EndTok.Low = '' then
    Exit(_('no end found for the else branch'));
  ABranch.Stop := EndTok;
  ABranch.HasSemi := Last.Low = ';';
  ABranch.LastLine := Last.Line;
  ABranch.LastCol := Last.Col;
end;

// Erstes Token und Ende der Anweisung (bzw. Liste). '' oder der Grund.
function BranchEnd(AMap: TRdxCodeMap; var ABranch: TRdxBranch): string;
var
  F      : TRdxToken;
  Li, Co : Integer;
begin
  F := After(AMap, ABranch.Keyword);
  ABranch.First := F;
  if F.Low = '' then
    Exit(_('end of file after the %s', [ABranch.Keyword.Low]));
  if F.Low = 'begin' then
    Exit(MsgStaleSuffix(_('the statement is already in begin..end')));
  if (F.Low = ';') or InList(F.Low, STATEMENT_STOPS) then
    Exit(_('empty statement after the %s', [ABranch.Keyword.Low]));
  // Der Token-Leser sieht keine Strings: begaenne die Anweisung mit einem,
  // waere F nicht ihr Anfang.
  if not FirstCharAfter(AMap, ABranch.Keyword, Li, Co)
     or (Li <> F.Line) or (Co <> F.Col) then
    Exit(_('the statement starts with a string'));
  if ABranch.IsList then
    Result := ListEnd(AMap, ABranch)
  else
    Result := StatementEnd(AMap, ABranch);
  if (Result = '') and not ABranch.HasSemi
     and not LastCharBefore(AMap, ABranch.Stop, ABranch.LastLine,
       ABranch.LastCol) then
    Result := MsgStatementEndNotFound;
end;

// Eine Direktive in den Zeilen B.CheckFrom bis zur letzten Zeile der
// Anweisung bzw. ihres Stoppers? Sie stuende nach der Hilfe womoeglich auf
// der anderen Seite von begin oder end - oder sie entschied, wem ein else
// gehoert ('{$IFDEF A} if X then Y {$ELSE} case K of 1: Y; {$ENDIF} else',
// Gegen-Review SCA101, Minor 2). Zeilenweise: lieber zu streng.
function DirectiveInRange(AMap: TRdxCodeMap; const B: TRdxBranch): Boolean;
var
  Last : Integer;
begin
  Last := B.LastLine;
  if B.Stop.Line > Last then
    Last := B.Stop.Line;
  Result := DirectiveInLines(AMap, B.CheckFrom, Last);
end;

// begin und end als eigene Zeilen: hinter die Zeile des Schluesselworts
// und hinter die letzte Zeile der Anweisung (deren Rest bleibt bei ihr).
function OwnLinesEdit(AMap: TRdxCodeMap; const B: TRdxBranch;
  const ASemi, AEnd: string): TRdxEdit;
var
  Last : string;
begin
  Result := Default(TRdxEdit);
  Last := AMap.Raw(B.LastLine);
  Result.Span := TRefactorSpan.Make(SPAN_101, B.Keyword.Line, B.Keyword.Col,
    B.LastLine, Length(Last) + 1);
  Result.Expected := RangeText(AMap, Result.Span);
  Result.NewText := Copy(AMap.Raw(B.Keyword.Line), B.Keyword.Col, MaxInt)
    + #10 + B.Indent + 'begin' + #10
    + RangeText(AMap, TRefactorSpan.Make(SPAN_101, B.Keyword.Line + 1, 1,
        B.LastLine, B.LastCol + 1))
    + ASemi + Copy(Last, B.LastCol + 1, MaxInt) + #10 + B.Indent + AEnd;
end;

// Folgt der Anweisung (ohne ';') ein else auf ihrer letzten Zeile?
function ElseOnLastLine(const B: TRdxBranch): Boolean;
begin
  Result := not B.HasSemi and (B.Stop.Low = 'else')
    and (B.Stop.Line = B.LastLine);
end;

// Alles auf der Zeile des Schluesselworts: dahinter begin, die Anweisung
// eine Stufe tiefer und end in eigenen Zeilen - ein else, das auf der
// Zeile folgte, beginnt eine weitere.
function SplitLineEdit(AMap: TRdxCodeMap; const B: TRdxBranch;
  const ASemi, AEnd: string): TRdxEdit;
var
  L, Body, Gap, Tail : string;
  EndCol             : Integer;
begin
  Result := Default(TRdxEdit);
  L := AMap.Raw(B.Keyword.Line);
  Body := Trim(Copy(L, B.Keyword.EndCol, B.LastCol + 1 - B.Keyword.EndCol))
    + ASemi;
  EndCol := B.LastCol + 1;
  Tail := '';
  if ElseOnLastLine(B) then
  begin
    Gap := Trim(Copy(L, B.LastCol + 1, B.Stop.Col - B.LastCol - 1));
    if Gap <> '' then
      Body := Body + ' ' + Gap;
    EndCol := B.Stop.Col;
    Tail := #10 + B.Indent;
  end;
  Result.Span := TRefactorSpan.Make(SPAN_101, B.Keyword.Line, B.Keyword.Col,
    B.Keyword.Line, EndCol);
  Result.Expected := Copy(L, B.Keyword.Col, EndCol - B.Keyword.Col);
  Result.NewText := Copy(L, B.Keyword.Col, B.Keyword.Len) + #10 + B.Indent
    + 'begin' + #10 + B.Indent + IndentStep(B.Indent, '') + Body + #10
    + B.Indent + AEnd + Tail;
end;

// Inline: 'begin ' vor die Anweisung, ' end' hinter sie - eine Ersetzung
// auf einer Zeile, sonst zwei.
function InlineEdits(AMap: TRdxCodeMap; const B: TRdxBranch;
  const ASemi, AEnd: string): TArray<TRdxEdit>;
var
  Close : string;
begin
  Close := ASemi + ' ' + AEnd;
  if B.First.Line = B.LastLine then
  begin
    SetLength(Result, 1);
    Result[0].Span := TRefactorSpan.Make(SPAN_101, B.First.Line, B.First.Col,
      B.LastLine, B.LastCol + 1);
    Result[0].Expected := Copy(AMap.Raw(B.LastLine), B.First.Col,
      B.LastCol + 1 - B.First.Col);
    Result[0].NewText := 'begin ' + Result[0].Expected + Close;
    Exit;
  end;
  SetLength(Result, 2);
  Result[0].Span := TRefactorSpan.Make(SPAN_101, B.First.Line, B.First.Col,
    B.First.Line, B.First.EndCol);
  Result[0].Expected := Copy(AMap.Raw(B.First.Line), B.First.Col, B.First.Len);
  Result[0].NewText := 'begin ' + Result[0].Expected;
  Result[1].Span := TRefactorSpan.Make(SPAN_101, B.LastLine, B.LastCol,
    B.LastLine, B.LastCol + 1);
  Result[1].Expected := Copy(AMap.Raw(B.LastLine), B.LastCol, 1);
  Result[1].NewText := Result[1].Expected + Close;
end;

// Die Form waehlen (s. WrapInBlock): eigene Zeilen, Zeile aufteilen oder
// inline.
function BlockEdits(AMap: TRdxCodeMap; const B: TRdxBranch): TArray<TRdxEdit>;
var
  Semi, EndText : string;
begin
  Semi := ';';
  EndText := 'end';
  if B.HasSemi then
  begin
    Semi := '';
    EndText := 'end;';
  end;
  if CanAppendLine(AMap, B.Keyword.Line, B.Keyword.EndCol - 1)
     and CanAppendLine(AMap, B.LastLine, B.LastCol) then
  begin
    SetLength(Result, 1);
    Result[0] := OwnLinesEdit(AMap, B, Semi, EndText);
  end
  else if (B.First.Line = B.Keyword.Line) and (B.LastLine = B.Keyword.Line)
     and (ElseOnLastLine(B) or TailIsComment(AMap, B.LastLine, B.LastCol)) then
  begin
    SetLength(Result, 1);
    Result[0] := SplitLineEdit(AMap, B, Semi, EndText);
  end
  else
    Result := InlineEdits(AMap, B, Semi, EndText);
end;

class function TRdxStructFixes.WrapInBlock(AMap: TRdxCodeMap;
  const AKeyword: TRdxToken; out AEdits: TArray<TRdxEdit>;
  out AReason: string): Boolean;
var
  B : TRdxBranch;
begin
  Result := False;
  AEdits := nil;
  B := Default(TRdxBranch);
  B.Keyword := AKeyword;
  if not InList(AKeyword.Low, BRANCH_WORDS) then
    AReason := MsgMovedSuffix(_(R_BRANCH))
  else
    AReason := BranchOwner(AMap, B);
  if AReason = '' then
    AReason := BranchEnd(AMap, B);
  if (AReason = '') and DirectiveInRange(AMap, B) then
    AReason := _('compiler directive in the range - begin or end would be '
      + 'on the other side');
  if AReason <> '' then Exit;
  AEdits := BlockEdits(AMap, B);
  Result := True;
end;

end.
