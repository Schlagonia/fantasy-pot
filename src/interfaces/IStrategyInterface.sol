// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IStrategyInterface is IStrategy {
    struct Player {
        bool activated;
        bool payed;
        bool couped;
    }

    struct TicTacToe {
        address player1;
        address player2;
        uint256 buyIn;
        address turn;
        uint8[9] board;
    }

    function lendingPool() external view returns (address);

    function aToken() external view returns (address);

    function start() external view returns (uint256);

    function end() external view returns (uint256);

    function winner() external view returns (address);

    function players(address) external view returns (Player memory);

    // List of all players who registerd and payed
    function playerList(uint256) external view returns (address);

    // Amount required to buy in.
    function buyIn() external view returns (uint256);

    // Storage for Games.
    function TicTacToeGames(bytes32) external view returns (TicTacToe memory);

    // Number of players that have couped against
    // The current managment.
    function couped() external view returns (uint256);

    function activateNewPlayer(address _player) external;

    function winnerWinnerChickenDinner(address _winner) external;

    function startNewTicTacToeGame(
        address _player1,
        address _player2,
        uint256 _buyIn
    ) external;

    function acceptNewTicTacToeGame(bytes32 _id) external;

    function makeMove(bytes32 _gameId, uint8 _spot) external;

    function getGameId(
        address _player1,
        address _player2,
        uint256 _buyIn
    ) external pure returns (bytes32);

    /**
     * The board is repersented as an array where each index
     * or `spot` corresponds to the diagram below.
     *
     *        [0] [1] [2]
     *
     *        [3] [4] [5]
     *
     *        [6] [7] [8]
     *
     */
    function getBoard(bytes32 _gameId) external view returns (uint8[9] memory);

    function getNextPlayer(bytes32 _gameId) external view returns (address);

    function stageACoup() external;
}
