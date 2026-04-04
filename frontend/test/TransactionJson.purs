-- Tests the write→read roundtrip for Transaction types.
-- Key concern: WriteForeign Transaction uses maybeToNullable for optional fields.
-- These tests verify that Nothing → null → Nothing survives the full roundtrip,
-- and that Just v → json value → Just v also survives.
module Test.TransactionJson where

import Prelude

import Data.Maybe (Maybe(..), isJust)
import Data.String (Pattern(..), contains)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Types.Transaction
  ( PaymentMethod(..)
  , PaymentTransaction(..)
  , TaxCategory(..)
  , Transaction(..)
  , TransactionItem(..)
  , TransactionStatus(..)
  , TransactionType(..)
  )
import Types.UUID (UUID(..))
import Yoga.JSON (readJSON_, writeJSON)

-- Minimal Transaction JSON with all optional fields null.
-- This is the format the backend sends; we parse it then roundtrip.
minimalTransactionJson :: String
minimalTransactionJson =
  """{"transactionId":"33333333-3333-3333-3333-333333333333","transactionStatus":"Created","transactionCreated":"2024-06-15T10:30:00Z","transactionCompleted":null,"transactionCustomerId":null,"transactionEmployeeId":"44444444-4444-4444-4444-444444444444","transactionRegisterId":"55555555-5555-5555-5555-555555555555","transactionLocationId":"66666666-6666-6666-6666-666666666666","transactionItems":[],"transactionPayments":[],"transactionSubtotal":0,"transactionDiscountTotal":0,"transactionTaxTotal":0,"transactionTotal":0,"transactionType":"Sale","transactionIsVoided":false,"transactionVoidReason":null,"transactionIsRefunded":false,"transactionRefundReason":null,"transactionReferenceTransactionId":null,"transactionNotes":null}"""

-- Transaction JSON with optional fields populated.
fullTransactionJson :: String
fullTransactionJson =
  """{"transactionId":"33333333-3333-3333-3333-333333333333","transactionStatus":"Completed","transactionCreated":"2024-06-15T10:30:00Z","transactionCompleted":"2024-06-15T11:00:00Z","transactionCustomerId":"77777777-7777-7777-7777-777777777777","transactionEmployeeId":"44444444-4444-4444-4444-444444444444","transactionRegisterId":"55555555-5555-5555-5555-555555555555","transactionLocationId":"66666666-6666-6666-6666-666666666666","transactionItems":[],"transactionPayments":[],"transactionSubtotal":2999,"transactionDiscountTotal":0,"transactionTaxTotal":240,"transactionTotal":3239,"transactionType":"Sale","transactionIsVoided":false,"transactionVoidReason":null,"transactionIsRefunded":false,"transactionRefundReason":null,"transactionReferenceTransactionId":null,"transactionNotes":"Regular customer"}"""

-- TransactionItem JSON
transactionItemJson :: String
transactionItemJson =
  """{"transactionItemId":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","transactionItemTransactionId":"33333333-3333-3333-3333-333333333333","transactionItemMenuItemSku":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","transactionItemQuantity":2,"transactionItemPricePerUnit":1499,"transactionItemDiscounts":[],"transactionItemTaxes":[{"taxCategory":"CannabisTax","taxRate":0.15,"taxAmount":450,"taxDescription":"Cannabis Tax"}],"transactionItemSubtotal":2998,"transactionItemTotal":3448}"""

-- PaymentTransaction JSON - Cash with no optional fields
cashPaymentJson :: String
cashPaymentJson =
  """{"paymentId":"cccccccc-cccc-cccc-cccc-cccccccccccc","paymentTransactionId":"33333333-3333-3333-3333-333333333333","paymentMethod":"Cash","paymentAmount":3239,"paymentTendered":4000,"paymentChange":761,"paymentReference":null,"paymentApproved":true,"paymentAuthorizationCode":null}"""

-- PaymentTransaction JSON - Credit with auth code
creditPaymentJson :: String
creditPaymentJson =
  """{"paymentId":"dddddddd-dddd-dddd-dddd-dddddddddddd","paymentTransactionId":"33333333-3333-3333-3333-333333333333","paymentMethod":"Credit","paymentAmount":3239,"paymentTendered":3239,"paymentChange":0,"paymentReference":"ref-123","paymentApproved":true,"paymentAuthorizationCode":"AUTH-XYZ-789"}"""

spec :: Spec Unit
spec = describe "Transaction JSON Roundtrips" do

  describe "Transaction — parse from backend JSON" do
    it "parses minimal Transaction" $
      (readJSON_ minimalTransactionJson :: Maybe Transaction) `shouldSatisfy` isJust

    it "parses full Transaction" $
      (readJSON_ fullTransactionJson :: Maybe Transaction) `shouldSatisfy` isJust

    it "null transactionCompleted → Nothing" $
      case readJSON_ minimalTransactionJson :: Maybe Transaction of
        Just (Transaction tx) -> tx.transactionCompleted `shouldEqual` Nothing
        Nothing               -> false `shouldEqual` true

    it "non-null transactionCompleted → Just" $
      case readJSON_ fullTransactionJson :: Maybe Transaction of
        Just (Transaction tx) -> (tx.transactionCompleted /= Nothing) `shouldEqual` true
        Nothing               -> false `shouldEqual` true

    it "null transactionCustomerId → Nothing" $
      case readJSON_ minimalTransactionJson :: Maybe Transaction of
        Just (Transaction tx) -> tx.transactionCustomerId `shouldEqual` Nothing
        Nothing               -> false `shouldEqual` true

    it "non-null transactionCustomerId → Just UUID" $
      case readJSON_ fullTransactionJson :: Maybe Transaction of
        Just (Transaction tx) ->
          tx.transactionCustomerId `shouldEqual` Just (UUID "77777777-7777-7777-7777-777777777777")
        Nothing -> false `shouldEqual` true

    it "null transactionNotes → Nothing" $
      case readJSON_ minimalTransactionJson :: Maybe Transaction of
        Just (Transaction tx) -> tx.transactionNotes `shouldEqual` Nothing
        Nothing               -> false `shouldEqual` true

    it "non-null transactionNotes → Just String" $
      case readJSON_ fullTransactionJson :: Maybe Transaction of
        Just (Transaction tx) -> tx.transactionNotes `shouldEqual` Just "Regular customer"
        Nothing               -> false `shouldEqual` true

    it "preserves transactionStatus Created" $
      case readJSON_ minimalTransactionJson :: Maybe Transaction of
        Just (Transaction tx) -> tx.transactionStatus `shouldEqual` Created
        Nothing               -> false `shouldEqual` true

    it "preserves transactionStatus Completed" $
      case readJSON_ fullTransactionJson :: Maybe Transaction of
        Just (Transaction tx) -> tx.transactionStatus `shouldEqual` Completed
        Nothing               -> false `shouldEqual` true

    it "preserves transactionType Sale" $
      case readJSON_ minimalTransactionJson :: Maybe Transaction of
        Just (Transaction tx) -> tx.transactionType `shouldEqual` Sale
        Nothing               -> false `shouldEqual` true

    it "preserves transactionId" $
      case readJSON_ minimalTransactionJson :: Maybe Transaction of
        Just (Transaction tx) ->
          tx.transactionId `shouldEqual` UUID "33333333-3333-3333-3333-333333333333"
        Nothing -> false `shouldEqual` true

    it "transactionIsVoided false" $
      case readJSON_ minimalTransactionJson :: Maybe Transaction of
        Just (Transaction tx) -> tx.transactionIsVoided `shouldEqual` false
        Nothing               -> false `shouldEqual` true

    it "empty transactionItems array" $
      case readJSON_ minimalTransactionJson :: Maybe Transaction of
        Just (Transaction tx) -> tx.transactionItems `shouldEqual` []
        Nothing               -> false `shouldEqual` true

  describe "Transaction write→read roundtrip (tests maybeToNullable)" do
    it "minimal Transaction roundtrips without data loss" do
      case readJSON_ minimalTransactionJson :: Maybe Transaction of
        Nothing -> false `shouldEqual` true
        Just tx ->
          let written = writeJSON tx
          in (readJSON_ written :: Maybe Transaction) `shouldSatisfy` isJust

    it "Nothing optionals write as null" do
      case readJSON_ minimalTransactionJson :: Maybe Transaction of
        Nothing -> false `shouldEqual` true
        Just tx ->
          let written = writeJSON tx
          in contains (Pattern "null") written `shouldEqual` true

    it "roundtrip preserves transactionStatus" do
      case readJSON_ minimalTransactionJson :: Maybe Transaction of
        Nothing -> false `shouldEqual` true
        Just tx ->
          case readJSON_ (writeJSON tx) :: Maybe Transaction of
            Just (Transaction tx2) -> tx2.transactionStatus `shouldEqual` Created
            Nothing                -> false `shouldEqual` true

    it "roundtrip preserves Nothing for transactionCompleted" do
      case readJSON_ minimalTransactionJson :: Maybe Transaction of
        Nothing -> false `shouldEqual` true
        Just tx ->
          case readJSON_ (writeJSON tx) :: Maybe Transaction of
            Just (Transaction tx2) -> tx2.transactionCompleted `shouldEqual` Nothing
            Nothing                -> false `shouldEqual` true

    it "roundtrip preserves Nothing for transactionCustomerId" do
      case readJSON_ minimalTransactionJson :: Maybe Transaction of
        Nothing -> false `shouldEqual` true
        Just tx ->
          case readJSON_ (writeJSON tx) :: Maybe Transaction of
            Just (Transaction tx2) -> tx2.transactionCustomerId `shouldEqual` Nothing
            Nothing                -> false `shouldEqual` true

    it "roundtrip preserves Nothing for transactionNotes" do
      case readJSON_ minimalTransactionJson :: Maybe Transaction of
        Nothing -> false `shouldEqual` true
        Just tx ->
          case readJSON_ (writeJSON tx) :: Maybe Transaction of
            Just (Transaction tx2) -> tx2.transactionNotes `shouldEqual` Nothing
            Nothing                -> false `shouldEqual` true

    it "full Transaction roundtrips" do
      case readJSON_ fullTransactionJson :: Maybe Transaction of
        Nothing -> false `shouldEqual` true
        Just tx ->
          (readJSON_ (writeJSON tx) :: Maybe Transaction) `shouldSatisfy` isJust

    it "full Transaction preserves notes after roundtrip" do
      case readJSON_ fullTransactionJson :: Maybe Transaction of
        Nothing -> false `shouldEqual` true
        Just tx ->
          case readJSON_ (writeJSON tx) :: Maybe Transaction of
            Just (Transaction tx2) -> tx2.transactionNotes `shouldEqual` Just "Regular customer"
            Nothing                -> false `shouldEqual` true

    it "full Transaction preserves customerId after roundtrip" do
      case readJSON_ fullTransactionJson :: Maybe Transaction of
        Nothing -> false `shouldEqual` true
        Just tx ->
          case readJSON_ (writeJSON tx) :: Maybe Transaction of
            Just (Transaction tx2) ->
              tx2.transactionCustomerId
                `shouldEqual` Just (UUID "77777777-7777-7777-7777-777777777777")
            Nothing -> false `shouldEqual` true

  describe "TransactionItem — parse from backend JSON" do
    it "parses TransactionItem" $
      (readJSON_ transactionItemJson :: Maybe TransactionItem) `shouldSatisfy` isJust

    it "preserves transactionItemQuantity" $
      case readJSON_ transactionItemJson :: Maybe TransactionItem of
        Just (TransactionItem ti) -> ti.transactionItemQuantity `shouldEqual` 2
        Nothing                   -> false `shouldEqual` true

    it "parses taxes array" $
      case readJSON_ transactionItemJson :: Maybe TransactionItem of
        Just (TransactionItem ti) -> (ti.transactionItemTaxes /= []) `shouldEqual` true
        Nothing                   -> false `shouldEqual` true

    it "preserves tax category" $
      case readJSON_ transactionItemJson :: Maybe TransactionItem of
        Just (TransactionItem ti) ->
          case ti.transactionItemTaxes of
            [ tax ] -> tax.taxCategory `shouldEqual` CannabisTax
            _       -> false `shouldEqual` true
        Nothing -> false `shouldEqual` true

    it "preserves tax rate" $
      case readJSON_ transactionItemJson :: Maybe TransactionItem of
        Just (TransactionItem ti) ->
          case ti.transactionItemTaxes of
            [ tax ] -> tax.taxRate `shouldEqual` 0.15
            _       -> false `shouldEqual` true
        Nothing -> false `shouldEqual` true

    it "preserves transactionItemMenuItemSku" $
      case readJSON_ transactionItemJson :: Maybe TransactionItem of
        Just (TransactionItem ti) ->
          ti.transactionItemMenuItemSku
            `shouldEqual` UUID "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
        Nothing -> false `shouldEqual` true

  describe "TransactionItem write→read roundtrip" do
    it "roundtrips without data loss" do
      case readJSON_ transactionItemJson :: Maybe TransactionItem of
        Nothing -> false `shouldEqual` true
        Just ti ->
          (readJSON_ (writeJSON ti) :: Maybe TransactionItem) `shouldSatisfy` isJust

    it "preserves quantity after roundtrip" do
      case readJSON_ transactionItemJson :: Maybe TransactionItem of
        Nothing -> false `shouldEqual` true
        Just ti ->
          case readJSON_ (writeJSON ti) :: Maybe TransactionItem of
            Just (TransactionItem ti2) -> ti2.transactionItemQuantity `shouldEqual` 2
            Nothing                    -> false `shouldEqual` true

    it "preserves tax category after roundtrip" do
      case readJSON_ transactionItemJson :: Maybe TransactionItem of
        Nothing -> false `shouldEqual` true
        Just ti ->
          case readJSON_ (writeJSON ti) :: Maybe TransactionItem of
            Just (TransactionItem ti2) ->
              case ti2.transactionItemTaxes of
                [ tax ] -> tax.taxCategory `shouldEqual` CannabisTax
                _       -> false `shouldEqual` true
            Nothing -> false `shouldEqual` true

  describe "PaymentTransaction — parse from backend JSON" do
    it "parses Cash payment" $
      (readJSON_ cashPaymentJson :: Maybe PaymentTransaction) `shouldSatisfy` isJust

    it "parses Credit payment" $
      (readJSON_ creditPaymentJson :: Maybe PaymentTransaction) `shouldSatisfy` isJust

    it "Cash: preserves paymentMethod" $
      case readJSON_ cashPaymentJson :: Maybe PaymentTransaction of
        Just (PaymentTransaction p) -> p.paymentMethod `shouldEqual` Cash
        Nothing                     -> false `shouldEqual` true

    it "Cash: preserves paymentApproved" $
      case readJSON_ cashPaymentJson :: Maybe PaymentTransaction of
        Just (PaymentTransaction p) -> p.paymentApproved `shouldEqual` true
        Nothing                     -> false `shouldEqual` true

    it "Cash: null paymentReference → Nothing" $
      case readJSON_ cashPaymentJson :: Maybe PaymentTransaction of
        Just (PaymentTransaction p) -> p.paymentReference `shouldEqual` Nothing
        Nothing                     -> false `shouldEqual` true

    it "Cash: null paymentAuthorizationCode → Nothing" $
      case readJSON_ cashPaymentJson :: Maybe PaymentTransaction of
        Just (PaymentTransaction p) -> p.paymentAuthorizationCode `shouldEqual` Nothing
        Nothing                     -> false `shouldEqual` true

    it "Credit: preserves paymentMethod" $
      case readJSON_ creditPaymentJson :: Maybe PaymentTransaction of
        Just (PaymentTransaction p) -> p.paymentMethod `shouldEqual` Credit
        Nothing                     -> false `shouldEqual` true

    it "Credit: preserves paymentAuthorizationCode" $
      case readJSON_ creditPaymentJson :: Maybe PaymentTransaction of
        Just (PaymentTransaction p) ->
          p.paymentAuthorizationCode `shouldEqual` Just "AUTH-XYZ-789"
        Nothing -> false `shouldEqual` true

    it "Credit: preserves paymentReference" $
      case readJSON_ creditPaymentJson :: Maybe PaymentTransaction of
        Just (PaymentTransaction p) ->
          p.paymentReference `shouldEqual` Just "ref-123"
        Nothing -> false `shouldEqual` true

  describe "PaymentTransaction write→read roundtrip" do
    it "Cash payment roundtrips" do
      case readJSON_ cashPaymentJson :: Maybe PaymentTransaction of
        Nothing -> false `shouldEqual` true
        Just p ->
          (readJSON_ (writeJSON p) :: Maybe PaymentTransaction) `shouldSatisfy` isJust

    it "Cash: Nothing options preserved after roundtrip" do
      case readJSON_ cashPaymentJson :: Maybe PaymentTransaction of
        Nothing -> false `shouldEqual` true
        Just p ->
          case readJSON_ (writeJSON p) :: Maybe PaymentTransaction of
            Just (PaymentTransaction p2) -> do
              p2.paymentReference `shouldEqual` Nothing
              p2.paymentAuthorizationCode `shouldEqual` Nothing
            Nothing -> false `shouldEqual` true

    it "Credit payment roundtrips" do
      case readJSON_ creditPaymentJson :: Maybe PaymentTransaction of
        Nothing -> false `shouldEqual` true
        Just p ->
          (readJSON_ (writeJSON p) :: Maybe PaymentTransaction) `shouldSatisfy` isJust

    it "Credit: auth code preserved after roundtrip" do
      case readJSON_ creditPaymentJson :: Maybe PaymentTransaction of
        Nothing -> false `shouldEqual` true
        Just p ->
          case readJSON_ (writeJSON p) :: Maybe PaymentTransaction of
            Just (PaymentTransaction p2) ->
              p2.paymentAuthorizationCode `shouldEqual` Just "AUTH-XYZ-789"
            Nothing -> false `shouldEqual` true

    it "Credit: preserves method after roundtrip" do
      case readJSON_ creditPaymentJson :: Maybe PaymentTransaction of
        Nothing -> false `shouldEqual` true
        Just p ->
          case readJSON_ (writeJSON p) :: Maybe PaymentTransaction of
            Just (PaymentTransaction p2) -> p2.paymentMethod `shouldEqual` Credit
            Nothing                      -> false `shouldEqual` true