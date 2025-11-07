# OTC Smart Contract (Proof of Capital Infrastructure)

Infrastructure EVM smart contract for OTC deliveries in the Proof of Capital technology stack. The contract acts as a secure middleware between an investor and a DAO administrator when purchasing DAO shares with a utility token. It supports funding with collateral or directly with the launch token, tranche-based delivery, and protected outcomes: delivery to a final destination, refund/buyback at a pre-agreed price, or investor withdrawal on timeout.

Use cases:
- Presales/OTC rounds where participants pool collateral and receive launch tokens in return.
- Safe delivery to a final destination (DAO/treasury/custodian), explicitly confirmed by the investor.
- Partial, tranche-based delivery with pre-defined prices/schedules to handle price changes over time.

Note: This is a specification/README. Function/event names below are examples—synchronize them with your implementation.

## Glossary

- Collateral: ERC-20 token used by the investor to pay (e.g., a stablecoin).
- Launch: the token being launched/distributed and delivered to the investor/final place.
- Delivery: the process of loading launch tokens into the contract and/or routing them to a final destination upon investor confirmation.
- Tranches: predefined delivery slices with individual prices/volumes/time windows.
- Destination: the final address to which tokens are sent in the planned path (e.g., a DAO treasury).
- Buyback: administrator’s right to buy back assets at a pre-declared price if the investor rejects the proposed destination.

## Roles and Permissions

- Investor:
  - Funds the contract with collateral.
  - Confirms or rejects the proposed destination address.
  - Can withdraw after lock/timeout if delivery isn’t completed.

- Administrator (OTC operator):
  - Configures the contract at deploy (token addresses, tranche schedule, prices, deadlines, buyback parameters).
  - Deposits launch tokens for delivery.
  - Proposes the final destination.
  - Executes buyback within the configured window.

- (Optional) DAO/Custodian:
  - Receives tokens after investor confirmation.

Recommendation: use Ownable/AccessControl; consider separating OWNER and OPERATOR roles.

## Flows

1) Funding
- Option A — Collateral funding:
  - Investor deposits collateral.
  - Admin deposits launch according to tranche schedule.
  - The contract tracks how much launch corresponds to deposited collateral based on tranche prices.

- Option B — Launch funding:
  - Admin deposits launch upfront (partially or fully).
  - Delivery is “preloaded”; routing to the final destination awaits investor confirmation.

2) Tranche-based delivery
- The schedule consists of N tranches: each with volume, price (collateral per launch), and optional time windows.
- Delivery can be partial; if price changes across tranches, the investor always receives amounts per the predefined rules.
- If delivery is interrupted, the contract can hold a “mix” (remaining collateral and/or delivered launch) until the final outcome.

3) Outcomes
- Planned outcome (confirm): admin proposes a destination; investor confirms; assets are transferred to the destination.
- Investor rejection:
  - If the investor rejects, the admin may perform buyback at the pre-declared price.
  - If the admin does not buy back before lock expiry, the investor can withdraw their assets (collateral/launch/mix).
- Delivery timeout:
  - If launch is not delivered for collateral within the specified period (e.g., 10 days), the investor can get a refund.

Note: Using Proof of Capital-compatible launch tokens is preferred (they are collateral-backed), providing extra safety. Arbitrary tokens are supported but may entail more risk for the end user.

## Configuration (Initialization)

Minimum parameters at deploy:
- collateralToken: ERC-20 collateral address.
- launchToken: ERC-20 launch token address.
- tranches: array of tranches with fields:
  - amountLaunch or amountCollateral (pick one invariant),
  - price (collateral per 1 launch, fixed-point),
  - deadline or start/end (optional).
- buybackPrice: price used for admin buyback (if applicable).
- deliveryTimeout: maximum allowed time for delivery (e.g., 10 days).
- lockUntil: timestamp/block until which the OTC is locked (investor cannot force withdraw if plan is on track).
- admin, investor: participant addresses for this OTC instance.
- destinationApprovalWindow: time window for investor decision and/or admin buyback after rejection.

Normalize all prices for differing decimals across tokens.

## State Machine

- Init: deployed, parameters fixed.
- FundingCollateral: collateral deposited, waiting for launch deposits.
- FundingLaunch: launch deposited (partially/fully).
- DeliveryPending: enough launch is available, waiting for destination.
- DestinationProposed: admin proposed a destination.
- Completed: investor accepted, tokens sent to destination.
- Rejected: investor rejected; buyback window for admin is open.
- Expired: timeout/lock expired; investor can withdraw.
- Cancelled: finished without delivery (refund).

Emit events on every state transition.

## Public Interface (example)

Align the signatures with your implementation. Recommend Solidity ^0.8.20 and OpenZeppelin SafeERC20.

- depositCollateral(uint256 amount)
- depositLaunch(uint256 amount)
- proposeDestination(address destination)
- acceptDestination() — investor only
- rejectDestination(uint8 reason) — investor only
- deliverTranche(uint256 trancheId, uint256 amountLaunch) — admin marks tranche fulfilment
- adminBuyback(uint256 amount) — at buybackPrice
- investorWithdraw() — after lock/timeout or in Expired/Cancelled states
- refundOnTimeout() — if delivery missed the deadline
- setPause(bool status) — optional
- rescueDust(address token, uint256 amount) — only for non-tracked tokens

Example interface (adjust to code):

```solidity
interface IOTC {
    function depositCollateral(uint256 amount) external;
    function depositLaunch(uint256 amount) external;
    function proposeDestination(address dst) external;
    function acceptDestination() external;
    function rejectDestination(uint8 reason) external;
    function deliverTranche(uint256 trancheId, uint256 amountLaunch) external;
    function adminBuyback(uint256 amountCollateralOrLaunch) external;
    function investorWithdraw() external;
    function refundOnTimeout() external;
    // views
    function getTranches() external view returns (/* ... */);
    function pendingLaunchForInvestor() external view returns (uint256);
    function pendingCollateralForInvestor() external view returns (uint256);
    function state() external view returns (uint8);
}
```

## Events (example)

- CollateralDeposited(investor, amount)
- LaunchDeposited(admin, amount)
- TrancheDelivered(trancheId, amountLaunch, price)
- DestinationProposed(admin, destination)
- DestinationAccepted(investor, destination)
- DestinationRejected(investor, reason)
- BuybackExecuted(admin, investor, amount, price)
- Withdrawn(investor, collateralAmount, launchAmount)
- RefundedOnTimeout(investor, collateralAmount)
- StateChanged(prev, next)

## Errors and Invariants

- Unauthorized calls must revert (onlyAdmin/onlyInvestor).
- Disallow proposing a new destination while a previous proposal is pending (or add explicit cancel).
- Disallow depositLaunch after completion or after refunds, if that’s your policy.
- Handle decimals consistently: use a unified 18-decimal scale for pricing calculations.
- Support fee-on-transfer tokens: use SafeERC20 and check actual received amounts.
- Guard against reentrancy (ReentrancyGuard on external token-transfer flows).
- Handle partial delivery and rounding in favor of the investor.
- Time comparisons use block.timestamp; account for small drift.

## Pricing and Calculations

- Choose a single invariant per tranche: either fixed amountLaunch with a price, or fixed amountCollateral with a price. Compute the counterpart deterministically.
- On investor rejection:
  - buybackPrice is fixed at deploy (or provably agreed off-chain) and applied to the relevant asset side.
  - Specify explicitly whether the admin buys back delivered launch from the investor or buys back the investor’s collateral obligation (document in code and events).

## Timing and Deadlines

- deliveryTimeout: global limit from start (deploy or first deposit).
- lockUntil: period during which the investor cannot force withdraw if the flow progresses normally.
- destinationApprovalWindow: window for investor decision and/or admin buyback.

Document all timing values for auditors.

## Security

- Use:
  - OpenZeppelin SafeERC20, ReentrancyGuard, Ownable/AccessControl.
  - Checks-Effects-Interactions pattern.
- Restrict rescue functions so they cannot pull tracked assets (collateral/launch).
- Lock critical parameters after initialization (immutable/one-time set).
- Emit comprehensive logs for all key actions.
- Ensure sum of delivered amountLaunch never exceeds contract’s launch balance.
- Avoid on-chain price oracles: prices/terms are set in tranches.

## Deployment

1) Prepare parameters:
   - token addresses,
   - tranche array,
   - buybackPrice,
   - lockUntil, deliveryTimeout,
   - admin, investor.
2) Deploy the contract and call initialize (for proxy) or pass params to constructor.
3) Set up roles/permissions (Ownable/AccessControl).
4) Dry-run on a testnet with realistic tokens and amounts.

## Example Usage (ethers.js)

```ts
const otc = new ethers.Contract(otcAddress, otcAbi, signer);

// Investor deposits collateral:
await collateral.connect(investor).approve(otc.address, amount);
await otc.connect(investor).depositCollateral(amount);

// Admin deposits launch and fulfills tranches:
await launch.connect(admin).approve(otc.address, amountLaunch);
await otc.connect(admin).depositLaunch(amountLaunch);
await otc.connect(admin).deliverTranche(0, amountLaunchPart);

// Admin proposes destination:
await otc.connect(admin).proposeDestination(destination);

// Investor accepts:
await otc.connect(investor).acceptDestination();

// On rejection:
await otc.connect(investor).rejectDestination(1); // reason code
await otc.connect(admin).adminBuyback(buybackAmount);

// On timeout:
await otc.connect(investor).refundOnTimeout();
```

## Test Cases (minimum set)

- Happy path: collateral → launch by tranches → propose → accept → transfer to destination.
- Partial delivery: first tranches fulfilled, then confirmation or rejection.
- Reject + buyback: investor rejects, admin buys back within the window.
- Reject + no buyback: buyback window expires, investor withdraws.
- Timeout: delivery not completed by deliveryTimeout → investor refunded.
- Edge: fee-on-transfer tokens, mixed decimals, rounding checks, min/max amounts, simulated reentrancy via token hooks.

## Example Tranche Definition (JSON)

```json
[
  { "trancheId": 0, "amountLaunch": "100000e18", "price": "0.80e18", "deadline": 1710000000 },
  { "trancheId": 1, "amountLaunch": "150000e18", "price": "0.95e18", "deadline": 1710600000 },
  { "trancheId": 2, "amountLaunch": "250000e18", "price": "1.10e18", "deadline": 1711200000 }
]
```

Explanation: price is “collateral per 1 launch” (normalized to 18 decimals). If price rises across tranches, the investor acquires some tokens cheaper and some more expensive; if delivery stops mid-way, the weighted average aligns with fulfilled tranches.

## Notes on Proof of Capital

- Prefer launch tokens that are Proof of Capital-backed: the investor always holds either collateral or a collateral-backed launch token.
- For arbitrary tokens, explicitly disclose risks and consider additional limits/insurance.

## Limitations and Disclaimer

- This README describes target logic. Exact semantics depend on your implementation.
- Before production, conduct an independent audit, stress testing, and formal verification of critical invariants.

## Suggested Repository Structure

- contracts/OTC.sol
- contracts/libs/…
- scripts/deploy.ts
- test/otc.spec.ts
- README.md (this file)
- SECURITY.md (vulnerability disclosure process)
- AUDIT.md (audit report/notes)
- configs/tranches.mainnet.json

---

If you share your exact function/event signatures and any implementation specifics (e.g., who holds delivered launch before acceptance, how buyback is settled precisely), I will update this README to match your code, add tailored call examples, and refine invariants.