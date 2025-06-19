// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract Project {
    // Market structure
    struct Market {
        uint256 id;
        string question;
        string[] outcomes;
        uint256 endTime;
        uint256 totalPool;
        bool resolved;
        uint256 winningOutcome;
        address creator;
        mapping(uint256 => uint256) outcomePools; // outcome index => total bet amount
        mapping(address => mapping(uint256 => uint256)) userBets; // user => outcome => bet amount
    }
    
    // State variables
    mapping(uint256 => Market) public markets;
    mapping(uint256 => mapping(uint256 => address[])) public outcomeBettors; // marketId => outcome => bettors array
    uint256 public nextMarketId;
    uint256 public platformFeePercent = 2; // 2% platform fee
    address public owner;
    
    // Events
    event MarketCreated(uint256 indexed marketId, string question, string[] outcomes, uint256 endTime);
    event BetPlaced(uint256 indexed marketId, address indexed bettor, uint256 outcome, uint256 amount);
    event MarketResolved(uint256 indexed marketId, uint256 winningOutcome);
    event RewardsClaimed(uint256 indexed marketId, address indexed winner, uint256 amount);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier marketExists(uint256 _marketId) {
        require(_marketId < nextMarketId, "Market does not exist");
        _;
    }
    
    modifier marketActive(uint256 _marketId) {
        require(block.timestamp < markets[_marketId].endTime, "Market has ended");
        require(!markets[_marketId].resolved, "Market already resolved");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        nextMarketId = 0;
    }
    
    /**
     * @dev Core Function 1: Create a new prediction market
     * @param _question The question being predicted
     * @param _outcomes Array of possible outcomes
     * @param _duration Duration in seconds for how long the market stays open
     */
    function createMarket(
        string memory _question,
        string[] memory _outcomes,
        uint256 _duration
    ) external returns (uint256) {
        require(_outcomes.length >= 2, "Must have at least 2 outcomes");
        require(_duration > 0, "Duration must be positive");
        require(bytes(_question).length > 0, "Question cannot be empty");
        
        uint256 marketId = nextMarketId;
        Market storage newMarket = markets[marketId];
        
        newMarket.id = marketId;
        newMarket.question = _question;
        newMarket.outcomes = _outcomes;
        newMarket.endTime = block.timestamp + _duration;
        newMarket.totalPool = 0;
        newMarket.resolved = false;
        newMarket.creator = msg.sender;
        
        nextMarketId++;
        
        emit MarketCreated(marketId, _question, _outcomes, newMarket.endTime);
        return marketId;
    }
    
    /**
     * @dev Core Function 2: Place a bet on a specific outcome
     * @param _marketId The ID of the market to bet on
     * @param _outcome The index of the outcome to bet on
     */
    function placeBet(uint256 _marketId, uint256 _outcome) 
        external 
        payable 
        marketExists(_marketId) 
        marketActive(_marketId) 
    {
        require(msg.value > 0, "Bet amount must be greater than 0");
        require(_outcome < markets[_marketId].outcomes.length, "Invalid outcome");
        
        Market storage market = markets[_marketId];
        
        // Update user's bet
        if (market.userBets[msg.sender][_outcome] == 0) {
            outcomeBettors[_marketId][_outcome].push(msg.sender);
        }
        market.userBets[msg.sender][_outcome] += msg.value;
        
        // Update market pools
        market.outcomePools[_outcome] += msg.value;
        market.totalPool += msg.value;
        
        emit BetPlaced(_marketId, msg.sender, _outcome, msg.value);
    }
    
    /**
     * @dev Core Function 3: Resolve market and determine winning outcome
     * @param _marketId The ID of the market to resolve
     * @param _winningOutcome The index of the winning outcome
     */
    function resolveMarket(uint256 _marketId, uint256 _winningOutcome) 
        external 
        onlyOwner 
        marketExists(_marketId) 
    {
        Market storage market = markets[_marketId];
        require(block.timestamp >= market.endTime, "Market has not ended yet");
        require(!market.resolved, "Market already resolved");
        require(_winningOutcome < market.outcomes.length, "Invalid winning outcome");
        
        market.resolved = true;
        market.winningOutcome = _winningOutcome;
        
        emit MarketResolved(_marketId, _winningOutcome);
    }
    
    /**
     * @dev Claim rewards for winning bets
     * @param _marketId The ID of the resolved market
     */
    function claimRewards(uint256 _marketId) external marketExists(_marketId) {
        Market storage market = markets[_marketId];
        require(market.resolved, "Market not resolved yet");
        
        uint256 userWinningBet = market.userBets[msg.sender][market.winningOutcome];
        require(userWinningBet > 0, "No winning bet found");
        
        // Calculate rewards
        uint256 winningPool = market.outcomePools[market.winningOutcome];
        uint256 platformFee = (market.totalPool * platformFeePercent) / 100;
        uint256 distributionPool = market.totalPool - platformFee;
        
        uint256 userReward = (userWinningBet * distributionPool) / winningPool;
        
        // Reset user's bet to prevent double claiming
        market.userBets[msg.sender][market.winningOutcome] = 0;
        
        // Transfer rewards
        payable(msg.sender).transfer(userReward);
        
        emit RewardsClaimed(_marketId, msg.sender, userReward);
    }
    
    // View functions
    function getMarket(uint256 _marketId) external view marketExists(_marketId) returns (
        uint256 id,
        string memory question,
        string[] memory outcomes,
        uint256 endTime,
        uint256 totalPool,
        bool resolved,
        uint256 winningOutcome,
        address creator
    ) {
        Market storage market = markets[_marketId];
        return (
            market.id,
            market.question,
            market.outcomes,
            market.endTime,
            market.totalPool,
            market.resolved,
            market.winningOutcome,
            market.creator
        );
    }
    
    function getUserBet(uint256 _marketId, address _user, uint256 _outcome) 
        external 
        view 
        marketExists(_marketId) 
        returns (uint256) 
    {
        return markets[_marketId].userBets[_user][_outcome];
    }
    
    function getOutcomePool(uint256 _marketId, uint256 _outcome) 
        external 
        view 
        marketExists(_marketId) 
        returns (uint256) 
    {
        return markets[_marketId].outcomePools[_outcome];
    }
    
    // Owner functions
    function withdrawPlatformFees() external onlyOwner {
        uint256 balance = address(this).balance;
        payable(owner).transfer(balance);
    }
    
    function updatePlatformFee(uint256 _newFeePercent) external onlyOwner {
        require(_newFeePercent <= 10, "Fee cannot exceed 10%");
        platformFeePercent = _newFeePercent;
    }
}