// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./fair-launch-uniswap-v2.sol";
import "./access/Governable.sol";

contract TokenFactory is Governable {
    uint256 public _tokenDeployedCount;
    mapping(uint256 => FairLaunchToken) public _tokensDeployed;
    mapping(bytes32 => bool) public deployedSymbols;

    address public tokenLauncher;
    address public feeDao;
    address public uniswapRouter;
    address public uniswapFactory;
    uint256 public platformFeePercent = 25;	// 25/1000 = 2.5%

    uint256 public buyFeePercentMax = 50;	// 50/1000 = 5%
    uint256 public sellFeePercentMax = 0;	// 0/1000 = 0%
    uint256 public percentMaxReservedForMining = 100;	// 10/1000 = 10%

    event TokenDeployed(uint256 id, address indexed token, address deployedBy, uint256 deployTime);

    constructor(address _launcher, address _feeDao, address _uniswapRouter, address _uniswapFactory) {
        tokenLauncher = _launcher;
        feeDao = _feeDao;
        uniswapRouter = _uniswapRouter;
        uniswapFactory = _uniswapFactory;
  	}

    function deployToken(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
    	uint256 _pricePerUnit,
        uint256 _amountPerUnit,
        uint256 _eachAddressLimitEthers,
        uint256 _buyTotalFees,
    	uint256 _sellTotalFees,
        uint256 _percentReservedForMining
  	) external returns (address) {
        bytes32 symbolEncoded = keccak256(abi.encodePacked(_symbol));
        require(deployedSymbols[symbolEncoded] == false, "symbol already deployed");
        require(_buyTotalFees <= buyFeePercentMax, "buy fee percent too large!");
        require(_sellTotalFees <= sellFeePercentMax, "sell fee percent too large!");
        require(_percentReservedForMining <= percentMaxReservedForMining, "token reserved for mining too large!");

        deployedSymbols[symbolEncoded] = true;
        uint256 id = _tokenDeployedCount++;
        _tokensDeployed[id] = new FairLaunchToken(_name, _symbol, _totalSupply, _pricePerUnit, _amountPerUnit, _eachAddressLimitEthers, 
													_buyTotalFees, _sellTotalFees, _percentReservedForMining, address(this), uniswapRouter, uniswapFactory);
        address tokenAddress = address(_tokensDeployed[id]);
        //console.log("tokenAddress: ", tokenAddress);

        emit TokenDeployed(id, tokenAddress, msg.sender, block.timestamp);
        return tokenAddress;
    }

    function setTokenLauncher(address _launcher) external onlyGov {
        require(_launcher != address(0x0), "invalid");
        tokenLauncher = _launcher;
    }

    function setFeeDao(address _dao) external onlyGov {
        require(_dao != address(0x0), "invalid");
        feeDao = _dao;
    }

    function setUniswapRouter(address _uniswapRouter) external onlyGov {
        require(_uniswapRouter != address(0x0), "invalid");
        uniswapRouter = _uniswapRouter;
    }

    function setUniswapFactory(address _uniswapFactory) external onlyGov {
        require(_uniswapFactory != address(0x0), "invalid");
        uniswapFactory = _uniswapFactory;
    }

    function setPlatformFeePercent(uint256 _platformFeePercent) external onlyGov {
        platformFeePercent = _platformFeePercent;
    }

    function setBuyFeePercentMax(uint256 _buyFeePercentMax) external onlyGov {
        buyFeePercentMax = _buyFeePercentMax;
    }

    function setSellFeePercentMax(uint256 _sellFeePercentMax) external onlyGov {
        sellFeePercentMax = _sellFeePercentMax;
    }

    function setPercentMaxReservedForMining(uint256 _percentMaxReservedForMining) external onlyGov {
        percentMaxReservedForMining = _percentMaxReservedForMining;
    }

    function tokenDeployedCount() external view returns (uint256) {
        return _tokenDeployedCount;
    }
}
