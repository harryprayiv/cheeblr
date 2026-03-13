## Phantom Indices, Singleton Witnesses, and the Road Not Yet Taken

### What crem is actually doing to my types

Let me begin with what my codebase would look like without crem. I would write something like this:

```haskell
data RegState = RegClosed | RegOpen

transition :: RegState -> RegCommand -> (RegEvent, RegState)
```

This typechecks. It also permits me to write `transition RegClosed CloseRegCmd = (_, RegOpen)`, which is a logical absurdity that the compiler will happily accept. My type system is not earning its keep.

Crem's contribution is to make the transition relation a first-class citizen of the type system. The key mechanism is the promoted topology:

```haskell
type RegTopology = 'Topology
  '[ '( 'RegClosed, '[ 'RegClosed, 'RegOpen])
   , '( 'RegOpen,   '[ 'RegOpen,   'RegClosed])
   ]
```

This is not a value. It is a type. More precisely, it is a type-level list of pairs, promoted from the value level via `DataKinds`. It encodes the directed graph of my state machine as a constraint that lives entirely in the type universe.

My state type then becomes a GADT indexed by a vertex:

```haskell
data RegState (v :: RegVertex) where
  ClosedState :: Register -> RegState 'RegClosed
  OpenState   :: Register -> RegState 'RegOpen
```

The index `v :: RegVertex` is a phantom in the sense that it does not appear in the stored data, but it is not phantom in the pejorative sense of being uninhabited or unverifiable. When I pattern-match on `ClosedState`, GHC refines `v` to `'RegClosed` in that branch. The GADT gives me local type equality witnesses.

The payoff arrives in `regAction`:

```haskell
regAction :: RegState v
          -> RegCommand
          -> ActionResult Identity RegTopology RegState v RegEvent
```

The type `ActionResult Identity RegTopology RegState v RegEvent` is where crem does its work. Inside `pureResult`, the library requires that the next state I hand back has a vertex type that is provably reachable from `v` in `RegTopology`. If I were to write:

```haskell
regAction (ClosedState reg) (CloseRegCmd _ _) =
  pureResult (RegWasClosed reg 0) (OpenState reg)  -- wrong direction!
```

I would receive a type error. Not a runtime error. Not a test failure. A compile-time rejection. The topology constraint is discharged by the type checker, not by me.

This is the essential value proposition of crem: it promotes what would otherwise be a runtime invariant into a compile-time proof obligation. My transition function is not merely a function, it is a proof-carrying function. Every call to `pureResult` is simultaneously a claim and a demonstration that the claim holds.

### The singletons tax

Now I arrive at the machinery that ought to make me uncomfortable, in a productive way.

Look at what I am actually importing:

```haskell
import Data.Singletons.Base.TH
$(singletons [d|
  data RegVertex = RegClosed | RegOpen deriving (Eq, Show)
  |])
```

This Template Haskell splice generates an entire parallel universe of types. Alongside my data type `RegVertex` with constructors `RegClosed` and `RegOpen`, I now have a singleton type `SRegVertex` with constructors `SRegClosed :: SRegVertex 'RegClosed` and `SRegOpen :: SRegVertex 'RegOpen`. And alongside those, I have promoted type-level equivalents `'RegClosed :: RegVertex` and `'RegOpen :: RegVertex`.

Three representations of the same concept. This is not a design flaw in crem. It is a precise and honest reflection of the limitations of GHC's type system.

The reason singletons exist is this: in GHC Haskell, types and values inhabit separate universes. A type `'RegClosed` cannot be examined at runtime because it has been erased. A value `RegClosed` can be examined at runtime but cannot constrain types. The singleton type `SRegVertex v` is a bridge: it is a value I can pattern-match on at runtime, and simultaneously it carries a type index `v` that GHC can reason about at compile time. It is the only mechanism available for writing runtime code that is sensitive to type-level information.

This is why `SomeRegState` looks the way it does:

```haskell
data SomeRegState = forall v. SomeRegState (SRegVertex v) (RegState v)
```

The singleton `SRegVertex v` accompanies the state so that whoever receives a `SomeRegState` can recover the vertex information by pattern-matching on the singleton. Without it, the existential would be genuinely opaque and I could do nothing useful with the state.

My `vertexOf` helper in the test suite:

```haskell
vertexOf :: SomeRegState -> RegVertex
vertexOf (SomeRegState sv _) = case sv of
  SRegClosed -> RegClosed
  SRegOpen   -> RegOpen
```

is the canonical example of this pattern. I am converting a singleton, which lives in both universes, back into a plain value, which lives only in the value universe. The `{-# LANGUAGE GADTs #-}` pragma is required because each branch of that case refines `v`, and without `MonoLocalBinds` (which `GADTs` implies) GHC cannot guarantee that this refinement does not escape its lexical scope unsoundly.

The warning I was seeing, `-Wgadt-mono-local-binds`, is GHC telling me: you are doing type-level reasoning through value-level pattern matching, and the scoping rules for this are subtle enough that I am not confident you understand the risk. It is not a spurious warning. It is a symptom of the underlying mismatch between what I want to express and what the type system can directly accommodate.

### Why dependent types would dissolve all of this

In a genuinely dependently typed language, Agda or Idris, the types-versus-values distinction does not exist in the same way. A value of type `RegVertex` can appear in a type directly. I would write my topology as an ordinary function:

```agda
successors : RegVertex -> List RegVertex
successors RegClosed = [RegClosed, RegOpen]
successors RegOpen   = [RegOpen,   RegClosed]
```

This is a perfectly ordinary function. And my transition function would have a type like:

```agda
regAction : (v : RegVertex)
          -> RegState v
          -> RegCommand
          -> (v' : RegVertex ** v' `elem` successors v ** RegState v')
```

The return type deserves careful reading. It is a dependent pair, a sigma type, written `(v' : ... ** ...)`. The type of the second component depends on the VALUE of the first component. The type of the third component depends on values computed from the first two. I am computing the set of allowed successor vertices as a value, and then requiring a proof that my chosen successor is in that set.

There are no singletons here. There is no Template Haskell. There is no `SomeRegState` existential, because `(v' : RegVertex ** RegState v')` is already the correct way to write "a state at some vertex I will tell you about." The sigma type IS the existential, and it is first class.

The `fromRegister` function illustrates the pain point most clearly. In my codebase it must return `SomeRegState` because the vertex is determined at runtime by inspecting `registerIsOpen`. In Agda I would write:

```agda
fromRegister : Register -> (v : RegVertex ** RegState v)
fromRegister reg with registerIsOpen reg
... | True  = (RegOpen,   OpenState   reg)
... | False = (RegClosed, ClosedState reg)
```

The dependent pair carries both the vertex and the state together, and any code that receives this pair can inspect the vertex and have the type of the state refined accordingly. No singleton needed, because the vertex IS already a first-class value that can appear in types.

My incomplete uni-pattern warnings are a second symptom of the same disease. When I wrote:

```haskell
let (ItemAdded item, _) = runTxCommand someState (AddItemCmd testItem)
```

GHC correctly observes that `runTxCommand` returns `(TxEvent, SomeTxState)`, and `TxEvent` has eight constructors, so this pattern can fail. GHC has no way of knowing that `AddItemCmd` on a `CreatedState` can only produce `ItemAdded`. That knowledge is implicit in the implementation of `txAction`. It is not reflected in the type of `runTxCommand`.

With dependent types I could make it reflected. I would define a type family or a function `emittedEvent : TxVertex -> TxCommand -> Type` mapping state-command pairs to their precise event type, and the return type of `runTxCommand` would use it. The pattern match would then be exhaustive by construction, not by convention.

### What crem has genuinely given me

None of the above criticism should obscure what crem has actually delivered. Before crem, my state machine was a convention enforced by tests. Now it is a theorem enforced by the type checker. The topology is not documentation; it is a type-level specification against which every `regAction` and `txAction` clause is checked.

Concretely, crem has given me four things.

**Topology as a type.** `RegTopology` is not a comment in my source file or a diagram in a wiki. It is a type that participates in type inference and type checking. When I add a new command or a new vertex, the type checker will immediately identify every transition clause that becomes invalid.

**GADT-indexed states.** `RegState v` and `TxState v` give me the ability to write functions that accept only states at specific vertices. `regAction (ClosedState reg) cmd` is a function that the type system guarantees will only ever be called with a closed register. I do not check this at runtime. I do not rely on my own discipline. The type checker enforces it.

**`ActionResult` as a proof obligation.** Every clause of `regAction` must discharge the proof that its chosen successor vertex is in the topology. `pureResult (RegOpened opened) (OpenState opened)` is accepted precisely because `'RegOpen` is in the successor list of `'RegClosed`. Change the topology and this line stops compiling.

**`SomeRegState` as a typed existential.** The existential packs not just a state but a singleton witness, allowing me to recover vertex information when I need it. This is significantly stronger than an untagged sum, because the tag and the state are bound together by the type index and cannot fall out of sync.

The gap between what crem achieves and what full dependent types would make effortless is real and worth sitting with. Crem is doing something genuinely impressive with the tools GHC provides. The singletons library, DataKinds, and promoted type-level lists are being assembled into a coherent framework for type-safe state machines. But the scaffolding required is substantial, and its necessity is an honest measure of how far GHC's type system still is from full dependent types.

The fact that I am now finding that scaffolding uncomfortable is a sign of progress. I have internalized the value of type-level invariants, and now the gap between the invariants I can express and the invariants I want to express has become visible. That gap has a name: it is the motivation for dependent types, and it has occupied a significant fraction of the programming languages research community for thirty years.