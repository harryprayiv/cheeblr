module Test.IntegrationMain where

import Prelude

import Effect (Effect)
import Test.GraphQLIntegration as GraphQLIntegration
import Test.HttpIntegration as HttpIntegration
import Test.Spec (describe)
import Test.Spec.Reporter.Console (consoleReporter)
import Test.Spec.Runner.Node (runSpecAndExitProcess)

main :: Effect Unit
main = runSpecAndExitProcess [ consoleReporter ] $ describe "Cheeblr Integration (HTTP)" do
  HttpIntegration.spec
  GraphQLIntegration.spec