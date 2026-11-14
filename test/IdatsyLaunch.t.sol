// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Idatsy} from "../src/Idatsy.sol";
import {WalletGas} from "./helpers/WalletGas.sol";

/// @dev Stands in for the launch factory: deploys the token by CREATE2 and runs the launch's
///      distribution in a single call, the way one launch transaction does on chain.
contract LaunchInOneCall {
    address public immutable controller = msg.sender;

    function launch(bytes32 salt, address distributor, address pool, address remainderTo, uint256 poolBps)
        external
        returns (Idatsy token)
    {
        require(msg.sender == controller, "controller only");
        token = new Idatsy{salt: salt}();
        uint256 supply = token.totalSupply();
        require(token.balanceOf(address(this)) == supply, "supply not with the factory");
        uint256 swarm = supply * 1_000 / 10_000;
        uint256 seeded = supply * poolBps / 10_000;
        require(token.transfer(distributor, swarm), "swarm transfer");
        require(token.balanceOf(distributor) == swarm, "swarm short");
        require(token.transfer(pool, seeded), "seed transfer");
        require(token.balanceOf(pool) == seeded, "seed short");
        uint256 rest = token.balanceOf(address(this));
        require(token.transfer(remainderTo, rest), "remainder transfer");
        require(token.balanceOf(remainderTo) == rest, "remainder short");
        require(token.balanceOf(address(this)) == 0, "factory kept something");
        require(token.totalSupply() == supply, "supply changed");
    }

    function call(address target, bytes calldata data) external returns (bool ok) {
        require(msg.sender == controller, "controller only");
        (ok,) = target.call(data);
    }
}

contract IdatsyLaunchTest is WalletGas {
    uint256 internal constant SUPPLY = 1_000_000_000 * 1e18;

    Idatsy internal token;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal spender = makeAddr("spender");

    function setUp() public {
        token = new Idatsy();
    }

    // ------------------------------------------------------------------ launch flow

    function test_launchInOneTransactionMovesEveryShareWhole() public {
        LaunchInOneCall factory = new LaunchInOneCall();
        address distributor = makeAddr("distributor");
        address pool = makeAddr("pool manager");
        address remainderTo = makeAddr("remainder");
        Idatsy launched = factory.launch(bytes32(uint256(7)), distributor, pool, remainderTo, 6_000);
        assertEq(launched.totalSupply(), SUPPLY);
        assertEq(launched.balanceOf(distributor), SUPPLY / 10);
        assertEq(launched.balanceOf(pool), SUPPLY * 6_000 / 10_000);
        assertEq(launched.balanceOf(remainderTo), SUPPLY - SUPPLY / 10 - SUPPLY * 6_000 / 10_000);
        assertEq(launched.balanceOf(address(factory)), 0);
    }

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_launchAnyPoolShareConservesSupply(uint256 poolBps, bytes32 salt) public {
        poolBps = bound(poolBps, 0, 9_000);
        LaunchInOneCall factory = new LaunchInOneCall();
        address distributor = makeAddr("distributor");
        address pool = makeAddr("pool manager");
        address remainderTo = makeAddr("remainder");
        Idatsy launched = factory.launch(salt, distributor, pool, remainderTo, poolBps);
        assertEq(launched.balanceOf(distributor) + launched.balanceOf(pool) + launched.balanceOf(remainderTo), SUPPLY);
    }

    function test_sameSaltCannotRedeployOverTheLaunchedToken() public {
        LaunchInOneCall factory = new LaunchInOneCall();
        factory.launch(bytes32(uint256(1)), alice, bob, spender, 1_000);
        vm.expectRevert();
        factory.launch(bytes32(uint256(1)), alice, bob, spender, 1_000);
    }

    function test_onlyTheControllerDrivesTheStandInFactory() public {
        LaunchInOneCall factory = new LaunchInOneCall();
        vm.prank(alice);
        vm.expectRevert(bytes("controller only"));
        factory.launch(bytes32(0), alice, bob, spender, 1_000);
    }

    // ------------------------------------------------------------------ no privileged hand

    function test_factoryAndStrangersCannotMintFreezeOrSeize() public {
        LaunchInOneCall factory = new LaunchInOneCall();
        address holder = makeAddr("holder");
        Idatsy launched = factory.launch(bytes32(uint256(3)), holder, bob, spender, 1_000);
        uint256 held = launched.balanceOf(holder);

        string[21] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)",
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "seize(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], holder, type(uint128).max);
            assertFalse(factory.call(address(launched), data), signatures[i]);
            vm.prank(alice);
            (bool ok,) = address(launched).call(data);
            assertFalse(ok, signatures[i]);
        }
        assertFalse(
            factory.call(address(launched), abi.encodeWithSignature("burnFrom(address,uint256)", holder, uint256(1)))
        );
        assertFalse(
            factory.call(
                address(launched), abi.encodeCall(launched.transferFrom, (holder, address(factory), uint256(1)))
            ),
            "the deployer moved a holder's tokens without approval"
        );
        assertEq(launched.totalSupply(), SUPPLY);
        assertEq(launched.balanceOf(holder), held);
        assertEq(launched.balanceOf(alice), 0);
        vm.prank(holder);
        assertTrue(launched.transfer(alice, held / 2));
        assertEq(launched.balanceOf(alice), held / 2);
    }

    function test_unknownSelectorAndEmptyCalldataRevert() public {
        (bool ok,) = address(token).call(hex"deadbeef");
        assertFalse(ok);
        (ok,) = address(token).call("");
        assertFalse(ok);
        (ok,) = address(token).call(hex"a9");
        assertFalse(ok, "a truncated selector is accepted");
    }

    function test_shortCalldataTransferReverts() public {
        // transfer(address,uint256) with the amount word cut off must not be read as a zero amount.
        bytes memory full = abi.encodeCall(token.transfer, (alice, 1));
        bytes memory cut = new bytes(full.length - 32);
        for (uint256 i; i < cut.length; ++i) {
            cut[i] = full[i];
        }
        (bool ok,) = address(token).call(cut);
        assertFalse(ok);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_runtimeCodeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        bool reachable = true;
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += op - 0x5F;
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "DELEGATECALL");
                assertTrue(op != 0xF2, "CALLCODE");
                assertTrue(op != 0xFF, "SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }

    // ------------------------------------------------------------------ edges

    function test_transferToTheTokenContractIsKeptAndCannotBeRecovered() public {
        // Plain ERC-20: tokens sent to the token's own address stay there. There is no rescue path,
        // so nobody, including the deployer, can pull them back out.
        assertTrue(token.transfer(address(token), 1e18));
        assertEq(token.balanceOf(address(token)), 1e18);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1e18)
        );
        token.transferFrom(address(token), address(this), 1e18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_allowanceOneBelowMaxIsSpent() public {
        uint256 almost = type(uint256).max - 1;
        assertTrue(token.approve(spender, almost));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 5));
        assertEq(token.allowance(address(this), spender), almost - 5);
    }

    function test_maxAllowanceStillBoundedByBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), type(uint256).max);
    }

    function test_approveSelfAndSpendOwnAllowance() public {
        assertTrue(token.approve(address(this), 10));
        assertTrue(token.transferFrom(address(this), alice, 10));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(alice), 10);
    }

    function test_approvalsArePerOwnerAndPerSpender() public {
        assertTrue(token.approve(spender, 10));
        assertEq(token.allowance(spender, address(this)), 0);
        assertEq(token.allowance(address(this), alice), 0);
        vm.prank(alice);
        assertTrue(token.approve(spender, 3));
        assertEq(token.allowance(address(this), spender), 10);
        assertEq(token.allowance(alice, spender), 3);
    }

    function testFuzz_transferBetweenArbitraryAddresses(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != address(this));
        amount = bound(amount, 0, SUPPLY);
        uint256 before = token.balanceOf(to);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(to), before + amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_strangerCannotSpendWithoutAllowance(address stranger, uint256 amount) public {
        vm.assume(stranger != address(this));
        amount = bound(amount, 1, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, stranger, 0, amount));
        vm.prank(stranger);
        token.transferFrom(address(this), stranger, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    // ------------------------------------------------------------------ wallet gas

    /// @dev Nothing in the token reads gasleft(), forwards fixed gas or catches a failed call; these
    ///      show the calls a holder sends do the same at the gas a wallet would estimate.
    function test_transferSameAtWalletGas() public {
        assertTrue(token.transfer(alice, 100e18));
        assertSameAtWalletGas(alice, address(token), abi.encodeCall(token.transfer, (bob, 40e18)));
        assertSameAtWalletGas(alice, address(token), abi.encodeCall(token.transfer, (bob, 100e18)));
    }

    function test_approveAndTransferFromSameAtWalletGas() public {
        assertTrue(token.transfer(alice, 100e18));
        assertSameAtWalletGas(alice, address(token), abi.encodeCall(token.approve, (spender, 50e18)));
        vm.prank(alice);
        assertTrue(token.approve(spender, 50e18));
        assertSameAtWalletGas(spender, address(token), abi.encodeCall(token.transferFrom, (alice, bob, 50e18)));
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        assertSameAtWalletGas(spender, address(token), abi.encodeCall(token.transferFrom, (alice, bob, 1e18)));
    }
}
