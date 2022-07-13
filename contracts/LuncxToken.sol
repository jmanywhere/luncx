// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "../interfaces/IUniswapV2Router02.sol";
import "../interfaces/IUniswapV2Factory.sol";
import "./LUNCDividendTracker.sol";

contract LuncxToken is Ownable, ERC20 {
    // Fee Percentages
    uint256 public burnFee;
    uint256 public luncFee;
    uint256 public marketingFee;
    uint256 public constant minSwap = 10_000 ether;
    // Global amounts held
    uint256 public burnAmount;
    uint256 public rewardsAmount;
    uint256 public marketingAmount;
    // Global amounts sent
    uint public marketingBnb;
    uint public lunaBurned;
    uint public lunaRewarded;
    // use by default 300,000 gas to process auto-claiming dividends
    uint256 public gasForProcessing = 300_000;
    // Constants
    uint256 public constant DIVISOR = 1_000;
    // Lock for swaps happening
    bool public swapping;
    address public marketingAddress;
    address public constant deadWallet =
        0x000000000000000000000000000000000000dEaD;

    address public immutable LUNC = address(0x156ab3346823B651294766e23e6Cf87254d68962);
    address public immutable dev = address(0xdB70A0771a1d070FeDFe781f8f156b09CA3feEa6);

    uint256 public endAntiDump;

    // Router
    IUniswapV2Router02 public uniswapV2Router;
    LUNCDividendTracker public dividendToken;

    mapping(address => bool) public feeExcluded;
    mapping(address => bool) public blacklist;

    event LogEvent(string data);
    event AddedPair(address indexed _pair);

    event ExcludeFromFees(address indexed account, bool isExcluded);
    event ExcludeMultipleAccountsFromFees(address[] accounts, bool isExcluded);

    event GasForProcessingUpdated(
        uint256 indexed newValue,
        uint256 indexed oldValue
    );

    event UpdatedFees(
        uint256 _burn,
        uint256 _reward,
        uint256 _marketing
    );
    event UpdateDividendTracker(
        address indexed newAddress,
        address indexed oldAddress
    );
    event UpdateMarketing(address _new, address _old);
    event UpdateUniswapV2Router(
        address indexed newAddress,
        address indexed oldAddress
    );
    event ProcessedDividendTracker(
        uint256 iterations,
        uint256 claims,
        uint256 lastProcessedIndex,
        bool indexed automatic,
        uint256 gas,
        address indexed processor
    );

    constructor(address _marketing) ERC20("LUNCX", "LUNCX") {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
            0x10ED43C718714eb63d5aA57B78B54704E256024E
        );
        address _swapPair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
        uniswapV2Router = _uniswapV2Router;


        burnFee = 30;
        luncFee = 30;
        marketingFee = 30;

        marketingAddress = _marketing;

        dividendToken = new LUNCDividendTracker();
        dividendToken.excludeFromDividends(_swapPair);
        dividendToken.excludeFromDividends(address(dividendToken));
        dividendToken.excludeFromDividends(dev);
        dividendToken.excludeFromDividends(deadWallet);
        dividendToken.excludeFromDividends(address(this));
        dividendToken.excludeFromDividends(address(0));
        dividendToken.excludeFromDividends(address(uniswapV2Router));

        excludeFromFees(dev, true);
        excludeFromFees(marketingAddress, true);
        excludeFromFees(address(this), true);
        _mint(dev, 100_000_000_000 ether); // 100 BILLION TOKENS TO OWNER
        transferOwnership(dev);
    }

    receive() external payable {}

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        uint256 currentBalance = balanceOf(address(this));
        bool canSwap = currentBalance >= minSwap;
        if (
            canSwap &&
            !swapping &&
            from != owner() &&
            to != owner()
        ) {
            swapping = true;
            swapRewardsAndDistribute(currentBalance);
            swapping = false;
        }
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        try dividendToken.setBalance(from, balanceOf(from)) {} catch {}
        try dividendToken.setBalance(to, balanceOf(to)) {} catch {}

        if (!swapping) {
            uint256 gas = gasForProcessing;

            try dividendToken.process(gas) returns (
                uint256 iterations,
                uint256 claims,
                uint256 lastProcessedIndex
            ) {
                emit ProcessedDividendTracker(
                    iterations,
                    claims,
                    lastProcessedIndex,
                    true,
                    gas,
                    tx.origin
                );
            } catch {}
        }
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(!blacklist[from] && !blacklist[to], "Blacklisted address");
        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }
        // TRY TO TAX ONLY SELLS AND BUYS THIS ALSO TAXES ADDING LIQUIDITY UNFORTUNATELY.
        // THERE'S NO WAY AROUND THIS UNLESS LIQUIDITY IS ADDED MANUALLY (NOT RECOMMENDED)
        if (!feeExcluded[from] && !swapping) {
                uint toBurn;
                uint toReward;
                uint toMarketing;
                (amount, toBurn, toReward, toMarketing) = taxAmount(amount);
                super._transfer(
                    from,
                    address(this),
                    toBurn + toReward + toMarketing
                );
                burnAmount += toBurn;
                rewardsAmount += toReward;
                marketingAmount += toMarketing;
        }
        super._transfer(from, to, amount);
    }

    function taxes() external view returns(uint _tax){
        _tax = burnFee + luncFee + marketingFee;
    }

    function taxAmount(uint256 amount)
        private
        view
        returns (
            uint256 _newAmount,
            uint256 _burn,
            uint256 _reward,
            uint256 _marketing
        )
    {
        if(block.timestamp <= endAntiDump){
            _burn = (100 * amount) / DIVISOR;
            _reward = (200 * amount) / DIVISOR;
            _marketing = (200 * amount) / DIVISOR;
            uint256 totalFee = _burn + _reward + _marketing;
            _newAmount = amount - totalFee;
        }
        else{
            _burn = (burnFee * amount) / DIVISOR;
            _reward = (luncFee * amount) / DIVISOR;
            _marketing = (marketingFee * amount) / DIVISOR;
            uint256 totalFee = _burn + _reward + _marketing;
            _newAmount = amount - totalFee;
        }
    }

    //PLEASE CHANGE BACK TO PRIVATE#3
    function swapRewardsAndDistribute(uint currentBalance) internal {
        swapForEth(currentBalance);
        
        uint ethMarketing = address(this).balance * marketingAmount / (marketingAmount + burnAmount + rewardsAmount);
        
        bool txSuccess = false;
        if(ethMarketing > 0){
            (txSuccess, ) = payable(marketingAddress).call{value: ethMarketing}("");
            if (txSuccess) {
                marketingAmount = 0;
                txSuccess = false;
                marketingBnb += ethMarketing;
            }
        }
        swapForLUNA();

        uint lunaBalance = ERC20(LUNC).balanceOf(address(this));
        uint rewardLuna = lunaBalance * rewardsAmount / (burnAmount + rewardsAmount);
        //sendToDividends( balances[0]);
        if (rewardLuna > 0) {
            txSuccess = ERC20(LUNC).transfer(address(dividendToken), rewardLuna);
            if (txSuccess) {
                dividendToken.distributeDividends(rewardLuna);
                rewardsAmount = 0;
                lunaRewarded += rewardLuna;
                txSuccess = false;
            }
        }
        
        lunaBalance -= rewardLuna;
        if(lunaBalance > 0){
            txSuccess = ERC20(LUNC).transfer(deadWallet, lunaBalance);
            if(txSuccess){
                burnAmount = 0;
                lunaBurned += lunaBalance;
            }
        }
    }

    //PLEASE CHANGE BACK TO PRIVATE#1
    function swapForEth(uint256 amount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), amount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }
    function swapForLUNA() private {
        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = LUNC;

        // make the swap
        uniswapV2Router.swapExactETHForTokens{value: address(this).balance}(
            0, // get all the LUNC we can
            path,
            address(this),
            block.timestamp
        );
    }

    //PLEASE CHANGE BACK TO PRIVATE#2
    function getPercentages(
        uint256[4] memory percentages,
        uint256 base,
        uint256 multiplier
    ) private pure returns (uint256[4] memory _finalValues) {
        for (uint8 i = 0; i < percentages.length; i++) {
            _finalValues[i] = (percentages[i] * multiplier) / base;
        }
    }

    function setFees(
        uint256 _burn,
        uint256 _reward,
        uint256 _marketing
    ) external onlyOwner {
        require(_burn + _reward + _marketing <= 500, "High fees");
        burnFee = _burn;
        luncFee = _reward;
        marketingFee = _marketing;
        emit UpdatedFees(_burn, _reward, _marketing);
    }

    function setMarketingWallet(address _marketingWallet)
        external
        onlyOwner
    {
        require(_marketingWallet != address(0), "use Marketing");
        emit UpdateMarketing(_marketingWallet, marketingAddress);
        marketingAddress = _marketingWallet;
    }

    function claim() external {
        dividendToken.processAccount(msg.sender, false);
    }

    /// @notice Updates the dividend tracker's address
    /// @param newAddress New dividend tracker address
    function updateDividendTracker(address newAddress) public onlyOwner {
        require(
            newAddress != address(dividendToken),
            "LUNCX: The dividend tracker already has that address"
        );

        LUNCDividendTracker newDividendToken = LUNCDividendTracker(
            newAddress
        );

        require(
            newDividendToken.owner() == address(this),
            "LUNCX: The new dividend tracker must be owned by the deployer of the contract"
        );

        newDividendToken.excludeFromDividends(address(newDividendToken));
        newDividendToken.excludeFromDividends(address(this));
        newDividendToken.excludeFromDividends(owner());
        newDividendToken.excludeFromDividends(address(uniswapV2Router));

        emit UpdateDividendTracker(newAddress, address(dividendToken));

        dividendToken = newDividendToken;
    }

    /// @notice Updates the uniswapV2Router's address
    /// @param newAddress New uniswapV2Router's address
    function updateUniswapV2Router(address newAddress) public onlyOwner {
        require(
            newAddress != address(uniswapV2Router),
            "LUNCX: The router already has that address"
        );
        emit UpdateUniswapV2Router(newAddress, address(uniswapV2Router));
        uniswapV2Router = IUniswapV2Router02(newAddress);
    }

    /// @notice Excludes address from fees
    /// @param account New uniswapV2Router's address
    /// @param excluded True if excluded
    function excludeFromFees(address account, bool excluded) public onlyOwner {
        require(
            feeExcluded[account] != excluded,
            "LUNCX: Account is already the value of 'excluded'"
        );
        feeExcluded[account] = excluded;

        emit ExcludeFromFees(account, excluded);
    }

    /// @notice Excludes multiple accounts from fees
    /// @param accounts Array of accounts to be excluded
    /// @param excluded True if excluded
    function excludeMultipleAccountsFromFees(
        address[] calldata accounts,
        bool excluded
    ) public onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            feeExcluded[accounts[i]] = excluded;
        }

        emit ExcludeMultipleAccountsFromFees(accounts, excluded);
    }

    /// @notice Includes address in the blacklist
    /// @param account Array of accounts to be excluded
    /// @param value True if excluded
    function blacklistAddress(address account, bool value) external onlyOwner {
        blacklist[account] = value;
    }

    /// @notice Updates gas amount for processing
    /// @param newValue New gas value
    function updateGasForProcessing(uint256 newValue) public onlyOwner {
        require(
            newValue >= 200000 && newValue <= 500000,
            "LUNCX: gasForProcessing must be between 200,000 and 500,000"
        );
        require(
            newValue != gasForProcessing,
            "LUNCX: Cannot update gasForProcessing to same value"
        );
        emit GasForProcessingUpdated(newValue, gasForProcessing);
        gasForProcessing = newValue;
    }

    /// @notice Allows owner to updates time to claim rewards
    /// @param claimWait New claim wait time
    function updateClaimWait(uint256 claimWait) external onlyOwner {
        dividendToken.updateClaimWait(claimWait);
    }

    /// @notice Checks the feeExcluded map to see if the account is excluded from fees
    /// @param account Address to check
    function isExcludedFromFees(address account) public view returns (bool) {
        return feeExcluded[account];
    }

    /// @notice Checks the withdrawable amount of dividends from account
    /// @param account Address to check
    function withdrawableDividendOf(address account)
        public
        view
        returns (uint256)
    {
        return dividendToken.withdrawableDividendOf(account);
    }

    // DIVIDEND SETTERS/GETTERS
    function dividendTokenBalanceOf(address account)
        public
        view
        returns (uint256)
    {
        return dividendToken.balanceOf(account);
    }

    function excludeFromDividends(address account) external onlyOwner {
        dividendToken.excludeFromDividends(account);
    }

    function processDividendTracker(uint256 gas) external {
        (
            uint256 iterations,
            uint256 claims,
            uint256 lastProcessedIndex
        ) = dividendToken.process(gas);
        emit ProcessedDividendTracker(
            iterations,
            claims,
            lastProcessedIndex,
            false,
            gas,
            tx.origin
        );
    }

    function getClaimWait() external view returns (uint256) {
        return dividendToken.claimWait();
    }

    function getTotalDividendsDistributed() external view returns (uint256) {
        return dividendToken.totalDividendsDistributed();
    }

    function getAccountDividendsInfo(address account)
        external
        view
        returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return dividendToken.getAccount(account);
    }

    function getAccountDividendsInfoAtIndex(uint256 index)
        external
        view
        returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return dividendToken.getAccountAtIndex(index);
    }

    function getLastProcessedIndex() external view returns (uint256) {
        return dividendToken.getLastProcessedIndex();
    }

    function getNumberOfDividendTokenHolders() external view returns (uint256) {
        return dividendToken.getNumberOfTokenHolders();
    }

    function startAntiDump() external onlyOwner{
        require(endAntiDump == 0, "Already used");
        endAntiDump = block.timestamp + 4 hours;
        emit LogEvent("Anti dump started");
    }
}