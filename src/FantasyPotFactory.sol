// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IStrategyInterface} from "./interfaces/IStrategyInterface.sol";
import {FantasyPot} from "./FantasyPot.sol";

contract FantasyPotFactory {
    event NewFantasyPot(address _fantasyPot, address _asset, uint256 _buyIn);

    /**
     * @notice Deploy a new Fantasy pot.
     */
    function newFantasyPot(
        address _asset,
        string memory _name,
        uint256 _buyIn
    ) external returns (address) {
        // Start defaults to start of regular season. September 7th, 2023 8:20 EST.
        // End to the end of the regular season. January 7th, 2024 Midnight EST.
        return newFantasyPot(_asset, _name, _buyIn, 1694089200, 1704690000);
    }

    /**
     * @notice Deploy a new Fantasy pot with custom start and finish times.
     */
    function newFantasyPot(
        address _asset,
        string memory _name,
        uint256 _buyIn,
        uint256 start,
        uint256 end
    ) public returns (address) {
        IStrategyInterface newPot = IStrategyInterface(
            address(new FantasyPot(_asset, _name, _buyIn, start, end))
        );

        // Set profit unlock time to 1.
        newPot.setProfitMaxUnlockTime(1);

        // Set Pending Management.
        newPot.setPendingManagement(msg.sender);

        emit NewFantasyPot(address(newPot), _asset, _buyIn);
        return address(newPot);
    }
}
