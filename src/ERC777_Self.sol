// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;
// ERC777 目前因为安全问题已经被openzeppelin-contracts弃用 重入攻击 替代合约： ERC20Permit.sol
import "openzeppelin-contracts/contracts/interfaces/IERC777.sol";
import "openzeppelin-contracts/contracts/interfaces/IERC777Recipient.sol";
import "openzeppelin-contracts/contracts/interfaces/IERC777Sender.sol";
import "openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import "openzeppelin-contracts/contracts/utils/Address.sol";
import "openzeppelin-contracts/contracts/interfaces/IERC1820Registry.sol";
import "openzeppelin-contracts/contracts/utils/Context.sol";

// ERC777 要兼容实现ERC20
abstract contract ERC777 is Context, IERC777, IERC20 {
    using Address for address;
    // ERC1820 注册表合约地址 (在所有链上的地址唯一 都是这个)
    IERC1820Registry internal constant _ERC1820_REGISTRY = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    
    mapping (address => uint256) private _balances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;
    // 发送者接口hash 用户查询是否实现了对应的接口
    bytes32 private constant _TOKENS_SENDER_INTERFACE_HASH = keccak256("ERC777TokensSender");
    // 发送者接口hash 用户查询是否实现了对应的接口
    bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");
    // 默认操作者列表 不用于读取
    address[] private _defaultOperatorsArray;
    // 用于索引默认操作者状态 不可变 可以被撤销(tracked in __revokedDefaultOperators).
    mapping (address => bool) private _defaultOperators;

    // For each account, a mapping of its operators and revoked default operators.
    // 保存授权的操作者
    mapping (address => mapping (address => bool)) private _operators;
    // 保存取消授权的默认操作者
    mapping (address => mapping (address => bool)) private _revokedDefaultOperators;
    // 兼容ERC20的授权信息
    mapping (address => mapping (address => uint256)) private _allowances;

    /**
     * @dev `defaultOperators` may be an empty array.
     */
    constructor (
        string memory name_,
        string memory symbol_,
        address[] memory defaultOperators_
    ){
        _name = name_;
        _symbol = symbol_;
        _defaultOperatorsArray = defaultOperators_;
        for (uint i = 0; i < defaultOperators_.length; i++) {
            _defaultOperators[defaultOperators_[i]] = true;
        }

        // 在ERC1820注册接口 [ 记录地址(第一个键) 的接口（第二个键）的实现地址（第二个值）]  
        // 相对应的 getInterfaceImplementer() 通过 interfaces 这个mapping 来获得接口的实现
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), keccak256("ERC777Token"), address(this));
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), keccak256("ERC20Token"), address(this));
    }
    function name() external view override returns (string memory) {
        return _name;
    }

    function symbol() external view override returns (string memory) {
        return _symbol;
    }
    // 精度只能设置成18 为了兼容ERC20
    function decimals() public pure virtual returns (uint8) {
        return 18;
    }
    // 粒度
    function granularity() public virtual view override returns (uint256) {
        return 1;
    }

    function totalSupply() public view override(IERC20, IERC777) returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(
        address tokenHolder
    ) public view override(IERC20, IERC777) returns (uint256) {
        return _balances[tokenHolder];
    }
    /**
     * 尝试调用持有者的 tokensToSend() 函数
     * @dev Call from.tokensToSend() if the interface is registered
     * @param operator address operator requesting the transfer
     * @param from address token holder address
     * @param to address recipient address
     * @param amount uint256 amount of tokens to transfer
     * @param userData bytes extra information provided by the token holder (if any)
     * @param operatorData bytes extra information provided by the operator (if any)
     */
    function _callTokensToSend(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData
    ) private {
        address implementer = _ERC1820_REGISTRY.getInterfaceImplementer(from, _TOKENS_SENDER_INTERFACE_HASH);
        if(implementer != address(0)){
            IERC777Sender(implementer).tokensToSend(operator, from, to, amount, userData, operatorData);
        }
    }

    /**
     * 代币发送前钩子函数
     * @dev Hook that is called before any token transfer. This includes
     * calls to {send}, {transfer}, {operatorSend}, minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be to transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256 amount
    ) internal virtual {}


    function _move(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData
    )private{
        _beforeTokenTransfer(operator, from, to, amount);
        uint256 fromBalance = _balances[from];
        require(fromBalance > amount, "ERC777: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
        }
        _balances[to] += amount;

        emit Sent(operator, from, to, amount, userData, operatorData);
        emit Transfer(from, to, amount);
    }

    /**
     * 尝试调用接收者的 tokensReceived()
     * @dev Call to.tokensReceived() if the interface is registered. Reverts if the recipient is a contract but
     * tokensReceived() was not registered for the recipient
     * @param operator address operator requesting the transfer
     * @param from address token holder address
     * @param to address recipient address
     * @param amount uint256 amount of tokens to transfer
     * @param userData bytes extra information provided by the token holder (if any)
     * @param operatorData bytes extra information provided by the operator (if any)
     * @param requireReceptionAck if true, contract recipients are required to implement ERC777TokensRecipient
     */
    function _callTokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData,
        bool requireReceptionAck
    ) private {
        address implementer = _ERC1820_REGISTRY.getInterfaceImplementer(to, _TOKENS_RECIPIENT_INTERFACE_HASH);
        if(implementer != address(0)){
            IERC777Recipient(implementer).tokensReceived(operator, from, to, amount, userData, operatorData);
        }else if (requireReceptionAck) {
            require(to.code.length <=0, "ERC777: token recipient contract has no implementer for ERC777TokensRecipient");
        }
    }



    /**
     * @dev Send tokens
     * @param from address token holder address
     * @param to address recipient address
     * @param amount uint256 amount of tokens to transfer
     * @param userData bytes extra information provided by the token holder (if any)
     * @param operatorData bytes extra information provided by the operator (if any)
     * @param requireReceptionAck if true, contract recipients are required to implement ERC777TokensRecipient
     */
    function _send(
        address from,
        address to,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData,
        bool requireReceptionAck
    )  internal virtual {
        require(from != address(0),"ERC777: send from the zero address");
        require(to != address(0),"ERC777: send to the zero address");

        address operator = _msgSender();

        _callTokensToSend(operator, from, to, amount, userData, operatorData);

        _move(operator, from, to, amount, userData, operatorData);

        _callTokensReceived(operator, from, to, amount, userData, operatorData, requireReceptionAck);
    }

    function send(
        address recipient,
        uint256 amount,
        bytes calldata data
    ) public virtual override {}

    function burn(uint256 amount, bytes calldata data) external override {}

    function isOperatorFor(
        address operator,
        address tokenHolder
    ) external view override returns (bool) {}

    function authorizeOperator(address operator) external override {}

    function revokeOperator(address operator) external override {}

    function defaultOperators()
        external
        view
        override
        returns (address[] memory)
    {}

    function operatorSend(
        address sender,
        address recipient,
        uint256 amount,
        bytes calldata data,
        bytes calldata operatorData
    ) external override {}

    function operatorBurn(
        address account,
        uint256 amount,
        bytes calldata data,
        bytes calldata operatorData
    ) external override {}
}
        
    
    
    
    