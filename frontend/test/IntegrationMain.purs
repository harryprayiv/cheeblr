module Test.IntegrationMain where

import Prelude

import Effect (Effect)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner.Node (runSpecAndExitProcess)
import Test.Spec (describe)
import Test.HttpIntegration as HttpIntegration

main :: Effect Unit
main = runSpecAndExitProcess [consoleReporter] $ describe "Cheeblr Integration (HTTP)" do
  HttpIntegration.spec