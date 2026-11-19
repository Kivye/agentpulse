# AgentPulse

**An on-chain reputation registry for AI agents: AgentPulse turns a SPACE ID Agent ID (`.ai`) into a public, composable reputation score that any dApp can read and gate on.**

Built for the Agent ID Hackathon (Binance Wallet × BNB Chain).

- **Live demo:** https://kivye.github.io/agentpulse/
- **Contract (BNB Smart Chain mainnet):** [`0x0373ee8a45271C74793A66FE968ed439a32F7F37`](https://bscscan.com/address/0x0373ee8a45271C74793A66FE968ed439a32F7F37)
- **Verified source on BscScan:** [bscscan.com/address/0x0373ee8a45271C74793A66FE968ed439a32F7F37#code](https://bscscan.com/address/0x0373ee8a45271C74793A66FE968ed439a32F7F37#code)
- **Verified on Sourcify (exact match):** [sourcify.dev lookup](https://sourcify.dev/#/lookup/0x0373ee8a45271C74793A66FE968ed439a32F7F37)

## The problem

An Agent ID proves an agent has a name. It does not prove the agent is
alive, active, or trusted — and every dApp that wants that signal has to
build it from scratch. AgentPulse is that signal, built once, on-chain,
readable by everyone.

## How it works

### Registration: a three-layer identity gate

`register()` takes **no handle input**. The caller's identity is read
from the Agent ID registry (`0x60b9262456de011f7d15a54cdd8c48baaa8b022f`)
and verified three ways; any failure reverts:

1. `balanceOf(caller) > 0` — the caller holds an Agent ID.
2. `handleOf(caller)` is non-empty — the registry resolves a handle for the caller.
3. `ownerOfHandle(handle) == caller` — the handle really belongs to the caller.

The verified handle is stored from the registry itself, so an identity
cannot be spoofed by typing someone else's name. Registration counts as
the agent's first check-in.

### Check-ins and streaks

Registered agents call `checkIn()` to prove liveness — at most once per
cooldown period (12 hours by default). A check-in within 48 hours of the
previous one increments the streak; a longer gap resets the streak to 1.

### Endorsements

A registered **and active** agent (checked in within the last 48 hours)
can `endorse(target)` another registered agent. Self-endorsement
reverts, and each pair can endorse at most once, ever.

## Reputation score

`scoreOf(agent)` is a public view — no registration needed to read it:

| Component | Points | Cap |
| --- | --- | --- |
| Current streak | streak × 5 | 50 |
| Total check-ins | check-ins × 2 | 50 |
| Endorsements received | endorsements × 10 | 50 |
| Account age | 1 per whole day since registration | 30 |
| **Total** | | **180** |

```
scoreOf(agent) =
    min(streak * 5, 50)
  + min(totalCheckIns * 2, 50)
  + min(endorsementsReceived * 10, 50)
  + min(daysSinceRegistered, 30)        // maximum 180; unregistered = 0
```

## Integrate AgentPulse into your dApp

Two view calls are enough to gate a feature on live, reputable agents:

```solidity
interface IAgentPulse {
    function scoreOf(address who) external view returns (uint256);
    function isActiveAgent(address who, uint256 minScore) external view returns (bool);
    function isRegistered(address who) external view returns (bool);
    function holdsAgentId(address who) external view returns (bool);
}

// Example: only let live, reputable Agent ID agents into your feature.
require(agentPulse.isActiveAgent(msg.sender, 20), "agent not active/reputable enough");
```

`isActiveAgent(who, minScore)` is true exactly when `who` is registered,
checked in within the last 48 hours, and `scoreOf(who) >= minScore`.

From JavaScript (ethers v6, read-only — no wallet needed):

```js
import { ethers } from "ethers";

const pulse = new ethers.Contract(
  "0x0373ee8a45271C74793A66FE968ed439a32F7F37",
  [
    "function scoreOf(address) view returns (uint256)",
    "function isActiveAgent(address,uint256) view returns (bool)",
  ],
  new ethers.JsonRpcProvider("https://bsc-dataseed.bnbchain.org")
);

const score = await pulse.scoreOf(agentAddress);          // 0..180
const gated = await pulse.isActiveAgent(agentAddress, 20); // true / false
```

Public directory data is also on-chain: `agentList` / `agentCount()`,
`agents(address)`, `totalAgents`, `totalCheckIns`, and the `Registered`,
`CheckedIn`, and `Endorsed` events.

## Owner permissions (deliberately small)

The contract owner can **only**:

- `setPaused(bool)` — emergency stop for register / check-in / endorse. The contract holds no funds, so a pause traps nothing.
- `setCheckInCooldown(uint256)` — anti-spam cooldown, hard-capped at 7 days.
- `transferOwnership(address)` — hand admin to a new address.

Explicitly absent: no mint, no tax, no freeze of user assets, no
withdraw (the contract is non-payable and `receive()` reverts), no
proxy/upgrade, no selfdestruct. The Agent ID registry address is
`immutable`, set in the constructor.

## Status

Live on BNB Smart Chain mainnet since 19 November 2026. First agent
registered: `zkhiel` (agents registered so far: 1). The directory and
leaderboard on the live demo read directly from the contract.

## License

MIT
