// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract UniswapV2 is Ownable {
    using SafeERC20 for IERC20;

    //Address is taken from https://docs.uniswap.org/protocol/V2/reference/smart-contracts/router-02#:~:text=Address,was%20built%20from%20commit%206961711.
    address private factoryAddress;
    address private routerAddress;
    address private wethAddress;

    event AddLiquidity(address indexed from, uint256 amountA, uint256 amountB, uint256 liquidity);
    event RemoveLiquidity(uint256 amountA, uint256 amountB);
    event SwapTokens(address indexed from, uint256 amountIn, address indexed to);

    constructor(address _factoryAddress, address _routerAddress, address _wethAddress){
        factoryAddress = _factoryAddress;
        routerAddress = _routerAddress;
        wethAddress = _wethAddress;
    }

    function setFactory(address _factoryAddress) external onlyOwner {
        factoryAddress = _factoryAddress;
    }

    function setRouter(address _routerAddress) external onlyOwner {
        routerAddress = _routerAddress;
    }

    //Adds the liquidity
    function addLiquidity(address _tokenA, address _tokenB, uint256 _amountA, uint256 _amountB) external onlyOwner {
        require(IERC20(_tokenA).transferFrom(msg.sender, address(this), _amountA), "transfer failed for TokenA");
        require(IERC20(_tokenB).transferFrom(msg.sender, address(this), _amountB), "transfer failed for TokenB");

        require(IERC20(_tokenA).approve(address(routerAddress), _amountA), "approve failed to router for tokenA");
        require(IERC20(_tokenB).approve(address(routerAddress), _amountB), "approved failed to router for tokenB");

        (uint amountA, uint amountB, uint liquidity) = IUniswapV2Router02(routerAddress).addLiquidity(_tokenA, _tokenB, _amountA, _amountB, 1, 1, address(this), block.timestamp);
        emit AddLiquidity(msg.sender, amountA, amountB, liquidity);
    }

    //Remove the liquidity
    function removeLiquidity(address _tokenA, address _tokenB) external onlyOwner {
        address pair = IUniswapV2Factory(factoryAddress).getPair(_tokenA, _tokenB);
        uint256 liquidity = IERC20(pair).balanceOf(address(this));
        IERC20(pair).approve(routerAddress, liquidity);

        (uint256 amountA, uint256 amountB) = IUniswapV2Router02(routerAddress).removeLiquidity(_tokenA, _tokenB, liquidity, 1, 1, address(this), block.timestamp);
        emit RemoveLiquidity(amountA, amountB);
    }

    //this swap function is used to trade from one token to another
    //the inputs are self explainatory
    //_tokenIn = the token address you want to trade out of
    //_tokenOut = the token address you want as the output of this trade
    //_amountIn = the amount of tokens you are sending in
    //to = the address you want the tokens to be sent to
    function swap(address _tokenIn, address _tokenOut, uint256 _amountIn, address _to) external onlyOwner {
        require(_tokenIn != address(0), "in token address can not be zero");
        require(_tokenOut != address(0), "out token address can not be zero");
        require(_amountIn > 0, "amount in can not be zero");
        require(_to != address(0), "address to send the tokens can not be zero");

        // transfer the amount in tokens from msg.sender to this contract
        require(IERC20(_tokenIn).transferFrom(msg.sender, address(this), _amountIn), "transfer failed for the token");

        //by calling IERC20 approve you allow the uniswap contract to spend the tokens in this contract
        require(IERC20(_tokenIn).approve(routerAddress, _amountIn), "approved failed for router");

        //path is an array of addresses.
        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;

        IUniswapV2Router02(routerAddress).swapExactTokensForTokens(_amountIn, 1, path, _to, block.timestamp);
        emit SwapTokens(msg.sender, _amountIn, _to);
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(_account, _amount);
    }
}
