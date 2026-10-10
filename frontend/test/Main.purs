module Test.Main where

import Prelude

import Effect (Effect)
import Test.AdminTypes as AdminTypes
import Test.Auth as Auth
import Test.EnumInstances as EnumInstances
import Test.FeedTypes as FeedTypes
import Test.FormParser as FormParser
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
import Test.TransactionModel as TransactionModel
import Test.UUID as UUID
import Test.WebUtils as WebUtils
import Test.Wire as Wire

main :: Effect Unit
main = runSpecAndExitProcess [ consoleReporter ] $ describe "Cheeblr Frontend" do

  Formatting.spec
  Money.spec
  UUID.spec
  FormParser.spec


  Auth.spec
  Session.spec


  Inventory.spec
  TransactionModel.spec


  JsonContract.spec
  Wire.spec
  GraphQL.spec
  TransactionJson.spec


  Stock.spec
  WebUtils.spec
  AdminTypes.spec
  ManagerTypes.spec
  FeedTypes.spec
  Location.spec
  EnumInstances.spec
  ShowInstances.spec

