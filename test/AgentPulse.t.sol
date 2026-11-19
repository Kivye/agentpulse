// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../contracts/AgentPulse.sol";
import "../contracts/MockAgentId.sol";

// Minimal forge-style test without forge-std import (Vm cheatcode interface inline).
interface Vm2 {
    function prank(address) external;
    function warp(uint256) external;
    function expectRevert() external;
}

contract AgentPulseTest {
    Vm2 constant vm = Vm2(address(uint160(uint256(keccak256("hevm cheat code")))));
    MockAgentId mock;
    AgentPulse pulse;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xCA401);
    address dave = address(0xDA9E);
    address eve = address(0xE9E);
    address frank = address(0xF4A9);
    address grace = address(0x64ACE);

    function setUp() public {
        mock = new MockAgentId();
        pulse = new AgentPulse(address(mock));
        mock.setAgent(alice, "alice");
        mock.setAgent(bob, "bob");
        mock.setAgent(carol, "carol");
        mock.setAgent(dave, "dave");
    }

    // ---------- helpers ----------
    function _register(address who) internal {
        vm.prank(who);
        pulse.register();
    }

    function _agent(address who)
        internal
        view
        returns (string memory handle, uint64 registeredAt, uint64 lastCheckIn, uint32 checkIns, uint32 streak, uint32 endorsementsReceived, bool registered)
    {
        return pulse.agents(who);
    }

    // ---------- POSITIVE ----------

    function testHolderRegistersWithHandleFromRegistry() public {
        _register(alice);
        require(pulse.isRegistered(alice), "not registered");
        (string memory handle, , , uint32 checkIns, uint32 streak, ,) = _agent(alice);
        require(keccak256(bytes(handle)) == keccak256("alice"), "handle must come from registry, no .ai suffix");
        require(checkIns == 1 && streak == 1, "initial checkin/streak");
        require(pulse.totalAgents() == 1 && pulse.agentCount() == 1, "counts");
        require(pulse.holdsAgentId(alice), "holdsAgentId");
    }

    function testCheckInRaisesStreak() public {
        _register(alice);
        vm.warp(block.timestamp + 12 hours);
        vm.prank(alice);
        pulse.checkIn();
        (, , , uint32 checkIns, uint32 streak, ,) = _agent(alice);
        require(checkIns == 2 && streak == 2, "checkin/streak after 12h");
        require(pulse.totalCheckIns() == 2, "global totalCheckIns");
    }

    function testStreakResetsAfter48hGap() public {
        _register(alice);
        vm.warp(block.timestamp + 12 hours);
        vm.prank(alice);
        pulse.checkIn(); // streak 2
        vm.warp(block.timestamp + 49 hours);
        vm.prank(alice);
        pulse.checkIn(); // gap > 48h -> reset
        (, , , uint32 checkIns, uint32 streak, ,) = _agent(alice);
        require(checkIns == 3 && streak == 1, "streak must reset to 1");
    }

    function testValidEndorsementRaisesTargetScore() public {
        _register(alice);
        _register(bob);
        uint256 before = pulse.scoreOf(alice);
        vm.prank(bob);
        pulse.endorse(alice);
        (, , , , , uint32 received,) = _agent(alice);
        require(received == 1, "endorsementsReceived");
        require(pulse.hasEndorsed(bob, alice), "pair recorded");
        require(pulse.scoreOf(alice) == before + 10, "score +10 per endorsement");
    }

    function testScoreFormulaManualScenario() public {
        // Alice: register (checkIns=1, streak=1), then 3 check-ins 12h apart
        // -> checkIns=4, streak=4, age = 36h = 1 day.
        _register(alice);
        for (uint256 i = 0; i < 3; i++) {
            vm.warp(block.timestamp + 12 hours);
            vm.prank(alice);
            pulse.checkIn();
        }
        // streak 4*5=20, checkIns 4*2=8, endorsements 0, age 1 -> 29
        require(pulse.scoreOf(alice) == 29, "score before endorsements");
        // Bob + Carol register now (active immediately) and endorse Alice: +20
        _register(bob);
        _register(carol);
        vm.prank(bob);
        pulse.endorse(alice);
        vm.prank(carol);
        pulse.endorse(alice);
        // 20 + 8 + 20 + 1 = 49
        require(pulse.scoreOf(alice) == 49, "score after 2 endorsements");
    }

    function testScoreCapsStreakAndCheckIns() public {
        // 30 extra check-ins 12h apart: checkIns=31, streak=31,
        // age = 360h = 15 days -> capped 50 + capped 50 + 0 + 15 = 115
        _register(alice);
        for (uint256 i = 0; i < 30; i++) {
            vm.warp(block.timestamp + 12 hours);
            vm.prank(alice);
            pulse.checkIn();
        }
        require(pulse.scoreOf(alice) == 115, "capped score");
    }

    function testScoreOfUnregisteredIsZero() public view {
        require(pulse.scoreOf(eve) == 0, "unregistered score 0");
    }

    function testIsActiveAgentTrueForActiveAgentWithEnoughScore() public {
        _register(alice);
        // fresh agent: streak 5 + checkIns 2 + 0 + age 0 = 7
        require(pulse.scoreOf(alice) == 7, "fresh score 7");
        require(pulse.isActiveAgent(alice, 7), "active at minScore 7");
        require(!pulse.isActiveAgent(alice, 8), "not active at minScore 8");
        // after 49h without check-in: no longer active regardless of score
        vm.warp(block.timestamp + 49 hours);
        require(!pulse.isActiveAgent(alice, 0), "inactive after 48h window");
    }

    // ---------- NEGATIVE: register gate ----------

    function testNonHolderCannotRegister() public {
        // Eve has a staged handle + owner record but NO balance.
        mock.setHandle(eve, "eve");
        mock.setOwnerOfHandle("eve", eve);
        vm.prank(eve);
        vm.expectRevert();
        pulse.register();
    }

    function testHolderWithEmptyHandleCannotRegister() public {
        mock.setBalance(eve, 1); // holder, but handleOf(eve) == ""
        vm.prank(eve);
        vm.expectRevert();
        pulse.register();
    }

    function testHandleOwnerMismatchCannotRegister() public {
        mock.setBalance(frank, 1);
        mock.setHandle(frank, "frank");
        mock.setOwnerOfHandle("frank", bob); // registry says someone else owns it
        vm.prank(frank);
        vm.expectRevert();
        pulse.register();
    }

    function testRegisterTwiceReverts() public {
        _register(alice);
        vm.prank(alice);
        vm.expectRevert();
        pulse.register();
    }

    // ---------- NEGATIVE: check-in ----------

    function testCheckInBeforeCooldownReverts() public {
        _register(alice);
        vm.warp(block.timestamp + 11 hours);
        vm.prank(alice);
        vm.expectRevert();
        pulse.checkIn();
    }

    function testCheckInWithoutRegisterReverts() public {
        mock.setAgent(grace, "grace"); // holder, never registers
        vm.prank(grace);
        vm.expectRevert();
        pulse.checkIn();
    }

    // ---------- NEGATIVE: endorsement ----------

    function testEndorseSelfReverts() public {
        _register(alice);
        vm.prank(alice);
        vm.expectRevert();
        pulse.endorse(alice);
    }

    function testEndorseTwiceSameTargetReverts() public {
        _register(alice);
        _register(bob);
        vm.prank(bob);
        pulse.endorse(alice);
        vm.prank(bob);
        vm.expectRevert();
        pulse.endorse(alice);
    }

    function testEndorseFromInactiveAgentReverts() public {
        _register(alice);
        _register(bob);
        vm.warp(block.timestamp + 49 hours); // both stale; giver alice inactive
        vm.prank(alice);
        vm.expectRevert();
        pulse.endorse(bob);
    }

    function testEndorseUnregisteredTargetReverts() public {
        _register(alice);
        vm.prank(alice);
        vm.expectRevert();
        pulse.endorse(grace);
    }

    function testEndorseFromUnregisteredGiverReverts() public {
        _register(alice);
        mock.setAgent(grace, "grace");
        vm.prank(grace);
        vm.expectRevert();
        pulse.endorse(alice);
    }

    // ---------- NEGATIVE: pause ----------

    function testPauseBlocksRegister() public {
        pulse.setPaused(true);
        vm.prank(dave);
        vm.expectRevert();
        pulse.register();
    }

    function testPauseBlocksCheckIn() public {
        _register(alice);
        vm.warp(block.timestamp + 12 hours);
        pulse.setPaused(true);
        vm.prank(alice);
        vm.expectRevert();
        pulse.checkIn();
    }

    function testPauseBlocksEndorse() public {
        _register(alice);
        _register(bob);
        pulse.setPaused(true);
        vm.prank(bob);
        vm.expectRevert();
        pulse.endorse(alice);
    }

    // ---------- NEGATIVE: owner-only ----------

    function testNonOwnerCannotSetPaused() public {
        vm.prank(alice);
        vm.expectRevert();
        pulse.setPaused(true);
    }

    function testNonOwnerCannotSetCooldown() public {
        vm.prank(alice);
        vm.expectRevert();
        pulse.setCheckInCooldown(1 hours);
    }

    function testNonOwnerCannotTransferOwnership() public {
        vm.prank(alice);
        vm.expectRevert();
        pulse.transferOwnership(alice);
    }

    function testCooldownAboveSevenDaysReverts() public {
        vm.expectRevert();
        pulse.setCheckInCooldown(7 days + 1);
    }

    function testOwnerCanSetCooldownWithinCap() public {
        pulse.setCheckInCooldown(7 days);
        require(pulse.checkInCooldown() == 7 days, "cooldown set");
        pulse.setCheckInCooldown(12 hours);
        require(pulse.checkInCooldown() == 12 hours, "cooldown reset");
    }
}
