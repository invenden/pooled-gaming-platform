pragma solidity ^0.5.10;

import './Address.sol';
import './ITRC20.sol';
import './PGPGame.sol';
import './ProposalPlatform.sol';
import './SafeMath.sol';

contract PooledGamePlatform is ProposalPlatform {
    using SafeMath for uint256;
    using Address for address;

    struct Player {
        uint shares;
        address referredBy;
    }

    struct Game {
        uint proposalId;
        address gameAddress;
        address tokenAddress;
        uint endsOn;
        bool running;
        mapping(address=>Player) players;
        uint numPlayers;
        address[] _players;
    }

    mapping(address=>Game) public games; // mapped by the game's tokenAddress
    uint constant WAITING_PERIOD = 2 days;

    constructor(address pgpToken) ProposalPlatform(pgpToken) public {
    }

    //// PLAYER FUNCTIONS ////
    function deposit(address tokenAddress, uint amount, address referredBy) noContracts onlyDuringGame(tokenAddress) public returns (uint) {
        require(amount > 0, "Cannot purchase 0 tokens.");
        Game storage game = games[tokenAddress];
        Player storage player = game.players[_msgSender()];
        if (player.referredBy == address(0)) { // new player
            player.referredBy = referredBy != address(0) && referredBy != _msgSender() ? referredBy : owner;
        }

        if (player.shares == 0) {
            // recycle array instead of actually deleting to conserve energy
            if (game._players.length == game.numPlayers) {
                game._players.length += 1;
            }
            game._players[game.numPlayers++] = _msgSender();
        }

        ITRC20 trc20 = ITRC20(game.tokenAddress);
        require(trc20.transferFrom(_msgSender(), address(this), amount));
        uint netAmount = extractFees(game, amount, true);
        player.shares = player.shares.add(netAmount);
        return player.shares;
    }

    function withdraw(address tokenAddress) onlyDuringGame(tokenAddress) onlyActivePlayers(tokenAddress) public returns (uint) {
        Game storage game = games[tokenAddress];
        Player storage player = game.players[_msgSender()];
        uint shares = extractFees(game, player.shares, false);
        ITRC20 trc20 = ITRC20(tokenAddress);
        uint toWithdraw = shares > trc20.balanceOf(address(this)) ? trc20.balanceOf(address(this)) : shares;
        trc20.transfer(_msgSender(), toWithdraw);
        player.shares = 0;
        return toWithdraw;
    }

    function claim(address tokenAddress) onlyBetweenGames(tokenAddress) onlyActivePlayers(tokenAddress) public returns (uint) {
        return _claim(tokenAddress, _msgSender());
    }

    function _claim(address tokenAddress, address receiver) internal returns (uint) {
        Player storage player = games[tokenAddress].players[receiver];
        ITRC20 trc20 = ITRC20(tokenAddress);
        uint shares = player.shares > trc20.balanceOf(address(this)) ? trc20.balanceOf(address(this)) : player.shares;
        trc20.transfer(receiver, shares);
        player.shares = 0;
        return shares;
    }

    function claimableShares(address tokenAddress) public view returns (uint) {
        return games[tokenAddress].players[_msgSender()].shares;
    }

    function sellableShares(address tokenAddress) public view returns (uint) {
        return games[tokenAddress].players[_msgSender()].shares.percentage(90); // total 10% fee will be applied if player sells.
    }

    function addToGame(address tokenAddress, uint amount) onlyDuringGame(tokenAddress) public {
        payPool(games[tokenAddress], amount);
    }

    function getRegisteredGame(address tokenAddress) public view returns (address gameAddress, uint endsOn, uint numPlayers) {
        Game storage game = games[tokenAddress];
        return (game.gameAddress, game.endsOn, game.numPlayers);
    }

    //// ADMIN FUNCTIONS ////
    function startGame(address tokenAddress, uint daysToRun) onlyAdmins onlyBetweenGames(tokenAddress) public {
        Game storage game = games[tokenAddress];
        require(block.timestamp >= game.endsOn + WAITING_PERIOD, "A new game cannot begin until players have had enough time to collect their earnings from the last game.");
        require(daysToRun > 0, "Cannot run a game for 0 days.");
        game.endsOn = block.timestamp.add(daysToRun.mul(1 days));
        game.running = true;
        ITRC20 trc20 = ITRC20(game.tokenAddress);
        uint seed = trc20.balanceOf(address(this));

        payPool(game, seed);

        for (uint i=0; i<game.numPlayers; i++) {
            game.players[game._players[i]].shares = 0;
        }
        game.numPlayers = 1;
        game._players[0] = owner;
    }

    function endGame(address tokenAddress) onlyAdmins onlyDuringGame(tokenAddress) public {
        Game storage game = games[tokenAddress];
        game.endsOn = block.timestamp;
        game.running = false;

        // Owner is always a player, but never a winner.
        _claim(tokenAddress, owner);

        PGPGame gameContract = PGPGame(game.gameAddress);
        uint claimedRewards = gameContract.claim();

        payDividends(game, owner, claimedRewards);
    }

    function registerGame(address gameAddress) onlyAdmins public {
        PGPGame gameContract = PGPGame(gameAddress);
        address tokenAddress = gameContract.tokenAddress();
        Game storage game = games[tokenAddress];
        
        require(!game.running, "A game is currently running.");
        game.gameAddress = gameAddress;
        game.tokenAddress = tokenAddress;
    }

    function collectDivs(address tokenAddress) onlyDuringGame(tokenAddress) public {
        Game storage game = games[tokenAddress];
        PGPGame gameContract = PGPGame(game.gameAddress);
        uint divs = gameContract.withdraw();
        payDividends(game, address(0), divs);
    }

    //// INTERNAL ////
    function extractFees(Game storage game, uint amount, bool shouldPayReferrer) internal returns (uint) {
        uint toPool = amount.percentage(4);
        uint toDivs = amount.percentage(4);
        uint toReferral = amount.percentage(2);

        if (shouldPayReferrer) {
            payReferral(game, game.players[_msgSender()].referredBy, toReferral);
        } else {
            toPool = toPool.add(toReferral);
            toReferral = 0;
        }

        payPool(game, toPool);
        payDividends(game, _msgSender(), toDivs);

        uint netAmount = amount.sub(toPool).sub(toDivs).sub(toReferral);

        return netAmount;
    }

    function payDividends(Game storage game, address exclude, uint dividends) internal {
        ITRC20 trc20 = ITRC20(game.tokenAddress);
        uint balance = trc20.balanceOf(address(this)).sub(dividends).sub(game.players[exclude].shares);

        for (uint i=0; i< game.numPlayers; i++) {
            if(game._players[i] == exclude) continue;

            Player storage player = game.players[game._players[i]];
            uint newShares = player.shares.div(balance).mul(dividends);
            player.shares = player.shares.add(newShares);
        }
    }

    function payPool(Game storage game, uint amount) internal {
        PGPGame gameContract = PGPGame(game.gameAddress);
        gameContract.deposit(amount);
    }

    function payReferral(Game storage game, address referrer, uint amount) internal {
        if (game.players[referrer].shares > 0) {
            payPlayer(game, referrer, amount);
        } else {
            payPlayer(game, owner, amount);
        }
    }

    function payPlayer(Game storage game, address player, uint amount) internal {
        game.players[player].shares = game.players[player].shares.add(amount);
    }

    //// MODIFIERS ////
    modifier onlyActivePlayers(address tokenAddress) {
        require(games[tokenAddress].players[_msgSender()].shares > 0, "You are not eligible.");
        _;
    }

    modifier onlyDuringGame(address tokenAddress) {
        require(games[tokenAddress].gameAddress != address(0), "There are no games for this token.");
        require(games[tokenAddress].running, "A game is not running.");
        _;
    }

    modifier onlyBetweenGames(address tokenAddress) {
        require(games[tokenAddress].gameAddress != address(0), "There are no games for this token.");
        require(!games[tokenAddress].running, "A game is currently running.");
        _;
    }
    
    modifier noContracts() {
        require(!Address.isContract(_msgSender()), "Contracts cannot play.");
        _;
    }
}
