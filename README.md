# Tokenized Fantasy Pot

This repo contains the code and instructions to use deploy your own Fantasy Pot to use for the 2023-2024 Fantasy Football season.

This pot is built as a Yearn V3 "Tokenized Strategy". For more information on the Tokenized Strategy please visit the [TokenizedStrategy Repo](https://github.com/yearn/tokenized-strategy).


## Deployment

The Factory is deployed on Polygon at :

You can deploy your own Pot either on PolygonScan or through a script by calling 

    factory.newFantasyPot(_asset, "Name for your pot", _buyIn)
    
    // NOTE: You can also specify start and stop times for your pot.
    factory.newFantasyPot(_asset, "Name for your pot", _buyIn, _startTimestamp, _stopTimestamp)

Where `asset` is the ERC20 token to use for the buy in that has a corresponding Aave market. and `_buyIn` is the amount denominated in `asset` that is required to buy in to the pot.

## Setup

Once deployed the address that deployed will need to call `newPot.acceptManagement()` to take over the management role.

The manager will then need to active each players address who will take part in the league pot.

    fantasyPot.acitvatePlayer(addressOfPlayer)
    
Once activated the player will need to call the ERC-4626 compliant 'Deposit' with the specified `buyIn` as the amount.

NOTE: Deposits are shut off after the `start` timestamp and are not possible to turn back on!!!

### Games
Once the season starts the funds are locked till the `end`. But will earn yield the whole period.

During the season players are able to challenge each other to games of [Tic Tac Toe](https://github.com/Schlagonia/fantasy-pot/blob/master/src/FantasyPot.sol#L329-L347). The winner earns the losers reward minus a 10% cut to increase the overall final pot.

Or if the manager is no longer trusted players can [Stage a Coup](https://github.com/Schlagonia/fantasy-pot/blob/master/src/FantasyPot.sol#L537-L575) to take over the management position before the end of the season.

### Declaring a Winner

At the end of the season once `end` has passed the Pots `management` can call:

    fantasyPot.winnerWinnerChickenDinner( winnersAddress )

This will declare the address passes in as the winner, burning all other players shares as well as recording the full profit accrued since the start of the season.

The 'winner' will now be able to withdraw the full amount of the pot.


#### Contract Verification

Once the Fantasy Pot is fully deployed, you will need to verify the TokenizedStrategy functions. To do this, navigate to the /#code page on Etherscan.

1. Click on the `More Options` drop-down menu
2. Click "is this a proxy?"
3. Click the "Verify" button
4. Click "Save"

This should add all of the external `TokenizedStrategy` functions to the contract interface on Etherscan.

