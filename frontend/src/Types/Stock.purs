module Types.Stock where

import Prelude

import Data.DateTime (DateTime)
import Data.Maybe (Maybe)
import Types.UUID (UUID)

data PullVertex
  = PullPending
  | PullAccepted
  | PullPulling
  | PullFulfilled
  | PullCancelled
  | PullIssue

derive instance eqPullVertex :: Eq PullVertex
derive instance ordPullVertex :: Ord PullVertex

instance showPullVertex :: Show PullVertex where
  show PullPending   = "PullPending"
  show PullAccepted  = "PullAccepted"
  show PullPulling   = "PullPulling"
  show PullFulfilled = "PullFulfilled"
  show PullCancelled = "PullCancelled"
  show PullIssue     = "PullIssue"

type PullRequest =
  { prId             :: UUID
  , prTransactionId  :: UUID
  , prItemSku        :: UUID
  , prItemName       :: String
  , prQuantityNeeded :: Int
  , prStatus         :: String
  , prCashierId      :: Maybe UUID
  , prRegisterId     :: Maybe UUID
  , prLocationId     :: UUID
  , prCreatedAt      :: DateTime
  , prUpdatedAt      :: DateTime
  , prFulfilledAt    :: Maybe DateTime
  }

type PullMessage =
  { pmId            :: UUID
  , pmPullRequestId :: UUID
  , pmFromRole      :: String
  , pmSenderId      :: UUID
  , pmMessage       :: String
  , pmCreatedAt     :: DateTime
  }

type PullRequestDetail =
  { pdPullRequest :: PullRequest
  , pdMessages    :: Array PullMessage
  }

data PullAction
  = ActionAccept
  | ActionStart
  | ActionFulfill
  | ActionReportIssue
  | ActionRetry
  | ActionCancel

validActions :: String -> Array PullAction
validActions = case _ of
  "PullPending"   -> [ ActionAccept, ActionCancel ]
  "PullAccepted"  -> [ ActionStart,  ActionCancel ]
  "PullPulling"   -> [ ActionFulfill, ActionReportIssue ]
  "PullIssue"     -> [ ActionRetry,  ActionCancel ]
  _               -> []

actionLabel :: PullAction -> String
actionLabel ActionAccept      = "Accept"
actionLabel ActionStart       = "Start Pull"
actionLabel ActionFulfill     = "Mark Fulfilled"
actionLabel ActionReportIssue = "Report Issue"
actionLabel ActionRetry       = "Retry"
actionLabel ActionCancel      = "Cancel"

statusClass :: String -> String
statusClass "PullPending"   = "status-pending"
statusClass "PullAccepted"  = "status-accepted"
statusClass "PullPulling"   = "status-pulling"
statusClass "PullFulfilled" = "status-fulfilled"
statusClass "PullCancelled" = "status-cancelled"
statusClass "PullIssue"     = "status-issue"
statusClass _               = ""