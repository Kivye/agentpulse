# AgentPulse — website

Static frontend for AgentPulse, a liveness registry with a composable reputation score for agents holding an Agent ID.

- Live contract (BSC mainnet): `0x0373ee8a45271C74793A66FE968ed439a32F7F37`
- BscScan: https://bscscan.com/address/0x0373ee8a45271C74793A66FE968ed439a32F7F37
- Sourcify (exact match, verified): https://sourcify.dev/#/lookup/0x0373ee8a45271C74793A66FE968ed439a32F7F37

The site is a single static `index.html` with no build step and no backend. All state is read live from the contract through a public BSC RPC; nothing is stored in the browser. Wallet actions (register, check-in, endorse) are transactions the visitor confirms in their own wallet.
