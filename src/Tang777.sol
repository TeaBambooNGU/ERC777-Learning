// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

import "./ERC777_Self.sol";


event RecveiveTokens(address indexed from, uint256 indexed amount);

event SendTokens(address indexed to, uint256 indexed amount);

contract Tang777 is ERC777 {

    bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");
    bytes32 private constant _TOKENS_SENDER_INTERFACE_HASH = keccak256("ERC777TokensSender");


    constructor (
        string memory name_, 
        string memory symbol_, 
        address[] memory defaultOperators
    )ERC777(name_, symbol_, defaultOperators){
        uint initialSupply = 710 * 10 ** 18;
        _mint(msg.sender,initialSupply,"","");

         //注册ERC1820接口 ERC777TokensRecipient
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), _TOKENS_RECIPIENT_INTERFACE_HASH, address(this));


    }



    // ERC1120 接收者受到代币 ERC1120会回调此接口
    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external  {
        emit RecveiveTokens(from, amount);
    }

    function tokensToSend(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external {
        emit SendTokens(to, amount);
    }

    

}