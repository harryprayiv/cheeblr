module Test.Gen (
  genUUID,
  genText,
  genMaybeText,
  genUTCTime,
  genMaybeUTCTime,
  genTransactionStatus,
  genTransactionType,
  genPaymentMethod,
  genTaxCategory,
  genDiscountType,
  genTaxRecord,
  genDiscountRecord,
  genTransactionItem,
  genPaymentTransaction,
  genTransaction,
  genSpecies,
  genItemCategory,
  genStrainLineage,
  genMenuItem,
  genInventory,
) where

import Data.Scientific (Scientific)
import Data.Text (Text)
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import qualified Data.Vector as V
import Hedgehog
import qualified Hedgehog.Gen as Gen
import qualified Hedgehog.Range as Range

import Types.Inventory
import Types.Location (LocationId (..))
import Types.Transaction

genUUID :: Gen UUID
genUUID =
  UUID.fromWords
    <$> Gen.word32 Range.constantBounded
    <*> Gen.word32 Range.constantBounded
    <*> Gen.word32 Range.constantBounded
    <*> Gen.word32 Range.constantBounded

genText :: Gen Text
genText = Gen.text (Range.linear 1 40) Gen.alphaNum

genMaybeText :: Gen (Maybe Text)
genMaybeText = Gen.maybe genText

genUTCTime :: Gen UTCTime
genUTCTime = do
  year <- Gen.integral (Range.linear 2020 2030)
  month <- Gen.integral (Range.linear 1 12)
  day <- Gen.integral (Range.linear 1 28)
  secs <- Gen.integral (Range.linear 0 86399)
  pure $ UTCTime (fromGregorian year month day) (secondsToDiffTime secs)

genMaybeUTCTime :: Gen (Maybe UTCTime)
genMaybeUTCTime = Gen.maybe genUTCTime

genTransactionStatus :: Gen TransactionStatus
genTransactionStatus =
  Gen.element [Created, InProgress, Completed, Voided, Refunded]

genTransactionType :: Gen TransactionType
genTransactionType =
  Gen.element [Sale, Return, Exchange, InventoryAdjustment, ManagerComp, Administrative]

genPaymentMethod :: Gen PaymentMethod
genPaymentMethod =
  Gen.choice
    [ pure Cash
    , pure Debit
    , pure Credit
    , pure ACH
    , pure GiftCard
    , pure StoredValue
    , pure Mixed
    , Other <$> genText
    ]

genTaxCategory :: Gen TaxCategory
genTaxCategory =
  Gen.element [RegularSalesTax, ExciseTax, CannabisTax, LocalTax, MedicalTax, NoTax]

-- Integer Scientific values roundtrip through JSON without precision noise.
genScientific :: Gen Scientific
genScientific = fromIntegral <$> Gen.int (Range.linear 0 10000)

genDiscountType :: Gen DiscountType
genDiscountType =
  Gen.choice
    [ PercentOff <$> genScientific
    , AmountOff <$> Gen.int (Range.linear 0 100000)
    , pure BuyOneGetOne
    , Custom <$> genText <*> Gen.int (Range.linear 0 100000)
    ]

genTaxRecord :: Gen TaxRecord
genTaxRecord =
  TaxRecord
    <$> genTaxCategory
    <*> genScientific
    <*> Gen.int (Range.linear 0 1000000)
    <*> genText

genDiscountRecord :: Gen DiscountRecord
genDiscountRecord =
  DiscountRecord
    <$> genDiscountType
    <*> Gen.int (Range.linear 0 1000000)
    <*> genText
    <*> Gen.maybe genUUID

genTransactionItem :: Gen TransactionItem
genTransactionItem =
  TransactionItem
    <$> genUUID
    <*> genUUID
    <*> genUUID
    <*> Gen.int (Range.linear 1 100)
    <*> Gen.int (Range.linear 100 1000000)
    <*> Gen.list (Range.linear 0 3) genDiscountRecord
    <*> Gen.list (Range.linear 0 3) genTaxRecord
    <*> Gen.int (Range.linear 0 1000000)
    <*> Gen.int (Range.linear 0 1000000)

genPaymentTransaction :: Gen PaymentTransaction
genPaymentTransaction =
  PaymentTransaction
    <$> genUUID
    <*> genUUID
    <*> genPaymentMethod
    <*> Gen.int (Range.linear 0 10000000)
    <*> Gen.int (Range.linear 0 10000000)
    <*> Gen.int (Range.linear 0 10000000)
    <*> Gen.maybe genText
    <*> Gen.bool
    <*> Gen.maybe genText

genTransaction :: Gen Transaction
genTransaction =
  Transaction
    <$> genUUID
    <*> genTransactionStatus
    <*> genUTCTime
    <*> genMaybeUTCTime
    <*> Gen.maybe genUUID
    <*> genUUID
    <*> genUUID
    <*> (LocationId <$> genUUID)
    <*> Gen.list (Range.linear 0 3) genTransactionItem
    <*> Gen.list (Range.linear 0 2) genPaymentTransaction
    <*> Gen.int (Range.linear 0 10000000)
    <*> Gen.int (Range.linear 0 1000000)
    <*> Gen.int (Range.linear 0 1000000)
    <*> Gen.int (Range.linear 0 10000000)
    <*> genTransactionType
    <*> Gen.bool
    <*> Gen.maybe genText
    <*> Gen.bool
    <*> Gen.maybe genText
    <*> Gen.maybe genUUID
    <*> Gen.maybe genText

genSpecies :: Gen Species
genSpecies =
  Gen.element [Indica, IndicaDominantHybrid, Hybrid, SativaDominantHybrid, Sativa]

genItemCategory :: Gen ItemCategory
genItemCategory =
  Gen.element
    [Flower, PreRolls, Vaporizers, Edibles, Drinks, Concentrates, Topicals, Tinctures, Accessories]

genVectorText :: Gen (V.Vector Text)
genVectorText = V.fromList <$> Gen.list (Range.linear 0 5) genText

genStrainLineage :: Gen StrainLineage
genStrainLineage =
  StrainLineage
    <$> genText
    <*> genText
    <*> genText
    <*> genText
    <*> genSpecies
    <*> genText
    <*> genVectorText
    <*> genVectorText
    <*> genText
    <*> genText

genMenuItem :: Gen MenuItem
genMenuItem =
  MenuItem
    <$> Gen.int (Range.linear 0 9999)
    <*> genUUID
    <*> genText
    <*> genText
    <*> Gen.int (Range.linear 0 10000000)
    <*> genText
    <*> genText
    <*> Gen.int (Range.linear 0 100000)
    <*> genItemCategory
    <*> genText
    <*> genText
    <*> genVectorText
    <*> genVectorText
    <*> genStrainLineage

genInventory :: Gen Inventory
genInventory = Inventory . V.fromList <$> Gen.list (Range.linear 0 5) genMenuItem
