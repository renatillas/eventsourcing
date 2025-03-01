# Event Sourcing Gleam Project Guidelines

## Build & Test Commands
- Build the project: `gleam build`
- Run all tests: `gleam test`
- Format code: `gleam format`
- Check formatting: `gleam format --check`

## Code Style Guidelines
- **Imports**: Group imports alphabetically. Standard library first, then third-party, then local.
- **Naming**: Use `snake_case` for functions/variables and `PascalCase` for types/variants.
- **Types**: Document with `///` comments explaining purpose and fields.
- **Functions**: Use labeled arguments for functions with multiple parameters.
- **Error Handling**: Return `Result` types for operations that can fail.
- **Documentation**: Use triple slash `///` for public API documentation.

## Event Sourcing Pattern Guidelines
- Each domain event should be immutable and represent a fact that happened.
- Commands should validate input and return appropriate domain errors.
- Apply functions should be pure and only update state based on events.
- Use snapshots for optimizing aggregate rebuilding after many events.
- Separate command handling from event application concerns.