module Services.API where

import Prelude

import Control.Monad.Reader (ReaderT(..), runReaderT)
import Data.Either (Either(..))
import Effect.Aff (Aff)
import Effect.Aff.Class (class MonadAff)
import Effect.Class (class MonadEffect, liftEffect)
import Effect.Class.Console as Console
import Types.Common (ServiceError)
import Types.Inventory (MenuItem(MenuItem))

-- Define the service typeclass
class Monad m <= MonadService m where
  addMenuItem :: MenuItem -> m (Either ServiceError MenuItem)

-- Live service implementation that connects to the backend
newtype LiveService a = LiveService (Aff a)

derive newtype instance functorLiveService :: Functor LiveService
derive newtype instance applyLiveService :: Apply LiveService
derive newtype instance applicativeLiveService :: Applicative LiveService
derive newtype instance bindLiveService :: Bind LiveService
derive newtype instance monadLiveService :: Monad LiveService
derive newtype instance monadEffectLiveService :: MonadEffect LiveService
derive newtype instance monadAffLiveService :: MonadAff LiveService

instance monadServiceLiveService :: MonadService LiveService where
  addMenuItem menuItem = do
    liftEffect $ Console.log "Adding menu item to API"
    -- Here you would make an API call to add the item
    -- This is a placeholder - you would replace with actual API call
    pure $ Right menuItem

runLiveService :: forall a. LiveService a -> Aff a
runLiveService (LiveService aff) = aff

-- Environment-dependent service
newtype AppService a = AppService (ReaderT AppEnv Aff a)

type AppEnv =
  { useReals :: Boolean
  }

derive newtype instance functorAppService :: Functor AppService
derive newtype instance applyAppService :: Apply AppService
derive newtype instance applicativAppService :: Applicative AppService
derive newtype instance bindAppService :: Bind AppService
derive newtype instance monadAppService :: Monad AppService
derive newtype instance monadEffectAppService :: MonadEffect AppService
derive newtype instance monadAffAppService :: MonadAff AppService

instance monadServiceAppService :: MonadService AppService where
  addMenuItem menuItem = do
    AppService
      ( ReaderT \env -> do
          if env.useReals then runLiveService (addMenuItem menuItem)
          else runMockService (addMenuItem menuItem)
      )

runAppService :: forall a. AppEnv -> AppService a -> Aff a
runAppService env (AppService reader) = runReaderT reader env

-- Mock service implementation for testing
newtype MockService a = MockService (Aff a)

derive newtype instance functorMockService :: Functor MockService
derive newtype instance applyMockService :: Apply MockService
derive newtype instance applicativeMockService :: Applicative MockService
derive newtype instance bindMockService :: Bind MockService
derive newtype instance monadMockService :: Monad MockService
derive newtype instance monadEffectMockService :: MonadEffect MockService
derive newtype instance monadAffMockService :: MonadAff MockService

instance monadServiceMockService :: MonadService MockService where
  addMenuItem (MenuItem item) = do
    liftEffect $ Console.log $ "Mock: Adding item " <> item.name
    pure $ Right (MenuItem item)

runMockService :: forall a. MockService a -> Aff a
runMockService (MockService aff) = aff