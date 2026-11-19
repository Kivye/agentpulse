// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IAgentIdRegistry {
    function balanceOf(address owner) external view returns (uint256);
    function handleOf(address owner) external view returns (string memory);
    function ownerOfHandle(string memory handle) external view returns (address);
}

/// @title AgentPulse — Agent ID liveness registry with composable reputation
/// @notice Registration, check-in and endorsement are gated by a real Agent ID
///         (SPACE ID Agent ID, BSC: 0x60b9262456de011f7d15a54cdd8c48baaa8b022f).
///         The handle stored for each agent is read from the Agent ID registry
///         itself (handleOf), never supplied by the user, and cross-checked
///         with ownerOfHandle — so a handle cannot be spoofed.
///
/// @notice Reputation score (scoreOf) — the exact formula, also in README:
///         scoreOf(agent) =
///             min(streak * 5, 50)              // streak contribution, capped at 50
///           + min(totalCheckIns * 2, 50)       // per-agent check-in count, capped at 50
///           + min(endorsementsReceived * 10, 50) // endorsements received, capped at 50
///           + min(daysSinceRegistered, 30)     // whole days since registeredAt, capped at 30
///         Theoretical maximum = 50 + 50 + 50 + 30 = 180. Unregistered = 0.
///
/// Owner permissions (documented for BscScan / hackathon review) — owner can ONLY:
/// - setPaused(bool): emergency stop for register / checkIn / endorse. The
///   contract holds no funds, so pausing cannot trap user assets.
/// - setCheckInCooldown(uint256): anti-spam cooldown between check-ins,
///   hard-capped at 7 days.
/// - transferOwnership(address): hand admin to a new address.
/// Explicitly NOT present: no mint, no tax, no freeze of user assets, no
/// withdraw (contract is non-payable, receive() reverts), no proxy / upgrade,
/// no selfdestruct. The Agent ID registry address is immutable.
contract AgentPulse {
    IAgentIdRegistry public immutable agentId;
    address public owner;
    bool public paused;
    uint256 public checkInCooldown = 12 hours;

    uint256 public constant MAX_COOLDOWN = 7 days;
    uint256 public constant ACTIVE_WINDOW = 48 hours;
    uint256 public constant STREAK_WINDOW = 48 hours;

    uint256 public totalAgents;
    uint256 public totalCheckIns;

    struct Agent {
        string handle;
        uint64 registeredAt;
        uint64 lastCheckIn;
        uint32 checkIns;
        uint32 streak;
        uint32 endorsementsReceived;
        bool registered;
    }

    mapping(address => Agent) public agents;
    address[] public agentList;

    /// @notice hasEndorsed[giver][target] — one endorsement per ordered pair, ever.
    mapping(address => mapping(address => bool)) public hasEndorsed;

    event Registered(address indexed agent, string handle, uint256 at);
    event CheckedIn(address indexed agent, uint32 streak, uint32 checkIns, uint256 at);
    event Endorsed(address indexed from, address indexed to, uint256 at);
    event Paused(bool paused);
    event OwnershipTransferred(address indexed from, address indexed to);
    event CooldownChanged(uint256 seconds_);

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }
    modifier notPaused() {
        require(!paused, "paused");
        _;
    }

    constructor(address agentId_) {
        require(agentId_ != address(0), "zero agentId");
        agentId = IAgentIdRegistry(agentId_);
        owner = msg.sender;
    }

    // --- core actions ---

    /// @notice Register the caller. No handle input: the handle is read from
    ///         the Agent ID registry and verified three ways —
    ///         (1) balanceOf(caller) > 0, (2) handleOf(caller) is non-empty,
    ///         (3) ownerOfHandle(handle) == caller. Any failure reverts.
    function register() external notPaused {
        require(agentId.balanceOf(msg.sender) > 0, "no Agent ID");
        string memory handle = agentId.handleOf(msg.sender);
        require(bytes(handle).length > 0, "no handle");
        require(agentId.ownerOfHandle(handle) == msg.sender, "handle owner mismatch");
        Agent storage a = agents[msg.sender];
        require(!a.registered, "already registered");
        a.handle = handle;
        a.registeredAt = uint64(block.timestamp);
        a.lastCheckIn = uint64(block.timestamp);
        a.checkIns = 1;
        a.streak = 1;
        a.registered = true;
        agentList.push(msg.sender);
        totalAgents += 1;
        totalCheckIns += 1;
        emit Registered(msg.sender, handle, block.timestamp);
        emit CheckedIn(msg.sender, 1, 1, block.timestamp);
    }

    /// @notice Periodic liveness check-in. Respects checkInCooldown (default
    ///         12 hours). The streak increments when the previous check-in was
    ///         at most 48 hours ago, otherwise it resets to 1.
    function checkIn() external notPaused {
        require(agentId.balanceOf(msg.sender) > 0, "no Agent ID");
        Agent storage a = agents[msg.sender];
        require(a.registered, "not registered");
        require(block.timestamp >= uint256(a.lastCheckIn) + checkInCooldown, "cooldown");
        if (block.timestamp <= uint256(a.lastCheckIn) + STREAK_WINDOW) {
            a.streak += 1;
        } else {
            a.streak = 1;
        }
        a.lastCheckIn = uint64(block.timestamp);
        a.checkIns += 1;
        totalCheckIns += 1;
        emit CheckedIn(msg.sender, a.streak, a.checkIns, block.timestamp);
    }

    /// @notice Endorse another registered agent. The giver must be registered
    ///         AND active (last check-in within 48 hours), the target must be
    ///         registered, self-endorsement is rejected, and each ordered
    ///         pair can endorse at most once.
    function endorse(address target) external notPaused {
        Agent storage giver = agents[msg.sender];
        require(giver.registered, "not registered");
        require(_isActive(giver), "giver not active");
        require(target != msg.sender, "self endorse");
        Agent storage t = agents[target];
        require(t.registered, "target not registered");
        require(!hasEndorsed[msg.sender][target], "already endorsed");
        hasEndorsed[msg.sender][target] = true;
        t.endorsementsReceived += 1;
        emit Endorsed(msg.sender, target, block.timestamp);
    }

    // --- public views (composable reputation for other dApps) ---

    /// @notice Reputation score, formula documented in the contract header:
    ///         min(streak*5,50) + min(checkIns*2,50)
    ///         + min(endorsementsReceived*10,50) + min(ageDays,30). Max 180.
    function scoreOf(address who) public view returns (uint256) {
        Agent storage a = agents[who];
        if (!a.registered) return 0;
        uint256 streakPts = uint256(a.streak) * 5;
        if (streakPts > 50) streakPts = 50;
        uint256 checkInPts = uint256(a.checkIns) * 2;
        if (checkInPts > 50) checkInPts = 50;
        uint256 endorsePts = uint256(a.endorsementsReceived) * 10;
        if (endorsePts > 50) endorsePts = 50;
        uint256 ageDays = (block.timestamp - uint256(a.registeredAt)) / 1 days;
        if (ageDays > 30) ageDays = 30;
        return streakPts + checkInPts + endorsePts + ageDays;
    }

    /// @notice Gate helper for other dApps: true when `who` is registered,
    ///         checked in within the last 48 hours, and scores >= minScore.
    function isActiveAgent(address who, uint256 minScore) external view returns (bool) {
        Agent storage a = agents[who];
        return a.registered && _isActive(a) && scoreOf(who) >= minScore;
    }

    function isRegistered(address who) external view returns (bool) {
        return agents[who].registered;
    }

    function holdsAgentId(address who) external view returns (bool) {
        return agentId.balanceOf(who) > 0;
    }

    function agentCount() external view returns (uint256) {
        return agentList.length;
    }

    function _isActive(Agent storage a) internal view returns (bool) {
        return a.lastCheckIn != 0 && block.timestamp <= uint256(a.lastCheckIn) + ACTIVE_WINDOW;
    }

    // --- owner admin (only these) ---
    function setPaused(bool p) external onlyOwner {
        paused = p;
        emit Paused(p);
    }

    function setCheckInCooldown(uint256 s) external onlyOwner {
        require(s <= MAX_COOLDOWN, "too long");
        checkInCooldown = s;
        emit CooldownChanged(s);
    }

    function transferOwnership(address to) external onlyOwner {
        require(to != address(0), "zero");
        emit OwnershipTransferred(owner, to);
        owner = to;
    }

    receive() external payable {
        revert("no funds");
    }
}
