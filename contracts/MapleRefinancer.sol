// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import {VennFirewallConsumer} from "@ironblocks/firewall-consumer/contracts/consumers/VennFirewallConsumer.sol";
import { IERC20 } from "../modules/erc20/contracts/interfaces/IERC20.sol";

import { IMapleRefinancer } from "./interfaces/IMapleRefinancer.sol";

import { MapleLoanStorage } from "./MapleLoanStorage.sol";

/*

    ███╗   ███╗ █████╗ ██████╗ ██╗     ███████╗    ██████╗ ███████╗███████╗██╗███╗   ██╗ █████╗ ███╗   ██╗ ██████╗███████╗██████╗
    ████╗ ████║██╔══██╗██╔══██╗██║     ██╔════╝    ██╔══██╗██╔════╝██╔════╝██║████╗  ██║██╔══██╗████╗  ██║██╔════╝██╔════╝██╔══██╗
    ██╔████╔██║███████║██████╔╝██║     █████╗      ██████╔╝█████╗  █████╗  ██║██╔██╗ ██║███████║██╔██╗ ██║██║     █████╗  ██████╔╝
    ██║╚██╔╝██║██╔══██║██╔═══╝ ██║     ██╔══╝      ██╔══██╗██╔══╝  ██╔══╝  ██║██║╚██╗██║██╔══██║██║╚██╗██║██║     ██╔══╝  ██╔══██╗
    ██║ ╚═╝ ██║██║  ██║██║     ███████╗███████╗    ██║  ██║███████╗██║     ██║██║ ╚████║██║  ██║██║ ╚████║╚██████╗███████╗██║  ██║
    ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝     ╚══════╝╚══════╝    ╚═╝  ╚═╝╚══════╝╚═╝     ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝╚══════╝╚═╝  ╚═╝

*/

/// @title Refinancer uses storage from a MapleLoan defined by MapleLoanStorage.
contract MapleRefinancer is VennFirewallConsumer, IMapleRefinancer, MapleLoanStorage {

    function decreasePrincipal(uint256 amount_) external override firewallProtected {
        principal -= amount_;

        emit PrincipalDecreased(amount_);
    }

    function increasePrincipal(uint256 amount_) external override firewallProtected {
        principal += amount_;

        emit PrincipalIncreased(amount_);
    }

    function setDelegateServiceFeeRate(uint64 delegateServiceFeeRate_) external override firewallProtected {
        emit DelegateServiceFeeRateSet(delegateServiceFeeRate = delegateServiceFeeRate_);
    }

    function setGracePeriod(uint32 gracePeriod_) external override firewallProtected {
        emit GracePeriodSet(gracePeriod = gracePeriod_);
    }

    function setInterestRate(uint64 interestRate_) external override firewallProtected {
        emit InterestRateSet(interestRate = interestRate_);
    }

    function setLateFeeRate(uint64 lateFeeRate_) external override firewallProtected {
        emit LateFeeRateSet(lateFeeRate = lateFeeRate_);
    }

    function setLateInterestPremiumRate(uint64 lateInterestPremiumRate_) external override firewallProtected {
        emit LateInterestPremiumRateSet(lateInterestPremiumRate = lateInterestPremiumRate_);
    }

    function setNoticePeriod(uint32 noticePeriod_) external override firewallProtected {
        emit NoticePeriodSet(noticePeriod = noticePeriod_);
    }

    function setPaymentInterval(uint32 paymentInterval_) external override firewallProtected {
        require(paymentInterval_ != 0, "R:SPI:ZERO_AMOUNT");

        emit PaymentIntervalSet(paymentInterval = paymentInterval_);
    }

}
