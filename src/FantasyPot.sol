// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {BaseTokenizedStrategy} from "@tokenized-strategy/BaseTokenizedStrategy.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPool} from "./interfaces/Aave/V3/IPool.sol";
import {IAToken} from "./interfaces/Aave/V3/IAtoken.sol";

import {TokenizedHelper} from "./TokenizedHelper.sol";

contract FantasyPot is BaseTokenizedStrategy, TokenizedHelper{
    using SafeERC20 for ERC20;

    struct Player {
        bool registered;
        bool payed;
        bool couped;
    }

    // Aave pool to deposit and withdraw through.
    IPool public constant lendingPool =
        IPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);

    // The token that we get in return for deposits.
    IAToken public immutable aToken;

    // Start of the regular season. 
    // September 7th, 2023 8:20 EST.
    uint256 public constant start = 1694089200;

    // End of regular season. 
    // January 7th, 2024 Midnight EST.
    uint256 public constant end = 1704690000;

    // Winner of the league.
    address public winner;

    // Mapping of a players address to theie Player struct
    mapping (address => Player) public players;

    // List of all players who registerd and payed
    address[] public playerList;

    // Amount required to buy in.
    uint256 public immutable buyIn;

    // Number of players that have couped against
    // The current managment.
    uint256 public couped;

    constructor(
        address _asset,
        string memory _name,
        uint256 _buyIn
    ) BaseTokenizedStrategy(_asset, _name) {
        // Set the aToken based on the asset we are using.
        aToken = IAToken(lendingPool.getReserveData(_asset).aTokenAddress);

        // Make sure its a real token.
        require(address(aToken) != address(0), "no aave pool");

        // Approve the lending pool for cheaper deposits.
        ERC20(_asset).safeApprove(address(lendingPool), type(uint256).max);

        // Set the buy in.
        buyIn = _buyIn;
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
            aToken.balanceOf(address(this)) +
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

        // If the player has been registered but hasn't payed.
        if (players[_owner].registered && !players[_owner].payed) {
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
    function registerNewPlayer(address _player) external onlyManagement {
        require(start > block.timestamp, "season started");
        require(!players[_player].registered, "already registered");

        players[_player].registered = true;
    }

    /**
    * @notice Allows managment to declare a winner!
    *
    * Will burn every other players shares and report the accumulated
    * profits so that the winner can now withdraw the full amount
    * of their winnings.
    *
     */
    function winnerWinnerChickenDinner(address _winner) external onlyManagement {
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
    * @notice Stage a Coup against the current management!
    *
    * If every other player other than the current manager 
    * votes to stage a Coup the current management will be
    * ceremonially removed from office and another player 
    * will be chosen at random to take over the duties.
     */
    function stageACoup() external {
        require(players[msg.sender].registered, "!registered");
        require(players[msg.sender].payed, "!payed");
        require(!players[msg.sender].couped, "already couped");
        require(msg.sender != TokenizedStrategy.management(), "No Suicide");

        // Add another soldier to the firing line
        couped ++;

        // If the full party has spoken.
        if (couped == playerList.length - 1) {
            // Remove the current manager and choose a new one at random.
            address newManagement = playerList[uint256(keccak256(abi.encodePacked(block.timestamp))) % playerList.length];
            if (newManagement == TokenizedStrategy.management()) {
                // New boss cant be the same as the old boss.
                newManagement = playerList[uint256(keccak256(abi.encodePacked(block.timestamp - 1))) % playerList.length];
            }

            // Set your new Dictator.
            _strategyStorage().management == newManagement;

            // Reset `couped` in case it doesn't work out with the new guy
            couped = 0;
        }
    }

    /*//////////////////////////////////////////////////////////////
                        4626 OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function deposit(
        uint256 assets,
        address receiver
    ) external returns (uint256 shares) {
        require(players[receiver].registered, "!registered");
        require(!players[receiver].payed, "Already payed");
        require(assets == buyIn, "Wrong amount");

        (bool success, bytes memory result) = tokenizedStrategyAddress.
            delegatecall(
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
        require(false, "Must Deposit");
    }

    // Dont allow transfers so we can burn the shares of the losers
    function transfer(address to, uint256 amount) external returns (bool) {
        require(false, "NO GIVE BACKS!");
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public returns (bool) {
        require(false, "Nice Try");
    }
}
