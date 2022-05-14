// SPDX-License-Identifier: MIT

//                                                 ______   __                                                   
//                                                /      \ /  |                                                  
//   _______   ______    ______   _______        /$$$$$$  |$$/  _______    ______   _______    _______   ______  
//  /       | /      \  /      \ /       \       $$ |_ $$/ /  |/       \  /      \ /       \  /       | /      \ 
// /$$$$$$$/ /$$$$$$  |/$$$$$$  |$$$$$$$  |      $$   |    $$ |$$$$$$$  | $$$$$$  |$$$$$$$  |/$$$$$$$/ /$$$$$$  |
// $$ |      $$ |  $$ |$$ |  $$/ $$ |  $$ |      $$$$/     $$ |$$ |  $$ | /    $$ |$$ |  $$ |$$ |      $$    $$ |
// $$ \_____ $$ \__$$ |$$ |      $$ |  $$ |      $$ |      $$ |$$ |  $$ |/$$$$$$$ |$$ |  $$ |$$ \_____ $$$$$$$$/ 
// $$       |$$    $$/ $$ |      $$ |  $$ |      $$ |      $$ |$$ |  $$ |$$    $$ |$$ |  $$ |$$       |$$       |
//  $$$$$$$/  $$$$$$/  $$/       $$/   $$/       $$/       $$/ $$/   $$/  $$$$$$$/ $$/   $$/  $$$$$$$/  $$$$$$$/
//                         .-.
//         .-""`""-.    |(@ @)
//      _/`oOoOoOoOo`\_ \ \-/
//     '.-=-=-=-=-=-=-.' \/ \
//       `-=.=-.-=.=-'    \ /\
//          ^  ^  ^       _H_ \

pragma solidity 0.8.13;

import "./interfaces/IController.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";


/**
* @title Corn Finance Path Finding Resolver 
* @author C.W.B.
*
* @notice When resolver contracts are called, the returned data is used as the
* input data on a seperate call. This means that the call to the resolver contract
* does not affect the gas used on the state-changing function call.
*
* This resolver contract is used for finding the best swap path across numerous
* Uniswap V2 Routers. Paths will be either:
*   a.) from token --> to token
*   b.) from token --> connector token #1 --> to token
*   c.) from token --> connector token #1 --> connector token #2 --> to token
*/
contract Resolver is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct SwapInfo {
        address router;
        address[] path;
        uint256[] amounts;
    }

    IUniswapV2Router02[] public routers = [
        IUniswapV2Router02(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff), // Quickswap
        IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506), // Sushiswap
        IUniswapV2Router02(0x94930a328162957FF1dd48900aF67B5439336cBD), // Polycat
        IUniswapV2Router02(0xC0788A3aD43d79aa53B09c2EaCc313A787d1d607), // ApeSwap
        IUniswapV2Router02(0xA102072A4C07F06EC3B4900FDC4C7B80b6c57429), // Dfyn
        IUniswapV2Router02(0x3a1D87f206D12415f5b0A33E786967680AAb4f6d)  // WaultSwap
    ];
    address[] public connectorTokens = [
        address(0),
        0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063, // DAI
        0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174, // USDC
        0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270, // WMATIC
        0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619, // WETH
        0xc2132D05D31c914a87C6611C10748AEb04B58e8F, // USDT
        0x831753DD7087CaC61aB5644b308642cc1c33Dc13, // QUICK
        0xa3Fa99A148fA48D14Ed51d610c367C61876997F1, // miMATIC
        0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6  // WBTC
    ];

    // --------------------------------------------------------------------------------

    /**
    * @dev Gelato executor will call this function before calling 'fillOrderGelato()'
    * in the Controller contract.
    * @param _vaultId: Vault that holds the order
    * @param _orderId: Order to fill
    * @param _fromToken: ERC20 token being swapped
    * @param _toToken: ERC20 token received from swap
    * @param _fromAmount: Amount of '_fromToken' going into the swap
    * @return (true: Gelato executor call 'fillOrderGelato()'; false: Gelato executor 
    * will not call 'fillOrderGelato()', Input data for 'fillOrderGelato()')
    */
    function checker(
        uint256 _vaultId, 
        uint256 _orderId, 
        address _fromToken, 
        address _toToken, 
        uint256 _fromAmount
    ) public view returns (bool, bytes memory) {
        // Find the best Uniswap V2 router and path for swapping tokens
        (address router, address[] memory path, ) = findBestPathExactIn(_fromToken, _toToken, _fromAmount);

        // Encode input data for when the Gelato executor calls 'fillOrderGelato()'
        return (
            true, 
            abi.encodeWithSelector(
                IController.fillOrderGelato.selector, 
                _vaultId, 
                _orderId, 
                router, 
                path
            )
        );
    }

    // --------------------------------------------------------------------------------

    /**
    * @dev Find the path on the router that returns the highest amount out for a given 
    * swap with a fixed amount in.
    * @param _fromToken: ERC20 token being swapped
    * @param _toToken: ERC20 token received from swap
    * @param _amountIn: Amount of '_fromToken' going into the swap 
    */
    function findBestPathExactIn(
        address _fromToken, 
        address _toToken, 
        uint256 _amountIn
    ) public view returns (address, address[] memory, uint256) {
        uint256 bestAmountOut = 0;
        address bestRouter;
        address[4] memory bestPath;

        (address[4][] memory paths, uint256 pathCount) = getAllPaths(_fromToken, _toToken);

        // Loop through all of the routers
        for(uint i = 0; i < routers.length; i++) {
            // Loop through all of the connector tokens
            for(uint j = 0; j < pathCount; j++) {
                // Get the 'to' amount from the swap
                uint256 amountOut = getAmountOut(
                    routers[i], 
                    _amountIn, 
                    paths[j]
                );

                // Current router and path produce the most amount out yet
                if(amountOut > bestAmountOut) {
                    bestAmountOut = amountOut;
                    bestRouter = address(routers[i]);
                    bestPath = paths[j];
                }
            }
        }

        address[] memory path;

        if(bestPath[3] == address(0)) {
            if(bestPath[2] == address(0)) {
                path = new address[](2);
                path[0] = bestPath[0];
                path[1] = bestPath[1];
            }
            else {
                path = new address[](3);
                path[0] = bestPath[0];
                path[1] = bestPath[1];
                path[2] = bestPath[2];
            }
        }
        else {
            path = new address[](4);
            path[0] = bestPath[0];
            path[1] = bestPath[1];
            path[2] = bestPath[2];
            path[3] = bestPath[3];
        }
        return (bestRouter, path, bestAmountOut);
    }

    // --------------------------------------------------------------------------------

    /**
    * @dev Find the path on the router that returns the lowest amount in for a given 
    * swap with a fixed amount out.
    * @param _fromToken: ERC20 token being swapped
    * @param _toToken: ERC20 token received from swap
    * @param _amountOut: Amount of '_toToken' received from the swap 
    */
    function findBestPathExactOut(
        address _fromToken, 
        address _toToken, 
        uint256 _amountOut
    ) public view returns (address, address[] memory, uint256) {
        uint256 bestAmountIn = type(uint256).max;
        address bestRouter;
        address[4] memory bestPath;

        (address[4][] memory paths, uint256 pathCount) = getAllPaths(_fromToken, _toToken);

        // Loop through all of the routers
        for(uint i = 0; i < routers.length; i++) {
            // Loop through all of the connector tokens
            for(uint j = 0; j < pathCount; j++) {
                // Get the 'to' amount from the swap
                uint256 amountIn = getAmountIn(
                    routers[i], 
                    _amountOut, 
                    paths[j]
                );

                // Current router and path produce the most amount out yet
                if(amountIn < bestAmountIn) {
                    bestAmountIn = amountIn;
                    bestRouter = address(routers[i]);
                    bestPath = paths[j];
                }
            }
        }

        address[] memory path;

        if(bestPath[3] == address(0)) {
            if(bestPath[2] == address(0)) {
                path = new address[](2);
                path[0] = bestPath[0];
                path[1] = bestPath[1];
            }
            else {
                path = new address[](3);
                path[0] = bestPath[0];
                path[1] = bestPath[1];
                path[2] = bestPath[2];
            }
        }
        else {
            path = new address[](4);
            path[0] = bestPath[0];
            path[1] = bestPath[1];
            path[2] = bestPath[2];
            path[3] = bestPath[3];
        }
        return (bestRouter, path, bestAmountIn);
    }

    // --------------------------------------------------------------------------------

    /**
    * @param _router: Router used to perform a swap
    * @param _amountIn: Amount of '_fromToken' going into the swap
    * @return Amount of '_toToken' received from the swap
    */
    function getAmountOut(
        IUniswapV2Router02 _router, 
        uint256 _amountIn, 
        address[4] memory _path
    ) public view returns (uint256) {
        address[] memory path;

        if(_path[3] == address(0)) {
            if(_path[2] == address(0)) {
                path = new address[](2);
                path[0] = _path[0];
                path[1] = _path[1];
            }
            else {
                path = new address[](3);
                path[0] = _path[0];
                path[1] = _path[1];
                path[2] = _path[2];
            }
        }
        else {
            path = new address[](4);
            path[0] = _path[0];
            path[1] = _path[1];
            path[2] = _path[2];
            path[3] = _path[3];
        }

        // Get the 'to' amount from the swap
        try _router.getAmountsOut(_amountIn, path) returns (uint256[] memory amountsOut) {
            return amountsOut[path.length.sub(1)];
        }
        // Call reverted
        catch {
            return 0;
        }
    }

    // --------------------------------------------------------------------------------

    /**
    * @param _router: Router used to perform a swap
    * @param _amountOut: Amount of '_toToken' received from the swap
    * @param _path: List of tokens to perform the swap
    * @return Amount of '_toToken' needed for the swap
    */
    function getAmountIn(
        IUniswapV2Router02 _router, 
        uint256 _amountOut,
        address[4] memory _path 
    ) public view returns (uint256) {
        address[] memory path;

        if(_path[3] == address(0)) {
            if(_path[2] == address(0)) {
                path = new address[](2);
                path[0] = _path[0];
                path[1] = _path[1];
            }
            else {
                path = new address[](3);
                path[0] = _path[0];
                path[1] = _path[1];
                path[2] = _path[2];
            }
        }
        else {
            path = new address[](4);
            path[0] = _path[0];
            path[1] = _path[1];
            path[2] = _path[2];
            path[3] = _path[3];
        }

        // Get the 'to' amount from the swap
        try _router.getAmountsIn(_amountOut, path) returns (uint256[] memory amountsIn) {
            return amountsIn[0];
        }
        // Call reverted
        catch {
            return type(uint256).max;
        }
    }

    // --------------------------------------------------------------------------------

    function swapExactIn(
        IUniswapV2Router02 _router, 
        uint256 _amountIn, 
        uint256 _amountOutMin, 
        address[] memory _path, 
        address _to, 
        uint _deadline
    ) external returns (uint256[] memory) {
        IERC20 tokenIn = IERC20(_path[0]);

        // Transfer tokens from caller to this contract
        tokenIn.safeTransferFrom(msg.sender, address(this), _amountIn);

        // Approve router for swap
        tokenIn.approve(address(_router), _amountIn);

        // Swap
        return _router.swapExactTokensForTokens(_amountIn, _amountOutMin, _path, _to, _deadline);
    }

    // --------------------------------------------------------------------------------

    function getAllPaths(address _fromToken, address _toToken) public view returns (address[4][] memory paths, uint256 pathCount) {
        paths = new address[4][](((connectorTokens.length - 1) ** 2) + 1); 
        pathCount = 0;

        paths[pathCount++] = [_fromToken, _toToken, address(0), address(0)];
        for(uint256 i = 1; i < connectorTokens.length; i++) {
            for(uint256 j = 0; j < connectorTokens.length; j++) {
                if(connectorTokens[i] != _fromToken && connectorTokens[i] != _toToken &&
                    connectorTokens[j] != _fromToken && connectorTokens[j] != _toToken &&
                    connectorTokens[i] != connectorTokens[j]
                ) {
                    if(connectorTokens[j] == address(0)) {
                        paths[pathCount++] = [_fromToken, connectorTokens[i], _toToken, address(0)];
                    }
                    else {
                        paths[pathCount++] = [_fromToken, connectorTokens[i], connectorTokens[j], _toToken];
                    }
                }
            }
        }
    }

    // --------------------------------------------------------------------------------

    /**
    * @notice ERC20 tokens are never stored in this contract. This function is only used
    * for claiming ERC20 tokens sent to this contract in error.
    */
    function emergencyWithdraw(IERC20 _token, uint256 _amount) external onlyOwner {
        _token.safeTransfer(owner(), _amount);
    } 
}