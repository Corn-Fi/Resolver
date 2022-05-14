// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./IUniswapV2Router02.sol";


interface IController {
    function fillOrderGelato(
        uint256 _vaultId, 
        uint256 _orderId, 
        IUniswapV2Router02 _router, 
        address[] memory _path
    ) external;
}