// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRandomnessSource} from "../../src/chopshop/IRandomnessSource.sol";

/// @notice A settable IRandomnessSource so Chop Shop outcomes are deterministic in tests.
/// @dev The real CommitRevealRandomness is exercised separately in its own suite. Forcing the draw
///      here is what lets win, loss and expiry paths each be asserted exactly.
contract MockRandomness is IRandomnessSource {
    uint256 public value;
    bool public ready = true;
    bool public expired;
    uint256 public nextId = 1;

    function setValue(uint256 v) external {
        value = v;
    }

    function setReady(bool r) external {
        ready = r;
    }

    function setExpired(bool e) external {
        expired = e;
        if (e) ready = false;
    }

    function requestRandomness(bytes32) external override returns (uint256) {
        return nextId++;
    }

    function isReady(uint256) external view override returns (bool) {
        return ready;
    }

    function isExpired(uint256) external view override returns (bool) {
        return expired;
    }

    function randomness(uint256) external view override returns (uint256) {
        return value;
    }
}
