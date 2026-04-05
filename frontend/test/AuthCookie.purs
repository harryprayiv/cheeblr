module Test.AuthCookie where

import Prelude

import Config.Auth (devAdmin, devCashier, devCustomer, devManager)
import Data.Maybe (Maybe(..), isNothing)
import Data.String (Pattern(..), contains)
import Data.String as String
import Effect.Class (liftEffect)
import Services.AuthService
  ( AuthState(..)
  , ActorId
  , UserId
  , clearToken
  , devModeAuthState
  , authStateForUserId
  , getUserId
  , isSignedIn
  , loadToken
  , persistToken
  , userIdFromAuth
  )
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Types.UUID (UUID(..))

-- Verify a string looks like a UUID: 36 chars, dashes in right places.
looksLikeUUID :: String -> Boolean
looksLikeUUID s =
  String.length s == 36
    && String.take 1 (String.drop 8  s) == "-"
    && String.take 1 (String.drop 13 s) == "-"
    && String.take 1 (String.drop 18 s) == "-"
    && String.take 1 (String.drop 23 s) == "-"

spec :: Spec Unit
spec = describe "AuthService — HttpOnly cookie migration" do

  -- ── Cookie store is now no-op ─────────────────────────────────────────────

  describe "persistToken is a no-op" do
    it "calling persistToken does not crash" do
      liftEffect $ persistToken "any-token-value"
      true `shouldEqual` true

    it "persistToken followed by loadToken still returns Nothing" do
      liftEffect $ persistToken "some-bearer-token"
      result <- liftEffect loadToken
      result `shouldEqual` Nothing

  describe "loadToken always returns Nothing" do
    it "returns Nothing on fresh call" do
      result <- liftEffect loadToken
      result `shouldEqual` Nothing

    it "returns Nothing even after multiple persist calls" do
      liftEffect $ persistToken "token-one"
      liftEffect $ persistToken "token-two"
      result <- liftEffect loadToken
      result `shouldEqual` Nothing

  describe "clearToken is a no-op" do
    it "calling clearToken does not crash" do
      liftEffect clearToken
      true `shouldEqual` true

    it "clearToken does not break loadToken" do
      liftEffect $ persistToken "some-token"
      liftEffect clearToken
      result <- liftEffect loadToken
      result `shouldEqual` Nothing

  -- ── ActorId slot carries UUID, not session token ──────────────────────────

  describe "SignedIn second slot is ActorId (UUID string), not bearer token" do
    it "devModeAuthState is SignedIn with a UUID-shaped ActorId" do
      case devModeAuthState of
        SignedOut -> false `shouldEqual` true
        SignedIn _ actorId -> looksLikeUUID actorId `shouldEqual` true

    it "userIdFromAuth returns a UUID-shaped string for devAdmin" do
      let state = SignedIn devAdmin (show devAdmin.userId)
      looksLikeUUID (userIdFromAuth state) `shouldEqual` true

    it "userIdFromAuth returns a UUID-shaped string for devCashier" do
      let state = SignedIn devCashier (show devCashier.userId)
      looksLikeUUID (userIdFromAuth state) `shouldEqual` true

    it "userIdFromAuth returns a UUID-shaped string for devManager" do
      let state = SignedIn devManager (show devManager.userId)
      looksLikeUUID (userIdFromAuth state) `shouldEqual` true

    it "userIdFromAuth returns a UUID-shaped string for devCustomer" do
      let state = SignedIn devCustomer (show devCustomer.userId)
      looksLikeUUID (userIdFromAuth state) `shouldEqual` true

    it "userIdFromAuth does NOT return a bearer token format (no 'Bearer' prefix)" do
      let state = SignedIn devAdmin (show devAdmin.userId)
      contains (Pattern "Bearer") (userIdFromAuth state) `shouldEqual` false

    it "userIdFromAuth does NOT contain whitespace" do
      let state = SignedIn devAdmin (show devAdmin.userId)
      contains (Pattern " ") (userIdFromAuth state) `shouldEqual` false

    it "userIdFromAuth returns empty string for SignedOut" do
      userIdFromAuth SignedOut `shouldEqual` ""

  describe "getUserId returns Just UUID string for SignedIn" do
    it "getUserId for admin is Just a UUID-shaped string" do
      let state = SignedIn devAdmin (show devAdmin.userId)
      case getUserId state of
        Nothing  -> false `shouldEqual` true
        Just uid -> looksLikeUUID uid `shouldEqual` true

    it "getUserId for cashier matches cashier's UUID" do
      let state = SignedIn devCashier (show devCashier.userId)
      getUserId state `shouldEqual` Just (show devCashier.userId)

    it "getUserId returns Nothing for SignedOut" do
      getUserId SignedOut `shouldEqual` Nothing

  -- ── authStateForUserId stores UUID as ActorId ─────────────────────────────

  describe "authStateForUserId stores UUID in ActorId slot" do
    it "finds admin and stores UUID as ActorId" do
      case authStateForUserId devAdmin.userId of
        Nothing -> false `shouldEqual` true
        Just (SignedOut) -> false `shouldEqual` true
        Just (SignedIn _ actorId) ->
          actorId `shouldEqual` show devAdmin.userId

    it "finds cashier and stores UUID as ActorId" do
      case authStateForUserId devCashier.userId of
        Nothing -> false `shouldEqual` true
        Just (SignedOut) -> false `shouldEqual` true
        Just (SignedIn _ actorId) ->
          looksLikeUUID actorId `shouldEqual` true

    it "returns Nothing for unknown UUID" do
      authStateForUserId (UUID "00000000-0000-0000-0000-000000000000")
        `shouldSatisfy` isNothing

  -- ── devModeAuthState invariants ───────────────────────────────────────────

  describe "devModeAuthState" do
    it "is SignedIn" do
      isSignedIn devModeAuthState `shouldEqual` true

    it "ActorId matches defaultDevUser UUID" do
      case devModeAuthState of
        SignedOut -> false `shouldEqual` true
        SignedIn user actorId ->
          actorId `shouldEqual` show user.userId

    it "ActorId is UUID-shaped" do
      case devModeAuthState of
        SignedOut -> false `shouldEqual` true
        SignedIn _ actorId -> looksLikeUUID actorId `shouldEqual` true

    it "userIdFromAuth on devModeAuthState returns non-empty UUID" do
      let uid = userIdFromAuth devModeAuthState
      (uid /= "") `shouldEqual` true
      looksLikeUUID uid `shouldEqual` true

  -- ── Type alias parity ─────────────────────────────────────────────────────

  describe "ActorId and UserId are both String (type alias parity)" do
    it "a UserId value is accepted where ActorId is expected" do
      let uid = show devAdmin.userId :: UserId
          aid = uid :: ActorId
      aid `shouldEqual` uid

    it "userIdFromAuth result type satisfies ActorId constraint" do
      let state = SignedIn devAdmin (show devAdmin.userId)
          aid   = userIdFromAuth state :: ActorId
      looksLikeUUID aid `shouldEqual` true