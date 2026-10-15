-- The model: a pure statement of how the backend answers each command and
-- what state it is in afterwards.
--
-- The rules here were read from the backend on 2026-10-12:
-- Server.SaleCommand and Server.Transaction for the order of the checks
-- (session, capability, sale ownership, then the service), Service.Sale,
-- Service.Transaction and DB.Transaction for the sale rules,
-- State.SaleTransactionMachine and State.RegisterMachine for the legal
-- transitions, and Types.Auth.capabilitiesForRole for who may do what.
-- They are written out again here on purpose. A model that imported the
-- backend's own functions would agree with the backend by construction.
module Model.Step
  ( initialModel
  , step
  , saleTotals
  , salePaid
  , saleView
  , registerView
  , stockView
  , isOpenStatus
  ) where

import Data.List (delete, sort)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map

import Model.Types

initialModel :: Rules -> Model v
initialModel rules =
  Model
    { modelRegisters = Map.empty
    , modelSales     = Map.empty
    , modelOnHand    = rulesStock rules
    }

-- Capabilities by role (Types.Auth.capabilitiesForRole).

canProcess :: Actor -> Bool
canProcess actor = actor `elem` [Admin, CashierA, CashierB]

canOpenOrClose :: Actor -> Bool
canOpenOrClose actor = actor `elem` [Admin, CashierA, CashierB]

canManageRegisters :: Actor -> Bool
canManageRegisters actor = actor == Admin

canVoidOrRefund :: Actor -> Bool
canVoidOrRefund actor = actor == Admin

-- Server.Transaction.mayWriteSale: the opener, or a manager or admin.
mayWrite :: Actor -> SaleM -> Bool
mayWrite actor sale = actor == saleOwner sale || actor == Admin

isOpenStatus :: Status -> Bool
isOpenStatus status = status == Created || status == InProgress

-- Money.

-- Domain.Pricing.roundDiv RoundHalfUp, for a non-negative numerator.
roundHalfUp :: Int -> Int -> Int
roundHalfUp numerator denominator
  | 2 * rest >= denominator = whole + 1
  | otherwise               = whole
  where
    (whole, rest) = numerator `quotRem` denominator

lineSubtotal :: Rules -> Int -> Int -> Int
lineSubtotal rules sku quantity =
  Map.findWithDefault 0 sku (rulesPrices rules) * quantity

lineTax :: Rules -> Int -> Int
lineTax rules subtotal = roundHalfUp (subtotal * rulesTaxPpm rules) 1000000

-- Subtotal, tax and total of a sale. Tax is computed per line.
saleTotals :: Rules -> SaleM -> (Int, Int, Int)
saleTotals rules sale = (subtotal, tax, subtotal + tax)
  where
    subtotals = [lineSubtotal rules sku qty | (sku, qty) <- Map.toList (saleLines sale)]
    subtotal  = sum subtotals
    tax       = sum (map (lineTax rules) subtotals)

salePaid :: SaleM -> Int
salePaid = sum . map snd . salePayments

-- Stock.

-- Units of a sku held by open sales other than the given one. A voided or
-- completed sale holds nothing.
reservedByOthers :: Model v -> Int -> Int -> Int
reservedByOthers model saleIx sku =
  sum
    [ Map.findWithDefault 0 sku (saleLines sale)
    | (ix, sale) <- Map.toList (modelSales model)
    , ix /= saleIx
    , isOpenStatus (saleStatus sale)
    ]

returnToStock :: SaleM -> Map Int Int -> Map Int Int
returnToStock sale onHand = Map.unionWith (+) onHand (saleLines sale)

takeFromStock :: SaleM -> Map Int Int -> Map Int Int
takeFromStock sale onHand = Map.unionWith (+) onHand (Map.map negate (saleLines sale))

-- The transition function: the HTTP status the backend must answer with,
-- and the model afterwards. Any status other than 200 leaves the model
-- unchanged.
step :: Rules -> Model v -> Cmd -> (Int, Model v)
step rules model cmd = case cmd of
  CreateRegister actor
    | actor == Anonymous             -> refuse 401
    | not (canManageRegisters actor) -> refuse 403
    | otherwise ->
        accept
          model
            { modelRegisters =
                Map.insert
                  (Map.size (modelRegisters model))
                  (RegisterM False 0)
                  (modelRegisters model)
            }

  OpenRegister actor reg cash ->
    onRegister actor reg $ \register ->
      if registerOpen register
        then refuse 409
        else acceptRegister reg (RegisterM True cash)

  -- The expected drawer amount is the starting cash and nothing else: the
  -- backend does not add cash payments to it. The model follows the
  -- backend here. If the backend starts counting cash sales, this is the
  -- rule to change.
  CloseRegister actor reg _counted ->
    onRegister actor reg $ \register ->
      if registerOpen register
        then acceptRegister reg register {registerOpen = False}
        else refuse 409

  -- The backend starts a sale on any register id, open or closed.
  StartSale actor reg
    | actor == Anonymous      -> refuse 401
    | not (canProcess actor)  -> refuse 403
    | otherwise ->
        accept
          model
            { modelSales =
                Map.insert
                  (Map.size (modelSales model))
                  (SaleM actor reg Created Map.empty [])
                  (modelSales model)
            }

  AddItem actor saleIx sku quantity ->
    onSale actor saleIx $ \sale ->
      let wanted    = Map.findWithDefault 0 sku (saleLines sale) + quantity
          onHand    = Map.findWithDefault 0 sku (modelOnHand model)
          available = onHand - reservedByOthers model saleIx sku
       in if quantity <= 0
            then refuse 400
            else if not (Map.member sku (rulesPrices rules))
              then refuse 404
              else if not (isOpenStatus (saleStatus sale))
                then refuse 409
                else if available < wanted
                  then refuse 400
                  else
                    acceptSale
                      saleIx
                      sale
                        { saleStatus = InProgress
                        , saleLines  = Map.insert sku wanted (saleLines sale)
                        }

  -- Removing the last line leaves the sale In Progress with no lines.
  RemoveItem actor saleIx sku ->
    onSale actor saleIx $ \sale ->
      if not (Map.member sku (saleLines sale))
        then refuse 404
        else if saleStatus sale /= InProgress
          then refuse 409
          else acceptSale saleIx sale {saleLines = Map.delete sku (saleLines sale)}

  -- The amount is checked before the sale's state. A payment larger than
  -- what is owed is accepted.
  AddPayment actor saleIx method amount tendered ->
    onSale actor saleIx $ \sale ->
      if amount <= 0 || maybe False (< amount) tendered
        then refuse 400
        else if saleStatus sale /= InProgress
          then refuse 409
          else acceptSale saleIx sale {salePayments = salePayments sale ++ [(method, amount)]}

  RemovePayment actor saleIx method amount ->
    onSale actor saleIx $ \sale ->
      if (method, amount) `notElem` salePayments sale
        then refuse 404
        else if saleStatus sale /= InProgress
          then refuse 409
          else acceptSale saleIx sale {salePayments = delete (method, amount) (salePayments sale)}

  Clear actor saleIx ->
    onSale actor saleIx $ \sale ->
      if isOpenStatus (saleStatus sale)
        then acceptSale saleIx sale {saleStatus = Created, saleLines = Map.empty, salePayments = []}
        else refuse 409

  Finalize actor saleIx ->
    onSale actor saleIx $ \sale ->
      let (_, _, total) = saleTotals rules sale
       in if saleStatus sale /= InProgress
            then refuse 409
            else if Map.null (saleLines sale) || salePaid sale < total
              then refuse 409
              else
                accept
                  model
                    { modelSales  = Map.insert saleIx sale {saleStatus = Completed} (modelSales model)
                    , modelOnHand = takeFromStock sale (modelOnHand model)
                    }

  -- Void and refund need their capability and nothing else: the sale does
  -- not have to be the actor's own.
  Void actor saleIx ->
    onAnySale actor saleIx $ \sale ->
      if saleStatus sale `elem` [Voided, Refunded]
        then refuse 409
        else
          accept
            model
              { modelSales  = Map.insert saleIx sale {saleStatus = Voided} (modelSales model)
              , modelOnHand =
                  if saleStatus sale == Completed && rulesRestockOnVoid rules
                    then returnToStock sale (modelOnHand model)
                    else modelOnHand model
              }

  Refund actor saleIx ->
    onAnySale actor saleIx $ \sale ->
      if saleStatus sale /= Completed
        then refuse 409
        else
          accept
            model
              { modelSales  = Map.insert saleIx sale {saleStatus = Refunded} (modelSales model)
              , modelOnHand =
                  if rulesRestockOnRefund rules
                    then returnToStock sale (modelOnHand model)
                    else modelOnHand model
              }

  Audit -> accept model
  where
    refuse code = (code, model)
    accept next = (200, next)

    acceptSale saleIx sale =
      accept model {modelSales = Map.insert saleIx sale (modelSales model)}

    acceptRegister reg register =
      accept model {modelRegisters = Map.insert reg register (modelRegisters model)}

    onRegister actor reg continue
      | actor == Anonymous         = refuse 401
      | not (canOpenOrClose actor) = refuse 403
      | otherwise =
          case Map.lookup reg (modelRegisters model) of
            Nothing       -> refuse 404
            Just register -> continue register

    -- The checks every sale write goes through, in the backend's order.
    onSale actor saleIx continue
      | actor == Anonymous     = refuse 401
      | not (canProcess actor) = refuse 403
      | otherwise =
          case Map.lookup saleIx (modelSales model) of
            Nothing -> refuse 404
            Just sale
              | not (mayWrite actor sale) -> refuse 403
              | otherwise                 -> continue sale

    onAnySale actor saleIx continue
      | actor == Anonymous          = refuse 401
      | not (canVoidOrRefund actor) = refuse 403
      | otherwise =
          case Map.lookup saleIx (modelSales model) of
            Nothing   -> refuse 404
            Just sale -> continue sale

-- What the backend should report for a model sale.
saleView :: Rules -> SaleM -> SaleView
saleView rules sale =
  SaleView
    { viewOwner     = Just (saleOwner sale)
    , viewRegister  = Just (saleRegister sale)
    , viewStatus    = show (saleStatus sale)
    , viewLines     = saleLines sale
    , viewPayments  = sort [(show method, amount) | (method, amount) <- salePayments sale]
    , viewSubtotal  = subtotal
    , viewTax       = tax
    , viewTotal     = total
    , viewLineTotal = total
    }
  where
    (subtotal, tax, total) = saleTotals rules sale

registerView :: RegisterM -> RegisterView
registerView register =
  RegisterView
    { viewOpen     = registerOpen register
    , viewExpected = registerExpected register
    }

-- On-hand and reserved quantity per sku. Reserved is what open sales hold.
stockView :: Model v -> Map Int StockView
stockView model = Map.mapWithKey view (modelOnHand model)
  where
    view sku onHand = StockView onHand (reservedByOthers model (-1) sku)
