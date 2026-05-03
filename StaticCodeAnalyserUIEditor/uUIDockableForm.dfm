object UIEditorFrame: TUIEditorFrame
  Left = 0
  Top = 0
  Width = 900
  Height = 480
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  ParentFont = False
  TabOrder = 0
  object TopBar: TPanel
    Left = 0
    Top = 0
    Width = 900
    Height = 36
    Align = alTop
    BevelOuter = bvNone
    Color = clBtnFace
    ParentBackground = False
    TabOrder = 0
    object LblForm: TLabel
      Left = 12
      Top = 10
      Width = 160
      Height = 15
      Caption = 'Form: (keine geoeffnet)'
    end
    object BtnRefresh: TButton
      Left = 800
      Top = 6
      Width = 92
      Height = 25
      Anchors = [akTop, akRight]
      Caption = 'Aktualisieren'
      TabOrder = 0
      OnClick = BtnRefreshClick
    end
  end
  object Grid: TStringGrid
    Left = 0
    Top = 36
    Width = 540
    Height = 425
    Align = alLeft
    DefaultColWidth = 100
    DefaultRowHeight = 20
    FixedCols = 0
    RowCount = 2
    Options = [goFixedVertLine, goFixedHorzLine, goVertLine, goHorzLine, goRowSelect, goThumbTracking]
    TabOrder = 1
    OnDblClick = GridDblClick
    OnSelectCell = GridSelectCell
  end
  object Splitter1: TSplitter
    Left = 540
    Top = 36
    Width = 6
    Height = 425
    Beveled = True
  end
  object DetailPanel: TPanel
    Left = 546
    Top = 36
    Width = 354
    Height = 425
    Align = alClient
    BevelOuter = bvNone
    Color = clWindow
    ParentBackground = False
    TabOrder = 2
    object LblSeverity: TLabel
      Left = 12
      Top = 12
      Width = 50
      Height = 17
      Caption = 'Severity'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clRed
      Font.Height = -13
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object LblRule: TLabel
      Left = 12
      Top = 38
      Width = 30
      Height = 15
      Caption = 'Regel'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -12
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object LblComponent: TLabel
      Left = 12
      Top = 60
      Width = 70
      Height = 15
      Caption = 'Komponente'
    end
    object MemoMessage: TMemo
      Left = 12
      Top = 88
      Width = 330
      Height = 280
      Anchors = [akLeft, akTop, akRight, akBottom]
      BorderStyle = bsNone
      Color = clWindow
      ReadOnly = True
      ScrollBars = ssVertical
      TabOrder = 0
    end
    object BtnSelect: TButton
      Left = 12
      Top = 388
      Width = 140
      Height = 25
      Anchors = [akLeft, akBottom]
      Caption = 'Im Designer markieren'
      TabOrder = 1
      OnClick = BtnSelectClick
    end
  end
  object StatusBar1: TStatusBar
    Left = 0
    Top = 461
    Width = 900
    Height = 19
    Panels = <>
    SimplePanel = True
    SimpleText = '0 Befund(e)'
  end
end
