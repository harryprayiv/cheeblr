-- | Module for defining an Order Fulfillment System using Mealy Machines
module OrderFulfillment where

import Control.Category
import Control.Arrow
import Data.Profunctor
import Prelude hiding (id, (.))

-- | Basic Mealy Machine type
-- Input type 'i', output type 'o', and internal state type 's'
data StateMachine i o = StateMachine
  { runMachine :: forall s. s -> i -> (s, o)      -- State transition function
  , initialState :: forall s. s                    -- Initial state
  }

-- | Types for our Order Fulfillment System
data OrderState
  = Idle
  | OrderReceived
  | Verification
  | Picking
  | Packing
  | QualityControl
  | ReadyForShipping
  | Completed
  deriving (Show, Eq)

-- | Inputs to our Mealy machine
data FulfillmentInput
  = NewTransaction OrderDetails
  | InventoryCheckComplete InventoryStatus
  | VerificationComplete
  | ItemsCollected
  | PackingComplete
  | QCApproved
  | CarrierPickup
  deriving (Show, Eq)

-- | Outputs from our Mealy machine
data FulfillmentOutput
  = OrderDetailsReceived PickingList
  | AvailabilityStatus InventoryStatus
  | PickingInstructions PickingRoute
  | PackingInstructions PackagingMaterials
  | QCInstructions VerificationRequirements
  | ShippingLabel ShippingDocumentation
  | OrderCompletion AnalyticsData
  | NoOp
  deriving (Show, Eq)

-- | Additional types needed for our system
data OrderDetails = OrderDetails
  { orderId :: OrderId
  , items :: [Item]
  , priority :: Priority
  , customerInfo :: CustomerInfo
  } deriving (Show, Eq)

type OrderId = String
type Item = (ProductId, Quantity)
type ProductId = String
type Quantity = Int

data Priority = Standard | Express | Rush
  deriving (Show, Eq, Ord)

data CustomerInfo = CustomerInfo
  { customerId :: String
  , address :: Address
  , contactInfo :: ContactInfo
  } deriving (Show, Eq)

data Address = Address
  { street :: String
  , city :: String
  , state :: String
  , zipCode :: String
  , country :: String
  } deriving (Show, Eq)

data ContactInfo = ContactInfo
  { email :: String
  , phone :: Maybe String
  } deriving (Show, Eq)

data InventoryStatus
  = AllItemsAvailable
  | PartiallyAvailable [ProductId]
  | OutOfStock [ProductId]
  deriving (Show, Eq)

data PickingList = PickingList
  { listId :: String
  , orderRef :: OrderId
  , itemsToCollect :: [(ProductId, Quantity, Location)]
  } deriving (Show, Eq)

data Location = Location
  { aisle :: String
  , shelf :: String
  , bin :: String
  } deriving (Show, Eq)

data PickingRoute = PickingRoute
  { pickingList :: PickingList
  , optimizedPath :: [Location]
  , estimatedCompletionTime :: Int  -- in minutes
  } deriving (Show, Eq)

data PackagingMaterials = PackagingMaterials
  { boxSize :: BoxSize
  , packagingMaterial :: PackagingMaterial
  , additionalRequirements :: [PackagingRequirement]
  } deriving (Show, Eq)

data BoxSize = Small | Medium | Large | Custom Int Int Int
  deriving (Show, Eq)

data PackagingMaterial = Cardboard | Bubble | Foam | Paper
  deriving (Show, Eq)

data PackagingRequirement = Fragile | Refrigerate | Hazardous
  deriving (Show, Eq)

data VerificationRequirements = VerificationRequirements
  { itemsToCheck :: [ProductId]
  , packagingToCheck :: Bool
  , additionalChecks :: [String]
  } deriving (Show, Eq)

data ShippingDocumentation = ShippingDocumentation
  { shippingLabel :: String
  , packageId :: String
  , carrier :: Carrier
  , trackingNumber :: String
  } deriving (Show, Eq)

data Carrier = FedEx | UPS | USPS | DHL
  deriving (Show, Eq)

data AnalyticsData = AnalyticsData
  { processingTime :: Int  -- in minutes
  , fulfilledItems :: [(ProductId, Quantity)]
  , resourcesUsed :: [Resource]
  , exceptionsRaised :: [Exception]
  } deriving (Show, Eq)

data Resource
  = StaffTime StaffRole Int  -- role, minutes
  | Materials Int            -- cost in cents
  | Equipment String Int     -- equipment type, minutes used
  deriving (Show, Eq)

data StaffRole = Picker | Packer | QCAgent | ShippingClerk
  deriving (Show, Eq)

data Exception
  = ItemSubstitution ProductId ProductId
  | DelayedProcessing Int  -- delay in minutes
  | InventoryDiscrepancy ProductId Int  -- expected vs actual difference
  | QualityIssue String
  deriving (Show, Eq)

-- | Category instance for StateMachine
instance Category StateMachine where
  -- | Identity machine simply passes through inputs
  id = StateMachine
    { runMachine = \s i -> (s, i)
    , initialState = ()
    }
  
  -- | Sequential composition (b . a) feeds outputs of 'a' as inputs to 'b'
  (StateMachine runB initB) . (StateMachine runA initA) = StateMachine
    { runMachine = \(sA, sB) i -> 
        let (sA', o1) = runA sA i
            (sB', o2) = runB sB o1
        in ((sA', sB'), o2)
    , initialState = (initA, initB)
    }

-- | Profunctor instance for StateMachine
instance Profunctor StateMachine where
  -- | Transform the inputs before they reach the machine
  lmap f (StateMachine run init) = StateMachine
    { runMachine = \s i -> run s (f i)
    , initialState = init
    }
  
  -- | Transform the outputs after they leave the machine
  rmap f (StateMachine run init) = StateMachine
    { runMachine = \s i -> 
        let (s', o) = run s i
        in (s', f o)
    , initialState = init
    }

-- | Strong instance for StateMachine
instance Strong StateMachine where
  -- | Run the machine on the first component of a pair
  first' (StateMachine run init) = StateMachine
    { runMachine = \s (a, c) ->
        let (s', b) = run s a
        in (s', (b, c))
    , initialState = init
    }
  
  -- | Run the machine on the second component of a pair
  second' (StateMachine run init) = StateMachine
    { runMachine = \s (c, a) ->
        let (s', b) = run s a
        in (s', (c, b))
    , initialState = init
    }

-- | Choice instance for StateMachine
instance Choice StateMachine where
  -- | Run the machine on Left values
  left' (StateMachine run init) = StateMachine
    { runMachine = \s ei -> case ei of
        Left a ->
          let (s', b) = run s a
          in (s', Left b)
        Right c -> (s, Right c)
    , initialState = init
    }
  
  -- | Run the machine on Right values
  right' (StateMachine run init) = StateMachine
    { runMachine = \s ei -> case ei of
        Left c -> (s, Left c)
        Right a ->
          let (s', b) = run s a
          in (s', Right b)
    , initialState = init
    }

-- | Arrow instance for StateMachine
instance Arrow StateMachine where
  -- | Convert a function to a machine
  arr f = StateMachine
    { runMachine = \s a -> (s, f a)
    , initialState = ()
    }
  
  -- | Run the machine on the first component of a pair
  first (StateMachine run init) = StateMachine
    { runMachine = \s (a, c) ->
        let (s', b) = run s a
        in (s', (b, c))
    , initialState = init
    }

-- | ArrowChoice instance for StateMachine
instance ArrowChoice StateMachine where
  -- | Run the machine on Left values
  left (StateMachine run init) = StateMachine
    { runMachine = \s ei -> case ei of
        Left a ->
          let (s', b) = run s a
          in (s', Left b)
        Right c -> (s, Right c)
    , initialState = init
    }

-- | Parallel composition of two machines
-- Both machines run in parallel with the same input
-- and their outputs are combined
fanOut :: StateMachine a b -> StateMachine a c -> StateMachine a (b, c)
fanOut (StateMachine runA initA) (StateMachine runB initB) = StateMachine
  { runMachine = \(sA, sB) i ->
      let (sA', b) = runA sA i
          (sB', c) = runB sB i
      in ((sA', sB'), (b, c))
  , initialState = (initA, initB)
  }

-- | Alternative composition of two machines
-- Depending on the input type, either the first or second machine is executed
fanIn :: StateMachine a c -> StateMachine b c -> StateMachine (Either a b) c
fanIn (StateMachine runA initA) (StateMachine runB initB) = StateMachine
  { runMachine = \(sA, sB) ei -> case ei of
      Left a ->
        let (sA', c) = runA sA a
        in ((sA', sB), c)
      Right b ->
        let (sB', c) = runB sB b
        in ((sA, sB'), c)
  , initialState = (initA, initB)
  }

-- | Create a basic fulfillment machine
fulfillmentMachine :: StateMachine FulfillmentInput FulfillmentOutput
fulfillmentMachine = StateMachine
  { runMachine = \state input -> 
      case (state, input) of
        (Idle, NewTransaction details) ->
          (OrderReceived, OrderDetailsReceived (generatePickingList details))
          
        (OrderReceived, InventoryCheckComplete status) ->
          (Verification, AvailabilityStatus status)
          
        (Verification, VerificationComplete) ->
          (Picking, PickingInstructions (generateOptimizedRoute state))
          
        (Picking, ItemsCollected) ->
          (Packing, PackingInstructions (determinePackagingMaterials state))
          
        (Packing, PackingComplete) ->
          (QualityControl, QCInstructions (generateQCRequirements state))
          
        (QualityControl, QCApproved) ->
          (ReadyForShipping, ShippingLabel (generateShippingDocumentation state))
          
        (ReadyForShipping, CarrierPickup) ->
          (Completed, OrderCompletion (generateAnalytics state))
          
        _ -> (state, NoOp)  -- No change for invalid state transitions
  , initialState = Idle
  }
  where
    -- | These functions would contain the business logic for each transition
    generatePickingList :: OrderDetails -> PickingList
    generatePickingList details = PickingList
      { listId = "PL-" ++ orderId details
      , orderRef = orderId details
      , itemsToCollect = map (\(pid, qty) -> (pid, qty, mockLocation pid)) (items details)
      }
    
    mockLocation :: ProductId -> Location
    mockLocation pid = Location
      { aisle = take 1 pid
      , shelf = take 2 $ drop 1 pid
      , bin = take 3 $ drop 3 pid
      }
    
    generateOptimizedRoute :: OrderState -> PickingRoute
    generateOptimizedRoute _ = PickingRoute
      { pickingList = PickingList "PL-mock" "mock-order" []
      , optimizedPath = []
      , estimatedCompletionTime = 15
      }
    
    determinePackagingMaterials :: OrderState -> PackagingMaterials
    determinePackagingMaterials _ = PackagingMaterials
      { boxSize = Medium
      , packagingMaterial = Cardboard
      , additionalRequirements = []
      }
    
    generateQCRequirements :: OrderState -> VerificationRequirements
    generateQCRequirements _ = VerificationRequirements
      { itemsToCheck = []
      , packagingToCheck = True
      , additionalChecks = []
      }
    
    generateShippingDocumentation :: OrderState -> ShippingDocumentation
    generateShippingDocumentation _ = ShippingDocumentation
      { shippingLabel = "Mock Label"
      , packageId = "PKG-123"
      , carrier = FedEx
      , trackingNumber = "TRACK123456"
      }
    
    generateAnalytics :: OrderState -> AnalyticsData
    generateAnalytics _ = AnalyticsData
      { processingTime = 45
      , fulfilledItems = []
      , resourcesUsed = [StaffTime Picker 15, StaffTime Packer 10]
      , exceptionsRaised = []
      }

-- | Helper function to run a machine with a specific sequence of inputs
runSequence :: StateMachine i o -> [i] -> [o]
runSequence (StateMachine run init) = go init
  where
    go s [] = []
    go s (i:is) =
      let (s', o) = run s i
      in o : go s' is

-- | Example usage
sampleOrderDetails :: OrderDetails
sampleOrderDetails = OrderDetails
  { orderId = "ORD-12345"
  , items =
      [ ("PROD-A", 2)
      , ("PROD-B", 1)
      , ("PROD-C", 3)
      ]
  , priority = Express
  , customerInfo = CustomerInfo
      { customerId = "CUST-789"
      , address = Address
          { street = "123 Main St"
          , city = "Springfield"
          , state = "IL"
          , zipCode = "62701"
          , country = "USA"
          }
      , contactInfo = ContactInfo
          { email = "customer@example.com"
          , phone = Just "555-123-4567"
          }
      }
  }

-- | Example input sequence for order processing
sampleInputSequence :: [FulfillmentInput]
sampleInputSequence =
  [ NewTransaction sampleOrderDetails
  , InventoryCheckComplete AllItemsAvailable
  , VerificationComplete
  , ItemsCollected
  , PackingComplete
  , QCApproved
  , CarrierPickup
  ]

-- | Process a sample order
processSampleOrder :: [FulfillmentOutput]
processSampleOrder = runSequence fulfillmentMachine sampleInputSequence

-- | Define a specialized machine that only handles express orders
expressOrderMachine :: StateMachine FulfillmentInput FulfillmentOutput
expressOrderMachine = StateMachine
  { runMachine = \state input -> 
      case input of
        NewTransaction details | priority details /= Express -> 
          (state, NoOp)  -- Only process Express orders
        _ -> runMachine fulfillmentMachine state input
  , initialState = Idle
  }

-- | Custom combinators for order fulfillment system

-- | Compose two machines with analytics
withAnalytics :: StateMachine FulfillmentInput FulfillmentOutput 
              -> StateMachine FulfillmentInput FulfillmentOutput
              -> StateMachine FulfillmentInput FulfillmentOutput
withAnalytics machineA machineB = StateMachine
  { runMachine = \(sA, sB, analytics) input ->
      let (sA', outputA) = runMachine machineA sA input
          (sB', outputB) = runMachine machineB sB input
          -- Merge the outputs with priority to machineA
          finalOutput = if outputA == NoOp then outputB else outputA
          -- Record analytics about this operation
          newAnalytics = updateAnalytics analytics input finalOutput
      in ((sA', sB', newAnalytics), finalOutput)
  , initialState = (initialState machineA, initialState machineB, [])
  }
  where
    updateAnalytics :: [(FulfillmentInput, FulfillmentOutput)] 
                    -> FulfillmentInput 
                    -> FulfillmentOutput 
                    -> [(FulfillmentInput, FulfillmentOutput)]
    updateAnalytics analytics input output = 
      if output == NoOp
        then analytics  -- Don't record no-ops
        else (input, output) : analytics

-- | Enhanced machine that handles errors and retries
withErrorHandling :: Int -> StateMachine FulfillmentInput FulfillmentOutput 
                  -> StateMachine FulfillmentInput FulfillmentOutput
withErrorHandling maxRetries machine = StateMachine
  { runMachine = \(s, retries) input ->
      let (s', output) = runMachine machine s input
      in case output of
           NoOp -> 
             if retries < maxRetries
               -- Retry the operation
               then let (s'', retriedOutput) = runMachine machine s input
                    in ((s'', retries + 1), retriedOutput)
               -- Max retries reached, propagate the NoOp
               else ((s', 0), NoOp)
           _ -> ((s', 0), output)  -- Reset retry count on success
  , initialState = (initialState machine, 0)
  }