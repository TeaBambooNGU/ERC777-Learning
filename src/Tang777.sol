// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

import "./ERC777_Self.sol";
import "openzeppelin-contracts/contracts/interfaces/IERC1820Implementer.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

event RecveiveTokens(address indexed from, uint256 indexed amount);

event SendTokens(address indexed to, uint256 indexed amount);

contract Tang777 is ERC777,Ownable {

    bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");
    bytes32 private constant _TOKENS_SENDER_INTERFACE_HASH = keccak256("ERC777TokensSender");
    bytes32 private constant _ERC1820_ACCEPT_MAGIC = keccak256(abi.encodePacked("ERC1820_ACCEPT_MAGIC"));
    // 委托该合约实现接口的账号
    mapping (address => mapping (bytes32 => bool)) private  interfaceForAccounts;


    constructor (
        string memory name_, 
        string memory symbol_, 
        address[] memory defaultOperators
    )ERC777(name_, symbol_, defaultOperators) Ownable(msg.sender){
        uint initialSupply = 710 * 10 ** 18;
        _mint(msg.sender,initialSupply,"","");

         //注册ERC1820接口 ERC777TokensRecipient
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), _TOKENS_RECIPIENT_INTERFACE_HASH, address(this));


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

    // ERC770 发送代币 ERC1120会回调此接口
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
    /// @notice 指示合约是否为地址 “addr” 实现接口 “interfaceHash”。
    /// 用于 一个普通的用户地址(账号)，委托一个合约来监听代币的转出
    /// @param interfaceHash 接口名称的 keccak256 哈希值
    /// @param account 为哪一个账号实现接口
    /// @return 有当合约为账号'account'实现'interfaceHash'时返回 ERC1820_ACCEPT_MAGIC
    function canImplementInterfaceForAddress(bytes32 interfaceHash, address account) external view returns (bytes32) {
        if (interfaceForAccounts[account][interfaceHash]) {
            return _ERC1820_ACCEPT_MAGIC;
        }else {
            return bytes32(0x00);
        }
        
    }

    function setInterfaceForAccounts(address account, bytes32 interfaceHash) external onlyOwner {
        interfaceForAccounts[account][interfaceHash] = true;
    }

    

}