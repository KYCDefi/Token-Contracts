pragma solidity 0.6.2;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20Burnable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "openzeppelin-solidity/contracts/utils/Address.sol";

contract KYCDToken is Ownable, ERC20Burnable {

    using Address for address;
    using SafeMath for uint256;

    /// Constant that holds token distribution.
    uint256 constant public MULTIPLIER = 10 ** 18;
    uint256 constant public TEAM_ALLOCATION = 100000 * MULTIPLIER;
    uint256 constant public MARKETING_ALLOCATION = 100000 * MULTIPLIER;
    uint256 constant public REWARDS_ALLOCATION = 300000 * MULTIPLIER;
    uint256 constant public PRESALE_ALLOCATION = 500000 * MULTIPLIER;

    /// Timestamp at which rewards tokens get released. i.e Till Pre Sale runs.
    uint256 public rewardsAllocationReleaseAt;
    /// Timestamp at which mearketing tokens get released. i.e 3 Months after the Pre Sale.
    uint256 public marketingAllocationReleaseAt; 
    /// Timestamp at which team tokens get released. i.e 
    /// Once Presale ends it will lock the tokens for 3 months and after that have a vesting of 1 year
    /// with a cliff of 3 months.
    uint256 public teamAllocationVestingStartAt;

    struct VestingMeta {
        /// Variable to keep track of last period vesting release.
        uint256 lastVestingReleaseTime;
        /// variable to keep track of the already release amount.
        uint256 alreadyReleasedAmount;
    }

    VestingMeta public vestingDetails;

    /// Boolean variable to know whether team tokens are allocated or not.
    bool public isTeamTokensAllocated;
    /// Boolean variable to know whether marketing tokens are allocated or not.
    bool public isMarketingTokensAllocated;
    /// Boolean variable to know whether rewards tokens are allocated or not.
    bool public isRewardsTokensAllocated;
    /// Private variable to switch off the minting.
    bool private _mintingClosed;
    /// Address of the sale contract address.
    address public preSaleContractAddress;
    /// Boolean variable to keep track whether release timings are set or not.
    bool public isReleaseTimingsSet;

    /// Even emitted when tokens get unlocked.
    event TokensUnlocked(address indexed _beneficiary, uint256 _amount);

    /// @dev Contructor to set the token name & symbol.
    ///
    /// @param _tokenName Name of the token.
    /// @param _tokenSymbol Symbol of the token.
    constructor(string memory _tokenName, string memory _tokenSymbol) ERC20(_tokenName, _tokenSymbol) public {
        // Set initial variables
        isTeamTokensAllocated = false;
        isMarketingTokensAllocated = false;
        isRewardsTokensAllocated = false;
        _mintingClosed = false;
        isReleaseTimingsSet = false;
    }

    /// @dev Used to mint initial number of tokens. Called only by the owner of the contract.
    /// This is a one time operation performed by the token issuer.
    ///
    /// @param _saleContractAddress Address of the pre sale contract.
    function initialMint(address _saleContractAddress) public onlyOwner {
        require(!_mintingClosed, "Intital minting closed");
        require(_saleContractAddress.isContract(), "Not a valid contract address");
        // Close the minting.
        _mintingClosed = true;
        // Mint Presale tokens to the sale contract address.
        _mint(_saleContractAddress, PRESALE_ALLOCATION);

        // Mint tokens for locking allocation.
        // Compute total amounts of token. Avoiding SafeMath as values are deterministics.
        uint256 _amount = TEAM_ALLOCATION + MARKETING_ALLOCATION + REWARDS_ALLOCATION;
        _mint(address(this), _amount);
    }

    /// @dev When sale cap is reached it will set the token release timings for different allocations
    /// NB - Can only be called by the pre sale contract address.
    function setReleaseTimings() external {
        require(_msgSender() == preSaleContractAddress, "Un-authorized access");
        require(!isReleaseTimingsSet, "Release timings are already set");
        uint256 currentTime = now;
        uint256 threeMonthsPeriod = currentTime + (3 * 30 days); // 3 months time.
        rewardsAllocationReleaseAt = currentTime;
        marketingAllocationReleaseAt = threeMonthsPeriod;
        teamAllocationVestingStartAt = threeMonthsPeriod;
        vestingDetails.lastVestingReleaseTime = teamAllocationVestingStartAt;
        vestingDetails.alreadyReleasedAmount = uint256(0);
        isReleaseTimingsSet = true;
    }

    /// @dev Used to unlock tokens, Only be called by the contract owner & also received by the owner as well.
    /// It commulate the `releaseAmount` as per the time passed and release the
    /// commulated number of tokens.
    /// e.g - Owner call this function at Monday, 08-Mar-21 10:00:00 UTC
    /// then commulated amount of tokens will be  REWARDS_ALLOCATION + MARKETING_ALLOCATION
    function unlockTokens() external onlyOwner {
        uint256 currentTime = now;
        uint256 releaseAmount = 0;
        if (!isRewardsTokensAllocated && currentTime >= rewardsAllocationReleaseAt) {
            releaseAmount = REWARDS_ALLOCATION;
            isRewardsTokensAllocated = true;
        }
        if (!isMarketingTokensAllocated && currentTime >= marketingAllocationReleaseAt) {
            releaseAmount += MARKETING_ALLOCATION;
            isMarketingTokensAllocated = true;
        }
        if (!isTeamTokensAllocated && currentTime >= teamAllocationVestingStartAt)  {
            releaseAmount += _getTeamTokenReleaseAmount();
        }
        require(releaseAmount > 0, "Tokens are locked");
        // Transfer funds to owner.
        _transfer(address(this), _msgSender(), releaseAmount);
        emit TokensUnlocked(_msgSender(), releaseAmount);
    }

    function _getTeamTokenReleaseAmount() internal returns(uint256 releasedAmount) {
        if (vestingDetails.alreadyReleasedAmount == TEAM_ALLOCATION) {
            isTeamTokensAllocated = true;
            return 0;
        } else {
            uint256 currentTime = now;
            uint256 noOfPeriods = currentTime.sub(vestingDetails.lastVestingReleaseTime) / (3 * 30 days);
            releasedAmount = TEAM_ALLOCATION.div(noOfPeriods);
            vestingDetails.lastVestingReleaseTime = currentTime;
            vestingDetails.alreadyReleasedAmount += releasedAmount;
        }
        
    }

}