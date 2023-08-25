// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {FantasyPot} from "./FantasyPot.sol";

contract FantasyPotFactory {


    function newFantasyPot(address _asset, string memory _name, uint256 _buyIn) external returns (address) {
        FantasyPot newPot = new FantasyPot(_asset, _name, _buyIn);

        // Set profit unlock time to 1

        // Set fee to 5%

        // Set Pending mgmt

        return address(newPot);
    }
}