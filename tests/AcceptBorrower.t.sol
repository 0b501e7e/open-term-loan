// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { Test } from "../modules/forge-std/src/Test.sol";

import { MapleLoanHarness }         from "./utils/Harnesses.sol";
import { MockFactory, MockGlobals } from "./utils/Mocks.sol";

contract AcceptBorrowerTests is Test {

    address account  = makeAddr("account");

    MockFactory      factoryMock = new MockFactory();
    MapleLoanHarness loan        = new MapleLoanHarness();
    MockGlobals      globals     = new MockGlobals();

    function setUp() external {
        factoryMock.__setGlobals(address(globals));

        loan.__setFactory(address(factoryMock));
    }

    function test_acceptBorrower_protocolPaused() external {
        globals.__setProtocolPaused(true);

        vm.expectRevert("ML:PROTOCOL_PAUSED");
        loan.acceptBorrower();
    }

    function test_acceptBorrower_notPendingBorrower() external {
        loan.__setPendingBorrower(account);

        vm.expectRevert("ML:AB:NOT_PENDING_BORROWER");
        loan.acceptBorrower();
    }

    function test_acceptBorrower_success() external {
        loan.__setPendingBorrower(account);

        vm.prank(account);
        loan.acceptBorrower();

        assertEq(loan.borrower(),        account);
        assertEq(loan.pendingBorrower(), address(0));
    }

}
