module Test.Wire where

import Prelude

import API.Request (ApiError(..), describe, isRefusal, status)
import Data.Array (length)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect.Aff (Aff)
import Test.Spec (Spec, describe, it) as Spec
import Test.Spec.Assertions (fail, shouldEqual)
import Types.Manager (ActivitySummary, ManagerAlert(..))
import Types.Primitives.Money (refundMoneyCents, saleMoneyCents)
import Types.Primitives.Quantity (RefundQuantity, refundQuantityCount, saleQuantityCount)
import Types.Register (CloseRegisterResult, Register)
import Types.Transaction (PaymentMethod(..), TaxCategory(..), TransactionStatus(..))
import Types.Transaction.Refund as Refund
import Types.Transaction.Sale as Sale
import Types.UUID (UUID(..))
import Yoga.JSON (class ReadForeign, readJSON, writeJSON)

-- Each JSON text below is written the way the backend's Aeson instances
-- write it: generic records with every field present, a missing optional
-- as null, UTC times with fractional seconds, money as integer cents, a tax
-- rate as a number in exponent form. These are hand-made copies. They are
-- not yet fixtures shared with the Haskell suite.

decoded :: forall a. ReadForeign a => String -> (a -> Aff Unit) -> Aff Unit
decoded json check = case readJSON json of
  Right value -> check value
  Left errors -> fail ("did not decode: " <> show errors)

completedSale :: String
completedSale =
  """{"saleId":"11111111-1111-4111-8111-111111111111","saleStatus":"Completed","saleCreated":"2026-10-10T15:04:05.123456789Z","saleCompleted":"2026-10-10T15:06:00.5Z","saleCustomerId":null,"saleEmployeeId":"0a6f2deb-892b-4411-8025-08c1a4d61229","saleRegisterId":"22222222-2222-4222-8222-222222222222","saleLocationId":"b2bd4b3a-d50f-4c04-90b1-01266735876b","saleItems":[{"itemId":"33333333-3333-4333-8333-333333333333","itemTransactionId":"11111111-1111-4111-8111-111111111111","itemMenuItemSku":"44444444-4444-4444-8444-444444444444","itemQuantity":2,"itemPricePerUnit":1500,"itemDiscounts":[],"itemTaxes":[{"taxCategory":"RegularSalesTax","taxRate":6.25e-2,"taxAmount":188,"taxDescription":"Sales tax"}],"itemSubtotal":3000,"itemTotal":3188}],"salePayments":[{"paymentId":"55555555-5555-4555-8555-555555555555","paymentTransactionId":"11111111-1111-4111-8111-111111111111","paymentMethod":"Cash","paymentAmount":3188,"paymentTendered":4000,"paymentChange":812,"paymentReference":null,"paymentApproved":true,"paymentAuthorizationCode":null}],"saleSubtotal":3000,"saleDiscountTotal":0,"saleTaxTotal":188,"saleTotal":3188,"saleKind":"StandardSale","saleIsVoided":false,"saleVoidReason":null,"saleIsRefunded":false,"saleRefundReason":null,"saleNotes":null}"""

refundedSale :: String
refundedSale =
  """{"saleId":"11111111-1111-4111-8111-111111111111","saleStatus":"Refunded","saleCreated":"2026-10-10T15:04:05Z","saleCompleted":"2026-10-10T15:06:00Z","saleCustomerId":null,"saleEmployeeId":"0a6f2deb-892b-4411-8025-08c1a4d61229","saleRegisterId":"22222222-2222-4222-8222-222222222222","saleLocationId":"b2bd4b3a-d50f-4c04-90b1-01266735876b","saleItems":[],"salePayments":[],"saleSubtotal":0,"saleDiscountTotal":0,"saleTaxTotal":0,"saleTotal":0,"saleKind":"StandardSale","saleIsVoided":false,"saleVoidReason":null,"saleIsRefunded":true,"saleRefundReason":"wrong item","saleNotes":null}"""

-- The refund of completedSale: money negated, quantity not negated.
refund :: String
refund =
  """{"refundId":"66666666-6666-4666-8666-666666666666","refundCreated":"2026-10-10T16:00:00.25Z","refundCompleted":"2026-10-10T16:00:00.25Z","refundCustomerId":null,"refundEmployeeId":"8b75ea4a-00a4-4a2a-a5d5-a1bab8883802","refundRegisterId":"22222222-2222-4222-8222-222222222222","refundLocationId":"b2bd4b3a-d50f-4c04-90b1-01266735876b","refundItems":[{"itemId":"77777777-7777-4777-8777-777777777777","itemTransactionId":"66666666-6666-4666-8666-666666666666","itemMenuItemSku":"44444444-4444-4444-8444-444444444444","itemQuantity":2,"itemPricePerUnit":1500,"itemDiscounts":[],"itemTaxes":[{"taxCategory":"RegularSalesTax","taxRate":6.25e-2,"taxAmount":-188,"taxDescription":"Sales tax"}],"itemSubtotal":-3000,"itemTotal":-3188}],"refundPayments":[{"paymentId":"88888888-8888-4888-8888-888888888888","paymentTransactionId":"66666666-6666-4666-8666-666666666666","paymentMethod":"Cash","paymentAmount":-3188,"paymentTendered":-4000,"paymentChange":-812,"paymentReference":null,"paymentApproved":true,"paymentAuthorizationCode":null}],"refundSubtotal":-3000,"refundDiscountTotal":0,"refundTaxTotal":-188,"refundTotal":-3188,"refundReferenceTransactionId":"11111111-1111-4111-8111-111111111111","refundReason":"wrong item","refundNotes":null}"""

closedRegister :: String
closedRegister =
  """{"registerId":"22222222-2222-4222-8222-222222222222","registerName":"Front counter","registerLocationId":"b2bd4b3a-d50f-4c04-90b1-01266735876b","registerIsOpen":false,"registerCurrentDrawerAmount":0,"registerExpectedDrawerAmount":0,"registerOpenedAt":null,"registerOpenedBy":null,"registerLastTransactionTime":null}"""

closeResult :: String
closeResult =
  """{"closeRegisterResultRegister":{"registerId":"22222222-2222-4222-8222-222222222222","registerName":"Front counter","registerLocationId":"b2bd4b3a-d50f-4c04-90b1-01266735876b","registerIsOpen":false,"registerCurrentDrawerAmount":9500,"registerExpectedDrawerAmount":10000,"registerOpenedAt":"2026-10-10T13:00:00Z","registerOpenedBy":"0a6f2deb-892b-4411-8025-08c1a4d61229","registerLastTransactionTime":null},"closeRegisterResultVariance":500}"""

activity :: String
activity =
  """{"asSummaryTime":"2026-10-10T16:00:00Z","asOpenRegisters":[],"asLiveTransactions":[{"tsId":"11111111-1111-4111-8111-111111111111","tsStatus":"InProgress","tsCreated":"2026-10-10T15:04:05Z","tsElapsedSecs":3355,"tsItemCount":1,"tsTotal":3188,"tsIsStale":true}],"asTodayStats":{"ldsTxCount":3,"ldsRevenue":-250,"ldsVoidCount":1,"ldsRefundCount":1,"ldsAvgTxValue":-84},"asAlerts":[{"tag":"LowInventoryAlert","contents":["44444444-4444-4444-8444-444444444444","OG Kush",2,5]},{"tag":"StaleTransactionAlert","contents":["11111111-1111-4111-8111-111111111111",3355]},{"tag":"RegisterVarianceAlert","contents":["22222222-2222-4222-8222-222222222222",-750]}]}"""

spec :: Spec.Spec Unit
spec = Spec.describe "Wire format as the backend writes it" do

  Spec.describe "A completed sale" do
    Spec.it "decodes" do
      decoded completedSale \(sale :: Sale.SaleTransaction) -> do
        sale.saleStatus `shouldEqual` Completed
        saleMoneyCents sale.saleTotal `shouldEqual` 3188
        length sale.saleItems `shouldEqual` 1
        length sale.salePayments `shouldEqual` 1
        sale.saleCustomerId `shouldEqual` Nothing

    Spec.it "keeps the line as the backend priced it" do
      decoded completedSale \(sale :: Sale.SaleTransaction) ->
        case sale.saleItems of
          [ item ] -> do
            saleQuantityCount item.itemQuantity `shouldEqual` 2
            saleMoneyCents item.itemPricePerUnit `shouldEqual` 1500
            saleMoneyCents item.itemTotal `shouldEqual` 3188
            (item.itemTaxes <#> _.taxCategory) `shouldEqual` [ RegularSalesTax ]
            (item.itemTaxes <#> _.taxRate) `shouldEqual` [ 0.0625 ]
          _ -> fail "expected one line"

    Spec.it "keeps the payment and its change" do
      decoded completedSale \(sale :: Sale.SaleTransaction) ->
        case sale.salePayments of
          [ payment ] -> do
            payment.paymentMethod `shouldEqual` Cash
            saleMoneyCents payment.paymentTendered `shouldEqual` 4000
            saleMoneyCents payment.paymentChange `shouldEqual` 812
          _ -> fail "expected one payment"

  Spec.describe "A refunded sale" do
    Spec.it "decodes with status Refunded and its reason" do
      decoded refundedSale \(sale :: Sale.SaleTransaction) -> do
        sale.saleStatus `shouldEqual` Refunded
        sale.saleIsRefunded `shouldEqual` true
        sale.saleRefundReason `shouldEqual` Just "wrong item"

  Spec.describe "A refund" do
    Spec.it "decodes" do
      decoded refund \(r :: Refund.RefundTransaction) -> do
        r.refundReferenceTransactionId
          `shouldEqual` UUID "11111111-1111-4111-8111-111111111111"
        r.refundReason `shouldEqual` "wrong item"

    Spec.it "has negative money" do
      decoded refund \(r :: Refund.RefundTransaction) -> do
        refundMoneyCents r.refundTotal `shouldEqual` (-3188)
        refundMoneyCents r.refundTaxTotal `shouldEqual` (-188)

    Spec.it "has a line quantity that is not negated" do
      decoded refund \(r :: Refund.RefundTransaction) ->
        (r.refundItems <#> \i -> refundQuantityCount i.itemQuantity)
          `shouldEqual` [ 2 ]

    Spec.it "refuses a negative line quantity" do
      case readJSON "-2" :: _ RefundQuantity of
        Left _ -> pure unit
        Right _ -> fail "a negative refund quantity was accepted"

  Spec.describe "A register" do
    Spec.it "decodes when closed and never opened" do
      decoded closedRegister \(register :: Register) -> do
        register.registerIsOpen `shouldEqual` false
        register.registerOpenedBy `shouldEqual` Nothing

    Spec.it "decodes the result of a close with its variance" do
      decoded closeResult \(result :: CloseRegisterResult) -> do
        result.closeRegisterResultVariance `shouldEqual` 500
        result.closeRegisterResultRegister.registerCurrentDrawerAmount
          `shouldEqual` 9500

    Spec.it "survives being written for a create and read back" do
      decoded closedRegister \(register :: Register) ->
        decoded (writeJSON register) \(again :: Register) ->
          again.registerId `shouldEqual` register.registerId

  Spec.describe "The manager's activity summary" do
    Spec.it "decodes the three kinds of alert" do
      decoded activity \(summary :: ActivitySummary) ->
        summary.asAlerts `shouldEqual`
          [ LowInventoryAlert
              { sku: UUID "44444444-4444-4444-8444-444444444444"
              , name: "OG Kush"
              , quantity: 2
              , threshold: 5
              }
          , StaleTransactionAlert
              { saleId: UUID "11111111-1111-4111-8111-111111111111"
              , elapsedSecs: 3355
              }
          , RegisterVarianceAlert
              { registerId: UUID "22222222-2222-4222-8222-222222222222"
              , variance: (-750)
              }
          ]

    Spec.it "decodes negative net revenue" do
      decoded activity \(summary :: ActivitySummary) ->
        summary.asTodayStats.ldsRevenue `shouldEqual` (-250)

    Spec.it "refuses an alert with an unknown tag" do
      case readJSON """{"tag":"SomethingElse","contents":[]}""" :: _ ManagerAlert of
        Left _ -> pure unit
        Right _ -> fail "an unknown alert tag was accepted"

    Spec.it "refuses an alert in the shape the front end used to expect" do
      case
        readJSON
          """{"tag":"LowInventoryAlert","id":"44444444-4444-4444-8444-444444444444","name":"OG Kush","quantity":2,"elapsed":null,"variance":null}"""
          :: _ ManagerAlert
        of
        Left _ -> pure unit
        Right _ -> fail "the old flat alert shape was accepted"

  Spec.describe "ApiError" do
    Spec.it "a refusal shows the backend's own message" do
      describe (Refused 409 "The sale is no longer open")
        `shouldEqual` "The sale is no longer open"

    Spec.it "a refusal with no body names the status" do
      describe (Refused 403 "")
        `shouldEqual` "The server refused the request (HTTP 403)"

    Spec.it "status is the HTTP status of a refusal" do
      status (Refused 404 "Sale not found") `shouldEqual` Just 404

    Spec.it "status is Nothing when no answer arrived or it did not decode" do
      status (Unreachable "offline") `shouldEqual` Nothing
      status (Undecodable "bad json") `shouldEqual` Nothing

    Spec.it "isRefusal matches one status only" do
      isRefusal 409 (Refused 409 "x") `shouldEqual` true
      isRefusal 409 (Refused 404 "x") `shouldEqual` false
      isRefusal 409 (Unreachable "x") `shouldEqual` false
