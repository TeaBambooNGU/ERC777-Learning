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
    // 用于索引默认操作者状态 不可变 可以被标记撤销(tracked in __revokedDefaultOperators).
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
        // ERC777的 Sent事件
        emit Sent(operator, from, to, amount, userData, operatorData);
        // ERC20的 Transfer事件
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
    // ERC777 定义的转账函数， 同时触发 ERC20的 `Transfer` 事件
    function send(
        address recipient,
        uint256 amount,
        bytes calldata data
    ) public virtual override {
        _send(_msgSender(),recipient,amount,data,"",true);
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Unlike `send`, `recipient` is _not_ required to implement the {IERC777Recipient}
     * interface if it is a contract.
     *
     * Also emits a {Sent} event.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        require(recipient != address(0), "ERC777: transfer to the zero address");
        address from = _msgSender();

        _callTokensToSend(from, from, recipient, amount, "", "");

        _move(from, from, recipient, amount, "", "");

        _callTokensReceived(from, from, recipient, amount, "", "", false);

        return true;
    }

    /**
     * @dev Burn tokens
     * @param from address token holder address
     * @param amount uint256 amount of tokens to burn
     * @param userData bytes extra information provided by the token holder
     * @param operatorData bytes extra information provided by the operator (if any)
     */
    function _burn(
        address from,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData
    ) internal virtual {
        require(from != address(0), "ERC777: burn from zero address");
        address operator = _msgSender();
        
        _callTokensToSend(operator, from , address(0), amount, userData, operatorData);

        _beforeTokenTransfer(operator, from, address(0), amount);

        uint256 fromBalance = _balances[from];

        require(fromBalance > amount, "ERC777: burn amount exceeds balance");

        unchecked {
            _balances[from] -= amount;
        }

        _totalSupply -= amount;

        emit Burned(operator, from, amount, userData, operatorData);
        emit Transfer(from, address(0), amount);
    }

    /**
     * 销毁函数 实际使用时 需要使用 _burn(msg.sender,amount,data, "");
     * @param amount 金额
     * @param data 代币拥有者的数据
     * Emits {Burn} {ERC20-Transfer}
     */
    function burn(uint256 amount, bytes calldata data) public virtual override {
        _burn(_msgSender(),amount,data, "");
    }

    function isOperatorFor(
        address operator,
        address tokenHolder
    ) public view virtual override returns (bool) {
        return 
            operator == tokenHolder ||
            (_defaultOperators[operator] && !_revokedDefaultOperators[tokenHolder][operator]) ||
            _operators[tokenHolder][operator];
    }

    // 授权操作者 实际使用时需要校验权限
    function authorizeOperator(address operator) public virtual override {
        require(_msgSender() != operator, "ERC777: anthorizing self as operator");

        if (_defaultOperators[operator]) {
            delete _revokedDefaultOperators[_msgSender()][operator];
        }else {
            _operators[_msgSender()][operator] = true;
        }

        emit AuthorizedOperator(operator, _msgSender());
    }
    // 撤销操作者 实际使用时需要校验权限
    function revokeOperator(address operator) external override {
        require(operator != _msgSender(), "ERC777: revoking self as operator");

        if(_defaultOperators[operator]){
            _revokedDefaultOperators[_msgSender()][operator] == true;
        }else {
            delete _operators[_msgSender()][operator];
        }

        emit RevokedOperator(operator, _msgSender());
    }

    function defaultOperators() public view virtual override returns (address[] memory){
            return _defaultOperatorsArray;
    }

    /**
     * @dev See {IERC777-operatorSend}.
     *
     * Emits {Sent} and {IERC20-Transfer} events.
     */
    function operatorSend(
        address account,
        address recipient,
        uint256 amount,
        bytes calldata data,
        bytes calldata operatorData
    ) public virtual override {
        require(isOperatorFor(_msgSender(), account),"ERC777: caller is not an operator for holder");
       _send(account, recipient, amount, data, operatorData, true);
    }

    /**
     * @dev See {IERC777-operatorBurn}.
     *
     * Emits {Burned} and {IERC20-Transfer} events.
     */
    function operatorBurn(
        address account,
        uint256 amount,
        bytes calldata data,
        bytes calldata operatorData
    )  public virtual override  {
        require(isOperatorFor(_msgSender(), account),"ERC777: caller is not an operator for holder");
        _burn(account,amount,data,operatorData);
    }

    /**
     * @dev See {IERC20-allowance}.
     *
     * Note that operator and allowance concepts are orthogonal: operators may
     * not have allowance, and accounts with allowance may not be operators
     * themselves.
     */
    function allowance(address holder, address spender) public view virtual override returns(uint256)  {
        return _allowances[holder][spender];
    }

    function _approve(address holder, address spender, uint256 value) internal {
        require(holder != address(0), "ERC777: approve from the zero address");
        require(spender != address(0), "ERC777: approve to the zero address");

        _allowances[holder][spender] = value;
        emit Approval(holder, spender, value);
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Note that accounts cannot have allowance issued by their operators.
     */
    function approve(address spender, uint256 value) public virtual override returns (bool) {
        address holder = _msgSender();
        _approve(holder, spender, value);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Note that operator and allowance concepts are orthogonal: operators cannot
     * call `transferFrom` (unless they have allowance), and accounts with
     * allowance cannot call `operatorSend` (unless they are operators).
     *
     * Emits {Sent}, {IERC20-Transfer} and {IERC20-Approval} events.
     */
    function transferFrom(
        address holder,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        require(recipient != address(0), "ERC777: transfer to the zero address");
        require(holder != address(0), "ERC777: transfer from the zero address");

        address spender = _msgSender();

        _callTokensToSend(spender,holder,recipient, amount, "", "");

        _move(spender, holder, recipient, amount, "", "");

        _callTokensReceived(spender, holder, recipient, amount, "", "", false);

        return true; 
    }


}
        
    
    
    
    