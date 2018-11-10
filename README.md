## Bet Dex Smart Contract

#### General Description
Bet Dex is a dapp on the Ethereum network for placing bets on real-life events (i.e. sports or politics) using the Ether cryptocurrency.

#### Current Live Versions
**Mainnet**: https://etherscan.io/address/0xb411eB71568B9f722a5b77C046d4BBEa5b36A0C5

**Ropsten**: https://ropsten.etherscan.io/address/0xE10698033391a1C2D77499Caaf928408A1f874B4

#### Project Components
* **Website**: Frontend interface to the smart contract. Users use the website to unlock their Ethereum wallet, browse events, place bets on events, and withdraw winnings.
* **Admin Desktop App**: A desktop app run locally on my machine that is used to create new events, set winner of events, and execute other only owner smart contract functions.
* **Smart Contract**: Holds the events and their corresponding bets.

#### Typical User Journey
1. User navigates to the betdex.io website
2. User unlocks their Metamask or Ledger Ethereum wallet
3. User finds an event they want to place a bet on
4. User places a bet after selecting the scenario to bet on and the amount of Ether to bet (the user's Ether funds are sent to the smart contract)
5. The user now waits to see if the scenario they selected has won or lost and if the event is a tie or was canceled.
6. If the user bet on the winner, the user withdraws their winning bet amount (winnings = (initial bet amount on winning scenario * scenario odds) - house fee)
7. If the user bet on the loser, the user will not be able to withdraw any winnings
8. If the event is canceled or the result is a tie, the user will be able to withdraw their refund, which is equal to the total amount they bet on the event (no house fee is charged on cancellations or ties)
