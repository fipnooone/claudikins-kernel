# Citation Rules for Technical Claims

When writing or reviewing a plan, use this guide to decide whether a claim needs `[Source: URL]` or `[UNVERIFIED]`.

## What Counts as a "Specific" Claim

Specific claims make falsifiable assertions about a library, API, or tool. They require `[Source: URL]`.

| Claim type          | Example                                             |
| ------------------- | --------------------------------------------------- |
| Version number      | "Install version 1.21.11"                           |
| Method/function     | "Call `.connect()` to establish the connection"     |
| Install flag        | "Run `npm install --save-exact`"                    |
| URL / download link | "Download from https://example.com/release"         |
| Compatibility       | "Requires Node >= 20", "Incompatible with Python 2" |
| Behaviour           | "Returns `null` when the key is missing"            |
| Config key          | "Set `MAX_RETRIES=3` in the config"                 |

## What Counts as a "General" Claim

General claims name a technology without asserting specific behaviour. No citation needed.

| Claim type             | Example                              |
| ---------------------- | ------------------------------------ |
| Technology selection   | "Use Redis for caching"              |
| Integration decision   | "Integrate with Stripe for payments" |
| Architecture direction | "Use a queue-based approach"         |
| Pattern recommendation | "Apply the repository pattern here"  |

## How to Apply

1. **Can I cite it?** Find an official doc URL, add `[Source: URL]` inline.
2. **Can't verify right now?** Mark `[UNVERIFIED]` — do not omit it or silently guess.
3. **Is it general?** No action needed — proceed without a citation.

## [UNVERIFIED] Tag Rules

- `[UNVERIFIED]` is a blocking tag. Plans with unresolved `[UNVERIFIED]` tags cannot be finalised without explicit user sign-off.
- The user may approve an `[UNVERIFIED]` claim if they know it to be correct or accept the risk.
- Preferred resolution: run taxonomy-extremist in docs/external mode to find the source, then replace `[UNVERIFIED]` with `[Source: URL]`.
