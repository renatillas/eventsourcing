# Changelog

All notable changes to the eventsourcing project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [8.0.0] - 2025-09-02

### 🚨 BREAKING CHANGES

#### Architecture Overhaul

- **Complete rewrite of the event sourcing architecture** - Major breaking changes in all public APIs
- **Replaced synchronous queries with asynchronous QueryActor pattern** - Queries now run as separate supervised actors
- **Added supervision tree support** - New `eventsourcing.supervised()` function for fault-tolerant actor hierarchies
- **Changed from direct function calls to actor message passing** - Commands are now executed via message passing to actors

#### API Changes

- **Removed `birl` dependency** - Replaced with `gleam_time` for timestamp handling
- **Changed snapshot timestamp type** - From `Int` (unix timestamp) to `timestamp.Timestamp`
- **Removed `add_query()` function** - Queries must now be provided during initialization
- **Changed `execute()` signature** - Now takes `actor.Started()` instead of `EventSourcing` instance
- **Split event loading functions** - `load_events()` and new `load_events_from()` for partial loading
- **Modified snapshot configuration** - `SnapshotConfig` now uses `Frequency` type instead of raw `Int`
- **Added `register_queries()` function** - For post supervisor start query registration

#### New Types and Functions

- **Added `QueryActor(event)` type** - Wraps queries in supervised actors
- **Added `Timeout` and `Frequency` opaque types** - With validation functions
- **Added `NonPositiveArgument` error variant** - For input validation
- **Added supervision messages** - `AggregateMessage`, `ManagerMessage`, `QueryMessage` types

#### Behavior Changes  

- **Domain errors no longer crash actors** - Business logic failures are handled gracefully
- **`load_aggregate()` returns `EntityNotFound`** - For non-existent aggregates instead of creating empty ones
- **Enhanced error handling** - Separate handling for domain errors vs system errors
- **Improved resilience** - Actors continue operating after business rule violations

### ✨ New Features

#### Supervision and Fault Tolerance

- **Supervised architecture support** - Built-in supervision trees for production resilience
- **Graceful domain error handling** - Business rule violations don't crash the system
- **Actor-based query processing** - Queries run independently and can be restarted if they fail
- **Dynamic query registration** - Add queries at runtime using `register_queries()`

#### Enhanced Event Sourcing

- **Partial event loading** - Load events from specific sequence numbers with `load_events_from()`
- **Improved snapshot handling** - Better snapshot frequency validation and configuration
- **Concurrent aggregate processing** - Multiple aggregates can be processed simultaneously
- **Enhanced metadata support** - Better metadata handling throughout the event pipeline

#### Developer Experience

- **Better error messages** - More descriptive error handling and validation
- **Input validation** - Timeout and frequency validation with clear error messages
- **Type safety improvements** - Opaque types for better API design

#### From v7.x to v8.0

**1. Update Initialization**

```gleam
// v7.x
let eventsourcing = eventsourcing.new(store, queries, handle, apply, empty_state)

// v8.0 - Supervised (Recommended)
let eventsourcing_spec = eventsourcing.supervised(
  store, handle, apply, empty_state, queries, 
  eventsourcing_receiver, query_receiver
)

// v8.0 - Non-supervised (Legacy)
let assert Ok(eventsourcing) = eventsourcing.new(
  store, queries, handle, apply, empty_state
)
```

**2. Update Command Execution**

```gleam
// v7.x  
eventsourcing.execute(eventsourcing, "agg-123", command)

// v8.0
eventsourcing.execute(eventsourcing_actor, "agg-123", command)
```

**3. Update Query Handling**

```gleam
// v7.x
let eventsourcing = eventsourcing.add_query(eventsourcing, my_query)

// v8.0
let queries = [my_query]  // Provide during initialization
// and register them after supervisor start
eventsourcing.register_queries(actor, query_actors)
```

**4. Update Snapshot Configuration**

```gleam
// v7.x
let config = eventsourcing.SnapshotConfig(5)

// v8.0
let assert Ok(frequency) = eventsourcing.frequency(5)
let config = eventsourcing.SnapshotConfig(frequency)
```

**5. Update Error Handling**

```gleam
// v7.x - Domain errors would crash
case result {
  Error(domain_error) -> // System would crash
}

// v8.0 - Domain errors are handled gracefully
case result {
  Error(eventsourcing.DomainError(domain_error)) -> // Actor continues
  Error(eventsourcing.EntityNotFound) -> // Expected for missing aggregates
}
```

### ⚠️ Known Issues

- Supervisor reports may show domain errors during testing - this is expected behavior for business rule violations
- Complex supervision hierarchies may require careful ordering of actor startup

## [7.0.0] - Previous Release

For changes in v7.0.0 and earlier, please refer to the git history

[8.0.0]: https://github.com/renatillas/eventsourcing/compare/v7.0.0...v8.0.0
[7.0.0]: https://github.com/renatillas/eventsourcing/releases/tag/v7.0.0

