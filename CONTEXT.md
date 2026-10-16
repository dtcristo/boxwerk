# Boxwerk

Boxwerk organizes application code into packages with explicit boundaries.

## Language

**Global context**:
Shared application configuration, gems, and constants available to all packages.
_Avoid_: Global box, root box

**Root package**:
The top-level application package, with its own dependencies and boundaries.
_Avoid_: Global context
