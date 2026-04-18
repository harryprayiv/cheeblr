# Mission

Cheeblr is a software stack for retail. It is licensed under the GNU Affero General Public License, version 3 or later. The retailer who deploys it owns the install, the data, and the right to modify the running system. AGPLv3 is the mechanism that keeps it that way.

## The pattern this exists to break

Look at any category of retail software in 2026 and the same shape appears.

A point-of-sale vendor charges per terminal, per transaction, per integration, per report. Their customer cannot leave without losing their inventory history, their customer records, and their accounting integrations, all of which were uploaded into a system the customer never owned. The vendor knows this. The contract is priced accordingly. The price goes up every renewal, the export tools get worse, the API rate limits tighten, and a feature that used to be included gets pulled into a higher tier.

A storefront platform takes a percentage of every sale. The platform's interests and the merchant's interests start aligned and then diverge as soon as the platform has a monopoly on the merchant's customer relationship. The platform inserts itself between the merchant and the buyer, sells search placement back to the merchant, sells the buyer's data to whoever else is buying, and steadily rewrites the terms in its own favour. The merchant cannot leave because leaving means losing the customers who only know how to find them through the platform.

An aggregator promises to connect customers to local businesses. It charges the businesses for being listed and the customers for the convenience of finding them. Both sides pay the same intermediary for what used to happen for free between them. The intermediary's job is to stay in the middle.

This is not a bug in any individual company. It is the equilibrium that proprietary, centrally-operated retail software arrives at, given enough runway. The vendor's incentives demand it. The customer's lock-in permits it. The shareholder's expectations require it. The shop and the shopper both pay for the work of standing between them.

The fix is not a better-behaved vendor in the same architecture. The fix is a different architecture.

## What Cheeblr is

Cheeblr is the software a retailer needs to run a shop without a vendor sitting in the middle of it. Inventory. Registers. Management. A real-time feed of available stock, published over an open protocol, that any aggregator can consume without anyone paying anyone for the right to be listed or the right to look.

The retailer deploys it on infrastructure they control. A small server in the back office. A Raspberry Pi behind the counter. A Nix-built OCI image on a cluster they rent. A NixOS box on their own bench. The build is hermetic from the compiler down, so what runs in production is what was audited.

The current proving ground is cannabis retail. That industry was chosen on purpose: it is heavily regulated, suspicious of incumbents, hostile to data leakage, and underserved by existing vendors. Software that survives a dispensary's compliance burden survives a coffee shop's. The lessons learned at the proving ground are not domain-specific. The architecture is not specialised. Inventory is inventory. A register is a register. A real-time feed of available stock works the same whether the stock is flower, espresso, vintage guitar pedals, or short-term rental availability. The categories will follow.

## The license is the lever

A LICENSE file alone cannot build a different equilibrium. But the wrong license guarantees the old one will repeat. Permissive licenses let any sufficiently-funded competitor take the code, close their fork, host it, and rent the result back to the people the project was meant to serve. Pseudo-open licenses (BSL, SSPL, fair-source) reserve the operator's right to extract while pretending otherwise. AGPLv3 is the only widely-deployed license that closes the loop.

Section 13 is the load-bearing clause. If anyone modifies Cheeblr and runs it as a network service, they must publish their modifications under the same license. There is no SaaS loophole. There is no clever corporate restructuring around it. There is no acquisition that can quietly amend it. The protection follows the code into every fork, into every hosted descendant, forever. A future maintainer cannot relicense the project to a permissive license without the consent of every contributor, and that is not an oversight. It is the load-bearing structural guarantee.

A competitor who forks Cheeblr and runs it as a service has two options: publish their changes under AGPLv3, in which case they are no longer a competitor but a contributor, or stop. There is no third option. That is the design.

## Engineering commitments

The license's promises are only real if the engineering can honour them. A guarantee that the build process can quietly violate is not a guarantee.

**Reproducible from source.** The development environment is a Nix flake. Production artifacts are Nix-built OCI images and NixOS configurations. Every dependency is open source and is checked transitively. A deployer who suspects a binary does not match the source can verify, byte for byte, that it does. Anyone who cannot verify their software cannot meaningfully be said to control it.

**Make invalid states unrepresentable.** Haskell on the backend, PureScript on the frontend. Both languages were chosen because their type systems can encode invariants the runtime then cannot violate. A sale the type checker rejects before it executes is preferable to a sale that completes and gets reconciled at 2am. The state machines that govern transactions, registers, and stock pulls are checked at compile time against their own topology. Illegal transitions are not tested for; they are made unspellable.

**Secure by default.** TLS is on. Sessions are HttpOnly cookies with token rotation. Passwords are hashed with Argon2id. Secrets live in sops-encrypted files, never in the repository. CSP, CORS, and security headers are tight. The defaults are the secure configuration, because the defaults are what gets deployed.

**No telemetry.** Cheeblr does not phone home. There is no analytics endpoint. There is no opt-out, because there is no opt-in. The shop's data is on the shop's hardware. What the shop does with it is the shop's business, not the maintainer's, and not anyone the maintainer might one day be subpoenaed by.

**Languages and dependencies vetted to the bottom of the stack.** Every dependency is open source. The compilers are open source. The runtimes are open source. A proprietary blob anywhere in the chain would compromise the AGPLv3 guarantee for downstream operators, and there are none.

**No language-model-generated code in the repository.** Contributions produced by code-generating LLMs are not accepted. The reasoning is provenance: AGPLv3 obliges the project to know who wrote what, under what license, with what authority to relicense. LLM output cannot answer those questions. The rule applies to contributions. It does not pretend the maintainer never uses such tools to think out loud.

**No bots in the workflow.** Pull requests, reviews, and merges are handled by humans.

**Manual CI on infrastructure the maintainer controls.** After the supply-chain compromises uncovered in hosted GitHub Actions workflows, executing arbitrary contributor input on every push is an attack surface this project will not accept. Builds run on machines the maintainer owns, triggered by a human.

**Mechanical formatting.** Haskell with `fourmolu`. PureScript with `purs-tidy`. Nix with `nixpkgs-fmt`. Discussions about formatting are not in scope.

## What the architecture rules out

A government or law enforcement agency that demands customer data from "Cheeblr" finds nothing, because Cheeblr is not a company holding data. The data lives on the deployer's hardware. Subpoenas go to the shop, the same as they would have had to before software existed. There is no centre to compel.

A future maintainer who decides to add telemetry, ship a model-generated feature, or pull in a proprietary dependency is forking, not maintaining. They are welcome to. The license guarantees the rest of us can stay on the version that did not.

A platform that wants to insert itself between Cheeblr's deployers and their customers cannot do so via the inventory feed: the feed is published over an open protocol that any consumer can read, and no consumer can charge for the right to be listed. A would-be aggregator can build a better consumer experience and earn its place. It cannot tax the connection.

A cooperative of shops that wants to federate inventory across multiple Cheeblr instances can do so without anyone's permission, because the protocol is open and the implementation is auditable. The infrastructure for that already exists. What it needs is shops.

## What this is for

There is a real shop, somewhere, paying a real monthly fee to a real proprietary vendor that is making the product worse on a quarterly cadence because the contract makes leaving more expensive than staying. The shop is not free in any meaningful sense. The customer who shops there is not free either. The vendor is the only party extracting freedom from the arrangement, and they are extracting it by the bushel.

That arrangement is not natural. It is not the price of doing business. It is a specific outcome produced by specific choices in licensing, architecture, and protocol, and different choices produce different outcomes. Cheeblr is what the different outcome looks like, built carefully, in one industry first, with the architecture in place to expand to every other industry that has the same problem. Which is most of them.

The dispensary is the proving ground. Retail is the domain. The license is the lever. The type system, the reproducible build, the open protocol, and the absence of a central operator are the load-bearing engineering. Everything else is implementation.