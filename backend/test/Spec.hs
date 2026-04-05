module Main where

import Test.Hspec

import qualified Test.API.AdminSpec
import qualified Test.API.OpenApiSpec
import qualified Test.API.TransactionSpec
import qualified Test.App.CspSpec
import qualified Test.App.MiddlewareSpec
import qualified Test.Auth.SimpleSpec
import qualified Test.DB.PureFunctionsSpec
import qualified Test.Effect.EventEmitterSpec
import qualified Test.Effect.InventoryDbSpec
import qualified Test.Effect.StockDbSpec
import qualified Test.GraphQL.ResolversSpec
import qualified Test.GraphQL.SchemaSpec
import qualified Test.Infrastructure.AvailabilityRelaySpec
import qualified Test.Manager.LogicSpec
import qualified Test.Manager.TypesSpec
import qualified Test.Props.JsonRoundtripSpec
import qualified Test.Props.NegateSpec
import qualified Test.Props.ParseShowSpec
import qualified Test.Props.StateMachineSpec
import qualified Test.Server.CookieSpec
import qualified Test.Server.Middleware.TracingSpec
import qualified Test.Service.RegisterSpec
import qualified Test.Service.StockSpec
import qualified Test.Service.TransactionSpec
import qualified Test.State.RegisterMachineSpec
import qualified Test.State.StockPullMachineSpec
import qualified Test.State.TransactionMachineSpec
import qualified Test.Types.AuthSpec
import qualified Test.Types.InventorySpec
import qualified Test.Types.Public.AvailableItemSpec
import qualified Test.Types.Public.FeedFrameSpec
import qualified Test.Types.Public.FeedPrivacySpec
import qualified Test.Types.TraceSpec
import qualified Test.Types.TransactionSpec

main :: IO ()
main = hspec $ do
  describe "Cheeblr Backend" $ do
    Test.Types.AuthSpec.spec
    Test.Types.TraceSpec.spec
    Test.Types.TransactionSpec.spec
    Test.Types.InventorySpec.spec
    Test.Types.Public.AvailableItemSpec.spec
    Test.Types.Public.FeedFrameSpec.spec
    Test.Types.Public.FeedPrivacySpec.spec
    Test.Auth.SimpleSpec.spec
    Test.API.TransactionSpec.spec
    Test.API.OpenApiSpec.spec
    Test.API.AdminSpec.spec
    Test.DB.PureFunctionsSpec.spec
    Test.GraphQL.SchemaSpec.spec
    Test.GraphQL.ResolversSpec.spec
    Test.State.TransactionMachineSpec.spec
    Test.State.RegisterMachineSpec.spec
    Test.Effect.InventoryDbSpec.spec
    Test.Effect.EventEmitterSpec.spec
    Test.Server.CookieSpec.spec
    Test.Server.Middleware.TracingSpec.spec
    Test.App.CspSpec.spec
    Test.App.MiddlewareSpec.spec
    Test.Service.TransactionSpec.spec
    Test.Service.RegisterSpec.spec
    Test.Props.JsonRoundtripSpec.spec
    Test.Props.ParseShowSpec.spec
    Test.Props.NegateSpec.spec
    Test.Props.StateMachineSpec.spec
    Test.Infrastructure.AvailabilityRelaySpec.spec
    Test.Manager.TypesSpec.spec
    Test.Manager.LogicSpec.spec
    Test.State.StockPullMachineSpec.spec
    Test.Effect.StockDbSpec.spec
    Test.Service.StockSpec.spec