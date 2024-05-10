// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ERC20.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";
//import "hardhat/console.sol";

interface IUniswapV2Router01 {
    function WETH() external pure returns (address);

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    )
        external
        payable
        returns (uint amountToken, uint amountETH, uint liquidity);
}

interface IUniswapV2Factory {
    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair);
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
}

interface ITokenFactory {
    function tokenLauncher() external view returns (address);
    function feeDao() external view returns (address);
    function platformFeePercent() external view returns (uint256);
}

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
}

contract FairLaunchToken is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    uint256 public price;
    uint256 public amountPerUnits;

    uint256 public amountReservedForMining;
    uint256 public percentReservedForMining;    //base is 1000. for example 10, 10/1000=1%

    uint256 public mintLimit;
    uint256 public minted;

    bool public started;
    address public tokenFactory;
    address public uniswapRouter;
    address public uniswapFactory;

    uint256 public eachAddressLimitEthers;
    uint256 public buyTotalFees;
    uint256 public sellTotalFees;
    uint256 public platformFeePercent;

    mapping(address => bool) public ammPairs;
    mapping(address => bool) private _isExcludedFromFees;

    event FairMinted(address indexed to, uint256 amount, uint256 ethAmount);
    event RefundEvent(address indexed from, uint256 amount, uint256 ethAmount);
    event LaunchEvent(address indexed token, address pair_address, uint256 amount, uint256 ethAmount, uint256 liquidity, uint256 platformFee);

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        uint256 _price,
        uint256 _amountPerUnits,
        uint256 _eachAddressLimitEthers,
        uint256 _buyTotalFees,
        uint256 _sellTotalFees,
        uint256 _percentReservedForMining,
        address _tokenFactory,
        address _uniswapRouter,
        address _uniswapFactory
    ) ERC20(_name, _symbol) {
        price = _price;
        amountPerUnits = _amountPerUnits;
        started = false;
        _mint(address(this), _totalSupply);

        percentReservedForMining = _percentReservedForMining;
        amountReservedForMining = calcAmountReservedForMining(_totalSupply, amountPerUnits, percentReservedForMining);

        //50% for fair mint
        mintLimit = (_totalSupply - amountReservedForMining) / 2;

        eachAddressLimitEthers = _eachAddressLimitEthers;
        buyTotalFees = _buyTotalFees;
        sellTotalFees = _sellTotalFees;

        tokenFactory = _tokenFactory;
        uniswapRouter = _uniswapRouter;
        uniswapFactory = _uniswapFactory;
        platformFeePercent = ITokenFactory(tokenFactory).platformFeePercent();
        transferMiningReserveToTokenManager(amountReservedForMining);
    }

    receive() external payable {
        if (msg.value == 0.0001 ether && !started) {
            if (minted == mintLimit) {
                start();
            } else {
                //before reach mintLimit, the project community can vote to start anyway.
                address launcher = getLauncher();
                require(msg.sender == launcher, "only launcher can start");
                start();
            }
        } else {
            mint();
        }
    }

    function getAvailableUnits() public view returns (uint256) {
        if (minted >= mintLimit) {
            return 0;
        }

        uint256 availAmount = mintLimit - minted;
        return availAmount / amountPerUnits; 
    }

    function mint() virtual internal nonReentrant {
        require(msg.value >= price, "value not match");
        require(!_isContract(msg.sender), "can not mint to contract");
        require(msg.sender == tx.origin, "can not mint to contract.");
        // not start
        require(!started, "trade already started");

        uint256 units = msg.value / price;
        uint256 availMaxUnits = getAvailableUnits();
        if (units > availMaxUnits) {
            units = availMaxUnits;
        }
        uint256 realCost = units * price;
        uint256 refund = msg.value - realCost;

        require(minted + units * amountPerUnits <= mintLimit, "exceed max supply");

        require(
            balanceOf(msg.sender) * price / amountPerUnits  + realCost <= eachAddressLimitEthers,
            "exceed max mint"
        );

        minted += units * amountPerUnits;
        _transfer(address(this), msg.sender, units * amountPerUnits);

        emit FairMinted(msg.sender, units * amountPerUnits, realCost);
        if (refund > 0) {
            payable(msg.sender).transfer(refund);
        }
    }

    function start() internal {
        require(!started, "already started");
        address _weth = IUniswapV2Router01(uniswapRouter).WETH();
        address _pair = IUniswapV2Factory(uniswapFactory).getPair(address(this), _weth);
        if (_pair == address(0)) {
            _pair = IUniswapV2Factory(uniswapFactory).createPair(address(this), _weth);
        }
        _pair = IUniswapV2Factory(uniswapFactory).getPair(address(this), _weth);
        // assert pair exists
        assert(_pair != address(0));

        // set started
        started = true;
        uint256 platformFee = payPlatformFee(_weth);

        // add liquidity
        IUniswapV2Router01 router = IUniswapV2Router01(uniswapRouter);
        uint256 balance = balanceOf(address(this));
        uint256 diff = balance - minted;
        // burn diff
        _burn(address(this), diff);
        _approve(address(this), uniswapRouter, type(uint256).max);
        // add liquidity
        (uint256 tokenAmount, uint256 ethAmount, uint256 liquidity) = router
            .addLiquidityETH{value: address(this).balance}(
            address(this), // token
            minted, // token desired
            minted, // token min
            address(this).balance, // eth min
            address(this), // lp to
            block.timestamp + 1 days // deadline
        );
        _handleLP(_pair);
        ammPairs[_pair] = true;
        emit LaunchEvent(address(this), _pair, tokenAmount, ethAmount, liquidity, platformFee);
    }
                                        
    function _handleLP(address lp) virtual internal {
        // default: drop lp
        IERC20 lpToken = IERC20(lp);
        lpToken.safeTransfer(address(0), lpToken.balanceOf(address(this)));
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20) {
        // if not started, only allow refund
        if (!started) {
            if (to == address(this) && from != address(0)) {
                // refund
            } else {
                // if it is not refund operation, check and revert.
                if (from != address(0) && from != address(this)) {
                    // if it is not INIT action, revert. from address(0) means INIT action. from address(this) means mint action.
                    revert("all tokens are locked until launch.");
                }
            }
        } else {
            if (to == address(this) && from != address(0)) {
                revert(
                    "You can not send token to contract after launched."
                );
            }
        }
        super._update(from, to, value);
        if (to == address(this) && from != address(0)) {
            _refund(from, value);
        }
    }

    function _refund(address from, uint256 value) internal nonReentrant {
        require(!started, "already started");
        require(!_isContract(from), "can not refund to contract");
        require(from == tx.origin, "can not refund to contract.");
        require(value >= amountPerUnits, "value not match");
        require(value % amountPerUnits == 0, "Fvalue not match");

        uint256 _bnb = (value / amountPerUnits) * price;
        require(_bnb > 0, "no refund");

        minted -= value;
        payable(from).transfer(_bnb);
        emit RefundEvent(from, value, _bnb);
    }

    // is contract
    function _isContract(address _addr) internal view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size > 0);
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        //console.log("in _transfer1");
        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        bool takeFee = true;
        // if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        uint256 fees = 0;
        // only take fees on buys/sells, do not take on wallet transfers
        if (started && takeFee) {
            // on sell
            if (ammPairs[to] && sellTotalFees > 0) {
                fees = amount.mul(sellTotalFees).div(1000);
            } else if (ammPairs[from] && buyTotalFees > 0) {
                // on buy
                fees = amount.mul(buyTotalFees).div(1000);
            }

            if (fees > 0) {
                address feeDao = getFeeDao();
                super._transfer(from, feeDao, fees);
            }

            amount -= fees;
        }
        super._transfer(from, to, amount);
    }

    function payPlatformFee(address _weth) internal returns (uint256 platformFee) {
        platformFee = address(this).balance * platformFeePercent / 1000;
        if (platformFee == 0) {
            return 0;
        }
        IWETH(_weth).deposit{value: platformFee}();

        address feeDao = getFeeDao();
        IWETH(_weth).transfer(feeDao, platformFee);
    }

    function calcAmountReservedForMining(uint256 _totalSupply, uint256 _amountPerUnits, uint256 _percentReservedForMining) internal pure returns (uint256) {
        uint256 totalUnits = _totalSupply / _amountPerUnits;
        uint256 percentUnits = totalUnits * _percentReservedForMining / 1000;
        return percentUnits * _amountPerUnits;
    }
    
    function transferMiningReserveToTokenManager(uint256 _amount) internal {
        if (_amount == 0) {
            return;
        }
        address feeDao = getFeeDao();
        _transfer(address(this), feeDao, _amount);
    }

    //helper functions to make contract works well
    modifier onlyLauncher() {
        address launcher = getLauncher();
        require(msg.sender == launcher, "not auth");
        _;
    }

    function setAutomatedMarketMakerPair(address pair, bool value) external onlyLauncher {
        ammPairs[pair] = value;
    }

    function excludeFromFees(address account, bool excluded) external onlyLauncher {
        _isExcludedFromFees[account] = excluded;
    }

    function getLauncher() public view returns (address) {
        ITokenFactory factory = ITokenFactory(tokenFactory);
        return factory.tokenLauncher();
    }

    function getFeeDao() public view returns (address) {
        ITokenFactory factory = ITokenFactory(tokenFactory);
        return factory.feeDao();
    }
}
