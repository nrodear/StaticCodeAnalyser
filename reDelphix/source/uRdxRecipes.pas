unit uRdxRecipes;

// reDelphix - die Rezepte: aus beschriebenen Quellstellen (TRefactorInfo
// aus dem SCA-Core, Konzept_SourceRefactor_Quellstellen Abschnitt 5) neuen
// Quelltext bauen. Reine Textarbeit - kein ToolsAPI, keine Datei, kein
// VCL. Deshalb laeuft diese Unit im FPC-Pruefstand und ihre Tests sind
// ohne IDE ausfuehrbar.
//
// WAS HIER ENTSTEHT
//
//   BuildFormatCall   'a' + X + 'b'      ->  Format('a%sb', [X])
//   BuildSqlTemplate  Q.SQL.Text := 'SELECT ... ' + Id
//                     ->  Q.SQL.Text := 'SELECT ... :p1';
//                         Q.ParamByName('p1').Value := Id;      (Vorlage)
//   DetectFramework   VCL oder FMX, aus den qualifizierten uses-Eintraegen
//
// Die Fakten kommen aus dem Core (Teilbereiche mit Rolle und Typ), die
// Politik steht hier: ein Format() wird nur gebaut, wenn JEDER Operand
// beweisbar ein String ist (sonst %d-fuer-String: uebersetzt, wirft zur
// Laufzeit EConvertError), und nie fuer SQL-Text (SCA003 - Vertrag im
// Kopf von uRefactorConcat).
//
// LITERALE
//
// Ein Teilbereich mit ROLE_LITERAL traegt den QUELLTEXT des Literals
// ('it''s', 'a'#13#10'b', #$41). DecodeLiteral macht daraus den Wert,
// EncodeLiteral den Quelltext zurueck - so bleibt ein '%' im Wert
// escapebar ('%%') und Steuerzeichen bleiben als #13#10 lesbar.

interface

uses
  System.SysUtils, System.Classes,
  uRefactorInfo;

type
  // Ein Teilbereich mit seinem Quelltext - die Form, in der die Rezepte
  // die Parts eines TRefactorInfo bekommen (der Text kommt aus
  // TSourcePlaces.TextOf, hier wird keine Datei gelesen).
  TRdxPart = record
    Role        : string;
    Text        : string;
    ValueType   : TRefactorValueType;
    // Deklarierter Typ des Operanden (nackt, klein; TRefactorSpan.Resolved
    // nach TSourcePlaces.ResolveOperandTypes), sonst ''.
    Resolved    : string;
    // Deklarierter Typ des einzigen Bezeichner-Arguments bei IntToStr(x) -
    // dann wird daraus %d/%u mit x statt %s (AH20). x.ToString bleibt
    // %s: ein eigener Integer-Helper koennte anders formatieren (AH22).
    ArgResolved : string;
    // Deklarierter Typ des KOPF-Bezeichners eines Member-/Index-Terms
    // ('V.Name', 'V[0]' bei V: Variant) - Variant-Anzeichen (AH22).
    HeadResolved : string;
  end;
  TRdxParts = TArray<TRdxPart>;

  // Urteil ueber einen Operanden fuer %s (Kompilat-Regel, AH20).
  TRdxOperandVerdict = (
    ovString,       // beweisbar String: Literal, deklariert, bekannter RTL-Aufruf/-Konstante, .ToString
    ovByCompiler,   // Typ unbekannt, aber die FORM ist ein Operand - das Kompilat buergt
    ovNonString,    // deklariert Zahl/Boolean/Datum oder Zahl-Cast
    ovAnsi,         // deklariert Nicht-Unicode-String - Format liefert UnicodeString
    ovVariantRisk,  // Variant-Anzeichen: deklariert Variant, .Value/.AsVariant, Null/True/nil
    ovNoOperand);   // keine Operandenform: Klammerausdruck, Zahl, Menge, Operator

  // Ergebnis von BuildFormatCall mit der Herkunft der Argumente.
  TRdxFormatBuild = record
    NewText    : string;
    Reason     : string;           // bei False
    Operands   : Integer;          // Argumente im Format-Aufruf
    Proven     : Integer;          // davon beweisbar (String oder Ganzzahl mit %d/%u)
    Numeric    : Integer;          // davon als %d/%u statt IntToStr/ToString
    ByCompiler : TArray<string>;   // Operanden, fuer die nur das Kompilat buergt
  end;

  TRdxFramework = (fwUnknown, fwVcl, fwFmx, fwBoth);

  TRdxRecipes = class
  public
    class function MakePart(const ARole, AText: string;
      AValueType: TRefactorValueType = rvUnknown;
      const AResolved: string = '';
      const AArgResolved: string = ''): TRdxPart; static;

    // Quelltext eines Pascal-String-Literals -> Wert. False bei allem,
    // was kein reines Literal ist (unbalancierte Quotes, '^M', Bezeichner).
    class function DecodeLiteral(const ASource: string;
      out AValue: string): Boolean; static;
    // Wert -> Quelltext: Quotes verdoppelt, Steuerzeichen (< #32) als #nn.
    class function EncodeLiteral(const AValue: string): string; static;

    // Zeilenumbrueche und Tabulatoren zu einem Leerzeichen, aussen getrimmt.
    class function CollapseWhitespace(const AText: string): string; static;

    // True, wenn der Text wie ein SQL-Statement aussieht: ein Statement-
    // Verb (select/insert/update/...) UND ein Strukturwort (from/into/
    // set/where/...) als ganze Woerter. 'Update available for' allein
    // ist KEIN SQL.
    class function LooksLikeSql(const AValue: string): Boolean; static;

    // Rezept 5.1 - Format() aus einer '+'-Kette. AParts in Quelltext-
    // Reihenfolge, Parts[0] darf ROLE_TARGET sein (wird uebersprungen).
    // False mit Grund, wenn ein Operand nach der Kompilat-Regel nicht
    // als %s taugt (JudgeOperand), kein Operand oder kein Literal
    // vorkommt, schon ein Format() in der Kette steht, ein Teil keine
    // Kette ist (ROLE_ARGUMENT) oder die Literale SQL ergeben.
    // IntToStr(x) / x.ToString mit bekanntem Ganzzahltyp werden %d/%u.
    // ATargetType: deklarierter Typ des Ziels (nackt, klein), wenn bekannt;
    // bei einem Unicode-Ziel (string/unicodestring/widestring) duerfen
    // Nicht-Unicode-Operanden mit, Format wandelt sie wie die Zuweisung.
    class function BuildFormatCall(const AParts: TRdxParts;
      out ABuild: TRdxFormatBuild;
      const ATargetType: string = ''): Boolean; overload; static;
    class function BuildFormatCall(const AParts: TRdxParts;
      out ANewText, AReason: string): Boolean; overload; static;

    // Leerraum zusammenziehen wie CollapseWhitespace, aber String-
    // Literale im Text bleiben Zeichen fuer Zeichen erhalten: der Text
    // eines Operanden wird so in den Format-Aufruf uebernommen
    // (StringReplace(S, '  ', ' ', ...) behaelt die zwei Leerzeichen; AH22).
    class function CollapseCode(const AText: string): string; static;

    // ---- Kompilat-Regel (AH20, Realworld-Stichprobe 2026-10-06) ----------
    //
    // Mit "nur beweisbar String" waeren am Korpus hoechstens 17 % der
    // SCA044-Stellen umformbar (Nachbildung an 200 von 2.363 Funden). Das
    // Kompilat buergt fuer mehr: eine '+'-Kette mit einem String-Literal
    // uebersetzt nur, wenn jeder Operand String-vertraeglich ist (String,
    // Char, PChar, AnsiString, Char-Array, ...) - oder ein Variant - oder
    // ein Record mit Implicit-Operator. %s nimmt die ersten beiden
    // (System.SysUtils.FormatBuf: vtVariant -> VariantToUnicodeString);
    // ein Record uebersetzt im Format-Aufruf nicht (sichtbarer Fehler,
    // Strg+Z - ohne Typinformation fremder Units nicht erkennbar).
    // Variant ist dennoch gesperrt: ist der Wert Null oder keine
    // Zeichenkette, wirft das Original (NullStrictConvert, Variant-
    // Arithmetik String+Zahl) oder die ganze Kette wird '' - Format gaebe
    // still die uebrigen Teile aus. Deshalb gilt ein Operand UNBEKANNTEN
    // Typs, wenn seine Form ein Operand ist (Bezeichner, Member, Aufruf,
    // Index, Cast) und er keine Variant-Anzeichen traegt; Zahlen, Zahl-
    // Casts, Klammerausdruecke und Mengen bleiben gesperrt. Ein deklarierter
    // Nicht-Unicode-String (AnsiString, RawByteString, UTF8String,
    // ShortString, RawUtf8) sperrt als Ziel immer und als Operand, wenn
    // das Ziel nicht nachweislich Unicode ist: Format liefert
    // UnicodeString. Ertrag in der Nachbildung: 83 %.

    // True, wenn der Text die Form eines Operanden hat: Bezeichner (oder
    // eine Klammergruppe mit folgendem '.', '[' oder '^', z. B.
    // '(Sender as TButton).Caption'), dann beliebig '.Bezeichner',
    // '(...)', '[...]', '^'. Literale im Text stoeren nicht. Kein
    // Operator, keine Zahl, kein blosser Klammerausdruck.
    class function IsOperandShape(const AText: string): Boolean; static;
    // True bei Variant-Anzeichen: letzter Name .Value/.AsVariant/
    // FieldValues, die Bezeichner Null/Unassigned/True/False/nil, ein
    // Variant(...)-Cast, ein mit String-Literal indizierter Bezeichner
    // (DS['Name'] = TDataSet.FieldValues).
    class function HasVariantTell(const AText: string): Boolean; static;
    // Der erste Bezeichner des Textes ('Obj' aus 'Obj.Items[i].Name'),
    // sonst ''.
    class function HeadIdentOf(const AText: string): string; static;
    // RTL-Konstanten mit String-Typ: sLineBreak, PathDelim, ...
    class function IsKnownStringConst(const AText: string): Boolean; static;
    // RTL-Funktionen mit String-Ergebnis jenseits der Core-Liste
    // (ExtractFileName, Copy, StringReplace, TPath.Combine, ...), deren
    // Klammer den ganzen Term abschliesst; qualifiziert nur mit
    // SysUtils/StrUtils/IOUtils.
    class function IsKnownStringFunc(const AText: string): Boolean; static;
    // AnsiString, RawByteString, UTF8String, ShortString, RawUtf8,
    // PAnsiChar, AnsiChar.
    class function IsNonUnicodeStringType(const ATypeLow: string): Boolean;
      static;
    class function IsPlainIdent(const AText: string): Boolean; static;
    class function JudgeOperand(const APart: TRdxPart): TRdxOperandVerdict;
      static;
    // '%d' fuer vorzeichenbehaftete Ganzzahlen und Byte/Word, '%u' fuer
    // Cardinal/LongWord/UInt32/UInt64/NativeUInt, sonst ''.
    class function IntegerSpec(const ATypeLow: string): string; static;
    // 'x' aus 'IntToStr(x)' (nur ein nackter Bezeichner), sonst ''.
    // 'x.ToString' absichtlich nicht: ein eigener Helper fuer Integer
    // kann anders formatieren als IntToStr (AH22).
    class function IntegerArgumentOf(const AText: string): string; static;
    // IntToStr(x) mit x = Bezeichner bekannten Ganzzahltyps
    // (APart.ArgResolved): dann Argument x und Spezifikator %d/%u.
    class function NumericArgument(const APart: TRdxPart;
      out AArgument, ASpec: string): Boolean; static;

    // Das Query-Objekt eines SQL-Ziels: 'Query.SQL.Text' -> 'Query',
    // 'FDQuery1.SQL.Add' -> 'FDQuery1', 'Cmd.CommandText' -> 'Cmd'.
    class function QueryObjectOf(const ATarget: string): string; static;

    // Rezept 5.2 - parametrisierte Vorlage (nie geschrieben, nur Text).
    // AIsCall: das Ziel ist ein Aufrufkopf (Q.SQL.Add) statt einer
    // Zuweisung. AIndent: fuehrende Leerzeichen je Zeile.
    class function BuildSqlTemplate(const ATarget: string; AIsCall: Boolean;
      const AParts: TRdxParts; AIndent: Integer;
      out ATemplate, AReason: string): Boolean; static;

    // Rahmenwerk einer Datei aus ihren uses-Eintraegen (qualifizierte
    // Namen 'Vcl.*' / 'FMX.*').
    class function DetectFramework(
      const AUnitNames: TArray<string>): TRdxFramework; static;
    // True, wenn AShortName als Eintrag vorkommt - unqualifiziert oder
    // als letztes Segment ('SysUtils' trifft 'System.SysUtils').
    class function HasUnit(const AUnitNames: TArray<string>;
      const AShortName: string): Boolean; static;

    // ---- uses-Klausel ergaenzen (AH19: Format() braucht System.SysUtils) --

    // Der Name, unter dem eine RTL-Unit in DIESE Datei passt: der
    // qualifizierte, wenn die Datei qualifizierte Namen benutzt oder noch
    // keinen uses-Eintrag hat; sonst der Kurzname (eine Datei, die
    // 'Classes, Windows' schreibt, bekommt 'SysUtils').
    class function UsesNameFor(const AUnitNames: TArray<string>;
      const AShortName, AQualifiedName: string): string; static;
    // True, wenn die Namen case-insensitiv aufsteigend sortiert sind -
    // dasselbe Kriterium wie SCA142 UnsortedUses (CompareText).
    class function IsSortedUses(const AUnitNames: TArray<string>): Boolean;
      static;
    // Index des Eintrags, VOR dem ANewName einzufuegen ist, damit eine
    // sortierte Liste sortiert bleibt; Length(AUnitNames) = anhaengen.
    // Eine unsortierte Liste bekommt den Neuen vorn (0) - dort faellt
    // er dem Leser am ehesten auf und erzeugt keinen neuen SCA142-Fund,
    // denn der steht dort schon.
    class function SortedInsertIndex(const AUnitNames: TArray<string>;
      const ANewName: string): Integer; static;
  end;

implementation

const
  SQL_VERBS: array[0..8] of string = (
    'select', 'insert', 'update', 'delete', 'create', 'alter', 'drop',
    'truncate', 'merge');
  SQL_WORDS: array[0..8] of string = (
    'from', 'into', 'set', 'where', 'table', 'values', 'join', 'index',
    'view');

function InList(const AValue: string; const AList: array of string): Boolean;
var
  i : Integer;
begin
  Result := False;
  for i := Low(AList) to High(AList) do
    if AList[i] = AValue then
      Exit(True);
end;

function HexValue(C: Char): Integer;
begin
  case C of
    '0'..'9': Result := Ord(C) - Ord('0');
    'a'..'f': Result := Ord(C) - Ord('a') + 10;
    'A'..'F': Result := Ord(C) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

function CharStr(C: Char): string;
// Ein Zeichen als String: TStringBuilder.Append(Char) ist unter FPC
// (delphiunicode) mehrdeutig, Append(string) nicht.
begin
  Result := C;
end;

function LastSegment(const AName: string): string;
var
  P : Integer;
begin
  P := LastDelimiter('.', AName);
  Result := Copy(AName, P + 1, MaxInt);
end;

{ TRdxRecipes }

class function TRdxRecipes.MakePart(const ARole, AText: string;
  AValueType: TRefactorValueType; const AResolved, AArgResolved: string): TRdxPart;
begin
  Result.Role         := ARole;
  Result.Text         := AText;
  Result.ValueType    := AValueType;
  Result.Resolved     := AResolved;
  Result.ArgResolved  := AArgResolved;
  Result.HeadResolved := '';
end;

class function TRdxRecipes.DecodeLiteral(const ASource: string;
  out AValue: string): Boolean;
var
  SB     : TStringBuilder;
  i, n   : Integer;
  Code   : Integer;
  Digits : Integer;
  Closed : Boolean;
  Hex    : Integer;
begin
  Result := False;
  AValue := '';
  n := Length(ASource);
  SB := TStringBuilder.Create;
  try
    i := 1;
    while i <= n do
    begin
      if ASource[i] <= ' ' then
      begin
        Inc(i);
        Continue;
      end;
      if ASource[i] = '''' then
      begin
        Inc(i);
        Closed := False;
        while i <= n do
        begin
          if ASource[i] = '''' then
          begin
            if (i < n) and (ASource[i + 1] = '''') then
            begin
              SB.Append('''');
              Inc(i, 2);
            end
            else
            begin
              Inc(i);
              Closed := True;
              Break;
            end;
          end
          else
          begin
            SB.Append(CharStr(ASource[i]));
            Inc(i);
          end;
        end;
        if not Closed then Exit;
      end
      else if ASource[i] = '#' then
      begin
        Inc(i);
        Code   := 0;
        Digits := 0;
        if (i <= n) and (ASource[i] = '$') then
        begin
          Inc(i);
          while i <= n do
          begin
            Hex := HexValue(ASource[i]);
            if Hex < 0 then Break;
            Code := Code * 16 + Hex;
            Inc(i);
            Inc(Digits);
            if Code > $FFFF then Exit;
          end;
        end
        else
          while (i <= n) and CharInSet(ASource[i], ['0'..'9']) do
          begin
            Code := Code * 10 + (Ord(ASource[i]) - Ord('0'));
            Inc(i);
            Inc(Digits);
            if Code > $FFFF then Exit;
          end;
        if Digits = 0 then Exit;
        SB.Append(CharStr(Char(Code)));
      end
      else
        Exit;
    end;
    AValue := SB.ToString;
    Result := True;
  finally
    SB.Free;
  end;
end;

class function TRdxRecipes.EncodeLiteral(const AValue: string): string;
var
  SB      : TStringBuilder;
  i       : Integer;
  InQuote : Boolean;
  C       : Char;
begin
  if AValue = '' then Exit('''''');
  SB := TStringBuilder.Create;
  try
    InQuote := False;
    for i := 1 to Length(AValue) do
    begin
      C := AValue[i];
      if C < ' ' then
      begin
        if InQuote then
        begin
          SB.Append('''');
          InQuote := False;
        end;
        SB.Append('#');
        SB.Append(IntToStr(Ord(C)));
      end
      else
      begin
        if not InQuote then
        begin
          SB.Append('''');
          InQuote := True;
        end;
        if C = '''' then
          SB.Append('''''')
        else
          SB.Append(CharStr(C));
      end;
    end;
    if InQuote then
      SB.Append('''');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

class function TRdxRecipes.CollapseWhitespace(const AText: string): string;
var
  i         : Integer;
  LastWhite : Boolean;
  C         : Char;
begin
  Result := '';
  LastWhite := True;   // fuehrenden Leerraum verschlucken
  for i := 1 to Length(AText) do
  begin
    C := AText[i];
    if C <= ' ' then
    begin
      if not LastWhite then
        Result := Result + ' ';
      LastWhite := True;
    end
    else
    begin
      Result := Result + C;
      LastWhite := False;
    end;
  end;
  Result := TrimRight(Result);
end;

class function TRdxRecipes.LooksLikeSql(const AValue: string): Boolean;
var
  Low     : string;
  i       : Integer;
  Word    : string;
  HasVerb : Boolean;
  HasWord : Boolean;

  procedure Flush;
  begin
    if Word = '' then Exit;
    if InList(Word, SQL_VERBS) then HasVerb := True;
    if InList(Word, SQL_WORDS) then HasWord := True;
    Word := '';
  end;

begin
  Low := LowerCase(AValue);
  HasVerb := False;
  HasWord := False;
  Word := '';
  for i := 1 to Length(Low) do
    if CharInSet(Low[i], ['a'..'z']) then
      Word := Word + Low[i]
    else
      Flush;
  Flush;
  Result := HasVerb and HasWord;
end;

{ ---- Kompilat-Regel (AH20) ---- }

const
  NON_UNICODE_STRING_TYPES: array[0..6] of string = (
    'ansistring', 'rawbytestring', 'utf8string', 'shortstring', 'rawutf8',
    'pansichar', 'ansichar');
  // RTL-Aliase auf string, die der Core-Resolver nicht als String kennt.
  STRING_ALIAS_TYPES: array[0..3] of string = (
    'tfilename', 'tcaption', 'tcomponentname', 'thintstring');
  SIGNED_INT_TYPES: array[0..12] of string = (
    'integer', 'int64', 'smallint', 'shortint', 'longint', 'nativeint',
    'int32', 'int16', 'int8', 'byte', 'word', 'uint8', 'uint16');
  UNSIGNED_INT_TYPES: array[0..7] of string = (
    'cardinal', 'longword', 'dword', 'uint32', 'uint64', 'qword',
    'nativeuint', 'ptruint');
  // Casts auf Zahl/Boolean: in einer String-Kette nur hinter einem
  // Variant uebersetzbar - und dann scheitert %s.
  NUMERIC_CAST_HEADS: array[0..21] of string = (
    'integer', 'cardinal', 'int64', 'uint64', 'word', 'byte', 'smallint',
    'shortint', 'longint', 'longword', 'nativeint', 'nativeuint', 'dword',
    'single', 'double', 'extended', 'currency', 'boolean', 'bytebool',
    'wordbool', 'longbool', 'tdatetime');
  KNOWN_STRING_CONSTS: array[0..8] of string = (
    'slinebreak', 'pathdelim', 'drivedelim', 'pathsep', 'emptystr',
    'lineending', 'directoryseparator', 'pathseparator', 'driveseparator');
  // Jenseits von uRefactorConcat.KNOWN_STRING_FUNCS (die der Core schon
  // als rvString liefert): Dateinamen, Teilstrings, Ersetzen, Codecs.
  EXT_STRING_FUNCS: array[0..51] of string = (
    'extractfilename', 'extractfilepath', 'extractfileext', 'extractfiledir',
    'extractfiledrive', 'changefileext', 'changefilepath',
    'includetrailingpathdelimiter', 'excludetrailingpathdelimiter',
    'includetrailingbackslash', 'excludetrailingbackslash', 'expandfilename',
    'expanduncfilename', 'extractshortpathname', 'extractrelativepath',
    'getcurrentdir', 'copy', 'stringreplace', 'chr', 'strpas',
    'ansireplacestr', 'replacestr', 'replacetext', 'ansireplacetext',
    'leftstr', 'rightstr', 'midstr', 'ansileftstr', 'ansirightstr',
    'ansimidstr', 'getenumname', 'vartostr', 'vartostrdef', 'utf8tostring',
    'utf8encode', 'utf8decode', 'utf8toansi', 'ansitoutf8',
    'utf8tounicodestring', 'wraptext', 'adjustlinebreaks', 'dequotedstr',
    'ansidequotedstr', 'currtostrf', 'formatcurr', 'getenvironmentvariable',
    'paramstr', 'reversestring', 'ansireversestring', 'stuffstring',
    'guidtostring', 'concat');
  TPATH_STRING_FUNCS: array[0..7] of string = (
    'tpath.combine', 'tpath.getfilename', 'tpath.getdirectoryname',
    'tpath.getextension', 'tpath.getfilenamewithoutextension',
    'tpath.gettemppath', 'tpath.changeextension', 'tpath.getfullpath');
  KNOWN_UNIT_QUALIFIERS: array[0..5] of string = (
    'sysutils', 'system.sysutils', 'strutils', 'system.strutils',
    'ioutils', 'system.ioutils');
  VARIANT_TELLS: array[0..7] of string = (
    'value', 'asvariant', 'fieldvalues', 'null', 'unassigned', 'true',
    'false', 'nil');

function IsIdentStartCh(C: Char): Boolean;
begin
  // Zeichen > #127 wie der Core (uRefactorInfoBuilder.IsIdentStart):
  // Bezeichner mit Umlaut sind in Delphi erlaubt.
  Result := (C = '_') or ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z'))
    or (C > #127);
end;

function IsIdentCh(C: Char): Boolean;
begin
  Result := IsIdentStartCh(C) or ((C >= '0') and (C <= '9'));
end;

// Literale ('...' mit '' und #nn) durch 'x' ersetzen, damit Klammern und
// Operatoren in Strings die Formpruefung nicht stoeren.
function BlankLiterals(const S: string): string;
var
  i, n : Integer;
begin
  Result := '';
  n := Length(S);
  i := 1;
  while i <= n do
  begin
    if S[i] = '''' then
    begin
      Inc(i);
      while i <= n do
      begin
        if S[i] = '''' then
        begin
          if (i < n) and (S[i + 1] = '''') then
          begin
            Inc(i, 2);
            Continue;
          end;
          Inc(i);
          Break;
        end;
        Inc(i);
      end;
      Result := Result + 'x';
    end
    else if (S[i] = '#') and (i < n) and CharInSet(S[i + 1], ['0'..'9', '$']) then
    begin
      Inc(i);
      if S[i] = '$' then Inc(i);
      while (i <= n) and CharInSet(S[i], ['0'..'9', 'A'..'F', 'a'..'f']) do
        Inc(i);
      Result := Result + 'x';
    end
    else
    begin
      Result := Result + S[i];
      Inc(i);
    end;
  end;
end;

// Kopf eines Aufrufs (Text vor der ersten '('), klein; '' wenn die
// Klammer hinter dem Kopf nicht den ganzen Term abschliesst.
function CallHeadOf(const AText: string): string;
var
  S     : string;
  P, i  : Integer;
  Depth : Integer;
begin
  Result := '';
  S := BlankLiterals(Trim(AText));
  P := Pos('(', S);
  if (P < 2) or (S[Length(S)] <> ')') then Exit;
  Depth := 0;
  for i := P to Length(S) do
  begin
    if S[i] = '(' then Inc(Depth)
    else if S[i] = ')' then
    begin
      Dec(Depth);
      if (Depth = 0) and (i < Length(S)) then Exit;   // 'Foo(a).Bar(b)'
    end;
  end;
  if Depth <> 0 then Exit;
  Result := LowerCase(Trim(Copy(S, 1, P - 1)));
end;

class function TRdxRecipes.IsPlainIdent(const AText: string): Boolean;
var
  i : Integer;
begin
  Result := (AText <> '') and IsIdentStartCh(AText[1]);
  for i := 2 to Length(AText) do
    if not IsIdentCh(AText[i]) then Exit(False);
end;

class function TRdxRecipes.IsOperandShape(const AText: string): Boolean;
var
  S         : string;
  i, n, k   : Integer;
  Depth     : Integer;
  WantIdent : Boolean;
begin
  Result := False;
  S := BlankLiterals(Trim(AText));
  n := Length(S);
  if n = 0 then Exit;
  i := 1;
  WantIdent := True;
  // Fuehrende Klammergruppe nur mit Member-/Index-/Deref-Zugriff dahinter:
  // '(Sender as TButton).Caption' ja, '(a + b)' nein.
  if S[1] = '(' then
  begin
    Depth := 0;
    repeat
      if CharInSet(S[i], ['(', '[']) then Inc(Depth)
      else if CharInSet(S[i], [')', ']']) then Dec(Depth);
      Inc(i);
    until (Depth = 0) or (i > n);
    if Depth <> 0 then Exit;
    k := i;
    while (k <= n) and (S[k] <= ' ') do Inc(k);
    if (k > n) or not CharInSet(S[k], ['.', '[', '^']) then Exit;
    WantIdent := False;
  end;
  while i <= n do
  begin
    if WantIdent then
    begin
      if S[i] = '&' then Inc(i);   // &Type, Item.&End
      if (i > n) or not IsIdentStartCh(S[i]) then Exit;
      while (i <= n) and IsIdentCh(S[i]) do Inc(i);
      WantIdent := False;
      Continue;
    end;
    if S[i] <= ' ' then
    begin
      Inc(i);
      Continue;
    end;
    case S[i] of
      '.':
        begin
          Inc(i);
          WantIdent := True;
        end;
      '^':
        Inc(i);
      '(', '[':
        begin
          Depth := 0;
          repeat
            if CharInSet(S[i], ['(', '[']) then Inc(Depth)
            else if CharInSet(S[i], [')', ']']) then Dec(Depth);
            Inc(i);
          until (Depth = 0) or (i > n);
          if Depth <> 0 then Exit;
        end;
    else
      Exit;
    end;
  end;
  Result := not WantIdent;
end;

// 'DS[''Name'']': ein Bezeichner, direkt mit einem String-Literal
// indiziert, nichts dahinter - TDataSet.FieldValues (Default-Property,
// Variant). Ein TDictionary<string, string> sieht genauso aus und wird
// mitgesperrt (bekannte Grenze).
function IsStringIndexedIdent(const S: string): Boolean;
var
  i, n  : Integer;
  Inner : string;
begin
  Result := False;
  n := Length(S);
  i := 1;
  if (n = 0) or not IsIdentStartCh(S[1]) then Exit;
  while (i <= n) and IsIdentCh(S[i]) do Inc(i);
  while (i <= n) and (S[i] <= ' ') do Inc(i);
  if (i > n) or (S[i] <> '[') or (S[n] <> ']') then Exit;
  Inner := Trim(Copy(S, i + 1, n - i - 1));
  Result := (Length(Inner) >= 2) and (Inner[1] = '''')
    and (Inner[Length(Inner)] = '''')
    and (Pos('''', Copy(Inner, 2, Length(Inner) - 2)) = 0);
end;

class function TRdxRecipes.HasVariantTell(const AText: string): Boolean;
var
  S     : string;
  i, n  : Integer;
  Depth : Integer;
  Last  : string;
  Head  : string;
begin
  S := BlankLiterals(Trim(AText));
  n := Length(S);
  Depth := 0;
  Last := '';
  Head := '';
  i := 1;
  while i <= n do
  begin
    if (Depth = 0) and IsIdentStartCh(S[i]) then
    begin
      Last := '';
      while (i <= n) and IsIdentCh(S[i]) do
      begin
        Last := Last + S[i];
        Inc(i);
      end;
      if Head = '' then Head := Last;
      Continue;
    end;
    if CharInSet(S[i], ['(', '[']) then Inc(Depth)
    else if CharInSet(S[i], [')', ']']) then Dec(Depth);
    Inc(i);
  end;
  Head := LowerCase(Head);
  Result := InList(LowerCase(Last), VARIANT_TELLS)
    or (Head = 'variant') or (Head = 'olevariant')
    or IsStringIndexedIdent(Trim(AText));
end;

class function TRdxRecipes.HeadIdentOf(const AText: string): string;
var
  S : string;
  i : Integer;
begin
  Result := '';
  S := Trim(AText);
  i := 1;
  if (i <= Length(S)) and (S[i] = '&') then Inc(i);
  if (i > Length(S)) or not IsIdentStartCh(S[i]) then Exit;
  while (i <= Length(S)) and IsIdentCh(S[i]) do
  begin
    Result := Result + S[i];
    Inc(i);
  end;
end;

class function TRdxRecipes.IsKnownStringConst(const AText: string): Boolean;
var
  S    : string;
  Dot  : Integer;
  Qual : string;
begin
  S := LowerCase(Trim(AText));
  Dot := LastDelimiter('.', S);
  if Dot > 0 then
  begin
    Qual := Copy(S, 1, Dot - 1);
    S := Copy(S, Dot + 1, MaxInt);
    if not InList(Qual, KNOWN_UNIT_QUALIFIERS) then Exit(False);
  end;
  Result := InList(S, KNOWN_STRING_CONSTS);
end;

class function TRdxRecipes.IsKnownStringFunc(const AText: string): Boolean;
var
  Head : string;
  Dot  : Integer;
  Qual : string;
begin
  Result := False;
  Head := CallHeadOf(AText);
  if Head = '' then Exit;
  if InList(Head, TPATH_STRING_FUNCS) then Exit(True);
  Dot := LastDelimiter('.', Head);
  if Dot > 0 then
  begin
    Qual := Copy(Head, 1, Dot - 1);
    Head := Copy(Head, Dot + 1, MaxInt);
    if not InList(Qual, KNOWN_UNIT_QUALIFIERS) then Exit;
  end;
  Result := InList(Head, EXT_STRING_FUNCS);
end;

class function TRdxRecipes.IsNonUnicodeStringType(
  const ATypeLow: string): Boolean;
begin
  Result := InList(ATypeLow, NON_UNICODE_STRING_TYPES);
end;

class function TRdxRecipes.JudgeOperand(
  const APart: TRdxPart): TRdxOperandVerdict;
var
  Text : string;
  Head : string;
begin
  Text := Trim(APart.Text);
  if APart.Role = ROLE_LITERAL then Exit(ovString);
  if APart.Resolved <> '' then
  begin
    if IsNonUnicodeStringType(APart.Resolved) then Exit(ovAnsi);
    if (APart.Resolved = 'variant') or (APart.Resolved = 'olevariant') then
      Exit(ovVariantRisk);
    if InList(APart.Resolved, STRING_ALIAS_TYPES) then Exit(ovString);
  end;
  // 'V.Name', 'V[0]' mit V: Variant - spaet gebunden, der Wert ist Variant.
  if (APart.HeadResolved = 'variant') or (APart.HeadResolved = 'olevariant') then
    Exit(ovVariantRisk);
  if APart.ValueType = rvNonString then Exit(ovNonString);
  if APart.ValueType = rvString then Exit(ovString);
  if IsKnownStringConst(Text) or IsKnownStringFunc(Text) then Exit(ovString);
  if HasVariantTell(Text) then Exit(ovVariantRisk);
  Head := CallHeadOf(Text);
  if (Head <> '') and InList(Head, NUMERIC_CAST_HEADS) then Exit(ovNonString);
  if not IsOperandShape(Text) then Exit(ovNoOperand);
  Result := ovByCompiler;
end;

class function TRdxRecipes.IntegerSpec(const ATypeLow: string): string;
begin
  if InList(ATypeLow, SIGNED_INT_TYPES) then
    Result := '%d'
  else if InList(ATypeLow, UNSIGNED_INT_TYPES) then
    Result := '%u'
  else
    Result := '';
end;

class function TRdxRecipes.IntegerArgumentOf(const AText: string): string;
var
  T   : string;
  Low : string;
begin
  Result := '';
  T := CollapseWhitespace(AText);
  Low := LowerCase(T);
  if (Copy(Low, 1, 9) = 'inttostr(') and (Low[Length(Low)] = ')') then
    Result := Trim(Copy(T, 10, Length(T) - 10));
  if not IsPlainIdent(Result) then Result := '';
end;

class function TRdxRecipes.CollapseCode(const AText: string): string;
var
  i, n      : Integer;
  LastWhite : Boolean;
  C         : Char;
begin
  Result := '';
  LastWhite := True;
  n := Length(AText);
  i := 1;
  while i <= n do
  begin
    C := AText[i];
    if C = '''' then
    begin
      // Literal Zeichen fuer Zeichen uebernehmen, '' bleibt ''.
      Result := Result + C;
      Inc(i);
      while i <= n do
      begin
        Result := Result + AText[i];
        if AText[i] = '''' then
        begin
          if (i < n) and (AText[i + 1] = '''') then
          begin
            Result := Result + '''';
            Inc(i, 2);
            Continue;
          end;
          Inc(i);
          Break;
        end;
        Inc(i);
      end;
      LastWhite := False;
      Continue;
    end;
    if C <= ' ' then
    begin
      if not LastWhite then
        Result := Result + ' ';
      LastWhite := True;
    end
    else
    begin
      Result := Result + C;
      LastWhite := False;
    end;
    Inc(i);
  end;
  Result := TrimRight(Result);
end;

{ ---- Formatstring aus den Literal-Quelltexten (AH22) ----
  Die Literale werden NICHT dekodiert und neu kodiert, sondern Token fuer
  Token uebernommen: '#$2103' bleibt '#$2103' (in einer ANSI-Datei waere
  das rohe Zeichen verloren), '#13' bleibt dezimal. Nur '%' in Quote-
  Teilen wird '%%', und ein '#37' (= '%') wird ''%%''. }

procedure AppendQuoted(var AFmt: string; var AInQuote: Boolean;
  const AInner: string);
begin
  if not AInQuote then
  begin
    AFmt := AFmt + '''';
    AInQuote := True;
  end;
  AFmt := AFmt + AInner;
end;

procedure AppendCode(var AFmt: string; var AInQuote: Boolean;
  const AToken: string);
begin
  if AInQuote then
  begin
    AFmt := AFmt + '''';
    AInQuote := False;
  end;
  AFmt := AFmt + AToken;
end;

// Haengt den Quelltext eines Literal-Terms ('a'#13#10'b', #$2103, 'x''y')
// an den Formatstring an. False bei allem, was kein Literal ist.
function AppendLiteralSource(var AFmt: string; var AInQuote: Boolean;
  const ASource: string): Boolean;
var
  i, n, k : Integer;
  Inner   : string;
  Code    : Integer;
  Digits  : Integer;
  Hex     : Integer;
  Closed  : Boolean;
begin
  Result := False;
  n := Length(ASource);
  i := 1;
  while i <= n do
  begin
    if ASource[i] <= ' ' then
    begin
      Inc(i);
      Continue;
    end;
    if ASource[i] = '''' then
    begin
      Inc(i);
      Inner := '';
      Closed := False;
      while i <= n do
      begin
        if ASource[i] = '''' then
        begin
          if (i < n) and (ASource[i + 1] = '''') then
          begin
            Inner := Inner + '''''';
            Inc(i, 2);
            Continue;
          end;
          Inc(i);
          Closed := True;
          Break;
        end;
        if ASource[i] = '%' then
          Inner := Inner + '%%'
        else
          Inner := Inner + ASource[i];
        Inc(i);
      end;
      if not Closed then Exit;
      AppendQuoted(AFmt, AInQuote, Inner);
    end
    else if ASource[i] = '#' then
    begin
      k := i;
      Inc(i);
      Code   := 0;
      Digits := 0;
      if (i <= n) and (ASource[i] = '$') then
      begin
        Inc(i);
        while i <= n do
        begin
          Hex := HexValue(ASource[i]);
          if Hex < 0 then Break;
          Code := Code * 16 + Hex;
          Inc(i);
          Inc(Digits);
          if Code > $FFFF then Exit;
        end;
      end
      else
        while (i <= n) and CharInSet(ASource[i], ['0'..'9']) do
        begin
          Code := Code * 10 + (Ord(ASource[i]) - Ord('0'));
          Inc(i);
          Inc(Digits);
          if Code > $FFFF then Exit;
        end;
      if Digits = 0 then Exit;
      if Code = Ord('%') then
        AppendQuoted(AFmt, AInQuote, '%%')
      else
        AppendCode(AFmt, AInQuote, Copy(ASource, k, i - k));
    end
    else
      Exit;
  end;
  Result := True;
end;

class function TRdxRecipes.NumericArgument(const APart: TRdxPart;
  out AArgument, ASpec: string): Boolean;
begin
  Result := False;
  AArgument := '';
  ASpec := '';
  if (APart.Role <> ROLE_OPERAND) or (APart.ArgResolved = '') then Exit;
  ASpec := IntegerSpec(APart.ArgResolved);
  if ASpec = '' then Exit;
  AArgument := IntegerArgumentOf(APart.Text);
  Result := AArgument <> '';
  if not Result then ASpec := '';
end;

class function TRdxRecipes.BuildFormatCall(const AParts: TRdxParts;
  out ABuild: TRdxFormatBuild; const ATargetType: string): Boolean;
var
  i        : Integer;
  Fmt      : string;
  InQuote  : Boolean;
  Literals : string;
  LitCount : Integer;
  Args     : string;
  Value    : string;
  Txt      : string;
  Arg      : string;
  Spec     : string;
  Verdict  : TRdxOperandVerdict;
  TargetU  : Boolean;
begin
  Result   := False;
  ABuild   := Default(TRdxFormatBuild);
  Fmt      := '';
  InQuote  := False;
  Literals := '';
  LitCount := 0;
  Args     := '';
  // Unicode-Ziel: Format wandelt einen AnsiString-Operanden genauso wie
  // die Zuweisung es taete (FormatBuf vtAnsiString -> UnicodeString).
  TargetU := (ATargetType = 'string') or (ATargetType = 'unicodestring')
    or (ATargetType = 'widestring');
  for i := 0 to High(AParts) do
  begin
    if AParts[i].Role = ROLE_TARGET then Continue;
    Txt := CollapseCode(AParts[i].Text);
    if AParts[i].Role = ROLE_LITERAL then
    begin
      if not DecodeLiteral(AParts[i].Text, Value)
         or not AppendLiteralSource(Fmt, InQuote, AParts[i].Text) then
      begin
        ABuild.Reason := 'Literal nicht lesbar: ' + Txt;
        Exit;
      end;
      Inc(LitCount);
      Literals := Literals + Value;
    end
    else if AParts[i].Role = ROLE_OPERAND then
    begin
      // Wie der Detektor (AlreadyUsesFormat): eine Kette, in der schon
      // Format() steht, wird nicht noch einmal in Format() gepackt -
      // sonst wuerde ein zweiter Lauf 'Format(''%s'', [Format(...)])'
      // bauen (reDelphix.Test, Rewrite_AppliedOnce_NoSecondFinding,
      // rot am 2026-10-06).
      if Pos('format(', LowerCase(Txt)) > 0 then
      begin
        ABuild.Reason := 'Kette enthaelt schon Format()';
        Exit;
      end;
      if NumericArgument(AParts[i], Arg, Spec) then
      begin
        // IntToStr(n) -> %d mit n: so schriebe man es von Hand.
        AppendQuoted(Fmt, InQuote, Spec);
        Txt := Arg;
        Inc(ABuild.Proven);
        Inc(ABuild.Numeric);
      end
      else
      begin
        Verdict := JudgeOperand(AParts[i]);
        if (Verdict = ovAnsi) and TargetU then Verdict := ovString;
        case Verdict of
          ovString:
            begin
              AppendQuoted(Fmt, InQuote, '%s');
              Inc(ABuild.Proven);
            end;
          ovByCompiler:
            begin
              AppendQuoted(Fmt, InQuote, '%s');
              SetLength(ABuild.ByCompiler, Length(ABuild.ByCompiler) + 1);
              ABuild.ByCompiler[High(ABuild.ByCompiler)] := Txt;
            end;
          ovNonString:
            begin
              ABuild.Reason := 'Operand ''' + Txt + ''': kein String';
              if AParts[i].Resolved <> '' then
                ABuild.Reason := ABuild.Reason + ' (' + AParts[i].Resolved + ')';
              Exit;
            end;
          ovAnsi:
            begin
              ABuild.Reason := 'Operand ''' + Txt + ''': ' + AParts[i].Resolved
                + ' - Format liefert UnicodeString';
              Exit;
            end;
          ovVariantRisk:
            begin
              ABuild.Reason := 'Operand ''' + Txt
                + ''': Variant moeglich (Null/Zahl: Original wirft, Format nicht)';
              Exit;
            end;
        else
          ABuild.Reason := 'Operand ''' + Txt + ''': kein einfacher Operand';
          Exit;
        end;
      end;
      Inc(ABuild.Operands);
      if Args <> '' then Args := Args + ', ';
      Args := Args + Txt;
    end
    else
    begin
      ABuild.Reason := 'kein reiner Term: ' + AParts[i].Role;
      Exit;
    end;
  end;
  if ABuild.Operands = 0 then
  begin
    ABuild.Reason := 'kein Operand in der Kette';
    Exit;
  end;
  // Ohne Literal gibt es keinen Formatstring, nur '%s%s' - das ist keine
  // Verbesserung (der Detektor verlangt Literal UND Nicht-Literal).
  if LitCount = 0 then
  begin
    ABuild.Reason := 'kein Literal in der Kette';
    Exit;
  end;
  if LooksLikeSql(Literals) then
  begin
    ABuild.Reason := 'SQL-Text: Umformung gesperrt (SCA003)';
    Exit;
  end;
  if InQuote then Fmt := Fmt + '''';
  ABuild.NewText := 'Format(' + Fmt + ', [' + Args + '])';
  Result := True;
end;

class function TRdxRecipes.BuildFormatCall(const AParts: TRdxParts;
  out ANewText, AReason: string): Boolean;
var
  B : TRdxFormatBuild;
begin
  Result   := BuildFormatCall(AParts, B);
  ANewText := B.NewText;
  AReason  := B.Reason;
end;

class function TRdxRecipes.QueryObjectOf(const ATarget: string): string;
var
  T   : string;
  Low : string;
  P   : Integer;
begin
  T   := Trim(ATarget);
  Low := LowerCase(T);
  P := Pos('.sql', Low);
  if P = 0 then
    P := Pos('.commandtext', Low);
  if P = 0 then
    P := LastDelimiter('.', T);
  if P > 0 then
    Result := Copy(T, 1, P - 1)
  else
    Result := T;
end;

class function TRdxRecipes.BuildSqlTemplate(const ATarget: string;
  AIsCall: Boolean; const AParts: TRdxParts; AIndent: Integer;
  out ATemplate, AReason: string): Boolean;
var
  i        : Integer;
  Sql      : string;
  Value    : string;
  N        : Integer;
  Operands : TArray<string>;
  Obj      : string;
  Indent   : string;
  Head     : string;
  k        : Integer;
  PName    : string;
begin
  Result    := False;
  ATemplate := '';
  AReason   := '';
  Sql := '';
  N   := 0;
  SetLength(Operands, 0);
  for i := 0 to High(AParts) do
  begin
    if AParts[i].Role = ROLE_TARGET then Continue;
    if AParts[i].Role = ROLE_LITERAL then
    begin
      if not DecodeLiteral(AParts[i].Text, Value) then
      begin
        AReason := 'Literal nicht lesbar: ' + CollapseWhitespace(AParts[i].Text);
        Exit;
      end;
      Sql := Sql + Value;
    end
    else if AParts[i].Role = ROLE_OPERAND then
    begin
      Inc(N);
      Sql := Sql + ':p' + IntToStr(N);
      SetLength(Operands, N);
      Operands[N - 1] := CollapseWhitespace(AParts[i].Text);
    end
    else
    begin
      AReason := 'Aufruf mit mehreren Argumenten - keine Vorlage';
      Exit;
    end;
  end;
  if N = 0 then
  begin
    AReason := 'kein Operand in der Kette';
    Exit;
  end;
  // Ein Parameter steht nie in Quotes: WHERE name=':p1' -> WHERE name=:p1
  for k := 1 to N do
  begin
    PName := ':p' + IntToStr(k);
    Sql := StringReplace(Sql, '''' + PName + '''', PName, [rfReplaceAll]);
  end;
  Obj    := QueryObjectOf(ATarget);
  Indent := StringOfChar(' ', AIndent);
  if AIsCall then
    Head := Trim(ATarget) + '(' + EncodeLiteral(Sql) + ');'
  else
    Head := Trim(ATarget) + ' := ' + EncodeLiteral(Sql) + ';';
  ATemplate := Indent + Head;
  for k := 1 to N do
    ATemplate := ATemplate + sLineBreak + Indent + Obj + '.ParamByName('
      + EncodeLiteral('p' + IntToStr(k)) + ').Value := ' + Operands[k - 1] + ';';
  Result := True;
end;

class function TRdxRecipes.DetectFramework(
  const AUnitNames: TArray<string>): TRdxFramework;
var
  i      : Integer;
  Low    : string;
  HasVcl : Boolean;
  HasFmx : Boolean;
begin
  HasVcl := False;
  HasFmx := False;
  for i := 0 to High(AUnitNames) do
  begin
    Low := LowerCase(AUnitNames[i]);
    if Copy(Low, 1, 4) = 'vcl.' then HasVcl := True;
    if Copy(Low, 1, 4) = 'fmx.' then HasFmx := True;
  end;
  if HasVcl and HasFmx then Exit(fwBoth);
  if HasVcl then Exit(fwVcl);
  if HasFmx then Exit(fwFmx);
  Result := fwUnknown;
end;

class function TRdxRecipes.HasUnit(const AUnitNames: TArray<string>;
  const AShortName: string): Boolean;
var
  i : Integer;
begin
  Result := False;
  for i := 0 to High(AUnitNames) do
    if SameText(LastSegment(AUnitNames[i]), AShortName) then
      Exit(True);
end;

class function TRdxRecipes.UsesNameFor(const AUnitNames: TArray<string>;
  const AShortName, AQualifiedName: string): string;
var
  i : Integer;
begin
  if Length(AUnitNames) = 0 then Exit(AQualifiedName);
  for i := 0 to High(AUnitNames) do
    if Pos('.', AUnitNames[i]) > 0 then
      Exit(AQualifiedName);
  Result := AShortName;
end;

class function TRdxRecipes.IsSortedUses(
  const AUnitNames: TArray<string>): Boolean;
var
  i : Integer;
begin
  Result := True;
  for i := 1 to High(AUnitNames) do
    if CompareText(AUnitNames[i - 1], AUnitNames[i]) > 0 then
      Exit(False);
end;

class function TRdxRecipes.SortedInsertIndex(
  const AUnitNames: TArray<string>; const ANewName: string): Integer;
var
  i : Integer;
begin
  if not IsSortedUses(AUnitNames) then Exit(0);
  for i := 0 to High(AUnitNames) do
    if CompareText(ANewName, AUnitNames[i]) < 0 then
      Exit(i);
  Result := Length(AUnitNames);
end;

end.
