// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";
import {FantasyPot} from "./FantasyPot.sol";

contract FantasyPotFactory {
    function newFantasyPot(
        address _asset,
        string memory _name,
        uint256 _buyIn
    ) external returns (address) {
        IStrategyInterface newPot = IStrategyInterface(address(new FantasyPot(_asset, _name, _buyIn)));

        // Set profit unlock time to 1
        newPot.setProfitMaxUnlockTime(1);
        // Set fee to minimum
        newPot.setPerformanceFee(newPot.MIN_FEE());
        // Set Pending mgmt
        newPot.setPendingManagement(msg.sender);
        
        return address(newPot);
    }
}
