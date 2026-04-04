module Test.Main where

import Prelude

import Effect (Effect)
import Test.AdminTypes as AdminTypes
import Test.Auth as Auth
import Test.Cart as Cart
import Test.EnumInstances as EnumInstances
import Test.FeedTypes as FeedTypes
import Test.Formatting as Formatting
import Test.GraphQL as GraphQL
import Test.Inventory as Inventory
import Test.JsonContract as JsonContract
import Test.Location as Location
import Test.ManagerTypes as ManagerTypes
import Test.Money as Money
import Test.Session as Session
import Test.ShowInstances as ShowInstances
import Test.Spec (describe)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner.Node (runSpecAndExitProcess)
import Test.Stock as Stock
import Test.TransactionJson as TransactionJson
import Test.UUID as UUID
import Test.Validation as Validation
import Test.ValidatorsV as ValidatorsV
import Test.WebUtils as WebUtils

main :: Effect Unit
main = runSpecAndExitProcess [ consoleReporter ] $ describe "Cheeblr Frontend" do
  -- Core types and utilities
  Validation.spec
  Formatting.spec
  Money.spec
  UUID.spec

  -- Auth and session
  Auth.spec
  Session.spec

  -- Business logic
  Cart.spec
  Inventory.spec

  -- JSON contracts (backend ↔ frontend)
  JsonContract.spec
  GraphQL.spec
  TransactionJson.spec

  -- New: type-specific coverage
  Stock.spec
  WebUtils.spec
  AdminTypes.spec
  ManagerTypes.spec
  FeedTypes.spec
  Location.spec
  EnumInstances.spec
  ValidatorsV.spec
  ShowInstances.spec
