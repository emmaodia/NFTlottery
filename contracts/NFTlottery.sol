// SPDX-License-Identifier: MIT

pragma solidity ^0.8.14;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import { Base64 } from "./Base64.sol";

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);

    function transfer(address to, uint256 amount) external returns (bool);
}

contract NFTlottery is ERC721URIStorage, Ownable, VRFConsumerBase  {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    uint256 public maxSupply;
    uint256 public totalSupply;
    uint256 public mintPrice = 0.0001 ether;
    address payable[] public players;
    mapping(address => uint256) public mintedWallets;

    uint256 public lotteryId;
    mapping (uint => address payable) public lotteryHistory;

    bytes32 internal keyHash;
    uint256 internal fee;
    uint256 public randomResult;

    string baseSVG = "<svg xmlns='http://www.w3.org/2000/svg' preserveAspectRatio='xMinYMin meet' viewBox='0 0 350 350'><style>.base { fill: white; font-family: serif; font-size: 24px; }</style><rect width='100%' height='100%' fill='black' /><text x='50%' y='50%' class='base' dominant-baseline='middle' text-anchor='middle'>";
    string[] firstWords = ["Jamie", "Claire", "Angus", "Jack", "Fraser", "Hamish"];
    string[] secondWords = ["Fraser", "MacKenzie", "Randall", "Hawkin", "MacQuarrie", "Grey"];
    string[] thirdWords = ["Midhope", "Leoch", "Kinloch", "Doune", "Falkland", "Culross"];

    constructor() 
                payable ERC721('EM Lottery Ticket', 'EMLRT')
                VRFConsumerBase(
                        0xdD3782915140c8f3b190B5D67eAc6dc5760C46E9, // VRF Coordinator
                        0xa36085F69e2889c224210F603D836748e7dC0088  // LINK Token
                )
     {
        maxSupply = 2;
        keyHash = 0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4;
        fee = 0.1 * 10 ** 18; // 0.1 LINK (Varies by network)
    }

    /** 
     * Requests randomness 
     */
    function getRandomNumber() public payable returns (bytes32 requestId) {
        require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK - fill contract with faucet");
        return requestRandomness(keyHash, fee);
    }

    /**
     * Callback function used by VRF Coordinator
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        randomResult = randomness;
        // payWinner();
    }

    // Implement a withdraw function to avoid locking your LINK in the contract 
    function withdrawLink() external onlyOwner returns(bool) {
        require(address(this).balance > 0, "There is no balance locked in the contract");
        LINK.transferFrom(address(this), msg.sender, address(this).balance);
        emit Transfer(address(this), msg.sender, address(this).balance);
        return true;
    }

    function getLinkBalance() public view returns(uint) {    
        return LINK.balanceOf(address(this));
    }

    function setMaxSupply(uint256 _maxSupply) public onlyOwner {
        maxSupply = _maxSupply;
    }

    /* Mint Lottery Ticket as NFTs*/

    function pickRandomFirstWord(uint256 tokenId) public view returns(string memory) {
        uint256 rand = random(string(abi.encodePacked("FIRST_WORD", Strings.toString(tokenId))));
        // bytes memory rand = getRandomNumber();
        rand = randomResult % firstWords.length;
        return firstWords[rand];
    }

    function pickRandomSecondWord(uint256 tokenId) public view returns(string memory) {
        uint256 rand = random(string(abi.encodePacked("SECOND_WORD", Strings.toString(tokenId))));
        rand = randomResult % secondWords.length;
        return secondWords[rand];
    }

    function pickRandomThirdWord(uint256 tokenId) public view returns(string memory) {
        uint256 rand = random(string(abi.encodePacked("THIRD_WORD", Strings.toString(tokenId))));
        rand = randomResult % thirdWords.length;
        return thirdWords[rand];
    }

    function random(string memory input) internal pure returns(uint256) {
        return uint256(keccak256(abi.encodePacked(input)));
    }

    function mintLotteryTicket() public payable {
        require(mintedWallets[msg.sender] < 1, 'You can only mint 1 ticket');
        require(msg.value == mintPrice, 'Mint Price is 0.00ETH');
        require(maxSupply > totalSupply, 'Tickets Sold Out');

        uint256 newItemId = _tokenIds.current();

        string memory first = pickRandomFirstWord(newItemId);
        string memory second = pickRandomSecondWord(newItemId);
        string memory third = pickRandomThirdWord(newItemId);
        string memory combinedWord = string(abi.encodePacked(first, second, third));

        string memory finalSVG = string(abi.encodePacked(baseSVG, combinedWord, "<text></svg>"));

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "',
                    // We set the title of our NFT as the generated word.
                    combinedWord,
                    '", "description": "A Rare Collection of Outlander Names.", "image": "data:image/svg+xml;base64,',
                    // We add data:image/svg+xml;base64 and then append our base64 encode our svg.
                    Base64.encode(bytes(finalSVG)),
                    '"}'
                    )
                )
            )
        );

        string memory finalTokenURI = string(abi.encodePacked("data:application/json;base64,",json));        
        totalSupply++;
        _safeMint(msg.sender, newItemId);
        _setTokenURI(newItemId, finalTokenURI);
        _tokenIds.increment();
        mintedWallets[msg.sender]++;
        players.push(payable(msg.sender));
    }

    function getContractBalance() public view returns(uint) {
        return address(this).balance;
    }

    function getPlayers() public view returns (address payable[] memory) {
        return players;
    }

    function pickWinner() public {
        getRandomNumber();
    }

    function payWinner() public {
        uint256 index = randomResult % players.length;
        players[index].transfer(address(this).balance);

        lotteryHistory[lotteryId] = players[index];
        lotteryId++;

        players = new address payable[](0);

        emit Transfer(address(this), msg.sender, address(this).balance);
    }

}