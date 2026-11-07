unit uOrderStatus;

interface

type
  /// <summary>Processing state of an order.</summary>
  TOrderStatus = (osNew, osPaid, osShipped, osCancelled);

/// <summary>Text for the status column of the order list.</summary>
function StatusText(AStatus: TOrderStatus): string;

implementation

// The unit starts without a comment between "unit" and "interface": what
// it is for, who owns it, nobody wrote down (SCA143).

function StatusText(AStatus: TOrderStatus): string;
const
  TEXTS: array[TOrderStatus] of string = ('new', 'paid', 'shipped',
    'cancelled');
begin
  Result := TEXTS[AStatus];
end;

end.
