// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Tang777.sol";
//import "openzeppelin-contracts";

contract Tang777Test is Test {

    Tang777 private  tang777;

    address[] defaultOperators = [0x70997970C51812dc3A010C7d01b50e0d17dc79C8,0x90F79bf6EB2c4f870365E785982E1f101E93b906];

    function setUp() public {
        tang777 = new Tang777("Tang777","777",defaultOperators);
    }

    function testMint() public {
        address reciptent = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        uint256 amount = 200 * 10 ** 18;
        tang777.mint(reciptent,amount,abi.encodePacked("Tang777Test",address(this)));
    }



}