// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {BaseTokenizedStrategy} from "@tokenized-strategy/BaseTokenizedStrategy.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPool} from "./interfaces/Aave/V3/IPool.sol";
import {IAToken} from "./interfaces/Aave/V3/IAtoken.sol";

import {TokenizedHelper} from "./TokenizedHelper.sol";

/**
 * @title Tokenized Fantasy Pot.
 */
contract FantasyPot is BaseTokenizedStrategy, TokenizedHelper {
    using SafeERC20 for ERC20;

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

    // Aave pool to deposit and withdraw through.
    IPool public constant lendingPool =
        IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);

    // The token that we get in return for deposits.
    IAToken public immutable aToken;

    // timestamp of Start of the regular season.
    // No more deposits after this date.
    uint256 public immutable start;

    // time stamp of End of regular season.
    // Can't declare a winner or withdraw till this time.
    uint256 public immutable end;

    // Winner of the league.
    address public winner;

    // Mapping of a players address to their Player struct
    mapping(address => Player) public players;

    // List of all players who registered and payed
    address[] public playerList;

    // Amount required to buy in.
    uint256 public immutable buyIn;

    // Storage for Games.
    mapping(bytes32 => TicTacToe) public TicTacToeGames;

    // Number of players that have couped against
    // The current management.
    uint256 public couped;

    constructor(
        address _asset,
        string memory _name,
        uint256 _buyIn,
        uint256 _start,
        uint256 _end
    ) BaseTokenizedStrategy(_asset, _name) {
        // Set the aToken based on the asset we are using.
        aToken = IAToken(lendingPool.getReserveData(_asset).aTokenAddress);

        // Make sure its a real token.
        require(address(aToken) != address(0), "no aave pool");

        // Approve the lending pool for cheaper deposits.
        ERC20(_asset).safeApprove(address(lendingPool), type(uint256).max);

        // Set the buy in.
        require(_buyIn != 0, "you gotta pump those numbers up");
        buyIn = _buyIn;

        // start and end Times.
        require(_start > block.timestamp, "how you gonna buy in?");
        require(_end > _start, "dumbass");
        start = _start;
        end = _end;
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Should deploy up to '_amount' of 'asset' in the yield source.
     *
     * This function is called at the end of a {deposit} or {mint}
     * call. Meaning that unless a whitelist is implemented it will
     * be entirely permsionless and thus can be sandwhiched or otherwise
     * manipulated.
     *
     * @param _amount The amount of 'asset' that the strategy should attemppt
     * to deposit in the yield source.
     */
    function _deployFunds(uint256 _amount) internal override {
        lendingPool.supply(asset, _amount, address(this), 0);
    }

    /**
     * @dev Will attempt to free the '_amount' of 'asset'.
     *
     * The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * This function is called during {withdraw} and {redeem} calls.
     * Meaning that unless a whitelist is implemented it will be
     * entirely permsionless and thus can be sandwhiched or otherwise
     * manipulated.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting puroposes.
     *
     * Any difference between `_amount` and what is actually freed will be
     * counted as a loss and passed on to the withdrawer. This means
     * care should be taken in times of illiquidity. It may be better to revert
     * if withdraws are simply illiquid so not to realize incorrect losses.
     *
     * @param _amount, The amount of 'asset' to be freed.
     */
    function _freeFunds(uint256 _amount) internal override {
        lendingPool.withdraw(
            asset,
            Math.min(aToken.balanceOf(address(this)), _amount),
            address(this)
        );
    }

    /**
     * @dev Internal function to harvest all rewards, redeploy any idle
     * funds and return an accurate accounting of all funds currently
     * held by the Strategy.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * redepositing etc. to get the most accurate view of current assets.
     *
     * NOTE: All applicable assets including loose assets should be
     * accounted for in this function.
     *
     * Care should be taken when relying on oracles or swap values rather
     * than actual amounts as all Strategy profit/loss accounting will
     * be done based on this returned value.
     *
     * This can still be called post a shutdown, a strategist can check
     * `TokenizedStrategy.isShutdown()` to decide if funds should be
     * redeployed or simply realize any profits/losses.
     *
     * @return _totalAssets A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds including idle funds.
     */
    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        // Dont record profits till the season ends.
        require(block.timestamp > end, "Season hasnt ended");

        _totalAssets =
            aToken.balanceOf(address(this)) + // this assumes aToken == asset
            ERC20(asset).balanceOf(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                    OPTIONAL TO OVERRIDE BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Optional function for strategist to override that can
     *  be called in between reports.
     *
     * If '_tend' is used tendTrigger() will also need to be overridden.
     *
     * This call can only be called by a persionned role so may be
     * through protected relays.
     *
     * This can be used to harvest and compound rewards, deposit idle funds,
     * perform needed poisition maintence or anything else that doesn't need
     * a full report for.
     *
     *   EX: A strategy that can not deposit funds without getting
     *       sandwhiched can use the tend when a certain threshold
     *       of idle to totalAssets has been reached.
     *
     * The TokenizedStrategy contract will do all needed debt and idle updates
     * after this has finished and will have no effect on PPS of the strategy
     * till report() is called.
     *
     * @param _totalIdle The current amount of idle funds that are available to deploy.
     */
    function _tend(uint256 _totalIdle) internal override {
        uint256 balance = ERC20(asset).balanceOf(address(this));
        if (balance != 0) {
            _deployFunds(balance);
        }
    }

    /**
     * @notice Gets the max amount of `asset` that an adress can deposit.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overriden by strategists.
     *
     * This function will be called before any deposit or mints to enforce
     * any limits desired by the strategist. This can be used for either a
     * traditional deposit limit or for implementing a whitelist etc.
     *
     *   EX:
     *      if(isAllowed[_owner]) return super.availableDepositLimit(_owner);
     *
     * This does not need to take into account any conversion rates
     * from shares to assets. But should know that any non max uint256
     * amounts may be converted to shares. So it is recommended to keep
     * custom amounts low enough as not to cause overflow when multiplied
     * by `totalSupply`.
     *
     * @param . The address that is depositing into the strategy.
     * @return . The avialable amount the `_owner` can deposit in terms of `asset`
     */
    function availableDepositLimit(
        address _owner
    ) public view override returns (uint256) {
        // If we are past the start no more deposits.
        if (block.timestamp > start) return 0;

        // If the player has been activated but hasn't payed.
        if (players[_owner].activated && !players[_owner].payed) {
            return buyIn;
        } else {
            return 0;
        }
    }

    /**
     * @notice Gets the max amount of `asset` that can be withdrawn.
     * @dev Defaults to an unlimited amount for any address. But can
     * be overriden by strategists.
     *
     * This function will be called before any withdraw or redeem to enforce
     * any limits desired by the strategist. This can be used for illiquid
     * or sandwhichable strategies. It should never be lower than `totalIdle`.
     *
     *   EX:
     *       return TokenIzedStrategy.totalIdle();
     *
     * This does not need to take into account the `_owner`'s share balance
     * or conversion rates from shares to assets.
     *
     * @param . The address that is withdrawing from the strategy.
     * @return . The avialable amount that can be withdrawn in terms of `asset`
     */
    function availableWithdrawLimit(
        address _owner
    ) public view override returns (uint256) {
        // only after end
        if (block.timestamp < end) return 0;

        // Only the winner can withdraw.
        if (_owner == winner) return type(uint256).max;

        return 0;
    }

    /*//////////////////////////////////////////////////////////////
                        PLAYER MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Allows the manager to register a new player.
     *
     * This will allow that player to deposit in the buy in and
     * get added to the player list once the buy in has been payed.
     */
    function activateNewPlayer(address _player) external onlyManagement {
        require(start > block.timestamp, "season started");
        require(!players[_player].activated, "already activated");

        players[_player].activated = true;
    }

    /**
     * @notice Allows management to declare a winner!
     *
     * Will burn every other players shares and report the accumulated
     * profits so that the winner can now withdraw the full amount
     * of their winnings.
     *
     */
    function winnerWinnerChickenDinner(
        address _winner
    ) external onlyManagement {
        require(block.timestamp >= end, "Seasons still going");
        require(winner == address(0), "Winner already Declared");
        require(players[_winner].payed, "!playing");
        require(TokenizedStrategy.balanceOf(_winner) != 0, "!shares");

        address[] memory _playerList = playerList;
        uint256 numPlayers = _playerList.length;
        StrategyData storage S = _strategyStorage();
        // Burn every other players shares.
        for (uint256 i; i < numPlayers; ++i) {
            address _player = _playerList[i];
            if (_player == _winner) continue;

            // Burn the losers shares.
            S.totalSupply -= S.balances[_player];
            S.balances[_player] = 0;
        }

        // Set the winner to receive any performance fees
        S.performanceFeeRecipient = _winner;

        // Set the winner as the new manager.
        S.management = _winner;

        // Set the strategy as its own Keeper in order to report.
        S.keeper = address(this);

        // Report all profits for the winner to withdraw
        TokenizedStrategy.report();

        // Set the winner
        winner = _winner;
    }

    /*//////////////////////////////////////////////////////////////
                            GAMES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Challenge ye rival to a game of Tic Tac Toe.
     *
     * This is step 1 of 2 to initate a new game. The opposing player will
     * also have to accept the game by calling {acceptNewTicTacToeGame}.
     *
     * Each player will take turns calling {makeMove} until either one
     * player wins or the board is filled up.
     *
     * The winner will get their money back plus 80% of the other players '
     * buyin as a prize. If it ends in a draw each player gets 90% of their
     * money back.
     *
     * Either way the pot keeps 20% as a house fee to add to then final fantasy pot.
     *
     * NOTE: Each player must approve this address to pull the `_buyin` amount
     *   from their wallet before the second player calls {acceptNewTicTacToeGame}
     * NOTE: Player 1 must be the msg.sender
     */
    function startNewTicTacToeGame(
        address _player1,
        address _player2,
        uint256 _buyIn
    ) external {
        require(block.timestamp < end, "Season has ended");
        require(
            _player1 != address(0) && _player2 != address(0),
            "Vitalik Can't play"
        );
        require(_player1 != _player2, "friendly fire");
        require(_player1 == msg.sender, "!player1");
        // Buy in has to be divisible by 5 for the Pot fee.
        require(_buyIn > 5, "What is this? A wager for ants!");

        bytes32 _gameId = getGameId(_player1, _player2, _buyIn);
        require(
            TicTacToeGames[_gameId].player1 == address(0),
            "Game in session"
        );

        TicTacToe memory newGame;
        newGame.player1 = _player1;
        newGame.player2 = _player2;
        newGame.buyIn = _buyIn;

        TicTacToeGames[_gameId] = newGame;
    }

    /**
     * @notice Accept a previously started game that you are player2 in.
     *
     * This will pull the funds from both players and set the msg.sender
     * as the first player to go.
     */
    function acceptNewTicTacToeGame(bytes32 _gameId) external {
        TicTacToe memory game = TicTacToeGames[_gameId];
        require(block.timestamp < end, "Season has ended");
        require(game.player1 != address(0), "must start game first");
        require(game.player2 == msg.sender, "Cant accept someone elses game");

        // Transfer the funds in from both players.
        // NOTE: Both players must have approved the Pot to pull the funds.
        ERC20(asset).safeTransferFrom(game.player1, address(this), game.buyIn);
        ERC20(asset).safeTransferFrom(msg.sender, address(this), game.buyIn);

        // Gotta earn that sweet yield while the game is played.
        _deployFunds(ERC20(asset).balanceOf(address(this)));

        // Player 2 Goes first.
        TicTacToeGames[_gameId].turn = msg.sender;
    }

    /**
     * @notice This is the thick of the action.
     *
     *  Once a game has started players will take turns making their move
     * on the board. The board is repersented as an array where each index
     * or `spot` corresponds to the diagram below.
     *
     *        [0] [1] [2]
     *
     *        [3] [4] [5]
     *
     *        [6] [7] [8]
     *
     * After each turn the board will be checked for a winner or
     * if the board is full and pay out the amounts accordingly.
     *
     * A board space having a 0 means its empty. 1 corresponds to
     * player1 and 2 corresponds to player2.
     *
     * Use the supplied helper functions to get things like your
     * `_gameId`, whos turn it is or the current state of the board.
     *
     */
    function makeMove(bytes32 _gameId, uint8 _spot) external {
        TicTacToe memory game = TicTacToeGames[_gameId];
        require(game.turn == msg.sender, "Not your turn");
        require(_spot < 9, "invalid spot");
        require(game.board[_spot] == 0, "Invalid move");

        // Player1 is 1 and player2 is 2.
        uint8 marker = game.player1 == msg.sender ? 1 : 2;

        TicTacToeGames[_gameId].board[_spot] = marker;

        // If the move is a winner.
        if (_isAWinner(TicTacToeGames[_gameId].board)) {
            // Pay the winner and rug the loser.
            // Pot keeps 10% of the buyins for the final fund.
            uint256 _toPay = (game.buyIn * 2) - (game.buyIn / 5);
            // Pull them from Aave
            _freeFunds(_toPay);
            // Pay the winner.
            ERC20(asset).safeTransfer(msg.sender, _toPay);

            // Delete game
            delete TicTacToeGames[_gameId];

            // If The game is full.
        } else if (_boardIsFull(TicTacToeGames[_gameId].board)) {
            // Pay back both players.
            // The pots keeps its cut cause the house always wins.
            uint256 _toPay = (game.buyIn * 2) - (game.buyIn / 5);
            // Pull them from Aave
            _freeFunds(_toPay);
            // Transfer to each player.
            ERC20(asset).safeTransfer(msg.sender, _toPay / 2);
            ERC20(asset).safeTransfer(
                marker == 1 ? game.player2 : game.player1,
                _toPay / 2
            );

            // Delete game
            delete TicTacToeGames[_gameId];
        } else {
            // Set the next turn.
            TicTacToeGames[_gameId].turn = marker == 1
                ? game.player2
                : game.player1;
        }
    }

    function getGameId(
        address _player1,
        address _player2,
        uint256 _buyIn
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_player1, _player2, _buyIn));
    }

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
    function getBoard(bytes32 _gameId) public view returns (uint8[9] memory) {
        return TicTacToeGames[_gameId].board;
    }

    function getNextPlayer(bytes32 _gameId) public view returns (address) {
        return TicTacToeGames[_gameId].turn;
    }

    function _isAWinner(uint8[9] memory board) internal view returns (bool) {
        // First Row.
        if (_isTheSame(board[0], board[1], board[2])) return true;
        // Second Row
        if (_isTheSame(board[3], board[4], board[5])) return true;
        // Third Row.
        if (_isTheSame(board[6], board[7], board[8])) return true;
        // First Column.
        if (_isTheSame(board[0], board[3], board[6])) return true;
        // Second Column
        if (_isTheSame(board[1], board[4], board[7])) return true;
        // Third Column
        if (_isTheSame(board[2], board[5], board[8])) return true;
        // Diagonals
        if (_isTheSame(board[0], board[4], board[8])) return true;
        if (_isTheSame(board[2], board[4], board[6])) return true;
    }

    function _isTheSame(
        uint8 i,
        uint8 j,
        uint8 k
    ) internal view returns (bool) {
        if (i != 0 && i == j && j == k) return true;
    }

    function _boardIsFull(
        uint8[9] memory board
    ) internal view returns (bool _full) {
        // Default to true. So we need to find and empty spot.
        _full = true;

        for (uint256 i; i < 9; ++i) {
            // If we find an empty spot.
            if (board[i] == 0) {
                // Boards not full.
                return false;
            }
        }
    }

    /**
     * @notice Stage a Coup against the current management!
     *
     * If every other player other than the current manager
     * votes to stage a Coup the current management will be
     * ceremonially removed from office and another player
     * will be chosen at random to take over the duties.
     */
    function stageACoup() external {
        require(players[msg.sender].payed, "!payed");
        require(!players[msg.sender].couped, "already couped");
        require(msg.sender != TokenizedStrategy.management(), "No Suicide");

        // Add another soldier to the firing line
        couped++;
        players[msg.sender].couped = true;

        // If the full tribe has spoken.
        if (couped == playerList.length - 1) {
            // Remove the current manager and choose a new one at random.
            address newManagement = playerList[
                uint256(keccak256(abi.encodePacked(block.timestamp))) %
                    playerList.length
            ];
            if (newManagement == TokenizedStrategy.management()) {
                // New boss can't be the same as the old boss.
                newManagement = playerList[
                    (uint256(keccak256(abi.encodePacked(block.timestamp))) -
                        1) % playerList.length
                ];
            }

            require(players[newManagement].payed, "Oopsie");

            // Set your new Dictator.
            _strategyStorage().management = newManagement;

            // Reset `couped` in case it doesn't work out with the new guy.
            couped = 0;

            // Give everyone a fresh start.
            address[] memory _playerList = playerList;
            uint256 numPlayers = _playerList.length;
            for (uint256 i; i < numPlayers; ++i) {
                address _player = _playerList[i];

                // You would never have done that to Jimmy.
                players[_player].couped = false;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function deposit(
        uint256 assets,
        address receiver
    ) external returns (uint256 shares) {
        require(players[receiver].activated, "!activated");
        require(!players[receiver].payed, "Already payed");
        require(assets == buyIn, "Wrong amount");

        (bool success, bytes memory result) = tokenizedStrategyAddress
            .delegatecall(
                abi.encodeWithSignature(
                    "deposit(uint256,address)",
                    assets,
                    receiver
                )
            );

        if (!success) {
            assembly {
                let ptr := mload(0x40)
                let size := returndatasize()
                returndatacopy(ptr, 0, size)
                revert(ptr, size)
            }
        }

        players[receiver].payed = true;
        playerList.push(receiver);

        return abi.decode(result, (uint256));
    }

    // Dont mint, cause I dont want to have to rewrite all the deposit code.
    function mint(
        uint256 shares,
        address receiver
    ) external returns (uint256 assets) {
        revert("Must Deposit");
    }

    // Dont allow transfers so we can burn the shares of the losers
    function transfer(address to, uint256 amount) external returns (bool) {
        revert("NO GIVE BACKS!");
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public returns (bool) {
        revert("Nice Try");
    }
}
