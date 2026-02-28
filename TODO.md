## Core Architectural Gap in Comparison to Deku Real World

**4. No parallel loading**

The realworld app uses `parSequence_` and `parallel`/`sequential` to load multiple resources concurrently. Your route handlers do sequential fetches with manual error handling at each step.

## Refactoring Steps Left

### Phase 5: Adopt the `run` + parallel loading pattern

**Goal:** Clean async data loading.

Steal the realworld app's `run` helper directly:

```purescript
run :: forall a r. Aff a -> { push :: a -> Effect Unit | r } -> Aff Unit
run aff { push } = aff >>= liftEffect <<< push
```

Use `parSequence_` for routes that need multiple resources (CreateTransaction needs both inventory and a register).
