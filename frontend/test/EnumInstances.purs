module Test.EnumInstances where

import Prelude

import Data.Array (head, last) as Array
import Data.Enum (pred, succ, fromEnum, toEnum)
import Data.Maybe (Maybe(..))
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)
import Config.LiveView (QueryMode(..))
import Types.Auth (UserRole(..))
import Types.Inventory (ItemCategory(..), Species(..))
import Utils.Formatting (getAllEnumValues)

spec :: Spec Unit
spec = describe "Enum Instances" do

  describe "UserRole Enum" do
    it "succ Customer = Just Cashier" $
      succ Customer `shouldEqual` Just Cashier
    it "succ Cashier = Just Manager" $
      succ Cashier `shouldEqual` Just Manager
    it "succ Manager = Just Admin" $
      succ Manager `shouldEqual` Just Admin
    it "succ Admin = Nothing" $
      succ Admin `shouldEqual` (Nothing :: Maybe UserRole)
    it "pred Cashier = Just Customer" $
      pred Cashier `shouldEqual` Just Customer
    it "pred Manager = Just Cashier" $
      pred Manager `shouldEqual` Just Cashier
    it "pred Admin = Just Manager" $
      pred Admin `shouldEqual` Just Manager
    it "pred Customer = Nothing" $
      pred Customer `shouldEqual` (Nothing :: Maybe UserRole)
    it "fromEnum Customer = 0" $
      fromEnum Customer `shouldEqual` 0
    it "fromEnum Cashier = 1" $
      fromEnum Cashier `shouldEqual` 1
    it "fromEnum Manager = 2" $
      fromEnum Manager `shouldEqual` 2
    it "fromEnum Admin = 3" $
      fromEnum Admin `shouldEqual` 3
    it "toEnum 0 = Just Customer" $
      (toEnum 0 :: Maybe UserRole) `shouldEqual` Just Customer
    it "toEnum 1 = Just Cashier" $
      (toEnum 1 :: Maybe UserRole) `shouldEqual` Just Cashier
    it "toEnum 2 = Just Manager" $
      (toEnum 2 :: Maybe UserRole) `shouldEqual` Just Manager
    it "toEnum 3 = Just Admin" $
      (toEnum 3 :: Maybe UserRole) `shouldEqual` Just Admin
    it "toEnum 4 = Nothing" $
      (toEnum 4 :: Maybe UserRole) `shouldEqual` Nothing
    it "toEnum (-1) = Nothing" $
      (toEnum (-1) :: Maybe UserRole) `shouldEqual` Nothing
    it "bottom = Customer" $
      (bottom :: UserRole) `shouldEqual` Customer
    it "top = Admin" $
      (top :: UserRole) `shouldEqual` Admin

  describe "ItemCategory Enum" do
    it "succ Flower = Just PreRolls" $
      succ Flower `shouldEqual` Just PreRolls
    it "succ PreRolls = Just Vaporizers" $
      succ PreRolls `shouldEqual` Just Vaporizers
    it "succ Tinctures = Just Accessories" $
      succ Tinctures `shouldEqual` Just Accessories
    it "succ Accessories = Nothing" $
      succ Accessories `shouldEqual` (Nothing :: Maybe ItemCategory)
    it "pred Flower = Nothing" $
      pred Flower `shouldEqual` (Nothing :: Maybe ItemCategory)
    it "pred PreRolls = Just Flower" $
      pred PreRolls `shouldEqual` Just Flower
    it "pred Accessories = Just Tinctures" $
      pred Accessories `shouldEqual` Just Tinctures
    it "fromEnum Flower = 0" $
      fromEnum Flower `shouldEqual` 0
    it "fromEnum Accessories = 8" $
      fromEnum Accessories `shouldEqual` 8
    it "toEnum 0 = Just Flower" $
      (toEnum 0 :: Maybe ItemCategory) `shouldEqual` Just Flower
    it "toEnum 4 = Just Drinks" $
      (toEnum 4 :: Maybe ItemCategory) `shouldEqual` Just Drinks
    it "toEnum 8 = Just Accessories" $
      (toEnum 8 :: Maybe ItemCategory) `shouldEqual` Just Accessories
    it "toEnum 9 = Nothing" $
      (toEnum 9 :: Maybe ItemCategory) `shouldEqual` Nothing
    it "bottom = Flower" $
      (bottom :: ItemCategory) `shouldEqual` Flower
    it "top = Accessories" $
      (top :: ItemCategory) `shouldEqual` Accessories

  describe "Species Enum" do
    it "succ Indica = Just IndicaDominantHybrid" $
      succ Indica `shouldEqual` Just IndicaDominantHybrid
    it "succ IndicaDominantHybrid = Just Hybrid" $
      succ IndicaDominantHybrid `shouldEqual` Just Hybrid
    it "succ Hybrid = Just SativaDominantHybrid" $
      succ Hybrid `shouldEqual` Just SativaDominantHybrid
    it "succ SativaDominantHybrid = Just Sativa" $
      succ SativaDominantHybrid `shouldEqual` Just Sativa
    it "succ Sativa = Nothing" $
      succ Sativa `shouldEqual` (Nothing :: Maybe Species)
    it "pred Indica = Nothing" $
      pred Indica `shouldEqual` (Nothing :: Maybe Species)
    it "pred IndicaDominantHybrid = Just Indica" $
      pred IndicaDominantHybrid `shouldEqual` Just Indica
    it "pred Sativa = Just SativaDominantHybrid" $
      pred Sativa `shouldEqual` Just SativaDominantHybrid
    it "fromEnum Indica = 0" $
      fromEnum Indica `shouldEqual` 0
    it "fromEnum Hybrid = 2" $
      fromEnum Hybrid `shouldEqual` 2
    it "fromEnum Sativa = 4" $
      fromEnum Sativa `shouldEqual` 4
    it "toEnum 0 = Just Indica" $
      (toEnum 0 :: Maybe Species) `shouldEqual` Just Indica
    it "toEnum 2 = Just Hybrid" $
      (toEnum 2 :: Maybe Species) `shouldEqual` Just Hybrid
    it "toEnum 4 = Just Sativa" $
      (toEnum 4 :: Maybe Species) `shouldEqual` Just Sativa
    it "toEnum 5 = Nothing" $
      (toEnum 5 :: Maybe Species) `shouldEqual` Nothing
    it "bottom = Indica" $
      (bottom :: Species) `shouldEqual` Indica
    it "top = Sativa" $
      (top :: Species) `shouldEqual` Sativa

  describe "QueryMode Show" do
    it "JsonMode" $ show JsonMode `shouldEqual` "JsonMode"
    it "HttpMode" $ show HttpMode `shouldEqual` "HttpMode"
    it "GqlMode"  $ show GqlMode  `shouldEqual` "GqlMode"

  describe "QueryMode Eq" do
    it "reflexive"     $ (JsonMode == JsonMode) `shouldEqual` true
    it "distinct pair" $ (JsonMode == HttpMode) `shouldEqual` false

  describe "QueryMode Ord" do
    it "JsonMode < HttpMode" $ (JsonMode < HttpMode) `shouldEqual` true
    it "HttpMode < GqlMode"  $ (HttpMode < GqlMode)  `shouldEqual` true

  describe "getAllEnumValues" do
    it "UserRole — all 4 values in order" $
      (getAllEnumValues :: Array UserRole)
        `shouldEqual` [ Customer, Cashier, Manager, Admin ]

    it "ItemCategory — all 9 values in order" $
      (getAllEnumValues :: Array ItemCategory)
        `shouldEqual`
          [ Flower, PreRolls, Vaporizers, Edibles, Drinks
          , Concentrates, Topicals, Tinctures, Accessories
          ]

    it "Species — all 5 values in order" $
      (getAllEnumValues :: Array Species)
        `shouldEqual`
          [ Indica, IndicaDominantHybrid, Hybrid, SativaDominantHybrid, Sativa ]

    it "UserRole count is 4" do
      let roles = getAllEnumValues :: Array UserRole
      (roles /= []) `shouldEqual` true

    it "first UserRole is Customer" do
      Array.head (getAllEnumValues :: Array UserRole) `shouldEqual` Just Customer

    it "last ItemCategory is Accessories" do
      Array.last (getAllEnumValues :: Array ItemCategory) `shouldEqual` Just Accessories