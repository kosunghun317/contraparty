// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6;
pragma abicoder v2;

import {Quoter} from "view-quoter-v3/contracts/Quoter.sol";

/// @notice Thin local wrapper so vm.deployCode can deploy a stable artifact path from src/.
contract MegaethViewQuoter is Quoter {
    constructor(address factory_) Quoter(factory_) {}
}
