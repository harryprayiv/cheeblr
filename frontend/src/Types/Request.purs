module Types.Request where

import Prelude

import Foreign (Foreign)

newtype ForeignRequestBody = ForeignRequestBody Foreign

data ServiceError
  = APIError String
  | ServiceValidationError String
  | NotFoundError String
  | AuthorizationError String
  | NetworkError String
  | UnknownError String

derive instance eqServiceError :: Eq ServiceError
derive instance ordServiceError :: Ord ServiceError

instance showServiceError :: Show ServiceError where
  show (APIError msg) = "API Error: " <> msg
  show (ServiceValidationError msg) = "Validation Error: " <> msg
  show (NotFoundError msg) = "Not Found: " <> msg
  show (AuthorizationError msg) = "Authorization Error: " <> msg
  show (NetworkError msg) = "Network Error: " <> msg
  show (UnknownError msg) = "Unknown Error: " <> msg