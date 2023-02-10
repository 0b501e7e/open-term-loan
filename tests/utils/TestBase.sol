// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { MockERC20 }      from "../../modules/erc20/contracts/test/mocks/MockERC20.sol";
import { console2, Test } from "../../modules/forge-std/src/Test.sol";

import { MapleLoanHarness }              from "./Harnesses.sol";
import { MapleGlobalsMock, MockFactory } from "./Mocks.sol";

contract TestBase is Test {

    address asset;
    address factory;
    address globals;
    address governor;

    uint256 start;

    function setUp() public virtual {
        governor = makeAddr("governor");

        asset    = address(new MockERC20("Asset", "A", 6));
        globals  = address(new MapleGlobalsMock(governor));
        factory  = address(new MockFactory(globals));

        start = block.timestamp;
    }

    function createLoan(
        address borrower,
        address lender,
        address fundsAsset,
        uint256 principal,
        uint32[3] memory termDetails,
        uint256[3] memory rates
    ) internal returns (address loan_) {
        MapleLoanHarness loan = new MapleLoanHarness();

        loan.__setFactory(factory);
        loan.__setBorrower(borrower);
        loan.__setLender(lender);
        loan.__setFundsAsset(fundsAsset);
        loan.__setPrincipal(principal);
        loan.__setGracePeriod(termDetails[0]);
        loan.__setNoticePeriod(termDetails[1]);
        loan.__setPaymentInterval(termDetails[2]);
        loan.__setInterestRate(rates[0]);
        loan.__setLateFeeRate(rates[1]);
        loan.__setLateInterestPremium(rates[2]);

        loan_ = address(loan);
    }

    function _createFixture(
        uint256 principal,
        uint256 paymentInterval,
        uint256 paymentDate,
        uint256[3] memory rates
    )
        internal returns (MapleLoanHarness loan_)
    {
        loan_ = new MapleLoanHarness();

        loan_.__setDateFunded(block.timestamp);
        loan_.__setPrincipal(principal);
        loan_.__setPaymentInterval(paymentInterval);

        loan_.__setInterestRate(rates[0]);
        loan_.__setLateFeeRate(rates[1]);
        loan_.__setLateInterestPremium(rates[2]);

        vm.warp(block.timestamp + paymentDate);
    }

}
