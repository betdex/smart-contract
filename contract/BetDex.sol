pragma solidity 0.4.20;

import "./usingOraclize.sol";

contract BetDex is usingOraclize {
  using SafeMath for uint256; //prevents overflows from occuring when working with uint

  address public owner;
  address public houseFeeAddress;
  uint public houseFeePercent = 3;
  uint public minimumBetAmount = 10000000000000000; //=> 0.01 Ether
  string public version = '1.0.0';

  uint public ORACLIZE_GAS_LIMIT = 100000;
  uint public ORACLIZE_GAS_PRICE = 10000000000;

  bytes32 public currOraclizeEventId;

  //struct that holds all of the data for a specific event
  struct Event {
    bytes32 eventId;
    bytes32 winningScenarioName;
    bytes32 firstScenarioName;
    bytes32 secondScenarioName;
    string oracleGameId;
    string category;
    uint index;
    uint totalNumOfBets;
    uint eventStartsTime;
    bool eventHasEnded;
    bool eventCancelled;
    bool resultIsATie;
    bool houseFeePaid;
    mapping(bytes32 => Scenario) scenarios;
    mapping(address => BettorInfo) bettorsIndex;
  }

  //struct that holds data for each of the two scenarios for each event
  //this data is placed inside the Event struct
  struct Scenario {
    uint totalBet;
    uint numOfBets;
  }

  //struct that holds data for each bettor address in an event
  //this data is placed inside the Event struct
  struct BettorInfo {
    bool rewarded;
    bool refunded;
    uint totalBet;
    mapping(bytes32 => uint) bets;
  }

  mapping (bytes32 => Event) events;
  bytes32[] eventsIndex;

  //events ted for frontend interface and administrative purposes
  event EventCreated(bytes32 indexed eventId, uint eventStartsTime);
  event BetPlaced(bytes32 indexed eventId, bytes32 scenarioBetOn, address indexed from, uint betValue, uint timestamp, bytes32 firstScenarioName, bytes32 secondScenarioName, string category);
  event WinnerSet(bytes32 indexed eventId, bytes32 winningScenarioName, uint timestamp);
  event HouseFeePaid(bytes32 indexed eventId, address houseFeeAddress, uint houseFeeAmount);
  event Withdrawal(bytes32 indexed eventId, string category, address indexed userAddress, bytes32 withdrawalType, uint amount, bytes32 firstScenarioName, bytes32 secondScenarioName, uint timestamp);
  event HouseFeePercentChanged(uint oldFee, uint newFee, uint timestamp);
  event HouseFeeAddressChanged(address oldAddress, address newAddress, uint timestamp);
  event OwnershipTransferred(address owner, address newOwner);
  event EventCancelled(bytes32 indexed eventId, bool dueToInsufficientBetAmount, uint timestamp);
  event TieResultSet(bytes32 indexed eventId, uint timestamp);
  event ExtendEventStartsTime(bytes32 indexed eventId, uint newEventStartsTime, uint timestamp);
  event NewOraclizeQuery(bytes32 indexed eventId, string description);
  event OraclizeQueryRecieved(bytes32 indexed eventId, string result);
  event OraclizeGasLimitSet(uint oldGasLimit, uint newGasLimit, uint timestamp);
  event OraclizeGasPriceSet(uint newGasPriceGwei, uint timestamp);
  event MinimumBetAmountChanged(uint oldMinimumAmountInWei, uint newMinimumAmountInWei, uint timestamp);

  //ran once on contract creation
  //houseFeeAddress and owner set
  function BetDex() public {
    houseFeeAddress = msg.sender;
    owner = msg.sender;

    //change default gas price from 20 Gwei to 10 Gwei
    oraclize_setCustomGasPrice(10000000000);
  }

  //modifier used to restrict certain functions to only owner calls
  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  //modifier used to restrict the __callback function to only oraclize address calls
  modifier onlyOraclize() {
    require(msg.sender == oraclize_cbAddress());
    _;
  }

  //for owner to add to contract balance if needed
  function () external payable onlyOwner {}

  //function to add new event to the events mapping
  function createNewEvent(bytes32 _eventId, string _category, string _oracleGameId, uint _eventStartsTime, string _firstScenarioName, string _secondScenarioName) external onlyOwner {
    require(!internalDoesEventExist(_eventId));
    require(stringToBytes32(_firstScenarioName) != stringToBytes32(_secondScenarioName));

    events[_eventId].eventId = _eventId;
    events[_eventId].oracleGameId = _oracleGameId;
    events[_eventId].index = eventsIndex.push(_eventId)-1;
    events[_eventId].category = _category;
    events[_eventId].eventStartsTime = _eventStartsTime;
    events[_eventId].firstScenarioName = stringToBytes32(_firstScenarioName);
    events[_eventId].secondScenarioName = stringToBytes32(_secondScenarioName);

    events[_eventId].scenarios[stringToBytes32(_firstScenarioName)];
    events[_eventId].scenarios[stringToBytes32(_secondScenarioName)];

    EventCreated(_eventId, _eventStartsTime);
  }

  //add bet to the bettorIndex mapping for a specific event
  function placeBet(bytes32 _eventId, string _scenarioBetOn) external payable {
    require(internalDoesEventExist(_eventId));
    require(msg.value >= minimumBetAmount);
    require(!events[_eventId].eventHasEnded);
    require(events[_eventId].eventStartsTime > now);
    require(stringToBytes32(_scenarioBetOn) == events[_eventId].firstScenarioName || stringToBytes32(_scenarioBetOn) == events[_eventId].secondScenarioName);

    events[_eventId].bettorsIndex[msg.sender].bets[stringToBytes32(_scenarioBetOn)] = (events[_eventId].bettorsIndex[msg.sender].bets[stringToBytes32(_scenarioBetOn)]).add(msg.value);
    events[_eventId].bettorsIndex[msg.sender].totalBet = (events[_eventId].bettorsIndex[msg.sender].totalBet).add(msg.value);

    events[_eventId].totalNumOfBets = (events[_eventId].totalNumOfBets).add(1);
    events[_eventId].scenarios[stringToBytes32(_scenarioBetOn)].numOfBets = (events[_eventId].scenarios[stringToBytes32(_scenarioBetOn)].numOfBets).add(1);
    events[_eventId].scenarios[stringToBytes32(_scenarioBetOn)].totalBet = (events[_eventId].scenarios[stringToBytes32(_scenarioBetOn)].totalBet).add(msg.value);

    BetPlaced(_eventId, stringToBytes32(_scenarioBetOn), msg.sender, msg.value, now, events[_eventId].firstScenarioName, events[_eventId].secondScenarioName, events[_eventId].category);
  }

  //function used by oraclize when it sends event data back to the smart contract
  function __callback(bytes32 myid, string result) public onlyOraclize {
    if (stringToBytes32(result) == stringToBytes32("tie")) {
      OraclizeQueryRecieved(currOraclizeEventId, "game result is a tie");
      events[currOraclizeEventId].resultIsATie = true;
      events[currOraclizeEventId].eventHasEnded = true;
    } else if (stringToBytes32(result) == events[currOraclizeEventId].firstScenarioName || stringToBytes32(result) == events[currOraclizeEventId].secondScenarioName) {
      OraclizeQueryRecieved(currOraclizeEventId, result);
      uint houseFeeAmount = ((events[currOraclizeEventId].scenarios[events[currOraclizeEventId].firstScenarioName].totalBet)
        .add(events[currOraclizeEventId].scenarios[events[currOraclizeEventId].secondScenarioName].totalBet))
        .mul(houseFeePercent)
        .div(100);
      if (!events[currOraclizeEventId].houseFeePaid) {
        houseFeeAddress.transfer(houseFeeAmount);
        events[currOraclizeEventId].houseFeePaid = true;
        HouseFeePaid(currOraclizeEventId, houseFeeAddress, houseFeeAmount);
      }
      events[currOraclizeEventId].winningScenarioName = stringToBytes32(result);
      events[currOraclizeEventId].eventHasEnded = true;
      WinnerSet(currOraclizeEventId, stringToBytes32(result), now);
    } else {
      OraclizeQueryRecieved(currOraclizeEventId, "error occurred");
    }
  }

  //set the winningScenarioId, calculate and send houseFee amount to houseFeeAddress, and end specific event
  function getWinnerOfEvent(bytes32 _eventId) public payable onlyOwner {
    require(internalDoesEventExist(_eventId));
    require(!events[_eventId].eventHasEnded);
    require(events[_eventId].eventStartsTime < now);

    //if there are no bets on one or both events, don't send query oraclize
    if (events[_eventId].scenarios[events[_eventId].firstScenarioName].totalBet == 0 || events[_eventId].scenarios[events[_eventId].secondScenarioName].totalBet == 0) {
      events[_eventId].eventCancelled = true;
      events[_eventId].eventHasEnded = true;
      EventCancelled(_eventId, true, now);
    } else {
      require(msg.value >= oraclize_getPrice("URL", ORACLIZE_GAS_LIMIT));
      currOraclizeEventId = _eventId;
      NewOraclizeQuery(_eventId, "Oraclize query was sent, standing by for the answer...");
      oraclize_query("URL", strConcat("json(https://api.betdex.io/api/sports/", events[_eventId].category, "/getGameResultById/", events[_eventId].oracleGameId, ").result"), ORACLIZE_GAS_LIMIT);
    }
  }

  //cancel and end specific event
  //event can be cancelled at any time, allowing users to refund their bet ether
  function cancelAndEndEvent(bytes32 _eventId) external onlyOwner {
    require(internalDoesEventExist(_eventId));
    require(!events[_eventId].eventCancelled);
    require(!events[_eventId].eventHasEnded);

    events[_eventId].eventCancelled = true;
    events[_eventId].eventHasEnded = true;
    EventCancelled(_eventId, false, now);
  }

  //find the msg.sender in the bettorsIndex, calculate the winning amount for the user, and transfer winning amount to user's address
  function claimWinnings(bytes32 _eventId) external {
    require(internalDoesEventExist(_eventId));
    require(events[_eventId].eventHasEnded);
    require(!events[_eventId].eventCancelled);
    require(!events[_eventId].resultIsATie);
    require(!events[_eventId].bettorsIndex[msg.sender].rewarded);
    require(!events[_eventId].bettorsIndex[msg.sender].refunded);
    require(events[_eventId].bettorsIndex[msg.sender].totalBet > 0);
    require(events[_eventId].scenarios[events[_eventId].winningScenarioName].totalBet > 0);

    uint transferAmount = calculateWinnings(_eventId, msg.sender);
    if (transferAmount > 0) {
      events[_eventId].bettorsIndex[msg.sender].rewarded = true;
      Withdrawal(_eventId, events[_eventId].category, msg.sender, stringToBytes32('winnings'), transferAmount, events[_eventId].firstScenarioName, events[_eventId].secondScenarioName, now);
      msg.sender.transfer(transferAmount);
    }
  }

  //internal function used to calculate the amount of winnings to award to a given user for a specific event
  function calculateWinnings(bytes32 _eventId, address _userAddress) internal constant returns (uint winnerReward) {
    uint totalReward = (events[_eventId].scenarios[events[_eventId].firstScenarioName].totalBet).add(events[_eventId].scenarios[events[_eventId].secondScenarioName].totalBet)
        .sub(((events[_eventId].scenarios[events[_eventId].firstScenarioName].totalBet)
        .add(events[_eventId].scenarios[events[_eventId].secondScenarioName].totalBet))
        .mul(houseFeePercent)
        .div(100));
    winnerReward = ((((totalReward).mul(10000000))
    .div(events[_eventId].scenarios[events[_eventId].winningScenarioName].totalBet))
    .mul(events[_eventId].bettorsIndex[_userAddress].bets[events[_eventId].winningScenarioName]))
    .div(10000000);
  }

  //find the msg.sender address in the bettorsIndex and transfer the refund amount to the user's address
  function claimRefund(bytes32 _eventId) external {
    require(internalDoesEventExist(_eventId));
    require(events[_eventId].eventHasEnded);
    require(events[_eventId].eventCancelled || events[_eventId].resultIsATie);
    require(!events[_eventId].bettorsIndex[msg.sender].rewarded);
    require(!events[_eventId].bettorsIndex[msg.sender].refunded);
    require(events[_eventId].bettorsIndex[msg.sender].totalBet > 0);

    events[_eventId].bettorsIndex[msg.sender].refunded = true;
    Withdrawal(_eventId, events[_eventId].category, msg.sender, stringToBytes32('refund'), events[_eventId].bettorsIndex[msg.sender].totalBet, events[_eventId].firstScenarioName, events[_eventId].secondScenarioName, now);
    msg.sender.transfer(events[_eventId].bettorsIndex[msg.sender].totalBet);
  }

  //change eventStartsTime value for a specific event
  //used if an event was given an incorrect start time or an event is postponed or delayed
  function extendEventStartsTime(bytes32 _eventId, uint _newEventStartsTime) external onlyOwner {
    require(internalDoesEventExist(_eventId));
    require(!events[_eventId].eventHasEnded);
    require(_newEventStartsTime > events[_eventId].eventStartsTime);

    events[_eventId].eventStartsTime = _newEventStartsTime;
    ExtendEventStartsTime(_eventId, _newEventStartsTime, now);
  }

  //change oraclize gas limit
  function setOraclizeGasLimit(uint _newGasLimit) external onlyOwner {
    require(_newGasLimit > 0);
    OraclizeGasLimitSet(ORACLIZE_GAS_LIMIT, _newGasLimit, now);
    ORACLIZE_GAS_LIMIT = _newGasLimit;
  }

  //update gas price that oraclize sends transactions with
  function setOraclizeGasPrice(uint _newGasPrice) external onlyOwner {
    require(_newGasPrice > 0);
    OraclizeGasPriceSet(_newGasPrice, now);
    oraclize_setCustomGasPrice(_newGasPrice);
  }

  //function used to change the house fee percent
  //house fee percent can only be lowered
  function changeHouseFeePercent(uint _newFeePercent) external onlyOwner {
    require(_newFeePercent < houseFeePercent);
    HouseFeePercentChanged(houseFeePercent, _newFeePercent, now);
    houseFeePercent = _newFeePercent;
  }

  //function used to change the house fee address
  function changeHouseFeeAddress(address _newAddress) external onlyOwner {
    require(_newAddress != houseFeeAddress);
    HouseFeeAddressChanged(houseFeeAddress, _newAddress, now);
    houseFeeAddress = _newAddress;
  }

  //function used to change the minimum bet amount
  function changeMinimumBetAmount(uint _newMinimumAmountInWei) external onlyOwner {
    MinimumBetAmountChanged(minimumBetAmount, _newMinimumAmountInWei, now);
    minimumBetAmount = _newMinimumAmountInWei;
  }

  //internal function used to verify that an event exists with a given eventId
  function internalDoesEventExist(bytes32 _eventId) internal constant returns (bool) {
    if (eventsIndex.length > 0) {
      return (eventsIndex[events[_eventId].index] == _eventId);
    } else {
      return (false);
    }
  }

  //external version of the internalDoesEventExist function
  function doesEventExist(bytes32 _eventId) public constant returns (bool) {
    if (eventsIndex.length > 0) {
      return (eventsIndex[events[_eventId].index] == _eventId);
    } else {
      return (false);
    }
  }

  //external function used by frontend to pull scenario names and event status from the contract
  function getScenarioNamesAndEventStatus(bytes32 _eventId) public constant returns (bytes32, bytes32, bool, bool, bool, bytes32, bool) {
    return (
      events[_eventId].firstScenarioName,
      events[_eventId].secondScenarioName,
      events[_eventId].eventHasEnded,
      events[_eventId].eventCancelled,
      events[_eventId].resultIsATie,
      events[_eventId].winningScenarioName,
      events[_eventId].houseFeePaid
    );
  }

  //external function used by frontend to pull event info from the contract
  function getEventInfo(bytes32 _eventId) public constant returns (uint, string, uint, string) {
    return (
      events[_eventId].totalNumOfBets,
      events[_eventId].category,
      events[_eventId].eventStartsTime,
      events[_eventId].oracleGameId
    );
  }

  //external function used by frontend to pull scenarios info from the contract
  function getScenariosInfo(bytes32 _eventId) public constant returns (bytes32, uint, uint, bytes32, uint, uint) {
    return (
      events[_eventId].firstScenarioName,
      events[_eventId].scenarios[events[_eventId].firstScenarioName].totalBet,
      events[_eventId].scenarios[events[_eventId].firstScenarioName].numOfBets,
      events[_eventId].secondScenarioName,
      events[_eventId].scenarios[events[_eventId].secondScenarioName].totalBet,
      events[_eventId].scenarios[events[_eventId].secondScenarioName].numOfBets
    );
  }

  //external function used by frontend to pull bet data for a user address
  function getAddressBetsForEvent(bytes32 _eventId, address _userAddress) public constant returns (uint, bool, bool, uint, uint) {
    return (
        events[_eventId].bettorsIndex[_userAddress].totalBet,
        events[_eventId].bettorsIndex[_userAddress].rewarded,
        events[_eventId].bettorsIndex[_userAddress].refunded,
        events[_eventId].bettorsIndex[_userAddress].bets[events[_eventId].firstScenarioName],
        events[_eventId].bettorsIndex[_userAddress].bets[events[_eventId].secondScenarioName]
    );
  }

  //internal function to concat a string, used for creating oraclize query string
  function strConcat(string _a, string _b, string _c, string _d, string _e) internal pure returns (string){
      bytes memory _ba = bytes(_a);
      bytes memory _bb = bytes(_b);
      bytes memory _bc = bytes(_c);
      bytes memory _bd = bytes(_d);
      bytes memory _be = bytes(_e);
      string memory abcde = new string(_ba.length + _bb.length + _bc.length + _bd.length + _be.length);
      bytes memory babcde = bytes(abcde);
      uint k = 0;
      for (uint i = 0; i < _ba.length; i++) babcde[k++] = _ba[i];
      for (i = 0; i < _bb.length; i++) babcde[k++] = _bb[i];
      for (i = 0; i < _bc.length; i++) babcde[k++] = _bc[i];
      for (i = 0; i < _bd.length; i++) babcde[k++] = _bd[i];
      for (i = 0; i < _be.length; i++) babcde[k++] = _be[i];
      return string(babcde);
  }

  //internal function to see if two strings are equal
  function compareStrings(string a, string b) internal pure returns (bool) {
    return keccak256(a) == keccak256(b);
  }

  //internal function to convert a string to bytes32
  function stringToBytes32(string memory source) internal pure returns (bytes32 result) {
    bytes memory tempEmptyStringTest = bytes(source);
    if (tempEmptyStringTest.length == 0) {
      return 0x0;
    }

    assembly {
      result := mload(add(source, 32))
    }
  }
}

//library used to avoid integer overflows
library SafeMath {
  function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a / b;
    return c;
  }

  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    assert(c >= a);
    return c;
  }
}
