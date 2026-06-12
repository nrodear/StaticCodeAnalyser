unit uNamingExt;

// Naming-Familie erweitert (SCA118-119).
//
//   * fkExceptionName        - Exception-Descendant ohne E-Prefix
//                              (z.B. MyError statt EMyError)
//   * fkLocalConstantName    - const im Methoden-Body sollte UPPER_SNAKE
//                              (z.B. MAX_RETRIES); PascalCase = Smell
//
// Beide AST-basiert: ExceptionName auf nkClass-Knoten mit Exception-
// Vererbung; LocalConstantName auf nkConst innerhalb von nkMethod.

interface

uses
  System.SysUtils, System.Generics.Collections,
  uAstNode, uSCAConsts, uMethodd12;

type
  TNamingExtDetector = class
  public
    class procedure AnalyzeUnit(UnitNode: TAstNode; const FileName: string;
      Results: TObjectList<TLeakFinding>);
  end;

implementation

// noinspection-file CyclomaticComplexity, GroupedDeclaration, LongMethod, NestedTry, TooLongLine, UnsortedUses
// Self-scan Stil-Cluster - im jeweiligen File idiomatisch oder Hot-Path-bedingt.

uses
  System.StrUtils;

function IsExceptionDescendant(const TypeRef: string): Boolean;
// True wenn das TypeRef-Feld eines Class-Nodes auf einer Exception-Klasse
// basiert. Match auf 'Exception' oder klassische E-prefixed Vorfahren.
var
  Lower : string;
begin
  Lower := LowerCase(TypeRef);
  Result :=
    (Pos('exception',         Lower) > 0) or
    (Pos('eaborterror',       Lower) > 0) or
    (Pos('eaccessviolation',  Lower) > 0) or
    (Pos('eexternal',         Lower) > 0);
end;

function IsUpperSnake(const Name: string): Boolean;
// True wenn Name nur aus A-Z, 0-9, _ besteht (klassisches Konstanten-
// Naming wie MAX_RETRIES).
var
  i : Integer;
begin
  Result := False;
  if Name = '' then Exit;
  for i := 1 to Length(Name) do
    if not CharInSet(Name[i], ['A'..'Z', '0'..'9', '_']) then
      Exit(False);
  Result := True;
end;

class procedure TNamingExtDetector.AnalyzeUnit(UnitNode: TAstNode;
  const FileName: string; Results: TObjectList<TLeakFinding>);
var
  Classes : TList<TAstNode>;
  Methods : TList<TAstNode>;
  C, M, K : TAstNode;
  F       : TLeakFinding;
  i       : Integer;
begin
  // ExceptionName: nkClass mit Exception-Parent, Name ohne E-Prefix
  Classes := UnitNode.FindAll(nkClass);
  try
    for C in Classes do
    begin
      if C.Name = '' then Continue;
      if not IsExceptionDescendant(C.TypeRef) then Continue;
      // Skip Eigenname startet mit 'E' (case-sensitive)
      if (Length(C.Name) >= 2) and (C.Name[1] = 'E') and
         CharInSet(C.Name[2], ['A'..'Z']) then Continue;
      // Skip 'Exception' selbst (Delphi-RTL-Klasse, nicht User-Code)
      if SameText(C.Name, 'Exception') then Continue;

      F            := TLeakFinding.Create;
      F.FileName   := FileName;
      F.MethodName := C.Name;
      F.LineNumber := IntToStr(C.Line);
      F.MissingVar :=
        Format('Exception class %s should start with ''E'' prefix ' +
               '(Delphi-RTL convention: EAbort, EDivByZero, EMyError). ' +
               'Suggested: E%s',
               [C.Name, C.Name]);
      F.SetKind(fkExceptionName);
      Results.Add(F);
    end;
  finally
    Classes.Free;
  end;

  // LocalConstantName: nkConstSection-Children (nkField) innerhalb eines
  // nkMethod-Knotens. Der Parser legt lokale const X = Wert; Eintraege
  // als nkField unter einer nkConstSection ab (siehe uParser2.pas:386 +
  // uFormatMismatch.pas:420 fuer das Muster).
  Methods := UnitNode.FindAll(nkMethod);
  try
    for M in Methods do
    begin
      var Sections := M.FindAll(nkConstSection);
      try
        for var Section in Sections do
          for i := 0 to Section.Children.Count - 1 do
          begin
            K := Section.Children[i];
            if K.Kind <> nkField then Continue;
            if K.Name = '' then Continue;
            // Sehr kurze Konst-Namen (z.B. 'i' als Loop-Counter) ueberspringen
            if Length(K.Name) <= 2 then Continue;
            if IsUpperSnake(K.Name) then Continue;
            // Strings / Chars sind oft Localisierte UI-Labels, wo
            // PascalCase OK ist - skip. (Heuristik via TypeRef-Inhalt.)
            if (K.TypeRef <> '') and
               ((Pos('string', LowerCase(K.TypeRef)) > 0) or
                (Pos('char',   LowerCase(K.TypeRef)) > 0)) then Continue;

            F            := TLeakFinding.Create;
            F.FileName   := FileName;
            F.MethodName := M.Name;
            F.LineNumber := IntToStr(K.Line);
            F.MissingVar :=
              Format('Local const %s in %s - consider UPPER_SNAKE_CASE ' +
                     '(MAX_RETRIES, BUFFER_SIZE) for numeric constants. ' +
                     'Helps reader distinguish constants from variables at ' +
                     'a glance.',
                     [K.Name, M.Name]);
            F.SetKind(fkLocalConstantName);
            Results.Add(F);
          end;
      finally
        Sections.Free;
      end;
    end;
  finally
    Methods.Free;
  end;
end;

end.
