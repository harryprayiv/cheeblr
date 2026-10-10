module Pages.Feed.Monitor where

import Deku.Core (Nut)
import Pages.Admin.Tabs.FeedMonitor (feedMonitor)
import UI.Leave (OnLeave)

page :: OnLeave -> Nut
page onLeave = feedMonitor onLeave
