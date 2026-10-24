object frmOrders: TfrmOrders
  Left = 0
  Top = 0
  Caption = 'Order Manager'
  ClientHeight = 480
  ClientWidth = 720
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 15
  object Label1: TLabel
    Left = 16
    Top = 19
    Width = 52
    Height = 15
    Caption = 'Customer'
  end
  object Edit1: TEdit
    Left = 80
    Top = 16
    Width = 200
    Height = 23
    TabOrder = 0
  end
  object Button1: TButton
    Left = 296
    Top = 15
    Width = 90
    Height = 25
    Caption = 'Search'
    TabOrder = 1
    OnClick = Button1Click
  end
  object btnRefresh: TButton
    Left = 400
    Top = 15
    Width = 90
    Height = 25
    Action = actRefresh
    TabOrder = 2
    OnClick = btnRefreshClick
  end
  object btnImport: TButton
    Left = 504
    Top = 15
    Width = 96
    Height = 25
    Caption = 'Import CSV'
    TabOrder = 3
    OnClick = btnImportClick
  end
  object btnExport: TButton
    Left = 608
    Top = 15
    Width = 96
    Height = 25
    Caption = 'Export'
    TabOrder = 4
    OnClick = btnExportClick
  end
  object lvOrders: TListView
    Left = 16
    Top = 56
    Width = 688
    Height = 392
    Columns = <
      item
        Caption = 'Order'
        Width = 80
      end
      item
        Caption = 'Customer'
        Width = 240
      end
      item
        Caption = 'Total'
        Width = 100
      end>
    TabOrder = 5
    ViewStyle = vsReport
    OnKeyDown = lvOrdersKeyDown
  end
  object sbStatus: TStatusBar
    Left = 0
    Top = 461
    Width = 720
    Height = 19
    Panels = <>
    SimplePanel = True
  end
  object FDConnection1: TFDConnection
    Params.Strings = (
      'Database=orders'
      'User_Name=shop'
      'Password=Sommer2024!'
      'Server=192.168.20.15'
      'DriverID=PG')
    LoginPrompt = False
    Left = 600
    Top = 104
  end
  object FDQuery1: TFDQuery
    Connection = FDConnection1
    Left = 600
    Top = 168
  end
  object alMain: TActionList
    Left = 600
    Top = 232
    object actRefresh: TAction
      Caption = 'Refresh'
      OnExecute = actRefreshExecute
    end
  end
end
