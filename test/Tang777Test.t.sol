// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Tang777.sol";
//import "openzeppelin-contracts";

contract Tang777Test is Test {

    Tang777 private  tang777;
    bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");
    IERC1820Registry internal constant _ERC1820_REGISTRY = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);



    address[] defaultOperators = [0x70997970C51812dc3A010C7d01b50e0d17dc79C8,0x90F79bf6EB2c4f870365E785982E1f101E93b906];

    function setUp() public {
        //注册ERC1820接口 ERC777TokensRecipient (初始化构造的时候铸币的时候1820会回调此接口 test合约必须实现这个接口)
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), _TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
        tang777 = new Tang777("Tang777","777",defaultOperators);
    }

    function testMint() public {
        address reciptent = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        uint256 amount = 200 * 10 ** 18;
        tang777.mint(reciptent,amount,abi.encodePacked("Tang777Test",address(this)));
    }
        // ERC770 接收者受到代币 ERC1120会回调此接口
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



}