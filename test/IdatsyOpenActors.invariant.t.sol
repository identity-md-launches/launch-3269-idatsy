// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Idatsy} from "../src/Idatsy.sol";

/// @dev Drives the token with holders that grow as tokens reach new addresses, including the
///      token's own address, and tracks what each spender may still move.
contract OpenActorsHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;

    Idatsy public immutable token;
    address[] public holders;
    mapping(address => bool) public known;
    uint256 public ghostMoved;
    uint256 public ghostFailedTransfers;
    /// @dev Total ever spent through each (owner, spender) pair, and total ever approved to it.
    mapping(address => mapping(address => uint256)) public spentVia;
    mapping(address => mapping(address => uint256)) public grantedTo;

    constructor() {
        token = new Idatsy();
        _remember(address(this));
        _remember(address(token));
        _remember(makeAddr("open alice"));
    }

    function holderCount() external view returns (uint256) {
        return holders.length;
    }

    function _remember(address a) internal {
        if (!known[a] && a != address(0)) {
            known[a] = true;
            holders.push(a);
        }
    }

    function _pick(uint256 seed) internal view returns (address) {
        return holders[seed % holders.length];
    }

    function transferToNew(uint256 fromSeed, address to, uint256 amount) external {
        if (to == address(0)) to = address(0xA11);
        address from = _pick(fromSeed);
        amount = bound(amount, 0, token.balanceOf(from));
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _remember(to);
        ghostMoved += amount;
    }

    function transferKnown(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _pick(fromSeed);
        address to = _pick(toSeed);
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        amount = bound(amount, 0, fromBefore);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        if (from == to) {
            assertEq(token.balanceOf(from), fromBefore);
        } else {
            assertEq(token.balanceOf(from), fromBefore - amount);
            assertEq(token.balanceOf(to), toBefore + amount);
        }
        ghostMoved += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = _pick(ownerSeed);
        address spender = _pick(spenderSeed);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        // A fresh approval resets what may still be spent.
        grantedTo[owner][spender] = spentVia[owner][spender] + amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) external {
        address owner = _pick(ownerSeed);
        address spender = _pick(spenderSeed);
        address to = _pick(toSeed);
        uint256 allowance = token.allowance(owner, spender);
        uint256 balance = token.balanceOf(owner);
        amount = bound(amount, 0, allowance < balance ? allowance : balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        spentVia[owner][spender] += amount;
        ghostMoved += amount;
    }

    /// @dev Any attempt above balance or allowance must fail and leave every balance alone.
    function tryOverspend(uint256 ownerSeed, uint256 spenderSeed, uint256 extra) external {
        address owner = _pick(ownerSeed);
        address spender = _pick(spenderSeed);
        uint256 allowance = token.allowance(owner, spender);
        uint256 balance = token.balanceOf(owner);
        uint256 limit = allowance < balance ? allowance : balance;
        extra = bound(extra, 1, SUPPLY);
        uint256 attempt = limit + extra;
        vm.prank(spender);
        try token.transferFrom(owner, spender, attempt) returns (bool) {
            revert("overspend succeeded");
        } catch {
            ghostFailedTransfers++;
        }
        assertEq(token.balanceOf(owner), balance);
        assertEq(token.allowance(owner, spender), allowance);
    }
}

contract IdatsyOpenActorsInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;

    OpenActorsHandler internal handler;
    Idatsy internal token;

    function setUp() public {
        handler = new OpenActorsHandler();
        token = handler.token();
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 128
    function invariant_supplyNeverChanges() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    /// forge-config: default.invariant.runs = 128
    function invariant_holdersSumToSupply() public view {
        uint256 n = handler.holderCount();
        uint256 sum;
        for (uint256 i; i < n; ++i) {
            sum += token.balanceOf(handler.holders(i));
        }
        assertEq(sum, SUPPLY);
    }

    /// forge-config: default.invariant.runs = 128
    function invariant_noSpenderExceedsWhatWasGranted() public view {
        uint256 n = handler.holderCount();
        for (uint256 i; i < n; ++i) {
            for (uint256 j; j < n; ++j) {
                address owner = handler.holders(i);
                address spender = handler.holders(j);
                assertLe(handler.spentVia(owner, spender), handler.grantedTo(owner, spender));
                assertEq(
                    token.allowance(owner, spender),
                    handler.grantedTo(owner, spender) - handler.spentVia(owner, spender)
                );
            }
        }
    }
}
