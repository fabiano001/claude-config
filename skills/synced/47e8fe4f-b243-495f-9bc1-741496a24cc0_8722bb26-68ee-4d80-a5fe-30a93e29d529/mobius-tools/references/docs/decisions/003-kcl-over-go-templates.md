# ADR-003: KCL Over Go Templates for Crossplane Compositions

**Status**: Accepted

**Date**: 2025-02-01

## Context

Crossplane provides two primary approaches for authoring composition functions:

1. **Go templates** via the `function-patch-and-transform` pipeline — define patches and transforms in YAML with Go template expressions
2. **KCL** (Kusion Configuration Language) via the `function-kcl` pipeline — author compositions in a Turing-complete language with type safety and standard library

Early Crossplane XRD repos tested Go templates. The approach worked but revealed challenges:
- Go template syntax is unfamiliar to most platform engineers
- No type checking — errors appear at runtime when compositions are rendered
- Difficult to unit-test locally — requires full Crossplane controller to render
- Limited expressiveness for complex transformation logic
- No rich standard library for common operations (AWS SDK calls, policy checks, etc.)

## Decision

Standardize on **KCL** for all new Crossplane composition functions. Existing Go template compositions may remain, but all new XRDs must use the `function-kcl` pipeline.

KCL provides:
- Strong typing and compile-time error detection
- Local testability via `kcl run` without a running Crossplane controller
- Rich standard library for string manipulation, data structures, and cloud operations
- Readable, Python-like syntax familiar to platform engineers
- Clear separation between composition logic and rendered manifests

## Consequences

### Positive

- **Type safety**: KCL's type system catches configuration errors at authoring time, not at cluster runtime when a claim is provisioned.
- **Local testability**: Developers and agents can validate compositions locally using `kcl run` and `crossplane beta render`, reducing cloud infrastructure dependencies.
- **Readable source**: KCL syntax is closer to Python/Python-adjacent languages, making it more accessible than Go templates to engineers without Go experience.
- **Rich standard library**: KCL includes built-in functions for common operations (AWS SDK calls, policy validation, multi-resource orchestration).
- **Consistency across XRDs**: All composition functions use the same language and patterns, reducing cognitive load when switching between repos.

### Negative

- **Team learning curve**: Engineers and agents must learn KCL syntax, semantics, and idioms. This is a one-time investment but adds friction to initial adoption.
- **Smaller ecosystem**: KCL has a smaller community and fewer third-party examples compared to Go templates. Less publicly available troubleshooting advice.
- **Crossplane function-kcl stability**: The `function-kcl` pipeline is newer than patch-and-transform. Potential for undiscovered edge cases or performance issues at scale.

### Neutral

- Go template compositions remain valid in the system. Mixed KCL/Go compositions can coexist, though new work should use KCL.
