# Transaction State Machine Integration

This document explains the integration of a type-safe state machine approach for transaction processing in our POS system, using the Crem library.

## Overview

We've added a robust state machine implementation to manage transaction state transitions in a type-safe manner. This means that illegal state transitions are caught at compile-time rather than runtime, making our application more reliable and easier to reason about.

### Key Benefits

- **Type Safety**: Illegal state transitions are prevented at the type level
- **Explicit State Modeling**: Each transaction state has its own explicit data type
- **Better Error Handling**: Clear error messages when someone attempts an invalid operation
- **Visualization**: The state machine can be visualized using Crem's rendering capabilities

## Key Components

### 1. Transaction Vertex Type

The `TransactionVertex` type defines all possible states a transaction can be in:

```haskell
data TransactionVertex
  = Created
  | InProgress
  | Completed
  | Voided
  | Refunded
```

### 2. Transaction Topology

The topology defines which state transitions are allowed:

```haskell
transactionTopology :: Topology TransactionVertex
transactionTopology =
  Topology
    [ (Created, [InProgress])
    , (InProgress, [InProgress, Completed, Voided])
    , (Completed, [Refunded, Voided])
    , (Voided, [])
    , (Refunded, [])
    ]
```

This shows that:
- A newly created transaction can only move to InProgress
- An in-progress transaction can stay in progress, be completed, or voided
- A completed transaction can be refunded or voided
- Voided and refunded transactions are terminal states with no further transitions

### 3. Transaction State

Each state has its own data type with appropriate fields:

```haskell
data TransactionState (vertex :: TransactionVertex) where
  CreatedState :: { ... } -> TransactionState 'Created
  InProgressState :: { ... } -> TransactionState 'InProgress
  CompletedState :: { ... } -> TransactionState 'Completed
  VoidedState :: { ... } -> TransactionState 'Voided
  RefundedState :: { ... } -> TransactionState 'Refunded
```

### 4. Commands and Events

We define commands that can be sent to the state machine:

```haskell
data TransactionCommand
  = InitTransaction UUID UTCTime UUID UUID UUID
  | AddItem TransactionItem
  | UpdateItem TransactionItem
  | RemoveItem UUID
  | AddPayment PaymentTransaction
  | RemovePayment UUID
  | FinalizeTransaction UTCTime
  | VoidTransaction Text UTCTime
  | RefundTransaction Text UTCTime UUID
```

And events that it emits in response:

```haskell
data TransactionEvent
  = TransactionCreated UUID
  | ItemAdded TransactionItem
  | ItemUpdated TransactionItem
  | ItemRemoved UUID
  | PaymentAdded PaymentTransaction
  | PaymentRemoved UUID
  | TransactionFinalized UTCTime
  | TransactionVoided Text UTCTime
  | TransactionRefunded Text UTCTime UUID
  | IllegalStateTransition Text
```

## Using the State Machine Implementation

### Enabling the State Machine

The system can use either the original implementation or the new state machine implementation. To enable the state machine:

```bash
# Set environment variable before starting the application
export USE_STATE_MACHINE=True
```

Or set this in your deployment configuration.

### Visualizing the State Machine

You can visualize the transaction state machine using Crem's rendering capabilities. Create a simple application that outputs a Mermaid diagram:

```haskell
import State.Transaction
import Crem.Render.Render
import Data.Text.IO qualified as Text

main :: IO ()
main = do
  let (Mermaid mermaid) = renderStateDiagram . topologyAsGraph $ transactionTopology
  Text.putStrLn mermaid
```

This will output a diagram showing all possible state transitions.

### Extending the State Machine

To add new states or transitions:

1. Add a new vertex to `TransactionVertex`
2. Update the `transactionTopology` to include transitions to/from the new state
3. Add a new constructor to `TransactionState` with appropriate fields
4. Update the `transactionMachine` function to handle the new state

### Service Layer

The service layer in `Service.Transaction` provides high-level functions that use the state machine internally:

- `createNewTransaction`: Creates a new transaction
- `addTransactionItem`: Adds an item to a transaction
- `removeTransactionItem`: Removes an item from a transaction
- `addPaymentTransaction`: Adds a payment to a transaction
- `removePaymentTransaction`: Removes a payment
- `finalizeTransaction`: Completes a transaction
- `voidTransaction`: Voids a transaction
- `refundTransaction`: Processes a refund

These functions validate state transitions and handle errors in a clean way.

## Error Handling

When an illegal state transition is attempted, the state machine emits an `IllegalStateTransition` event with a descriptive error message. For example, if you try to add an item to a completed transaction, you'll get an error like:

```
"Failed to add item: Cannot add items to a completed transaction"
```

## Future Improvements

Potential future improvements:

1. Add more sophisticated validation rules within allowed transitions
2. Create state machines for other entities (Register, Inventory)
3. Implement transaction event sourcing using the state machine events
4. Add property-based testing to verify state machine invariants
5. Create visual dashboards showing state transitions in the system