# Mission

Cheeblr is a software stack for retail, licensed under the GNU Affero General Public License, version 3 or later. The current implementation targets cannabis dispensaries as the first vertical and is engineered to generalise to the rest of retail once the domain layer proves itself. Deployers own the install, the data, and the right to modify what they run. AGPLv3 keeps that ownership from eroding.

## The pattern this exists to break

Every category of retail software in 2026 produces the same silhouette.

A point-of-sale vendor charges per terminal, per transaction, per integration, per report. Their customer cannot leave without abandoning inventory history, customer records, and accounting integrations loaded into a system the customer never owned. The vendor knows it and prices the contract accordingly. Renewals creep upward, export tools decay, API rate limits tighten, and features that used to be included migrate quietly into higher tiers.

A storefront platform takes a percentage of every sale. Its interests and the merchant's align at first and diverge the moment the platform owns the merchant's customer relationship. The platform inserts itself between merchant and buyer, sells search placement back to the merchant, sells the buyer's data to whoever else is paying, and rewrites the terms in its own favour on a schedule. The merchant cannot leave because leaving means losing the customers who only know how to find them through the platform.

An aggregator promises to connect customers to local businesses. It charges the businesses to be listed and charges the customers to find them. Both sides pay the same intermediary for something that used to happen directly between them. Standing in the middle is the entire product.

Every vendor in the category arrives here eventually, because the incentives make it the destination. Vendor interests demand it, customer lock-in permits it, and shareholder expectations require it. The shop and the shopper both pay the toll on a road that didn't need to exist.

A better-behaved vendor inside the same architecture will, given enough runway, become the vendor they replaced. What changes the outcome is changing the architecture.

## What Cheeblr is

Cheeblr is the software a retailer needs to run a shop with nobody sitting in the middle of it. Inventory. Registers. Management. A real-time feed of available stock, published over an open protocol, which any aggregator can consume without anyone paying anyone for the right to be listed or the right to look.

The retailer runs it on infrastructure they control: a server in the back office, a Raspberry Pi behind the counter, a Nix-built OCI image on a cluster they rent, a NixOS box on their own bench. The build is hermetic from the compiler down, so what runs in production is what was audited.

The intended shape of the finished system is a retail stack polymorphic in its domain. The domain definition lives in one place: products, transactions, and the state machine governing them. Everything below that layer is derived rather than separately maintained. Schema, forms, register workflows, stock feed, and admin surfaces are all functions of the domain definition. The type system that rejects an impossible sale in the current build will reject an impossible sale in every build, because the impossibility is stated at the domain layer and the code underneath is generated from the statement. A coffee roaster, a record shop, a hardware store, a vintage pedal dealer, and a dispensary each write their own domain and share the same engine underneath.

That generalisation is deferred on purpose. An abstraction extracted from a single working example is almost always the wrong abstraction. The ones that survive come from two or three concrete systems after they have diverged enough to expose their shared bones. Until the second and third systems exist, the domain layer stays hand-written for dispensaries. Lifting it out sooner would produce a polymorphic framework shaped around guesses about what retail has in common, which is the usual way these projects fail.

Cannabis retail was chosen for the first build for reasons external to cannabis itself. The industry operates under heavy regulation, reflexive suspicion of incumbents, acute sensitivity to data leakage, and a shortage of vendors worth paying. Software that survives a dispensary's compliance burden will survive a coffee shop's. The harder the environment, the more the architecture gets stress-tested before anyone tries to abstract over it. Cannabis is only the first vertical; the architectural work underneath is being done so additional verticals can be added without rebuilding the system around them.

## The license is the lever

A LICENSE file cannot single-handedly build a different equilibrium. The wrong license, however, guarantees the old one repeats. Permissive licenses let any well-funded competitor fork the code, close the fork, host it, and rent the result back to the people the project was meant to serve. Pseudo-open licenses (BSL, SSPL, fair-source) reserve the operator's right to extract while flying the open-source flag. AGPLv3 is the only widely-deployed license that closes the loop.

Section 13 is the clause doing the work. Anyone who modifies Cheeblr and runs it as a network service must publish their modifications under the same license. The SaaS loophole, the corporate-restructuring dodge, and the quiet post-acquisition relicense are all foreclosed by the same clause. The protection travels with the code into every fork and every hosted descendant, permanently. A future maintainer cannot relicense to a permissive license without the consent of every contributor, which is the structural guarantee the whole project rests on.

A competitor who forks Cheeblr and runs it as a service has two paths available: publish their changes under AGPLv3 (at which point they are a contributor rather than a competitor), or stop. Nothing else is on the menu. That absence is deliberate.

## Resisting embrace, extend, extinguish

The license defends against capture through the SaaS layer. On its own, it does nothing to defend against capture through the contribution firehose.

The pattern is well-documented. A competitor with budget and headcount floods a project with pull requests, refactors, proposals, and architectural "improvements" faster than the maintainers can meaningfully review them. The maintainers either rubber-stamp the changes and cede control of the codebase, or fall behind and cede momentum. Either way, direction slips out of the maintainer's hands. Free-software projects have been hollowed out this way often enough that treating it as hypothetical would be naïve.

Cheeblr's defences against this are structural and deliberately friction-heavy. They will slow down well-intentioned contributors. That cost is accepted.

**Scale thresholds.** Pull requests are sized by the review burden they impose, not by the lines they touch. A small PR (a bug fix, a targeted refactor, a documentation correction) follows the normal review path. A medium PR (a new module, a non-trivial refactor, a schema change) requires an issue opened first, a design sketch agreed to before code is written, and test coverage proportional to the change. A large PR (architectural rework, a new subsystem, a cross-cutting refactor spanning many modules) will be closed on sight and the contributor asked to open an RFC issue. "I already wrote it" does not earn a waiver. Code written without an agreed-upon plan is not a contribution; it is a demand for unpaid review labour.

**Burstiness triggers investigation.** A contributor who opens many pull requests in a short window, or whose contribution volume jumps by an order of magnitude without explanation, will have their in-flight work paused until the maintainer has had time to understand what is happening. This is a rate limit, not an accusation.

**Direction is decided in issues, not in pull requests.** Architectural choices are made through discussion, with the maintainer's consent documented before implementation begins. A pull request that attempts to decide architecture by fait accompli will be closed regardless of code quality. The project's shape is not auctioned off to whoever writes fastest.

**Provenance matters.** Contributors sign off their commits and attest that they have the right to contribute the code under AGPLv3. Submissions from accounts with no prior history, aimed at sensitive components (authentication, cryptography, payment, the domain-event pipeline), will receive extra scrutiny and may be asked to start with smaller changes to establish a track record.

**The maintainer's time is the bottleneck by design.** A project that can accept arbitrary quantities of contribution is a project that can be captured by whoever has the most contribution to offer. Cheeblr will not be that project. Review capacity is deliberately finite, the bar is deliberately high, and the queue moves at whatever pace the maintainer can sustain without dropping quality. Contributors who find this frustrating are welcome to fork.

## Engineering commitments

The license's promises hold only when the engineering backs them. A guarantee the build process can quietly violate is no guarantee.

**Reproducible from source.** The development environment is a Nix flake. Production artifacts are Nix-built OCI images and NixOS configurations. Every dependency is open source and checked transitively. A deployer who suspects a binary does not match the source can verify it, byte for byte. Software that cannot be verified cannot meaningfully be said to be controlled.

**Make invalid states unrepresentable.** Haskell on the backend, PureScript on the frontend. Their type systems encode invariants the runtime then cannot violate. A sale rejected by the type checker before it executes beats a sale that completes and has to be reconciled at 2am. The state machines governing transactions, registers, and stock pulls are checked against their own topology at compile time. Illegal transitions are unspellable rather than merely tested-against. The same machinery is what will eventually allow the domain to be parameterised without giving up any of the guarantees it provides today.

**Secure by default.** TLS is on. Sessions are HttpOnly cookies with token rotation. Passwords are hashed with Argon2id. Secrets live in sops-encrypted files and never in the repository. CSP, CORS, and security headers are tight. The defaults are the secure configuration, because the defaults are what gets deployed.

**No telemetry.** Cheeblr does not phone home. There is no analytics endpoint, no opt-out, no opt-in. The shop's data is on the shop's hardware. What the shop does with it is the shop's business, and specifically none of the business of whoever might one day subpoena the maintainer.

**Dependencies vetted to the bottom of the stack.** Dependencies are open source. Compilers are open source. Runtimes are open source. A proprietary blob anywhere in the chain would compromise the AGPLv3 guarantee for downstream operators, and there are none.

**LLM-generated code is held to a higher standard than human-written code.** The maintainer uses language models during development and will not pretend otherwise. Code whose first draft came from a model is accepted only when it has been read, understood, tested, and benchmarked more thoroughly than equivalent human-written code would require. The provenance is disclosed in the commit message. Tests are proportional to the uncertainty. A plausible-looking function with no tests behind it is a liability waiting for a production incident, and it will be treated as one. Contributors who follow this standard are welcome. Contributors submitting unverified model output are not.

**No bots in the workflow.** Pull requests, reviews, and merges are handled by humans.

**Manual CI on infrastructure the maintainer controls.** After the supply-chain compromises uncovered in hosted GitHub Actions workflows, executing arbitrary contributor input on every push is an attack surface this project will not accept. Builds run on machines the maintainer owns, triggered by a human.

**Mechanical formatting.** Haskell with `fourmolu`, PureScript with `purs-tidy`, Nix with `nixpkgs-fmt`. Discussions about formatting are out of scope.

## What the architecture rules out

A government or law enforcement agency demanding customer data from "Cheeblr" finds nothing, because Cheeblr is not a company holding data. The data lives on the deployer's hardware. Subpoenas go to the shop, as they would have had to before software existed. There is no centre to compel.

A future maintainer who decides to add telemetry, ship unverified model-generated features, or pull in a proprietary dependency is forking rather than maintaining. They are welcome to. The license guarantees the community can stay on the version that did not.

A platform hoping to insert itself between Cheeblr's deployers and their customers cannot do so through the inventory feed. The feed is published over an open protocol any consumer can read, and no consumer can charge for the right to be listed. A would-be aggregator can build a better consumer experience and earn its place; taxing the connection is not available to it.

A cooperative of shops that wants to federate inventory across multiple Cheeblr instances can do so without asking anyone's permission. The protocol is open, the implementation is auditable, and the infrastructure already exists. What it needs is shops.

## What this is for

Somewhere a real shop pays a real monthly fee to a real proprietary vendor that is making its product worse on a quarterly cadence because the contract makes leaving more expensive than staying. The shop is not free in any meaningful sense. The customer who shops there is no freer. The vendor is the only party extracting freedom from the arrangement, and they are extracting it by the bushel.

That arrangement was not natural, and it is not the price of doing business. It was produced by specific choices in licensing, architecture, and protocol, and different choices would have produced a different outcome. Cheeblr is what the different outcome looks like, built carefully in one vertical first and engineered so the rest of retail can follow once the domain layer is ready to be parameterised.

The immediate work is domain code specific to dispensaries. After that comes lifting the domain into a parameter and rebuilding the next vertical against the parameterised version. After that comes adding verticals until the middleman tax stops being a retail default.