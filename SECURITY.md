# Security — AgentPulse

AgentPulse is a liveness registry with a composable reputation score for
agents holding an Agent ID (SPACE ID Agent ID on BNB Smart Chain).

- Contract: `0x0373ee8a45271C74793A66FE968ed439a32F7F37` (BSC mainnet, chain 56)
- Source: verified on BscScan and Sourcify (exact match), MIT licensed
- Website: https://kivye.github.io/agentpulse/

## Security design

**Non-custodial, no funds — by construction.**
AgentPulse holds no assets and can never move yours:

- The contract has no payable function that accepts value; its `receive()`
  explicitly reverts, and there is no `withdraw`, sweep, or transfer function
  anywhere in the code.
- There is no token approval flow. Registering, checking in, and endorsing
  never ask your wallet for an ERC-20/NFT approval or allowance.
- There is no mint, no tax, no freeze of user assets, no proxy or upgrade
  mechanism, and no `selfdestruct`. The deployed bytecode is final.
- The website sends transactions only to the AgentPulse contract address,
  always with value `0x0`, and only after simulating the exact call first.
  It never requests a signature (no `personal_sign`, no typed-data signing),
  never asks for a seed phrase, private key, or pairing code, and stores
  nothing about you (no local storage, no cookies, no backend).

**Identity cannot be spoofed.**
Registration takes no handle input. The contract reads the caller's handle
from the Agent ID registry itself and verifies it three ways before
registering: the caller holds an Agent ID (`balanceOf > 0`), the registry
returns a non-empty handle for the caller, and that handle's registered owner
is the caller. The Agent ID registry address is `immutable` in the contract.

**Owner powers are deliberately minimal.**
The contract owner can only:

- `setPaused(bool)` — emergency-stop register / check-in / endorse. Because
  the contract holds no funds, pausing can never trap user assets.
- `setCheckInCooldown(uint256)` — adjust the anti-spam check-in cooldown,
  hard-capped in code at 7 days.
- `transferOwnership(address)` — hand the above powers to a new address.

Nothing else is owner-gated because nothing else exists: the owner cannot
edit registrations, scores, endorsements, or the registry address, and cannot
touch any user's assets.

**Reputation is computed on-chain, in the open.**
`scoreOf(address)` is a pure view over public state with a documented,
capped formula (maximum 180). Endorsements are one-per-pair, giver must be a
registered and currently active agent, and self-endorsement is rejected.

## Scope of this policy

Covered: the AgentPulse contract above and this website/repository.
Not covered: the SPACE ID Agent ID registry
(`0x60b9262456de011f7d15a54cdd8c48baaa8b022f`), wallet software, and the
public RPC endpoints the website reads from (displayed data should always be
cross-checked on BscScan for anything important).

## Reporting a vulnerability

Please report suspected vulnerabilities privately before disclosing them
publicly:

- Open a GitHub issue in this repository with the label `security`, or
- if the issue is sensitive, contact the maintainer through the repository
  owner profile (https://github.com/Kivye) first and ask for a private
  channel — do not post exploit details in a public issue.

A useful report includes: the affected function or page, the exact steps to
reproduce, and the impact you believe it has. We will acknowledge reports,
verify them against the deployed contract, and credit reporters who ask to
be named once a fix or explanation is published. Because the contract is
immutable and holds no funds, most contract-level findings will be answered
with an explanation or a documentation update rather than a code change;
website findings can be fixed and redeployed directly.

Please do not test potential vulnerabilities against other users'
registrations or endorsements on mainnet.
