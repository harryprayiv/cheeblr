# What happens to stock when a COMPLETED sale is voided or refunded.
#
# Each setting takes one of two values:
#
#   "restock"     the sale's quantities are added back to stock
#   "no-restock"  stock is left as it is
#
# The backend reads them from RESTOCK_ON_VOID and RESTOCK_ON_REFUND and
# refuses to start when either is missing or has any other value. It has no
# default for them. The dev shell exports both from this file.
#
# Voiding a sale that was never completed is not affected: such a sale only
# holds reservations, and those are always released.
{
  restockOnVoid   = "restock";
  restockOnRefund = "no-restock";
}
