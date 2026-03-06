module Test.Main where

import Prelude

import Effect (Effect)
import Test.Auth as Auth
import Test.Cart as Cart
import Test.Formatting as Formatting
import Test.Inventory as Inventory
import Test.JsonContract as JsonContract
import Test.Money as Money
import Test.Session as Session
import Test.Spec (describe)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner.Node (runSpecAndExitProcess)
import Test.UUID as UUID
import Test.Validation as Validation

main :: Effect Unit
main = runSpecAndExitProcess [consoleReporter] $ describe "Cheeblr Frontend" do
  Validation.spec
  Formatting.spec
  Money.spec
  Auth.spec
  Cart.spec
  Inventory.spec
  UUID.spec
  Session.spec
  JsonContract.spec