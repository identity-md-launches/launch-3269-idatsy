// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Idatsy} from "../../src/Idatsy.sol";

/// @dev Local test fixture only; never part of the deployment.
contract TokenFactory {
    function deploy() external returns (Idatsy) {
        return new Idatsy();
    }

    function deployDeterministic(bytes32 salt) external returns (Idatsy) {
        return new Idatsy{salt: salt}();
    }

    function move(Idatsy token, address to, uint256 amount) external {
        require(token.transfer(to, amount), "transfer failed");
    }
}
