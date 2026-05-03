unit uDfmIssues;

// Detektoren fuer UI-Smells im Form Designer.
// Arbeitet auf einer fertig instanziierten Komponentenhierarchie (Root-Form
// aus IOTAFormEditor.GetRootComponent), nicht auf dem .dfm-Text. Damit
// koennen Properties direkt per RTTI gelesen werden.

interface

uses
  System.Classes, System.SysUtils, System.Generics.Collections,
  System.TypInfo, System.RegularExpressions,
  Vcl.Controls;

type
  TUISeverity = (uisInfo, uisWarning, uisError);

  TUIIssue = record
    Severity       : TUISeverity;
    RuleId         : string;
    Message        : string;
    ComponentName  : string;
    ComponentClass : string;
  end;

  TUIIssueList = TList<TUIIssue>;

  TDfmIssueDetector = class
  private
    class procedure CheckDefaultName(C: TComponent; Issues: TUIIssueList); static;
    class procedure CheckButtonOnClick(C: TComponent; Issues: TUIIssueList); static;
    class procedure CheckDuplicateTabOrder(Root: TComponent;
      Issues: TUIIssueList); static;
    class procedure WalkComponents(Root: TComponent;
      const Visitor: TProc<TComponent>); static;
  public
    // Liefert alle Befunde fuer den Komponentenbaum unter Root (inklusive
    // Root selbst). Aufrufer ist Eigentuemer der Liste.
    class function Detect(Root: TComponent): TUIIssueList; static;
    class function SeverityToStr(S: TUISeverity): string; static;
  end;

implementation

{ TDfmIssueDetector }

class function TDfmIssueDetector.SeverityToStr(S: TUISeverity): string;
begin
  case S of
    uisError:   Result := 'Error';
    uisWarning: Result := 'Warning';
  else          Result := 'Info';
  end;
end;

class procedure TDfmIssueDetector.WalkComponents(Root: TComponent;
  const Visitor: TProc<TComponent>);
var
  i: Integer;
begin
  if Root = nil then Exit;
  Visitor(Root);
  for i := 0 to Root.ComponentCount - 1 do
    WalkComponents(Root.Components[i], Visitor);
end;

class procedure TDfmIssueDetector.CheckDefaultName(C: TComponent;
  Issues: TUIIssueList);
var
  ClsName, Stem: string;
  Issue: TUIIssue;
begin
  if (C = nil) or (C.Name = '') then Exit;

  // Namensschema "<Stamm><Zahl>" wobei <Stamm> der Klassenname ohne
  // fuehrendes T ist, exakt wie der IDE-Designer es vorschlaegt.
  ClsName := C.ClassName;
  if (Length(ClsName) < 2) or (ClsName[1] <> 'T') then Exit;
  Stem := Copy(ClsName, 2, MaxInt);

  if TRegEx.IsMatch(C.Name, '^' + Stem + '\d+$') then
  begin
    Issue.Severity       := uisWarning;
    Issue.RuleId         := 'UI001-DefaultName';
    Issue.Message        := Format('Default-Name "%s" beibehalten - sollte ' +
                                   'sprechend benannt werden.', [C.Name]);
    Issue.ComponentName  := C.Name;
    Issue.ComponentClass := ClsName;
    Issues.Add(Issue);
  end;
end;

class procedure TDfmIssueDetector.CheckButtonOnClick(C: TComponent;
  Issues: TUIIssueList);
var
  PropInfo: PPropInfo;
  M: TMethod;
  Issue: TUIIssue;
begin
  // Nur Button-aehnliche Klassen pruefen. Heuristik: Klassenname endet
  // auf 'Button' und besitzt eine OnClick-Property.
  if (C = nil) or not C.ClassName.EndsWith('Button') then Exit;

  PropInfo := GetPropInfo(C, 'OnClick', [tkMethod]);
  if PropInfo = nil then Exit;

  M := GetMethodProp(C, PropInfo);
  if (M.Code = nil) and (M.Data = nil) then
  begin
    Issue.Severity       := uisError;
    Issue.RuleId         := 'UI002-ButtonNoOnClick';
    Issue.Message        := Format('Button "%s" hat keinen OnClick-Handler.',
                                   [C.Name]);
    Issue.ComponentName  := C.Name;
    Issue.ComponentClass := C.ClassName;
    Issues.Add(Issue);
  end;
end;

class procedure TDfmIssueDetector.CheckDuplicateTabOrder(Root: TComponent;
  Issues: TUIIssueList);
var
  ParentMap: TObjectDictionary<TWinControl, TList<TWinControl>>;
  Pair: TPair<TWinControl, TList<TWinControl>>;
  Children: TList<TWinControl>;
  Seen: TDictionary<Integer, TWinControl>;
  Other: TWinControl;
  i: Integer;
  Issue: TUIIssue;
begin
  ParentMap := TObjectDictionary<TWinControl, TList<TWinControl>>.Create([doOwnsValues]);
  try
    WalkComponents(Root,
      procedure(C: TComponent)
      var
        WC: TWinControl;
        L : TList<TWinControl>;
      begin
        if not (C is TWinControl) then Exit;
        WC := TWinControl(C);
        if (WC.Parent = nil) or not WC.TabStop then Exit;
        if not ParentMap.TryGetValue(WC.Parent, L) then
        begin
          L := TList<TWinControl>.Create;
          ParentMap.Add(WC.Parent, L);
        end;
        L.Add(WC);
      end);

    for Pair in ParentMap do
    begin
      Children := Pair.Value;
      Seen := TDictionary<Integer, TWinControl>.Create;
      try
        for i := 0 to Children.Count - 1 do
          if Seen.TryGetValue(Children[i].TabOrder, Other) then
          begin
            Issue.Severity       := uisWarning;
            Issue.RuleId         := 'UI003-DuplicateTabOrder';
            Issue.Message        := Format(
              'Doppelte TabOrder %d: "%s" und "%s" (Parent: %s).',
              [Children[i].TabOrder, Other.Name, Children[i].Name,
               Pair.Key.Name]);
            Issue.ComponentName  := Children[i].Name;
            Issue.ComponentClass := Children[i].ClassName;
            Issues.Add(Issue);
          end
          else
            Seen.Add(Children[i].TabOrder, Children[i]);
      finally
        Seen.Free;
      end;
    end;
  finally
    ParentMap.Free;
  end;
end;

class function TDfmIssueDetector.Detect(Root: TComponent): TUIIssueList;
var
  Result_: TUIIssueList;
begin
  Result_ := TUIIssueList.Create;
  try
    if Root = nil then Exit(Result_);

    WalkComponents(Root,
      procedure(C: TComponent)
      begin
        CheckDefaultName(C, Result_);
        CheckButtonOnClick(C, Result_);
      end);

    CheckDuplicateTabOrder(Root, Result_);
    Result := Result_;
  except
    Result_.Free;
    raise;
  end;
end;

end.
