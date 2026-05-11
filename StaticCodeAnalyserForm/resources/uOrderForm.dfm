object OrderForm: TOrderForm
  Left = 0
  Top = 0
  Caption = 'Bestelluebersicht'
  ClientHeight = 392
  ClientWidth = 598
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Segoe UI'
  Font.Style = []
  TextHeight = 13
  object pnlInputs: TPanel
    Left = 0
    Top = 0
    Width = 598
    Height = 200
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object lblOrderNo: TLabel
      Left = 16
      Top = 16
      Width = 48
      Height = 13
      Caption = 'Order Nr.'
    end
    object lblTotal: TLabel
      Left = 16
      Top = 48
      Width = 37
      Height = 13
      Caption = 'Summe'
    end
    object lblNotes: TLabel
      Left = 16
      Top = 80
      Width = 40
      Height = 13
      Caption = 'Notizen'
    end
    object edOrderNo: TDBEdit
      Left = 80
      Top = 13
      Width = 200
      Height = 21
      DataField = 'OrderNo'
      DataSource = dsOrders
      TabOrder = 0
    end
    object edTotal: TDBEdit
      Left = 80
      Top = 45
      Width = 200
      Height = 21
      DataField = 'Total'
      DataSource = dsOrders
      TabOrder = 1
    end
    object edNotes: TDBEdit
      Left = 80
      Top = 77
      Width = 400
      Height = 21
      DataField = 'Notes'
      DataSource = dsOrders
      TabOrder = 2
    end
  end
  object pnlButtons: TPanel
    Left = 0
    Top = 343
    Width = 598
    Height = 49
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 1
    object btnSave: TButton
      Left = 16
      Top = 12
      Width = 90
      Height = 25
      Caption = 'Speichern'
      TabOrder = 0
      OnClick = btnSaveClick
    end
    object btnSearch: TButton
      Left = 120
      Top = 12
      Width = 90
      Height = 25
      Caption = 'Suchen'
      TabOrder = 1
      OnClick = btnSearchClick
    end
    object Button1: TButton
      Left = 224
      Top = 12
      Width = 90
      Height = 25
      Caption = 'Hilfe'
      TabOrder = 2
      OnClick = Button1Click
    end
  end
  object qOrders: TADOQuery
    CursorType = ctStatic
    Parameters = <>
    SQL.Strings = (
      'SELECT ID, OrderNo, Total, CustomerName, Notes'
      'FROM Orders'
      'WHERE Total > 100'
      'ORDER BY OrderNo')
    Left = 32
    Top = 16
    object qOrdersID: TIntegerField
      FieldName = 'ID'
      Required = True
    end
    object qOrdersOrderNo: TStringField
      FieldName = 'OrderNo'
      Required = True
    end
    object qOrdersTotal: TFloatField
      FieldName = 'Total'
      Required = True
      DisplayFormat = '#,##0.00'
    end
    object qOrdersCustomerName: TStringField
      FieldName = 'CustomerName'
      Size = 100
    end
    object qOrdersNotes: TMemoField
      FieldName = 'Notes'
      BlobType = ftMemo
    end
  end
  object dsOrders: TDataSource
    DataSet = qOrders
    Left = 88
    Top = 16
  end
end
