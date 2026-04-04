module Pages.Feed.Monitor where

import Deku.Core (Nut)
import FRP.Poll (Poll)
import Pages.Admin.Tabs.FeedMonitor (feedMonitor)
import Services.AuthService (AuthState, UserId)

page :: Poll AuthState -> UserId -> Nut
page _authPoll userId = feedMonitor userId